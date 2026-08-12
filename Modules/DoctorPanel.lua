--[[
Module: DoctorPanel

Purpose
- In-game diagnostics for Roth_Skinner.
- Shows module health (errors / session disables), basic performance, and export/import.

Constraints
- No external dependencies.
- Safe to open in combat: mutating actions are routed through core (queue).
--]]

local _, ns = ...
local RS = (ns and ns.RothSkinner) or _G.RothSkinner
if not RS then return end

local Module = {
  name = "DoctorPanel",
  version = "0.6.1",
  priority = 5,
  enabledByDefault = true,
  events = { "PLAYER_LOGIN" },
}

local Panel
local Controls = {}

-- -----------------------------------------------------------------------------
-- UI helpers
-- -----------------------------------------------------------------------------

local function CreateTitle(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  fs:SetText(text)
  fs:SetJustifyH("LEFT")
  return fs
end

local function CreateSubTitle(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetText(text)
  fs:SetJustifyH("LEFT")
  return fs
end

local function CreateText(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  fs:SetText(text)
  fs:SetJustifyH("LEFT")
  fs:SetJustifyV("TOP")
  fs:SetNonSpaceWrap(true)
  fs:SetWordWrap(true)
  return fs
end

local function CreateButton(parent, text, width)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetText(text)
  b:SetWidth(width or 160)
  b:SetHeight(22)
  return b
end

local function CreateCheckbox(parent, text)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb.Text:SetText(text)
  return cb
end

local function CreateEditBox(parent, width, height)
  local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  eb:SetAutoFocus(false)
  eb:SetSize(width or 520, height or 40)
  eb:SetMultiLine(true)
  eb:SetMaxLetters(0)
  eb:SetTextInsets(8, 8, 6, 6)
  eb:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  eb:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
  end)
  return eb
end

-- -----------------------------------------------------------------------------
-- Doctor report
-- -----------------------------------------------------------------------------

local function Trunc(s, n)
  s = tostring(s or "")
  n = n or 140
  if #s > n then
    return s:sub(1, n) .. "..."
  end
  return s
end

local function BuildReport(core)
  local lines = {}

  local theme = core:GetThemeName() or "?"
  local toc = select(4, GetBuildInfo())
  local memKB = collectgarbage and collectgarbage("count") or 0
  local qLen, qRunning = core:GetQueueSize()

  lines[#lines + 1] = string.format("Roth Skinner v%s | Theme: %s | toc=%s", tostring(core.version or "?"), tostring(theme), tostring(toc or "?"))
  lines[#lines + 1] = string.format("InCombat: %s", InCombatLockdown() and "yes" or "no")
  lines[#lines + 1] = string.format("Queued ops: %d (running=%s)", tonumber(qLen) or 0, qRunning and "yes" or "no")
  lines[#lines + 1] = string.format("Lua memory: %.0f KB", tonumber(memKB) or 0)
  lines[#lines + 1] = ""

  -- Module health
  lines[#lines + 1] = "Module health:"
  local anyWarn = false
  local disabledCount, errCount = 0, 0

  for _, name in ipairs(core:GetModuleNames()) do
    local h = core:GetModuleHealth(name)
    local enabled = core:IsModuleEnabled(name)

    if h and h.disabled then disabledCount = disabledCount + 1 end
    if h and (h.errors or 0) > 0 then errCount = errCount + 1 end

    if h and (h.disabled or (h.errors or 0) > 0) then
      anyWarn = true
      local flag = h.disabled and "AUTO-DISABLED" or "ERROR"
      lines[#lines + 1] = string.format(" - %s: %s | enabled=%s | errors=%d/%d | %s", name, flag, enabled and "yes" or "no", h.errors or 0, h.limit or 3, Trunc(h.lastError, 160))
    end
  end

  if not anyWarn then
    lines[#lines + 1] = " - (no errors recorded)"
  end

  lines[#lines + 1] = string.format("Totals: %d modules | %d auto-disabled | %d with errors", #core:GetModuleNames(), disabledCount, errCount)
  lines[#lines + 1] = ""

  -- Performance
  lines[#lines + 1] = "Perf (last apply per module):"
  local anyPerf = false
  for _, name in ipairs(core:GetModuleNames()) do
    local st = core:GetStats(name)
    if st and st.lastApplyMS then
      anyPerf = true
      lines[#lines + 1] = string.format(" - %s: %.1f ms", name, tonumber(st.lastApplyMS) or 0)
    end
  end
  if not anyPerf then
    lines[#lines + 1] = " - (no apply timings yet)"
  end

  lines[#lines + 1] = ""
  lines[#lines + 1] = "Tips:"
  lines[#lines + 1] = " - If a module is AUTO-DISABLED, fix the error, then use 'Reset session errors'."
  lines[#lines + 1] = " - Use export/import to iterate quickly across characters or share a reproducible config."
  lines[#lines + 1] = " - For UI targeting: /rothskin inspect, /rothskin trace <module> on, /rslog filter <module>."

  return table.concat(lines, "\n")
end

local function SetEditBoxText(eb, txt)
  if not eb then return end
  eb.__rsLock = true
  eb:SetText(txt or "")
  eb.__rsLock = false
end

local function RefreshUI(core)
  if not Panel or not Panel:IsShown() then return end

  if Controls.status then
    Controls.status:SetText(string.format("Roth Skinner v%s (Theme: %s)", tostring(core.version or "?"), tostring(core:GetThemeName() or "?")))
  end

  if Controls.devMode then
    local ui = core.db.profile.ui or {}
    Controls.devMode:SetChecked(ui.devMode and true or false)
  end

  if Controls.exportBox then
    SetEditBoxText(Controls.exportBox, core:ExportSettings() or "")
  end

  if Controls.reportFS then
    Controls.reportFS:SetText(BuildReport(core))
  end
end

local function PrintReportToChat(core)
  local rep = BuildReport(core)
  for line in rep:gmatch("[^\n]+") do
    core:Log(line)
  end
end

-- -----------------------------------------------------------------------------
-- Settings registration
-- -----------------------------------------------------------------------------

local function RegisterInBlizzardSettings(core)
  if Panel then return end

  Panel = CreateFrame("Frame")
  Panel.name = "Roth Skinner: Doctor"

  local title = CreateTitle(Panel, "Roth Skinner — Doctor")
  title:SetPoint("TOPLEFT", 16, -16)

  local status = CreateSubTitle(Panel, "")
  status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  Controls.status = status

  local scroll = CreateFrame("ScrollFrame", nil, Panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -12)
  scroll:SetPoint("BOTTOMRIGHT", -30, 16)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)

  local y = -2

  local dev = CreateCheckbox(content, "Developer mode (show advanced controls in some panels)")
  dev:SetPoint("TOPLEFT", 2, y)
  dev:SetScript("OnClick", function(self)
    local ui = core.db.profile.ui or {}
    ui.devMode = self:GetChecked() and true or false
    core.db.profile.ui = ui
    core:Log("DevMode:", ui.devMode and "ON" or "OFF")
  end)
  Controls.devMode = dev
  y = y - 28

  local btnApply = CreateButton(content, "Apply all", 120)
  btnApply:SetPoint("TOPLEFT", 2, y)
  btnApply:SetScript("OnClick", function()
    core:ApplyAll()
  end)

  local btnReset = CreateButton(content, "Reset session errors", 170)
  btnReset:SetPoint("LEFT", btnApply, "RIGHT", 8, 0)
  btnReset:SetScript("OnClick", function()
    core:ResetSessionDisables()
    core:Log("Session error state cleared.")
    RefreshUI(core)
  end)

  local btnRefresh = CreateButton(content, "Refresh", 120)
  btnRefresh:SetPoint("LEFT", btnReset, "RIGHT", 8, 0)
  btnRefresh:SetScript("OnClick", function()
    RefreshUI(core)
  end)

  y = y - 34

  local btnLog = CreateButton(content, "Open log viewer", 140)
  btnLog:SetPoint("TOPLEFT", 2, y)
  btnLog:SetScript("OnClick", function()
    if SlashCmdList and SlashCmdList.ROTHSKINNERLOG then
      SlashCmdList.ROTHSKINNERLOG("")
    else
      core:Warn("Log viewer not available (enable DevTools module).")
    end
  end)

  local btnPrint = CreateButton(content, "Print report to chat", 170)
  btnPrint:SetPoint("LEFT", btnLog, "RIGHT", 8, 0)
  btnPrint:SetScript("OnClick", function()
    PrintReportToChat(core)
  end)

  y = y - 40

  local expTitle = CreateSubTitle(content, "Export")
  expTitle:SetPoint("TOPLEFT", 2, y)
  y = y - 18

  local expHelp = CreateText(content, "Copy this string to share/backup settings. This string is safe to paste back into Import.")
  expHelp:SetPoint("TOPLEFT", 2, y)
  expHelp:SetWidth(560)
  y = y - 34

  local exportBox = CreateEditBox(content, 560, 60)
  exportBox:SetPoint("TOPLEFT", 2, y)
  exportBox.__rsLock = false
  exportBox:SetScript("OnEditFocusGained", function(self)
    SetEditBoxText(self, core:ExportSettings() or "")
    self:HighlightText()
  end)
  exportBox:SetScript("OnTextChanged", function(self, user)
    if self.__rsLock then return end
    if user then
      SetEditBoxText(self, core:ExportSettings() or "")
      self:HighlightText()
    end
  end)
  Controls.exportBox = exportBox

  y = y - 78

  local impTitle = CreateSubTitle(content, "Import")
  impTitle:SetPoint("TOPLEFT", 2, y)
  y = y - 18

  local impHelp = CreateText(content, "Paste an export string and click Import. This overwrites supported sections (RothMode, FX, Masque, UI devMode).")
  impHelp:SetPoint("TOPLEFT", 2, y)
  impHelp:SetWidth(560)
  y = y - 34

  local importBox = CreateEditBox(content, 560, 60)
  importBox:SetPoint("TOPLEFT", 2, y)
  Controls.importBox = importBox

  local importBtn = CreateButton(content, "Import", 120)
  importBtn:SetPoint("TOPLEFT", importBox, "BOTTOMLEFT", 0, -8)
  importBtn:SetScript("OnClick", function()
    local s = importBox:GetText() or ""
    local ok, err = core:ImportSettings(s)
    if ok then
      core:Log("Import OK")
      RefreshUI(core)
    else
      core:Error("Import failed:", err)
    end
  end)

  local impClear = CreateButton(content, "Clear", 120)
  impClear:SetPoint("LEFT", importBtn, "RIGHT", 8, 0)
  impClear:SetScript("OnClick", function()
    importBox:SetText("")
    importBox:ClearFocus()
  end)

  y = y - 120

  local repTitle = CreateSubTitle(content, "Report")
  repTitle:SetPoint("TOPLEFT", 2, y)
  y = y - 18

  local repScroll = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
  repScroll:SetPoint("TOPLEFT", 2, y)
  repScroll:SetSize(560, 260)

  local repContent = CreateFrame("Frame", nil, repScroll)
  repContent:SetSize(1, 1)
  repScroll:SetScrollChild(repContent)

  local repFS = CreateText(repContent, "")
  repFS:SetPoint("TOPLEFT", 2, -2)
  repFS:SetWidth(540)
  Controls.reportFS = repFS

  repContent:SetHeight(380)

  -- Expand content height to enable outer scrolling
  content:SetHeight(math.max(720, -y + 340))

  Panel:SetScript("OnShow", function()
    RefreshUI(core)
  end)

  if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory then
    local category = _G.Settings.RegisterCanvasLayoutCategory(Panel, Panel.name)
    category.ID = Panel.name
    _G.Settings.RegisterAddOnCategory(category)
  elseif _G.InterfaceOptions_AddCategory then
    _G.InterfaceOptions_AddCategory(Panel)
  end
end

function Module:PLAYER_LOGIN(core)
  RegisterInBlizzardSettings(core)
end

function Module:OnEnable(core)
  core:Claim("Config:DoctorPanel", self.name)
  RegisterInBlizzardSettings(core)
end

RS:RegisterModule(Module.name, Module)
