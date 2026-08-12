--[[
Module: FX_Options

Purpose
- Add Blizzard Settings UI pages for the FX layer:
  - Frame Decorations (border/glow)
  - Faders (mouseover transparency)

Design goals
- Development-first UX: grouped controls, scrollable, immediate "Apply".
- Color input: HEX (fast + stable) + optional wheel via ColorPickerFrame.

This module is standalone and depends only on the base Settings API (Retail 12.0+).
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "FX_Options",
  version = "0.5.1",
  priority = 5,
  enabledByDefault = true,
  events = { "PLAYER_LOGIN" },
}

-- -----------------------------------------------------------------------------
-- Small UI helpers
-- -----------------------------------------------------------------------------

local function Clamp01(x)
  x = tonumber(x) or 0
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function RGBToHex(r, g, b)
  r = math.floor(Clamp01(r) * 255 + 0.5)
  g = math.floor(Clamp01(g) * 255 + 0.5)
  b = math.floor(Clamp01(b) * 255 + 0.5)
  return string.format("%02X%02X%02X", r, g, b)
end

local function HexToRGB(hex)
  if type(hex) ~= "string" then return nil end
  hex = hex:gsub("#", "")
  if #hex == 3 then
    hex = hex:sub(1,1)..hex:sub(1,1)..hex:sub(2,2)..hex:sub(2,2)..hex:sub(3,3)..hex:sub(3,3)
  end
  if #hex ~= 6 then return nil end
  local r = tonumber(hex:sub(1,2), 16)
  local g = tonumber(hex:sub(3,4), 16)
  local b = tonumber(hex:sub(5,6), 16)
  if not r or not g or not b then return nil end
  return r/255, g/255, b/255
end

local function MakeTitle(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  return fs
end

local function MakeGroupHeader(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  fs:SetTextColor(1, 0.82, 0)
  return fs
end

local function MakeText(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetText(text or "")
  fs:SetJustifyH("LEFT")
  fs:SetTextColor(0.9, 0.9, 0.9)
  return fs
end

local function MakeCheck(parent, label)
  local b = CreateFrame("CheckButton", nil, parent, "SettingsCheckButtonTemplate")
  b.Text:SetText(label or "")
  return b
end

local function MakeSlider(parent, label, minV, maxV, step)
  local s = CreateFrame("Slider", nil, parent, "SettingsSliderTemplate")
  s:SetMinMaxValues(minV or 0, maxV or 1)
  s:SetValueStep(step or 0.01)
  s.SliderLabel:SetText(label or "")
  s.ValueText:SetText("")
  return s
end

local function MakeButton(parent, label)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetText(label or "")
  b:SetHeight(22)
  return b
end

local function MakeHexColorRow(parent, label)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(24)

  local t = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  t:SetPoint("LEFT", 0, 0)
  t:SetText(label or "")

  local edit = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
  edit:SetAutoFocus(false)
  edit:SetWidth(80)
  edit:SetHeight(22)
  edit:SetPoint("LEFT", t, "RIGHT", 10, 0)
  edit:SetTextInsets(6, 6, 2, 2)

  local sw = row:CreateTexture(nil, "ARTWORK")
  sw:SetSize(18, 18)
  sw:SetPoint("LEFT", edit, "RIGHT", 8, 0)
  sw:SetColorTexture(1, 1, 1, 1)

  local pick = MakeButton(row, "Pick")
  pick:SetWidth(48)
  pick:SetPoint("LEFT", sw, "RIGHT", 8, 0)

  row.label = t
  row.edit = edit
  row.swatch = sw
  row.pick = pick
  return row
end

local function MakeScrollCanvas(parent)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local canvas = CreateFrame("Frame", nil, scroll)
  canvas:SetSize(1, 1)
  scroll:SetScrollChild(canvas)
  scroll.Canvas = canvas
  return scroll
end

-- -----------------------------------------------------------------------------
-- Bindings to DB
-- -----------------------------------------------------------------------------

local function GetFX(core)
  local p = core.db and core.db.profile
  p.fx = p.fx or {}
  p.fx.frames = p.fx.frames or {}
  p.fx.faders = p.fx.faders or {}
  return p.fx.frames, p.fx.faders
end

local function GetDyn(core)
  local p = core.db and core.db.profile
  p.fx = p.fx or {}
  p.fx.dynamics = p.fx.dynamics or {}
  return p.fx.dynamics
end

local function ApplyAll(core)
  core:ApplyAll()
end

local function WireCheck(core, check, getter, setter)
  check:SetChecked(getter())
  check:SetScript("OnClick", function(self)
    setter(self:GetChecked() and true or false)
  end)
end

local function WireSlider(core, slider, getter, setter, fmt)
  local function Refresh()
    local v = getter()
    slider:SetValue(v)
    slider.ValueText:SetText((fmt and string.format(fmt, v)) or tostring(v))
  end
  Refresh()
  slider:SetScript("OnValueChanged", function(self, value)
    setter(value)
    self.ValueText:SetText((fmt and string.format(fmt, value)) or tostring(value))
  end)
end

local function WireHexColor(core, row, getter, setter)
  local function Refresh()
    local c = getter()
    local r, g, b, a = core:UnpackColor(c, 1)
    row.edit:SetText(RGBToHex(r, g, b))
    row.swatch:SetColorTexture(r, g, b, 1)
  end

  row.edit:SetScript("OnEnterPressed", function(self)
    local hex = self:GetText()
    local r, g, b = HexToRGB(hex)
    if not r then
      Refresh()
      self:ClearFocus()
      return
    end
    local c = getter() or {}
    c.r, c.g, c.b = r, g, b
    setter(c)
    ApplyAll(core)
    Refresh()
    self:ClearFocus()
  end)

  row.pick:SetScript("OnClick", function()
    local c = getter() or {}
    local r, g, b, a = core:UnpackColor(c, 1)
    if _G.ColorPickerFrame then
      local prev = { r = r, g = g, b = b }
      ColorPickerFrame.hasOpacity = false
      ColorPickerFrame.func = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        c.r, c.g, c.b = nr, ng, nb
        setter(c)
        ApplyAll(core)
        Refresh()
      end
      ColorPickerFrame.cancelFunc = function()
        c.r, c.g, c.b = prev.r, prev.g, prev.b
        setter(c)
        ApplyAll(core)
        Refresh()
      end
      ColorPickerFrame:SetColorRGB(r, g, b)
      ColorPickerFrame:Show()
    end
  end)

  Refresh()
end

-- -----------------------------------------------------------------------------
-- Panels
-- -----------------------------------------------------------------------------

local function BuildFramesPanel(core)
  local root = CreateFrame("Frame")

  local scroll = MakeScrollCanvas(root)
  scroll:SetPoint("TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -30, 4)

  local c = scroll.Canvas

  local title = MakeTitle(c, "Roth Skinner: FX / Frame Decorations")
  title:SetPoint("TOPLEFT", 12, -12)

  local desc = MakeText(c, "Border + glow overlays for Blizzard panels and dialogs. Theme assets define the final look.")
  desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  desc:SetWidth(520)

  local frames, _ = GetFX(core)

  local y = -70

  local g1 = MakeGroupHeader(c, "Master")
  g1:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local enabled = MakeCheck(c, "Enable frame decorations")
  enabled:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, enabled,
    function() return frames.enabled ~= false end,
    function(v) frames.enabled = v; ApplyAll(core) end)

  local g2 = MakeGroupHeader(c, "Border")
  g2:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local borderOn = MakeCheck(c, "Enable border overlay")
  borderOn:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, borderOn,
    function() return frames.border ~= false end,
    function(v) frames.border = v; ApplyAll(core) end)

  local borderSize = MakeSlider(c, "Border size", 0, 12, 1)
  borderSize:SetPoint("TOPLEFT", 12, y)
  borderSize:SetWidth(420)
  y = y - 56

  WireSlider(core, borderSize,
    function() return tonumber(frames.borderSize) or 1 end,
    function(v) frames.borderSize = math.floor(v + 0.5); ApplyAll(core) end,
    "%.0f")

  local borderAlpha = MakeSlider(c, "Border alpha", 0, 1, 0.01)
  borderAlpha:SetPoint("TOPLEFT", 12, y)
  borderAlpha:SetWidth(420)
  y = y - 56

  WireSlider(core, borderAlpha,
    function() return tonumber(frames.borderAlpha) or 0.9 end,
    function(v) frames.borderAlpha = v; ApplyAll(core) end,
    "%.2f")

  local borderColor = MakeHexColorRow(c, "Border color (HEX)")
  borderColor:SetPoint("TOPLEFT", 12, y)
  y = y - 32

  frames.colors = frames.colors or {}
  WireHexColor(core, borderColor,
    function() return (frames.colors and frames.colors.border) or frames.borderColor end,
    function(col) frames.colors.border = col; frames.colorSource = "override" end)

  local g3 = MakeGroupHeader(c, "Glow")
  g3:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local glowOn = MakeCheck(c, "Enable outer glow")
  glowOn:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, glowOn,
    function() return frames.glow ~= false end,
    function(v) frames.glow = v; ApplyAll(core) end)

  local glowSize = MakeSlider(c, "Glow size", 0, 24, 1)
  glowSize:SetPoint("TOPLEFT", 12, y)
  glowSize:SetWidth(420)
  y = y - 56

  WireSlider(core, glowSize,
    function() return tonumber(frames.glowSize) or 6 end,
    function(v) frames.glowSize = math.floor(v + 0.5); ApplyAll(core) end,
    "%.0f")

  local glowAlpha = MakeSlider(c, "Glow alpha", 0, 1, 0.01)
  glowAlpha:SetPoint("TOPLEFT", 12, y)
  glowAlpha:SetWidth(420)
  y = y - 56

  WireSlider(core, glowAlpha,
    function() return tonumber(frames.glowAlpha) or 0.28 end,
    function(v) frames.glowAlpha = v; ApplyAll(core) end,
    "%.2f")

  local glowColor = MakeHexColorRow(c, "Glow color (HEX)")
  glowColor:SetPoint("TOPLEFT", 12, y)
  y = y - 32

  WireHexColor(core, glowColor,
    function() return (frames.colors and frames.colors.glow) or frames.glowColor end,
    function(col) frames.colors.glow = col; frames.colorSource = "override" end)

  local glowPulse = MakeCheck(c, "Pulse glow")
  glowPulse:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, glowPulse,
    function() return frames.glowPulse == true end,
    function(v) frames.glowPulse = v; ApplyAll(core) end)

  local glowPeriod = MakeSlider(c, "Pulse period (seconds)", 0.4, 4.0, 0.05)
  glowPeriod:SetPoint("TOPLEFT", 12, y)
  glowPeriod:SetWidth(420)
  y = y - 56

  WireSlider(core, glowPeriod,
    function() return tonumber(frames.glowPulsePeriod) or 1.6 end,
    function(v) frames.glowPulsePeriod = v; ApplyAll(core) end,
    "%.2f")

  local g4 = MakeGroupHeader(c, "Theme")
  g4:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local useTheme = MakeCheck(c, "Use theme colors (recommended)")
  useTheme:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, useTheme,
    function() return frames.colorSource ~= "override" end,
    function(v) frames.colorSource = v and "theme" or "override"; ApplyAll(core) end)

  local apply = MakeButton(c, "Apply Now")
  apply:SetPoint("TOPLEFT", 12, y)
  apply:SetWidth(120)
  apply:SetScript("OnClick", function() ApplyAll(core) end)
  y = y - 40

  c:SetHeight(-y + 20)
  return root
