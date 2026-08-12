--[[
DevTools module (optional)

Adds an in-game log viewer window.
Core already provides /rothskin tail/inspect/trace. This module is for
comfortable iteration while designing skins.

Slash:
  /rslog            - toggle viewer
  /rslog clear      - clear viewer buffer (does not clear core log)
  /rslog filter <m> - filter by module (empty resets)

Notes
- Viewer reads from the core log ring buffer stored in SavedVariables.
- Zero protected changes; safe in combat.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "DevTools",
  version = "0.3.0",
  priority = 1,
  enabledByDefault = true,
}

local Viewer
local lastSeen = 0
local filterMod = nil

local function EnsureViewer(core)
  if Viewer then return Viewer end

  local f = CreateFrame("Frame", "RothSkinnerLogViewer", UIParent, "BackdropTemplate")
  f:SetSize(700, 360)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = false,
    edgeSize = 1,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })

  local theme = core:GetTheme()
  local t = theme and theme.tokens
  local bg = t and t.colors and t.colors.panelBg or { r = 0, g = 0, b = 0, a = 0.85 }
  local border = t and t.colors and t.colors.panelBorder or { r = 0.7, g = 0.1, b = 0.1, a = 0.9 }
  f:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
  f:SetBackdropBorderColor(border.r, border.g, border.b, border.a)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("RothSkinner Log Viewer")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  local msg = CreateFrame("ScrollingMessageFrame", nil, f)
  msg:SetPoint("TOPLEFT", 10, -30)
  msg:SetPoint("BOTTOMRIGHT", -10, 12)
  msg:SetFontObject(GameFontHighlightSmall)
  msg:SetJustifyH("LEFT")
  msg:SetFading(false)
  msg:SetMaxLines(500)

  f.msg = msg
  f:Hide()

  Viewer = f
  return Viewer
end

local function FormatEntry(e)
  local ts = e.t and string.format("%7.1f", e.t) or "   ?  "
  local lvl = e.lvl or "INFO"
  local mod = e.mod or "Core"
  local m = e.msg or ""
  return string.format("%s  %-5s  %-18s  %s", ts, lvl, mod, m)
end

local function Pump(core)
  if not Viewer or not Viewer:IsShown() then return end

  local entries = core.db and core.db.profile and core.db.profile.log and core.db.profile.log.entries
  if type(entries) ~= "table" then return end

  for i = lastSeen + 1, #entries do
    local e = entries[i]
    if e then
      if (not filterMod) or (e.mod == filterMod) then
        Viewer.msg:AddMessage(FormatEntry(e))
      end
    end
  end

  lastSeen = #entries
end

local function ToggleViewer(core)
  local v = EnsureViewer(core)
  if v:IsShown() then
    v:Hide()
  else
    v:Show()
    v.msg:Clear()
    lastSeen = 0
    Pump(core)
  end
end

SLASH_ROTHSKINNERLOG1 = "/rslog"
SlashCmdList.ROTHSKINNERLOG = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")

  if msg == "" then
    ToggleViewer(RS)
    return
  end

  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""

  if cmd == "clear" then
    if Viewer and Viewer.msg then Viewer.msg:Clear() end
    return
  end

  if cmd == "filter" then
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    filterMod = rest ~= "" and rest or nil
    if Viewer and Viewer:IsShown() then
      Viewer.msg:Clear()
      lastSeen = 0
      Pump(RS)
    end
    RS:Log("Log viewer filter:", filterMod or "(none)")
    return
  end

  RS:Log("/rslog commands: (no args)=toggle, clear, filter <module>")
end

function Module:OnEnable(core)
  core:Debug(self.name, "OnEnable")
  core:Claim("DevTools:LogViewer", self.name)

  -- Lightweight pump timer.
  core:Throttle("DevTools:Pump", 0.2, function()
    Pump(core)
  end, true) -- repeating
end

function Module:OnThemeChanged(core)
  if not Viewer then return end
  local theme = core:GetTheme()
  local t = theme and theme.tokens
  if not t or not t.colors then return end
  Viewer:SetBackdropColor(t.colors.panelBg.r, t.colors.panelBg.g, t.colors.panelBg.b, t.colors.panelBg.a)
  Viewer:SetBackdropBorderColor(t.colors.panelBorder.r, t.colors.panelBorder.g, t.colors.panelBorder.b, t.colors.panelBorder.a)
end

RS:RegisterModule(Module.name, Module)
