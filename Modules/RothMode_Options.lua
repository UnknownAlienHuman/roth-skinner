--[[
Module: RothMode_Options

Purpose
- Add a dedicated "Roth Mode" configuration page to Blizzard Settings.
- Provide:
  - grouped controls (no UI mess)
  - scrollable layout
  - color pickers (ColorPickerFrame wheel) + HEX input
  - gradient controls + preview

Notes
- Does not depend on Ace3.
- Writes to RS.db.profile.rothmode.
--]]

local _, ns = ...
local RS = (ns and ns.RothSkinner) or _G.RothSkinner
if not RS then return end

local Module = {
  name = "RothMode_Options",
  version = "0.5.0",
  priority = 3,
  enabledByDefault = true,
  events = { "PLAYER_LOGIN" },
}

local Panel
local UI = {}

-- -----------------------------------------------------------------------------
-- Small utilities
-- -----------------------------------------------------------------------------

local function Clamp01(x)
  x = tonumber(x) or 0
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function GetCfg(core)
  local p = core.db and core.db.profile
  p.rothmode = p.rothmode or {}
  p.rothmode.colors = p.rothmode.colors or {}
  p.rothmode.gradient = p.rothmode.gradient or {}
  return p.rothmode
end

local function RGBToHex(r, g, b)
  r = math.floor(Clamp01(r) * 255 + 0.5)
  g = math.floor(Clamp01(g) * 255 + 0.5)
  b = math.floor(Clamp01(b) * 255 + 0.5)
  return string.format("%02X%02X%02X", r, g, b)
end

local function HexToRGB(hex)
  if not hex then return nil end
  hex = tostring(hex):gsub("#", "")
  if #hex ~= 6 then return nil end
  local r = tonumber(hex:sub(1, 2), 16)
  local g = tonumber(hex:sub(3, 4), 16)
  local b = tonumber(hex:sub(5, 6), 16)
  if not r or not g or not b then return nil end
  return r / 255, g / 255, b / 255
end

local function OpenColorPicker(initial, onChanged)
  if not (ColorPickerFrame and onChanged) then return end

  local r = initial.r or 1
  local g = initial.g or 1
  local b = initial.b or 1
  local a = (initial.a ~= nil) and initial.a or 1

  -- Modern API (preferred)
  if ColorPickerFrame.SetupColorPickerAndShow then
    local function GetA()
      if ColorPickerFrame.GetColorAlpha then
        return 1 - (ColorPickerFrame:GetColorAlpha() or 0)
      end
      return a
    end
    local info = {
      r = r,
      g = g,
      b = b,
      opacity = 1 - a,
      hasOpacity = true,
      swatchFunc = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = GetA()
        onChanged(nr, ng, nb, na)
      end,
      opacityFunc = function()
        local nr, ng, nb = ColorPickerFrame:GetColorRGB()
        local na = GetA()
        onChanged(nr, ng, nb, na)
      end,
      cancelFunc = function(prev)
        if prev then
          local na = 1 - (prev.opacity or 0)
          onChanged(prev.r, prev.g, prev.b, na)
        end
      end,
    }
    ColorPickerFrame:SetupColorPickerAndShow(info)
    return
  end

  -- Legacy API fallback
  ColorPickerFrame.hasOpacity = true
  ColorPickerFrame.opacity = 1 - a
  ColorPickerFrame.previousValues = { r = r, g = g, b = b, opacity = 1 - a }

  ColorPickerFrame.func = function()
    local nr, ng, nb = ColorPickerFrame:GetColorRGB()
    local na = 1 - (OpacitySliderFrame and OpacitySliderFrame:GetValue() or 0)
    onChanged(nr, ng, nb, na)
  end
  ColorPickerFrame.opacityFunc = ColorPickerFrame.func
  ColorPickerFrame.cancelFunc = function(prev)
    if prev then
      local na = 1 - (prev.opacity or 0)
      onChanged(prev.r, prev.g, prev.b, na)
    end
  end

  ColorPickerFrame:SetColorRGB(r, g, b)
  ColorPickerFrame:Hide()
  ColorPickerFrame:Show()
end

local function RequestApply(core)
  core:Throttle("RothMode_Options:Apply", 0.05, function()
    core:ApplyAll()
  end)
end