end

local function BuildFadersPanel(core)
  local root = CreateFrame("Frame")

  local scroll = MakeScrollCanvas(root)
  scroll:SetPoint("TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -30, 4)

  local c = scroll.Canvas

  local title = MakeTitle(c, "Roth Skinner: FX / Faders")
  title:SetPoint("TOPLEFT", 12, -12)

  local desc = MakeText(c, "Mouseover transparency. Useful for making panels visually quiet until interacted with.")
  desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  desc:SetWidth(520)

  local _, faders = GetFX(core)

  local y = -70

  local g1 = MakeGroupHeader(c, "Master")
  g1:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local enabled = MakeCheck(c, "Enable faders")
  enabled:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, enabled,
    function() return faders.enabled ~= false end,
    function(v) faders.enabled = v; ApplyAll(core) end)

  local g2 = MakeGroupHeader(c, "Alpha")
  g2:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local active = MakeSlider(c, "Active alpha", 0, 1, 0.01)
  active:SetPoint("TOPLEFT", 12, y)
  active:SetWidth(420)
  y = y - 56

  WireSlider(core, active,
    function() return tonumber(faders.activeAlpha) or 1 end,
    function(v) faders.activeAlpha = v; ApplyAll(core) end,
    "%.2f")

  local inactive = MakeSlider(c, "Inactive alpha", 0, 1, 0.01)
  inactive:SetPoint("TOPLEFT", 12, y)
  inactive:SetWidth(420)
  y = y - 56

  WireSlider(core, inactive,
    function() return tonumber(faders.inactiveAlpha) or 0.35 end,
    function(v) faders.inactiveAlpha = v; ApplyAll(core) end,
    "%.2f")

  local g3 = MakeGroupHeader(c, "Timing")
  g3:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local fadeIn = MakeSlider(c, "Fade in (seconds)", 0, 1.0, 0.01)
  fadeIn:SetPoint("TOPLEFT", 12, y)
  fadeIn:SetWidth(420)
  y = y - 56

  WireSlider(core, fadeIn,
    function() return tonumber(faders.fadeIn) or 0.10 end,
    function(v) faders.fadeIn = v; ApplyAll(core) end,
    "%.2f")

  local fadeOut = MakeSlider(c, "Fade out (seconds)", 0, 1.5, 0.01)
  fadeOut:SetPoint("TOPLEFT", 12, y)
  fadeOut:SetWidth(420)
  y = y - 56

  WireSlider(core, fadeOut,
    function() return tonumber(faders.fadeOut) or 0.22 end,
    function(v) faders.fadeOut = v; ApplyAll(core) end,
    "%.2f")

  local g4 = MakeGroupHeader(c, "Rules")
  g4:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local ooc = MakeCheck(c, "Only fade out of combat")
  ooc:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, ooc,
    function() return faders.onlyOutOfCombat ~= false end,
    function(v) faders.onlyOutOfCombat = v; ApplyAll(core) end)

  local focus = MakeCheck(c, "Keep active when keyboard focus is inside")
  focus:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, focus,
    function() return faders.keepActiveWhenFocused ~= false end,
    function(v) faders.keepActiveWhenFocused = v; ApplyAll(core) end)

  local g5 = MakeGroupHeader(c, "Coverage")
  g5:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local p1 = MakeCheck(c, "Panels (UIPanelWindows)")
  p1:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, p1,
    function() return faders.panels ~= false end,
    function(v) faders.panels = v; ApplyAll(core) end)

  local p2 = MakeCheck(c, "Popups (GameMenu, StaticPopup, ColorPicker, Settings)")
  p2:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, p2,
    function() return faders.popups ~= false end,
    function(v) faders.popups = v; ApplyAll(core) end)

  local p3 = MakeCheck(c, "Dropdown lists")
  p3:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, p3,
    function() return faders.dropdownLists ~= false end,
    function(v) faders.dropdownLists = v; ApplyAll(core) end)

  local p4 = MakeCheck(c, "Tooltips")
  p4:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, p4,
    function() return faders.tooltips ~= false end,
    function(v) faders.tooltips = v; ApplyAll(core) end)

  local apply = MakeButton(c, "Apply Now")
  apply:SetPoint("TOPLEFT", 12, y)
  apply:SetWidth(120)
  apply:SetScript("OnClick", function() ApplyAll(core) end)
  y = y - 40

  c:SetHeight(-y + 20)
  return root
