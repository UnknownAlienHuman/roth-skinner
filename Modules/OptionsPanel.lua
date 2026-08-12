--[[
Module: OptionsPanel

Purpose
- Add Roth Skinner configuration into Blizzard settings UI.

Requirements
- Retail 12.0+ (Settings UI exists).
- Fallback to InterfaceOptions for older clients (kept, but not expected in 12.0).

Notes
- This module is intentionally lightweight and does not depend on Ace3.
- Uses core APIs for module enable/disable, theme switching, debug/trace.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "OptionsPanel",
  version = "0.6.0",
  priority = 2,
  enabledByDefault = true,
  events = { "PLAYER_LOGIN" },
}

local Panel
local Controls = {}

local function CreateTitle(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", 16, -16)
  fs:SetText(text)
  return fs
end

local function CreateSubTitle(parent, text, anchor)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
  fs:SetText(text)
  return fs
end

local function CreateCheckbox(parent, label)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb.Text:SetText(label)
  return cb
end

local function CreateButton(parent, label, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetText(label)
  b:SetSize(w or 140, 22)
  return b
end

local function CreateDropdown(parent)
  local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  return dd
end

local function EnsurePanel(core)
  if Panel then return Panel end

  local p = CreateFrame("Frame", "RothSkinnerOptionsPanel", UIParent)
  p.name = "Roth Skinner"
  p:Hide()

  local title = CreateTitle(p, "Roth Skinner")

  local intro = p:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  intro:SetText("Global skin framework for Blizzard UI (themes + modules).\nUse this panel to toggle modules and switch theme.\nCombat lockdown: changes may be queued until leaving combat.")

  -- Theme
  local themeLabel = CreateSubTitle(p, "Theme", intro)
  local dd = CreateDropdown(p)
  dd:SetPoint("TOPLEFT", themeLabel, "BOTTOMLEFT", -8, -6)
  Controls.themeDropdown = dd

  -- Debug
  local dbg = CreateCheckbox(p, "Enable debug log")
  dbg:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 16, -8)
  dbg:SetScript("OnClick", function(self)
    core.db.profile.debug = self:GetChecked() and true or false
    core:Log("Debug:", core.db.profile.debug and "ON" or "OFF")
  end)
  Controls.debug = dbg

  -- Buttons row
  local applyBtn = CreateButton(p, "Apply now", 120)
  applyBtn:SetPoint("TOPLEFT", dbg, "BOTTOMLEFT", 0, -10)
  applyBtn:SetScript("OnClick", function()
    core:ApplyAll()
  end)
  Controls.apply = applyBtn

  local logBtn = CreateButton(p, "Open log", 120)
  logBtn:SetPoint("LEFT", applyBtn, "RIGHT", 8, 0)
  logBtn:SetScript("OnClick", function()
    if _G.RothSkinnerLogViewer then
      if _G.RothSkinnerLogViewer:IsShown() then _G.RothSkinnerLogViewer:Hide() else _G.RothSkinnerLogViewer:Show() end
    else
      core:Log("Use /rslog to open the log viewer (DevTools module)")
    end
  end)
  Controls.log = logBtn

  local clearBtn = CreateButton(p, "Clear core log", 140)
  clearBtn:SetPoint("LEFT", logBtn, "RIGHT", 8, 0)
  clearBtn:SetScript("OnClick", function()
    core:ClearLog()
  end)
  Controls.clear = clearBtn

  local resetBtn = CreateButton(p, "Reset session errors", 170)
  resetBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
  resetBtn:SetScript("OnClick", function()
    core:ResetSessionDisables()
    core:Log("Session error state cleared.")
    if Controls.refresh then Controls.refresh(core) end
  end)
  Controls.reset = resetBtn

  -- Modules section
  local modLabel = CreateSubTitle(p, "Modules", applyBtn)

  local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", modLabel, "BOTTOMLEFT", 0, -6)
  scroll:SetPoint("BOTTOMRIGHT", -34, 16)
  Controls.scroll = scroll

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  Controls.content = content

  p:SetScript("OnShow", function()
    if Controls.refresh then Controls.refresh(core) end
  end)

  Panel = p
  return p
end

local function RegisterInBlizzardSettings(core)
  local p = EnsurePanel(core)

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local category = Settings.RegisterCanvasLayoutCategory(p, p.name)
    category.ID = p.name
    Settings.RegisterAddOnCategory(category)
    core:Trace(Module.name, "Registered via Settings API")
    return
  end

  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(p)
    core:Trace(Module.name, "Registered via InterfaceOptions")
  end
end

local function RebuildModuleList(core)
  local content = Controls.content
  if not content then return end

  -- Clear previous rows
  if Controls.rows then
    for _, r in ipairs(Controls.rows) do
      if r and r.Hide then r:Hide() end
      if r and r.SetParent then r:SetParent(nil) end
    end
  end
  Controls.rows = {}

  local y = 0
  local rowH = 22

  for _, name in ipairs(core:GetModuleNames()) do
    if name ~= Module.name then
      local row = CreateFrame("Frame", nil, content)
      row:SetSize(520, rowH)
      row:SetPoint("TOPLEFT", 0, -y)
      y = y + rowH + 6

      local enable = CreateCheckbox(row, "")
      enable:SetPoint("LEFT", 0, 0)
      enable:SetSize(24, 24)

      local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      label:SetPoint("LEFT", enable, "RIGHT", 4, 0)
      label:SetText(name)

      local trace = CreateCheckbox(row, "Trace")
      trace:SetPoint("LEFT", label, "RIGHT", 18, 0)

      local stats = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
      stats:SetPoint("LEFT", trace.Text, "RIGHT", 14, 0)
      stats:SetText("")

      enable:SetScript("OnClick", function(self)
        if self:GetChecked() then
          core:EnableModule(name)
        else
          core:DisableModule(name)
        end
        if Controls.refresh then Controls.refresh(core) end
      end)

      trace:SetScript("OnClick", function(self)
        core.db.profile.trace[name] = self:GetChecked() and true or false
        core:Log("Trace", name .. ":", core.db.profile.trace[name] and "ON" or "OFF")
      end)

      Controls.rows[#Controls.rows + 1] = {
        frame = row,
        name = name,
        enable = enable,
        trace = trace,
        stats = stats,
        label = label,
      }
    end
  end

  content:SetHeight(y + 10)
  content:SetWidth(520)
end

local function RefreshUI(core)
  if not Panel then return end

  -- Theme dropdown
  local dd = Controls.themeDropdown
  if dd then
    local themes = core:GetThemeNames()
    UIDropDownMenu_Initialize(dd, function(self)
      for _, name in ipairs(themes) do
        local info = UIDropDownMenu_CreateInfo()
        info.text = name
        info.value = name
        info.func = function()
          UIDropDownMenu_SetSelectedValue(dd, name)
          core:SetActiveTheme(name)
        end
        UIDropDownMenu_AddButton(info)
      end
    end)
    UIDropDownMenu_SetWidth(dd, 180)
    UIDropDownMenu_SetSelectedValue(dd, core:GetThemeName() or themes[1])
  end

  -- Debug
  if Controls.debug then
    Controls.debug:SetChecked(core.db.profile.debug and true or false)
  end

  -- Module list
  if not Controls.rows then
    RebuildModuleList(core)
  end

  if Controls.rows then
    for _, r in ipairs(Controls.rows) do
      local enabled = core:IsModuleEnabled(r.name)
      r.enable:SetChecked(enabled)
      r.trace:SetChecked(core.db.profile.trace[r.name] and true or false)
      local h = core:GetModuleHealth(r.name)
      local st = core:GetStats(r.name)
      local ms = st and st.lastApplyMS

      local parts = {}
      if h and h.disabled then
        parts[#parts+1] = string.format("AUTO-DISABLED (%d/%d)", h.errors or 0, h.limit or 3)
      elseif ms then
        parts[#parts+1] = string.format("%.1fms", ms)
      end
      if h and (h.errors or 0) > 0 and not h.disabled then
        parts[#parts+1] = string.format("err:%d/%d", h.errors or 0, h.limit or 3)
      end

      r.stats:SetText(table.concat(parts, " | "))

      if r.label and r.label.SetTextColor then
        if h and h.disabled then
          r.label:SetTextColor(1, 0.35, 0.25)
        else
          r.label:SetTextColor(0.9, 0.9, 0.9)
        end
      end
    end
  end
end

function Module:OnEnable(core)
  core:Claim("Config:OptionsPanel", self.name)
  RegisterInBlizzardSettings(core)
  Controls.refresh = RefreshUI
  RefreshUI(core)
end

function Module:OnEvent(core, event)
  if event == "PLAYER_LOGIN" then
    -- Ensure themes/modules are fully registered before building UI.
    C_Timer.After(0, function()
      EnsurePanel(core)
      RebuildModuleList(core)
      RefreshUI(core)
    end)
  end
end

RS:RegisterModule(Module.name, Module)