-- -----------------------------------------------------------------------------
-- Widgets
-- -----------------------------------------------------------------------------

local function CreateTitle(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", 16, -16)
  fs:SetText(text)
  return fs
end

local function CreateHint(parent, anchor, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)
  return fs
end

local function CreateSectionHeader(parent, anchor, text)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(22)
  f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -14)
  f:SetPoint("RIGHT", -16, 0)

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)
  f.__bg = bg

  local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("LEFT", 8, 0)
  fs:SetText(text)
  f.__text = fs

  return f
end

local function CreateCheckbox(parent, label)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb.Text:SetText(label)
  return cb
end

local function CreateSlider(parent, label, minV, maxV, step)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(520, 40)

  local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", 0, 0)
  fs:SetText(label)

  local sl = CreateFrame("Slider", nil, f, "OptionsSliderTemplate")
  sl:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -6)
  sl:SetMinMaxValues(minV, maxV)
  sl:SetValueStep(step or 0.01)
  sl:SetObeyStepOnDrag(true)
  sl:SetWidth(320)
  sl.Low:SetText(tostring(minV))
  sl.High:SetText(tostring(maxV))

  local val = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  val:SetPoint("LEFT", sl, "RIGHT", 12, 0)
  val:SetText("")

  f.label = fs
  f.slider = sl
  f.valueText = val

  return f
end