end



local function BuildDynamicsPanel(core)
  local root = CreateFrame("Frame")

  local scroll = MakeScrollCanvas(root)
  scroll:SetPoint("TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", -30, 4)

  local c = scroll.Canvas

  local title = MakeTitle(c, "Roth Skinner: FX / Dynamics")
  title:SetPoint("TOPLEFT", 12, -12)

  local desc = MakeText(c, "Reactive pulses/flashes on UI targets for gameplay events (combat, loot, victory). Development-first: many knobs, safe defaults.")
  desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  desc:SetWidth(520)

  local dyn = GetDyn(core)

  local y = -70

  local g1 = MakeGroupHeader(c, "Master")
  g1:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local enabled = MakeCheck(c, "Enable dynamics FX")
  enabled:SetPoint("TOPLEFT", 12, y)
  y = y - 28

  WireCheck(core, enabled,
    function() return dyn.enabled ~= false end,
    function(v) dyn.enabled = v; ApplyAll(core) end)

  local g2 = MakeGroupHeader(c, "Events")
  g2:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local e1 = MakeCheck(c, "Enter combat (PLAYER_REGEN_DISABLED)")
  e1:SetPoint("TOPLEFT", 12, y)
  y = y - 28
  WireCheck(core, e1,
    function() return dyn.onEnterCombat ~= false end,
    function(v) dyn.onEnterCombat = v; ApplyAll(core) end)

  local e2 = MakeCheck(c, "Leave combat (PLAYER_REGEN_ENABLED)")
  e2:SetPoint("TOPLEFT", 12, y)
  y = y - 28
  WireCheck(core, e2,
    function() return dyn.onLeaveCombat == true end,
    function(v) dyn.onLeaveCombat = v; ApplyAll(core) end)

  local e3 = MakeCheck(c, "Loot received (LOOT_READY / CHAT_MSG_LOOT)")
  e3:SetPoint("TOPLEFT", 12, y)
  y = y - 28
  WireCheck(core, e3,
    function() return dyn.onLoot ~= false end,
    function(v) dyn.onLoot = v; ApplyAll(core) end)

  local e4 = MakeCheck(c, "Victory (ENCOUNTER_END success)")
  e4:SetPoint("TOPLEFT", 12, y)
  y = y - 28
  WireCheck(core, e4,
    function() return dyn.onVictory ~= false end,
    function(v) dyn.onVictory = v; ApplyAll(core) end)

  local g3 = MakeGroupHeader(c, "Targets")
  g3:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local t1 = MakeCheck(c, "Action bars (MainMenuBar / MultiBar* / Pet / Stance / Override)")
  t1:SetPoint("TOPLEFT", 12, y)
  y = y - 28
  WireCheck(core, t1,
    function() return dyn.actionBars ~= false end,
    function(v) dyn.actionBars = v; ApplyAll(core) end)

  local t2 = MakeCheck(c, "Bag bar (Backpack + bag slots)")
  t2:SetPoint("TOPLEFT", 12, y)
  y = y - 28
  WireCheck(core, t2,
    function() return dyn.bagBar ~= false end,
    function(v) dyn.bagBar = v; ApplyAll(core) end)

  local t3 = MakeCheck(c, "Global overlay (UIParent)")
  t3:SetPoint("TOPLEFT", 12, y)
  y = y - 28
  WireCheck(core, t3,
    function() return dyn.globalOverlay == true end,
    function(v) dyn.globalOverlay = v; ApplyAll(core) end)

  local g4 = MakeGroupHeader(c, "Throttle")
  g4:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local thrLoot = MakeSlider(c, "Loot throttle (seconds)", 0.0, 5.0, 0.05)
  thrLoot:SetPoint("TOPLEFT", 12, y)
  thrLoot:SetWidth(420)
  y = y - 56
  WireSlider(core, thrLoot,
    function() return tonumber(dyn.throttleLoot) or 1.0 end,
    function(v) dyn.throttleLoot = v; ApplyAll(core) end,
    "%.2f")

  local thrVic = MakeSlider(c, "Victory throttle (seconds)", 0.0, 10.0, 0.05)
  thrVic:SetPoint("TOPLEFT", 12, y)
  thrVic:SetWidth(420)
  y = y - 56
  WireSlider(core, thrVic,
    function() return tonumber(dyn.throttleVictory) or 2.0 end,
    function(v) dyn.throttleVictory = v; ApplyAll(core) end,
    "%.2f")

  local g5 = MakeGroupHeader(c, "Visual")
  g5:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local fd = MakeSlider(c, "Flash duration (seconds)", 0.05, 1.5, 0.01)
  fd:SetPoint("TOPLEFT", 12, y)
  fd:SetWidth(420)
  y = y - 56
  WireSlider(core, fd,
    function() return tonumber(dyn.flashDuration) or 0.35 end,
    function(v) dyn.flashDuration = v; ApplyAll(core) end,
    "%.2f")

  local fa = MakeSlider(c, "Flash alpha", 0, 1, 0.01)
  fa:SetPoint("TOPLEFT", 12, y)
  fa:SetWidth(420)
  y = y - 56
  WireSlider(core, fa,
    function() return tonumber(dyn.flashAlpha) or 0.65 end,
    function(v) dyn.flashAlpha = v; ApplyAll(core) end,
    "%.2f")

  local fs = MakeSlider(c, "Flash scale", 1.0, 1.15, 0.005)
  fs:SetPoint("TOPLEFT", 12, y)
  fs:SetWidth(420)
  y = y - 56
  WireSlider(core, fs,
    function() return tonumber(dyn.flashScale) or 1.03 end,
    function(v) dyn.flashScale = v; ApplyAll(core) end,
    "%.3f")

  local gd = MakeSlider(c, "Afterglow duration (seconds)", 0.05, 2.5, 0.01)
  gd:SetPoint("TOPLEFT", 12, y)
  gd:SetWidth(420)
  y = y - 56
  WireSlider(core, gd,
    function() return tonumber(dyn.glowDuration) or 0.75 end,
    function(v) dyn.glowDuration = v; ApplyAll(core) end,
    "%.2f")

  local ga = MakeSlider(c, "Afterglow alpha", 0, 1, 0.01)
  ga:SetPoint("TOPLEFT", 12, y)
  ga:SetWidth(420)
  y = y - 56
  WireSlider(core, ga,
    function() return tonumber(dyn.glowAlpha) or 0.30 end,
    function(v) dyn.glowAlpha = v; ApplyAll(core) end,
    "%.2f")

  local g6 = MakeGroupHeader(c, "Colors")
  g6:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  dyn.colors = dyn.colors or {}

  local c1 = MakeHexColorRow(c, "Combat color (HEX)")
  c1:SetPoint("TOPLEFT", 12, y)
  y = y - 32
  WireHexColor(core, c1,
    function() return dyn.colors.combat end,
    function(col) dyn.colors.combat = col; dyn.colorSource = "override" end)

  local c2 = MakeHexColorRow(c, "Loot color (HEX)")
  c2:SetPoint("TOPLEFT", 12, y)
  y = y - 32
  WireHexColor(core, c2,
    function() return dyn.colors.loot end,
    function(col) dyn.colors.loot = col; dyn.colorSource = "override" end)

  local c3 = MakeHexColorRow(c, "Victory color (HEX)")
  c3:SetPoint("TOPLEFT", 12, y)
  y = y - 32
  WireHexColor(core, c3,
    function() return dyn.colors.victory end,
    function(col) dyn.colors.victory = col; dyn.colorSource = "override" end)

  local useTheme = MakeCheck(c, "Use theme accent colors (recommended)")
  useTheme:SetPoint("TOPLEFT", 12, y)
  y = y - 28
  WireCheck(core, useTheme,
    function() return dyn.colorSource ~= "override" end,
    function(v) dyn.colorSource = v and "theme" or "override"; ApplyAll(core) end)

  local g7 = MakeGroupHeader(c, "Test")
  g7:SetPoint("TOPLEFT", 12, y)
  y = y - 22

  local b1 = MakeButton(c, "Test Combat")
  b1:SetPoint("TOPLEFT", 12, y)
  b1:SetWidth(120)
  b1:SetScript("OnClick", function()
    local m = core:GetModule("FX_Dynamics")
    if m and m.Test then m:Test(core, "combat") end
  end)

  local b2 = MakeButton(c, "Test Loot")
  b2:SetPoint("LEFT", b1, "RIGHT", 10, 0)
  b2:SetWidth(120)
  b2:SetScript("OnClick", function()
    local m = core:GetModule("FX_Dynamics")
    if m and m.Test then m:Test(core, "loot") end
  end)

  local b3 = MakeButton(c, "Test Victory")
  b3:SetPoint("LEFT", b2, "RIGHT", 10, 0)
  b3:SetWidth(120)
  b3:SetScript("OnClick", function()
    local m = core:GetModule("FX_Dynamics")
    if m and m.Test then m:Test(core, "victory") end
  end)

  y = y - 40

  local apply = MakeButton(c, "Apply Now")
  apply:SetPoint("TOPLEFT", 12, y)
  apply:SetWidth(120)
  apply:SetScript("OnClick", function() ApplyAll(core) end)
  y = y - 40

  c:SetHeight(-y + 20)
  return root
