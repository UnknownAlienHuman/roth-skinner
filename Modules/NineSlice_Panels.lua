--[[
Module: NineSlice_Panels

Goal
- Provide a broad-stroke recolor for Blizzard panels that use NineSlice.
- The intent is *not* to replace every atlas; it's to unify darkness + border tone.

Strategy
- Skin known global frames (StaticPopups, GameMenu, Settings).
- Skin UI panel windows registered in UIPanelWindows.
- Hook OnShow for frames found so late-created windows get skinned when visible.
- Listen to ADDON_LOADED for major Blizzard UI addons and re-scan.

Non-goals
- Deep recursive skinning of every child widget (handled by WidgetPolicy modules).
- Aggressive texture swapping. We start with vertex color policy only.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "NineSlice_Panels",
  version = "0.3.0",
  priority = 30,
  enabledByDefault = true,

  events = { "PLAYER_LOGIN" },

  -- Re-scan when these Blizzard modules load.
  blizzardAddons = {
    "Blizzard_Settings",
    "Blizzard_CharacterUI",
    "Blizzard_PlayerSpells",
    "Blizzard_Professions",
    "Blizzard_Collections",
    "Blizzard_EncounterJournal",
    "Blizzard_QuestUI",
    "Blizzard_AuctionHouseUI",
    "Blizzard_TradeSkillUI",
    "Blizzard_GuildUI",
  },

  targets = {
    claims = { "NineSlice:UIPanels" },
  },
}

local function ApplyToFrame(core, theme, frame, label)
  if not frame or not theme or not theme.tokens then return end
  label = label or (frame.GetName and frame:GetName()) or tostring(frame)

  if not core:FrameOnce(frame, "RSNineSlice:Skinned") then
    return
  end

  local t = theme.tokens
  local border = t.colors and t.colors.panelBorder or { r = 1, g = 1, b = 1, a = 1 }
  local inset  = t.colors and t.colors.panelInset or { r = 0, g = 0, b = 0, a = 0.25 }

  core:Trace(Module.name, "apply", label)

  -- Border edges/corners
  core:ColorNineSlice(frame, border.r, border.g, border.b, border.a)

  -- Optional darken center (some NineSlice objects expose Center texture)
  local nsObj = frame.NineSlice or frame
  if nsObj and nsObj.Center and nsObj.Center.SetVertexColor then
    nsObj.Center:SetVertexColor(inset.r, inset.g, inset.b, inset.a)
  end
end

local function HookFrame(core, frame, label)
  if not frame then return end
  core:HookOnShow(frame, "NS:" .. (label or (frame.GetName and frame:GetName()) or "?"), function(f)
    ApplyToFrame(core, core:GetTheme(), f, label)
  end)
end

local function ScanStaticPopups(core)
  for i = 1, 4 do
    local f = _G["StaticPopup" .. i]
    if f then HookFrame(core, f, "StaticPopup" .. i) end
  end
end

local function ScanKnownGlobals(core)
  local candidates = {
    "GameMenuFrame",
    "SettingsPanel",
    "SettingsFrame",
    "VideoOptionsFrame",
    "InterfaceOptionsFrame",
  }
  for _, name in ipairs(candidates) do
    local f = _G[name]
    if f then HookFrame(core, f, name) end
  end
end

local function ScanUIPanelWindows(core)
  local t = _G.UIPanelWindows
  if type(t) ~= "table" then return end

  local count = 0
  for frameName in pairs(t) do
    local f = _G[frameName]
    if f then
      count = count + 1
      HookFrame(core, f, "UIPanel:" .. frameName)
    end
  end

  core:Trace(Module.name, "scan", "UIPanelWindows", "count=", count)
end

local function Rescan(core)
  ScanStaticPopups(core)
  ScanKnownGlobals(core)
  ScanUIPanelWindows(core)
end

function Module:OnEnable(core)
  core:Debug(self.name, "OnEnable")
  core:Claim("NineSlice:UIPanels", self.name)

  -- Initial scan is safe and quick.
  Rescan(core)
end

function Module:OnAddonLoaded(core, addonName)
  core:Trace(self.name, "addon", addonName)
  core:Throttle("NineSlice:Rescan", 0.05, function()
    Rescan(core)
  end)
end

function Module:Apply(core)
  -- Apply is handled via OnShow hooks; still do a scan to hook any missed frames.
  Rescan(core)
end

function Module:OnThemeChanged(core)
  -- Drop per-frame markers so we can re-apply new colors.
  -- We only clear our own marker key.
  local function clearMarker(f)
    if f and f.__RothSkinner then
      f.__RothSkinner["RSNineSlice:Skinned"] = nil
    end
  end

  -- Clear for known/popups/panels.
  for i = 1, 4 do clearMarker(_G["StaticPopup" .. i]) end

  local t = _G.UIPanelWindows
  if type(t) == "table" then
    for frameName in pairs(t) do
      clearMarker(_G[frameName])
    end
  end

  -- Re-scan and let OnShow immediate apply handle visible frames.
  Rescan(core)
end

function Module:OnEvent(core, event)
  if event == "PLAYER_LOGIN" then
    -- Late frames appear after login; do a delayed rescan.
    core:Throttle("NineSlice:LoginRescan", 1.0, function()
      Rescan(core)
    end)
  end
end

RS:RegisterModule(Module.name, Module)