local function CreateDropdown(parent, label)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(520, 44)

  local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", 0, 0)
  fs:SetText(label)

  local dd = CreateFrame("Frame", nil, f, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", -10, -4)

  f.label = fs
  f.dropdown = dd
  return f
end

local function CreateColorRow(parent, label)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(520, 26)

  local fs = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("LEFT", 0, 0)
  fs:SetText(label)

  local sw = CreateFrame("Button", nil, f)
  sw:SetSize(20, 20)
  sw:SetPoint("LEFT", fs, "RIGHT", 12, 0)

  local swBg = sw:CreateTexture(nil, "BACKGROUND")
  swBg:SetAllPoints()
  swBg:SetColorTexture(1, 1, 1, 1)

  local swBorder = sw:CreateTexture(nil, "BORDER")
  swBorder:SetPoint("TOPLEFT", -1, 1)
  swBorder:SetPoint("BOTTOMRIGHT", 1, -1)
  swBorder:SetColorTexture(0, 0, 0, 1)

  local hex = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  hex:SetAutoFocus(false)
  hex:SetSize(90, 20)
  hex:SetPoint("LEFT", sw, "RIGHT", 10, 0)
  hex:SetText("FFFFFF")

  local a = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
  a:SetAutoFocus(false)
  a:SetSize(50, 20)
  a:SetPoint("LEFT", hex, "RIGHT", 10, 0)
  a:SetText("1.00")

  local alphaLabel = f:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  alphaLabel:SetPoint("LEFT", a, "RIGHT", 6, 0)
  alphaLabel:SetText("A")

  f.label = fs
  f.swatch = sw
  f.swatchTex = swBg
  f.hex = hex
  f.alpha = a
  f._value = { r = 1, g = 1, b = 1, a = 1 }

  return f
end

local function CreateGradientPreview(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(520, 34)

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.55)

  local g = f:CreateTexture(nil, "ARTWORK")
  g:SetAllPoints()
  g:SetColorTexture(1, 1, 1, 1)

  f.bg = bg
  f.grad = g
  return f
end

-- -----------------------------------------------------------------------------
-- Panel build / bind
-- -----------------------------------------------------------------------------

local function EnsurePanel(core)
  if Panel then return Panel end

  local p = CreateFrame("Frame", "RothSkinnerRothModeOptions", UIParent)
  p.name = "Roth Skinner: Roth Mode"
  p:Hide()

  local title = CreateTitle(p, "Roth Mode")
  local hint = CreateHint(p, title, "Global recolor/reskin policy for Blizzard UI widgets.\nChanges apply immediately; some frames re-skin on next show.")

  -- Scroll container
  local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -12)
  scroll:SetPoint("BOTTOMRIGHT", -34, 14)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)

  UI.scroll = scroll
  UI.content = content

  local yAnchor = content
  local function Place(w)
    w:SetPoint("TOPLEFT", yAnchor, "TOPLEFT", 0, (yAnchor == content) and 0 or -8)
    yAnchor = w
  end

  -- -------------------------------------------------------------------------
  -- General
  -- -------------------------------------------------------------------------
  local genHdr = CreateSectionHeader(content, content, "General")
  Place(genHdr)

  local enabled = CreateCheckbox(content, "Enable Roth Mode global reskin")
  enabled:SetPoint("TOPLEFT", genHdr, "BOTTOMLEFT", 8, -8)
  yAnchor = enabled
  UI.enabled = enabled

  local desat = CreateCheckbox(content, "Desaturate affected textures (where supported)")
  desat:SetPoint("TOPLEFT", enabled, "BOTTOMLEFT", 0, -6)
  yAnchor = desat
  UI.desaturate = desat

  local intensity = CreateSlider(content, "Intensity (darkness multiplier)", 0.20, 1.00, 0.01)
  intensity:SetPoint("TOPLEFT", desat, "BOTTOMLEFT", -8, -10)
  yAnchor = intensity
  UI.intensity = intensity

  local covHdr = CreateSectionHeader(content, intensity, "Coverage")
  Place(covHdr)

  local cPanels = CreateCheckbox(content, "Panels (UIPanelWindows)")
  cPanels:SetPoint("TOPLEFT", covHdr, "BOTTOMLEFT", 8, -8)
  yAnchor = cPanels
  UI.cPanels = cPanels

  local cButtons = CreateCheckbox(content, "Buttons (UIPanelButtonTemplate / 3-piece)")
  cButtons:SetPoint("TOPLEFT", cPanels, "BOTTOMLEFT", 0, -6)
  yAnchor = cButtons
  UI.cButtons = cButtons

  local cControls = CreateCheckbox(content, "Controls (checkboxes, sliders, editboxes)")
  cControls:SetPoint("TOPLEFT", cButtons, "BOTTOMLEFT", 0, -6)
  yAnchor = cControls
  UI.cControls = cControls

  local cDropdowns = CreateCheckbox(content, "Dropdown lists (UIDropDownMenu)")
  cDropdowns:SetPoint("TOPLEFT", cControls, "BOTTOMLEFT", 0, -6)
  yAnchor = cDropdowns
  UI.cDropdowns = cDropdowns

  local cPopups = CreateCheckbox(content, "Popups (StaticPopup, GameMenu, ColorPicker)")
  cPopups:SetPoint("TOPLEFT", cDropdowns, "BOTTOMLEFT", 0, -6)
  yAnchor = cPopups
  UI.cPopups = cPopups

  local cTooltips = CreateCheckbox(content, "Tooltips (GameTooltip and friends)")
  cTooltips:SetPoint("TOPLEFT", cPopups, "BOTTOMLEFT", 0, -6)
  yAnchor = cTooltips
  UI.cTooltips = cTooltips

  local cSpecial = CreateCheckbox(content, "Also skin UISpecialFrames (ESC-closable dialogs)")
  cSpecial:SetPoint("TOPLEFT", cTooltips, "BOTTOMLEFT", 0, -6)
  yAnchor = cSpecial
  UI.cSpecial = cSpecial

  -- -------------------------------------------------------------------------
  -- Palette
  -- -------------------------------------------------------------------------
  local palHdr = CreateSectionHeader(content, cSpecial, "Palette")
  Place(palHdr)

  local useTheme = CreateCheckbox(content, "Use active theme tokens (recommended)")
  useTheme:SetPoint("TOPLEFT", palHdr, "BOTTOMLEFT", 8, -8)
  yAnchor = useTheme
  UI.useTheme = useTheme

  local borderRow = CreateColorRow(content, "Border")
  borderRow:SetPoint("TOPLEFT", useTheme, "BOTTOMLEFT", -8, -10)
  yAnchor = borderRow
  UI.borderRow = borderRow

  local bgRow = CreateColorRow(content, "Background")
  bgRow:SetPoint("TOPLEFT", borderRow, "BOTTOMLEFT", 0, -8)
  yAnchor = bgRow
  UI.bgRow = bgRow

  local insetRow = CreateColorRow(content, "Inset")
  insetRow:SetPoint("TOPLEFT", bgRow, "BOTTOMLEFT", 0, -8)
  yAnchor = insetRow
  UI.insetRow = insetRow

  local accentRow = CreateColorRow(content, "Accent / hover")
  accentRow:SetPoint("TOPLEFT", insetRow, "BOTTOMLEFT", 0, -8)
  yAnchor = accentRow
  UI.accentRow = accentRow

  -- -------------------------------------------------------------------------
  -- Gradient
  -- -------------------------------------------------------------------------
  local gradHdr = CreateSectionHeader(content, accentRow, "Gradient")
  Place(gradHdr)

  local gEnable = CreateCheckbox(content, "Enable gradient overlay on panels")
  gEnable:SetPoint("TOPLEFT", gradHdr, "BOTTOMLEFT", 8, -8)
  yAnchor = gEnable
  UI.gEnable = gEnable

  local gFrom = CreateColorRow(content, "Gradient from")
  gFrom:SetPoint("TOPLEFT", gEnable, "BOTTOMLEFT", -8, -10)
  yAnchor = gFrom
  UI.gFrom = gFrom

  local gTo = CreateColorRow(content, "Gradient to")
  gTo:SetPoint("TOPLEFT", gFrom, "BOTTOMLEFT", 0, -8)
  yAnchor = gTo
  UI.gTo = gTo

  local gOri = CreateDropdown(content, "Orientation")
  gOri:SetPoint("TOPLEFT", gTo, "BOTTOMLEFT", 0, -10)
  yAnchor = gOri
  UI.gOri = gOri

  local preview = CreateGradientPreview(content)
  preview:SetPoint("TOPLEFT", gOri, "BOTTOMLEFT", 0, -10)
  yAnchor = preview
  UI.preview = preview

  local gApplyPanels = CreateCheckbox(content, "Apply gradient to panels")
  gApplyPanels:SetPoint("TOPLEFT", preview, "BOTTOMLEFT", 8, -10)
  yAnchor = gApplyPanels
  UI.gApplyPanels = gApplyPanels

  local gApplyPopups = CreateCheckbox(content, "Also apply gradient to popups")
  gApplyPopups:SetPoint("TOPLEFT", gApplyPanels, "BOTTOMLEFT", 0, -6)
  yAnchor = gApplyPopups
  UI.gApplyPopups = gApplyPopups

  local gApplyButtons = CreateCheckbox(content, "Also apply gradient to buttons")
  gApplyButtons:SetPoint("TOPLEFT", gApplyPopups, "BOTTOMLEFT", 0, -6)
  yAnchor = gApplyButtons
  UI.gApplyButtons = gApplyButtons

  -- -------------------------------------------------------------------------
  -- Actions
  -- -------------------------------------------------------------------------
  local actHdr = CreateSectionHeader(content, gApplyButtons, "Actions")
  Place(actHdr)

  local applyNow = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  applyNow:SetSize(140, 22)
  applyNow:SetText("Apply now")
  applyNow:SetPoint("TOPLEFT", actHdr, "BOTTOMLEFT", 8, -10)
  yAnchor = applyNow
  UI.applyNow = applyNow

  local reset = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  reset:SetSize(180, 22)
  reset:SetText("Reset overrides")
  reset:SetPoint("LEFT", applyNow, "RIGHT", 10, 0)
  UI.reset = reset

  -- Content size
  content:SetHeight(1100)
  content:SetWidth(520)

  Panel = p
  return p