end
-- -----------------------------------------------------------------------------
-- Settings registration
-- -----------------------------------------------------------------------------

local function RegisterCategory(core, panel, name)
  if not _G.Settings or not Settings.RegisterCanvasLayoutCategory then return end
  local cat = Settings.RegisterCanvasLayoutCategory(panel, name)
  Settings.RegisterAddOnCategory(cat)
  return cat
end

function Module:OnEvent(core, event)
  if event ~= "PLAYER_LOGIN" then return end
  if not _G.Settings or not Settings.RegisterCanvasLayoutCategory then return end

  local framesPanel = BuildFramesPanel(core)
  local fadersPanel = BuildFadersPanel(core)
  local dynamicsPanel = BuildDynamicsPanel(core)

  -- Root category for FX (kept separate to avoid colliding with the main OptionsPanel category).
  local rootPanel = CreateFrame("Frame")
  do
    local title = rootPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Roth Skinner: FX")

    local t = rootPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    t:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    t:SetWidth(520)
    t:SetJustifyH("LEFT")
    t:SetText("Development controls for global frame decorations and faders. Use the subpages on the left.")

    local apply = CreateFrame("Button", nil, rootPanel, "UIPanelButtonTemplate")
    apply:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -12)
    apply:SetSize(140, 22)
    apply:SetText("Apply All Now")
    apply:SetScript("OnClick", function() core:ApplyAll() end)
  end

  local cat = Settings.RegisterCanvasLayoutCategory(rootPanel, "Roth Skinner: FX")
  Settings.RegisterAddOnCategory(cat)

  -- Subcategories
  Settings.RegisterCanvasLayoutSubcategory(cat, framesPanel, "Frames")
  Settings.RegisterCanvasLayoutSubcategory(cat, fadersPanel, "Faders")
  Settings.RegisterCanvasLayoutSubcategory(cat, dynamicsPanel, "Dynamics")

  core:Trace(self.name, "Settings categories registered")
end

RS:RegisterModule(Module.name, Module)
