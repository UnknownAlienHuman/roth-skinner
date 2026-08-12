--[[
Module: WidgetPolicy_Controls

Goal
- Extend widget skinning beyond the conservative basics module.
- Focus on Settings/Options-style UI controls:
  - CheckButtons, SettingsCheckBox controls, sliders, drop-down wrappers, list rows.

Why separate
- Settings UI contains many nested frames; we keep scanning bounded and targeted.
- Allows disabling if it causes visual regressions.

Approach
- Hook OnShow for SettingsPanel and InterfaceOptions/OptionsFrame (if present).
- On show, scan visible subtree with a node budget and apply idempotent skins.
- Do not touch protected frames in combat (core queues them if needed).

Notes
- This module does not try to redraw every element.
  It applies a consistent color policy for common control families.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "WidgetPolicy_Controls",
  version = "0.3.0",
  priority = 45,
  enabledByDefault = true,

  events = { "PLAYER_LOGIN" },
  blizzardAddons = {
    "Blizzard_Settings",
  },

  targets = {
    claims = { "Widgets:Controls" },
  },
}

local function SetVertex(tex, c)
  if tex and tex.SetVertexColor and c then
    tex:SetVertexColor(c.r, c.g, c.b, c.a or 1)
  end
end

local function SetColorTexture(tex, c)
  if tex and tex.SetColorTexture and c then
    tex:SetColorTexture(c.r, c.g, c.b, c.a or 1)
  end
end

local function GetThemeColors(theme)
  local t = theme and theme.tokens
  local c = t and t.colors
  return {
    border = c and c.panelBorder or { r=0.40,g=0.08,b=0.06,a=0.90 },
    bg     = c and c.panelBg     or { r=0.06,g=0.06,b=0.065,a=0.92 },
    inset  = c and c.panelInset  or { r=0.00,g=0.00,b=0.00,a=0.25 },
    hover  = c and c.hover       or { r=1.00,g=0.36,b=0.16,a=0.18 },
    press  = c and c.press       or { r=1.00,g=0.20,b=0.12,a=0.25 },
    text   = c and c.text        or { r=0.92,g=0.90,b=0.85,a=1.00 },
    muted  = c and c.mutedText   or { r=0.65,g=0.62,b=0.58,a=1.00 },
  }
end

local function SkinThreePiece(core, theme, obj)
  if not obj then return end
  if not core:FrameOnce(obj, "RSWidget:3Piece") then return end
  local cc = GetThemeColors(theme)
  SetVertex(obj.Left, cc.border)
  SetVertex(obj.Middle, cc.bg)
  SetVertex(obj.Right, cc.border)
  core:StatInc(Module.name, "threePiece", 1)
end

local function SkinButton(core, theme, btn)
  if not btn or not btn.GetObjectType or btn:GetObjectType() ~= "Button" then return end
  if not core:FrameOnce(btn, "RSWidget:Button2") then return end
  local cc = GetThemeColors(theme)

  -- Classic three-piece buttons
  if btn.Left and btn.Middle and btn.Right then
    SetVertex(btn.Left, cc.border)
    SetVertex(btn.Middle, cc.bg)
    SetVertex(btn.Right, cc.border)
  end

  local n = btn.GetNormalTexture and btn:GetNormalTexture()
  if n and n.SetVertexColor then
    n:SetVertexColor(cc.border.r, cc.border.g, cc.border.b, 0.65)
  end
  local h = btn.GetHighlightTexture and btn:GetHighlightTexture()
  if h and h.SetColorTexture then
    h:SetColorTexture(cc.hover.r, cc.hover.g, cc.hover.b, cc.hover.a)
  end

  core:StatInc(Module.name, "buttons", 1)
end

local function SkinCheckButton(core, theme, cb)
  if not cb or not cb.GetObjectType or cb:GetObjectType() ~= "CheckButton" then return end
  if not core:FrameOnce(cb, "RSWidget:CheckButton") then return end
  local cc = GetThemeColors(theme)

  local n = cb.GetNormalTexture and cb:GetNormalTexture()
  if n and n.SetVertexColor then
    n:SetVertexColor(cc.border.r, cc.border.g, cc.border.b, 0.85)
  end

  local c = cb.GetCheckedTexture and cb:GetCheckedTexture()
  if c and c.SetVertexColor then
    c:SetVertexColor(cc.border.r, cc.border.g, cc.border.b, 0.95)
  end

  local h = cb.GetHighlightTexture and cb:GetHighlightTexture()
  if h and h.SetColorTexture then
    h:SetColorTexture(cc.hover.r, cc.hover.g, cc.hover.b, cc.hover.a)
  end

  core:StatInc(Module.name, "checkButtons", 1)
end

local function SkinSettingsCheckBoxControl(core, theme, frame)
  -- Settings* control frames often wrap an inner CheckBox + Label.
  if not frame or not frame.GetObjectType or frame:GetObjectType() ~= "Frame" then return end
  if not frame.CheckBox then return end
  if not core:FrameOnce(frame, "RSWidget:SettingsCheckBoxControl") then return end

  SkinCheckButton(core, theme, frame.CheckBox)
  if frame.Label and frame.Label.SetTextColor then
    local cc = GetThemeColors(theme)
    frame.Label:SetTextColor(cc.text.r, cc.text.g, cc.text.b, cc.text.a)
  end

  core:StatInc(Module.name, "settingsCheckBox", 1)
end

local function SkinEditBox(core, theme, eb)
  if not eb or not eb.GetObjectType or eb:GetObjectType() ~= "EditBox" then return end
  local wrapper = (eb.GetParent and eb:GetParent()) or eb
  if wrapper and wrapper.GetObjectType and wrapper:GetObjectType() ~= "Frame" then wrapper = eb end
  if not core:FrameOnce(wrapper, "RSWidget:EditBox2") then return end
  local cc = GetThemeColors(theme)

  -- Three-piece wrappers
  if wrapper.Left and wrapper.Middle and wrapper.Right then
    SetVertex(wrapper.Left, cc.border)
    SetVertex(wrapper.Middle, cc.inset)
    SetVertex(wrapper.Right, cc.border)
  end

  if wrapper.SetBackdrop then
    wrapper:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    wrapper:SetBackdropColor(cc.inset.r, cc.inset.g, cc.inset.b, cc.inset.a)
    wrapper:SetBackdropBorderColor(cc.border.r, cc.border.g, cc.border.b, cc.border.a)
  end

  core:StatInc(Module.name, "editBoxes", 1)
end

local function SkinSlider(core, theme, slider)
  if not slider or not slider.GetObjectType or slider:GetObjectType() ~= "Slider" then return end
  if not core:FrameOnce(slider, "RSWidget:Slider") then return end
  local cc = GetThemeColors(theme)

  local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
  if thumb then
    if thumb.SetColorTexture then
      thumb:SetColorTexture(cc.border.r, cc.border.g, cc.border.b, 0.9)
    elseif thumb.SetVertexColor then
      thumb:SetVertexColor(cc.border.r, cc.border.g, cc.border.b, 0.9)
    end
  end

  -- Common templates: Backdrop/Track
  if slider.Backdrop and slider.Backdrop.SetBackdropColor then
    slider.Backdrop:SetBackdropColor(cc.inset.r, cc.inset.g, cc.inset.b, cc.inset.a)
  end

  core:StatInc(Module.name, "sliders", 1)
end

local function WalkChildrenBudget(frame, maxDepth, budget, fn)
  if not frame or maxDepth <= 0 or budget <= 0 then return budget end
  local children = { frame:GetChildren() }
  for _, ch in ipairs(children) do
    if budget <= 0 then break end
    budget = budget - 1
    fn(ch)
    budget = WalkChildrenBudget(ch, maxDepth - 1, budget, fn)
  end
  return budget
end

local function SkinTree(core, theme, root)
  if not root then return end

  local budget = 1400
  budget = WalkChildrenBudget(root, 6, budget, function(obj)
    if not obj or not obj.GetObjectType then return end
    local t = obj:GetObjectType()
    if t == "Button" then
      SkinButton(core, theme, obj)
      SkinThreePiece(core, theme, obj)
    elseif t == "CheckButton" then
      SkinCheckButton(core, theme, obj)
    elseif t == "EditBox" then
      SkinEditBox(core, theme, obj)
    elseif t == "Slider" then
      SkinSlider(core, theme, obj)
    elseif t == "Frame" then
      SkinSettingsCheckBoxControl(core, theme, obj)

      -- Dropdown/selector wrappers (often Left/Middle/Right)
      if obj.Left and obj.Middle and obj.Right then
        SkinThreePiece(core, theme, obj)
      end

      -- NineSlice insets inside settings
      if obj.NineSlice then
        local cc = GetThemeColors(theme)
        core:ColorNineSlice(obj, cc.border.r, cc.border.g, cc.border.b, cc.border.a)
      end
    end
  end)

  core:Trace(Module.name, "scan", (root.GetName and root:GetName()) or tostring(root), "budgetLeft=", budget)
end

local function HookTargets(core)
  local theme = core:GetTheme()

  -- New Settings UI (Retail)
  if _G.SettingsPanel then
    core:HookOnShow(_G.SettingsPanel, "SettingsPanelControls", function(panel)
      local st = core:GetStats(Module.name)
      if st then st.counters = {} end
      SkinTree(core, core:GetTheme(), panel)
    end)
  end

  -- Legacy options (still present in some branches)
  if _G.InterfaceOptionsFrame then
    core:HookOnShow(_G.InterfaceOptionsFrame, "InterfaceOptionsControls", function(panel)
      local st = core:GetStats(Module.name)
      if st then st.counters = {} end
      SkinTree(core, core:GetTheme(), panel)
    end)
  end
end

function Module:OnEnable(core)
  core:Claim("Widgets:Controls", self.name)
  HookTargets(core)
end

function Module:OnAddonLoaded(core)
  core:Throttle("WidgetsControls:Rehook", 0.05, function()
    HookTargets(core)
  end)
end

function Module:OnThemeChanged(core)
  -- Clear markers so controls recolor on next show.
  if _G.SettingsPanel and _G.SettingsPanel.__RothSkinner then
    _G.SettingsPanel.__RothSkinner["RSWidget:Panel"] = nil
  end
end

function Module:OnEvent(core, event)
  if event == "PLAYER_LOGIN" then
    HookTargets(core)
  end
end

RS:RegisterModule(Module.name, Module)