end

-- -----------------------------------------------------------------------------
-- Binding / refresh
-- -----------------------------------------------------------------------------

local function SetColorRow(row, c)
  c = c or row._value
  row._value.r = Clamp01(c.r or 1)
  row._value.g = Clamp01(c.g or 1)
  row._value.b = Clamp01(c.b or 1)
  row._value.a = Clamp01((c.a ~= nil) and c.a or 1)

  row.swatchTex:SetColorTexture(row._value.r, row._value.g, row._value.b, 1)
  row.hex:SetText(RGBToHex(row._value.r, row._value.g, row._value.b))
  row.alpha:SetText(string.format("%.2f", row._value.a))
end

local function BindColorRow(core, row, getter, setter)
  local function Commit(r, g, b, a)
    local c = getter()
    c.r, c.g, c.b, c.a = Clamp01(r), Clamp01(g), Clamp01(b), Clamp01(a)
    setter(c)
    SetColorRow(row, c)
    RequestApply(core)
  end

  row.swatch:SetScript("OnClick", function()
    OpenColorPicker(getter(), Commit)
  end)

  row.hex:SetScript("OnEnterPressed", function(self)
    local r, g, b = HexToRGB(self:GetText())
    if r then
      local a = tonumber(row.alpha:GetText()) or getter().a or 1
      Commit(r, g, b, Clamp01(a))
    else
      SetColorRow(row, getter())
    end
    self:ClearFocus()
  end)

  row.alpha:SetScript("OnEnterPressed", function(self)
    local a = Clamp01(tonumber(self:GetText()) or 1)
    local c = getter()
    Commit(c.r or 1, c.g or 1, c.b or 1, a)
    self:ClearFocus()
  end)
end

local function UpdateGradientPreview(core)
  local cfg = GetCfg(core)
  local g = cfg.gradient or {}
  local from = g.from or { r = 0, g = 0, b = 0, a = 0 }
  local to = g.to or { r = 0, g = 0, b = 0, a = 0.22 }
  local ori = g.orientation or "VERTICAL"

  if UI.preview and UI.preview.grad and UI.preview.grad.SetGradientAlpha then
    UI.preview.grad:SetGradientAlpha(ori, from.r or 0, from.g or 0, from.b or 0, from.a or 0, to.r or 0, to.g or 0, to.b or 0, to.a or 0)
  end
end

local function RefreshUI(core)
  local cfg = GetCfg(core)

  UI.enabled:SetChecked(cfg.enabled and true or false)
  UI.desaturate:SetChecked(cfg.desaturate and true or false)

  UI.intensity.slider:SetValue(tonumber(cfg.intensity) or 0.85)
  UI.intensity.valueText:SetText(string.format("%.2f", tonumber(cfg.intensity) or 0.85))

  UI.cPanels:SetChecked(cfg.panels ~= false)
  UI.cButtons:SetChecked(cfg.buttons and true or false)
  UI.cControls:SetChecked(cfg.controls and true or false)
  UI.cDropdowns:SetChecked(cfg.dropdowns and true or false)
  UI.cPopups:SetChecked(cfg.popups and true or false)
  UI.cTooltips:SetChecked(cfg.tooltips ~= false)
  UI.cSpecial:SetChecked(cfg.specialFrames and true or false)

  local colors = cfg.colors or {}
  UI.useTheme:SetChecked(colors.useTheme ~= false)

  SetColorRow(UI.borderRow, colors.border)
  SetColorRow(UI.bgRow, colors.bg)
  SetColorRow(UI.insetRow, colors.inset)
  SetColorRow(UI.accentRow, colors.accent)

  local grad = cfg.gradient or {}
  UI.gEnable:SetChecked(grad.enabled and true or false)
  SetColorRow(UI.gFrom, grad.from)
  SetColorRow(UI.gTo, grad.to)
  UI.gApplyPanels:SetChecked(grad.applyToPanels ~= false)
  UI.gApplyPopups:SetChecked(grad.applyToPopups and true or false)
  UI.gApplyButtons:SetChecked(grad.applyToButtons and true or false)

  UIDropDownMenu_Initialize(UI.gOri.dropdown, function(self)
    local function Add(val, text)
      local info = UIDropDownMenu_CreateInfo()
      info.text = text
      info.value = val
      info.func = function()
        grad.orientation = val
        UIDropDownMenu_SetSelectedValue(UI.gOri.dropdown, val)
        cfg.gradient = grad
        UpdateGradientPreview(core)
        RequestApply(core)
      end
      UIDropDownMenu_AddButton(info)
    end
    Add("VERTICAL", "Vertical")
    Add("HORIZONTAL", "Horizontal")
  end)
  UIDropDownMenu_SetWidth(UI.gOri.dropdown, 140)
  UIDropDownMenu_SetSelectedValue(UI.gOri.dropdown, grad.orientation or "VERTICAL")

  UpdateGradientPreview(core)
end

local function Bind(core)
  local cfg = GetCfg(core)

  UI.enabled:SetScript("OnClick", function(self)
    cfg.enabled = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.desaturate:SetScript("OnClick", function(self)
    cfg.desaturate = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.intensity.slider:SetScript("OnValueChanged", function(self, v)
    cfg.intensity = Clamp01(v)
    UI.intensity.valueText:SetText(string.format("%.2f", cfg.intensity))
    RequestApply(core)
  end)

  UI.cPanels:SetScript("OnClick", function(self)
    cfg.panels = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.cButtons:SetScript("OnClick", function(self)
    cfg.buttons = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.cControls:SetScript("OnClick", function(self)
    cfg.controls = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.cDropdowns:SetScript("OnClick", function(self)
    cfg.dropdowns = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.cPopups:SetScript("OnClick", function(self)
    cfg.popups = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.cTooltips:SetScript("OnClick", function(self)
    cfg.tooltips = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.cSpecial:SetScript("OnClick", function(self)
    cfg.specialFrames = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.useTheme:SetScript("OnClick", function(self)
    cfg.colors.useTheme = self:GetChecked() and true or false
    RequestApply(core)
  end)

  BindColorRow(core, UI.borderRow, function() cfg.colors.border = cfg.colors.border or { r = 0.40, g = 0.08, b = 0.06, a = 0.90 }; return cfg.colors.border end, function(c) cfg.colors.border = c end)
  BindColorRow(core, UI.bgRow,     function() cfg.colors.bg = cfg.colors.bg or { r = 0.06, g = 0.06, b = 0.065, a = 0.55 }; return cfg.colors.bg end, function(c) cfg.colors.bg = c end)
  BindColorRow(core, UI.insetRow,  function() cfg.colors.inset = cfg.colors.inset or { r = 0.00, g = 0.00, b = 0.00, a = 0.18 }; return cfg.colors.inset end, function(c) cfg.colors.inset = c end)
  BindColorRow(core, UI.accentRow, function() cfg.colors.accent = cfg.colors.accent or { r = 1.00, g = 0.36, b = 0.16, a = 0.18 }; return cfg.colors.accent end, function(c) cfg.colors.accent = c end)

  UI.gEnable:SetScript("OnClick", function(self)
    cfg.gradient.enabled = self:GetChecked() and true or false
    UpdateGradientPreview(core)
    RequestApply(core)
  end)

  BindColorRow(core, UI.gFrom, function() cfg.gradient.from = cfg.gradient.from or { r = 0.00, g = 0.00, b = 0.00, a = 0.00 }; return cfg.gradient.from end, function(c) cfg.gradient.from = c end)
  BindColorRow(core, UI.gTo,   function() cfg.gradient.to = cfg.gradient.to or { r = 0.00, g = 0.00, b = 0.00, a = 0.22 }; return cfg.gradient.to end, function(c) cfg.gradient.to = c end)

  UI.gApplyPanels:SetScript("OnClick", function(self)
    cfg.gradient.applyToPanels = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.gApplyPopups:SetScript("OnClick", function(self)
    cfg.gradient.applyToPopups = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.gApplyButtons:SetScript("OnClick", function(self)
    cfg.gradient.applyToButtons = self:GetChecked() and true or false
    RequestApply(core)
  end)

  UI.applyNow:SetScript("OnClick", function()
    core:ApplyAll()
  end)

  UI.reset:SetScript("OnClick", function()
    cfg.colors.useTheme = true
    cfg.colors.border = nil
    cfg.colors.bg = nil
    cfg.colors.inset = nil
    cfg.colors.accent = nil
    cfg.gradient = cfg.gradient or {}
    cfg.gradient.enabled = true
    cfg.gradient.orientation = "VERTICAL"
    cfg.gradient.applyToPanels = true
    cfg.gradient.applyToPopups = false
    cfg.gradient.applyToButtons = false
    cfg.gradient.from = { r = 0.00, g = 0.00, b = 0.00, a = 0.00 }
    cfg.gradient.to = { r = 0.00, g = 0.00, b = 0.00, a = 0.22 }
    RefreshUI(core)
    RequestApply(core)
  end)
end

local function RegisterCategory(core)
  local p = EnsurePanel(core)

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(p, p.name)
    category.ID = p.name
    Settings.RegisterAddOnCategory(category)
    return true
  end

  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(p)
    return true
  end

  return false
end

function Module:OnEnable(core)
  EnsurePanel(core)
  RegisterCategory(core)
  Bind(core)
  Panel:SetScript("OnShow", function()
    RefreshUI(core)
  end)
end

RS:RegisterModule(Module.name, Module)
