--[[
Module: Masque_Integration

Goal
- If Masque is installed, register Blizzard button frames into Masque groups.
- This lets users apply any Masque skin (e.g. Masque_Diabolic) to Blizzard bars.

Notes
- We treat Masque as an external dependency.
- For convenience, we optionally auto-apply a SkinID by calling the group internal method __Set.
  This is disabled by default.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local LibStub = _G.LibStub

local Module = {
  name = "Masque_Integration",
  version = "0.6.0",
  priority = 55,
  enabledByDefault = true,
  -- Re-run when Masque (external) and key Blizzard UI add-ons are loaded.
  blizzardAddons = {
    "Masque",
    "Blizzard_ActionBar",
    "Blizzard_Bags",
    "Blizzard_UIWidgets",
    "Blizzard_EditMode",
  },

  events = { "PLAYER_LOGIN" },
}

local MSQ
local Groups = { action = nil, bags = nil }

-- Minimal metrics for debugging.
local Stats = {
  lastScan = 0,
  actionButtons = 0,
  bagButtons = 0,
}

local function GetMasque()
  if MSQ then return MSQ end
  if not LibStub then return nil end
  MSQ = LibStub("Masque", true)
  return MSQ
end

local function GetCfg(core)
  local db = core and core.db and core.db.profile
  return db and db.masque
end

local function EnsureGroups(core)
  local cfg = GetCfg(core)
  if not cfg or not cfg.enabled then return nil end

  local msq = GetMasque()
  if not msq then return nil end

  -- Use stable IDs so Masque persists its settings.
  if cfg.actionBars and not Groups.action then
    Groups.action = msq:Group(RS.name, "Blizzard", "ActionBars")
  end
  if cfg.bagBar and not Groups.bags then
    Groups.bags = msq:Group(RS.name, "Blizzard", "BagBar")
  end

  return msq
end

local function AutoApplySkin(core, group, skinID)
  local cfg = GetCfg(core)
  if not cfg or not cfg.autoApply then return end
  if not group or not skinID or skinID == "" then return end

  -- Masque does not provide a public SetSkin API on groups.
  -- __Set exists on Group objects; we keep it as an optional convenience.
  if type(group.__Set) == "function" then
    group:__Set("SkinID", skinID)
    if type(group.ReSkin) == "function" then
      group:ReSkin()
    end
  end
end

local function AddNamedRange(group, prefix, first, last)
  local n = 0
  for i = first, last do
    local b = _G[prefix .. i]
    if b then
      group:AddButton(b)
      n = n + 1
    end
  end
  return n
end

local function AddIfExists(group, globalName)
  local b = _G[globalName]
  if b then
    group:AddButton(b)
    return 1
  end
  return 0
end

local function ScanActionBars(core)
  local group = Groups.action
  if not group then return 0 end

  local total = 0

  -- Main + Multi bars (Edit Mode can surface additional bars; we include common prefixes).
  total = total + AddNamedRange(group, "ActionButton", 1, 12)
  total = total + AddNamedRange(group, "MultiBarBottomLeftButton", 1, 12)
  total = total + AddNamedRange(group, "MultiBarBottomRightButton", 1, 12)
  total = total + AddNamedRange(group, "MultiBarRightButton", 1, 12)
  total = total + AddNamedRange(group, "MultiBarLeftButton", 1, 12)
  total = total + AddNamedRange(group, "MultiBar5Button", 1, 12)
  total = total + AddNamedRange(group, "MultiBar6Button", 1, 12)

  -- Override bar.
  total = total + AddNamedRange(group, "OverrideActionBarButton", 1, 12)

  -- Extra action + zone ability.
  total = total + AddNamedRange(group, "ExtraActionButton", 1, 1)
  total = total + AddIfExists(group, "ZoneAbilityFrameSpellButton")

  -- Pet bar.
  total = total + AddNamedRange(group, "PetActionButton", 1, 10)

  -- Stance / shapeshift.
  total = total + AddNamedRange(group, "StanceButton", 1, 10)

  -- Possess bar.
  total = total + AddNamedRange(group, "PossessButton", 1, 2)

  -- Convenience auto-apply.
  AutoApplySkin(core, group, (GetCfg(core) or {}).skinActionBars)

  return total
end

local function ScanBagBar(core)
  local group = Groups.bags
  if not group then return 0 end

  local total = 0

  -- Backpack + character bag slots.
  total = total + AddIfExists(group, "MainMenuBarBackpackButton")
  total = total + AddNamedRange(group, "CharacterBag", 0, 3)

  -- Reagent bag slot (Retail).
  total = total + AddIfExists(group, "CharacterReagentBag0Slot")

  -- Convenience auto-apply.
  AutoApplySkin(core, group, (GetCfg(core) or {}).skinBagBar)

  return total
end

local function RunScan(core)
  local cfg = GetCfg(core)
  if not cfg or not cfg.enabled then
    return
  end

  if not GetMasque() then
    RS:Trace(Module.name, "Masque not detected; module inert")
    return
  end

  EnsureGroups(core)

  Stats.lastScan = GetTime and GetTime() or 0
  Stats.actionButtons = 0
  Stats.bagButtons = 0

  if Groups.action then
    Stats.actionButtons = ScanActionBars(core)
  end
  if Groups.bags then
    Stats.bagButtons = ScanBagBar(core)
  end

  RS:Trace(Module.name, "Scan complete:", "action=", Stats.actionButtons, "bags=", Stats.bagButtons)
end

function Module:GetStats()
  return Stats
end

function Module:OnAddonLoaded(core, addonName)
  if addonName == "Masque" then
    MSQ = nil
  end
  RunScan(core)
end

function Module:OnEnable(core)
  RunScan(core)
end

function Module:OnDisable(core)
  -- Deleting groups reverts affected buttons to their default skin.
  if Groups.action and type(Groups.action.Delete) == "function" then
    Groups.action:Delete()
  end
  if Groups.bags and type(Groups.bags.Delete) == "function" then
    Groups.bags:Delete()
  end
  Groups.action = nil
  Groups.bags = nil
  RS:Trace(Module.name, "Disabled: Masque groups deleted")
end

function Module:Apply(core)
  RunScan(core)
end

-- Standalone slash for quick diagnostics.
SLASH_ROTHMASQUE1 = "/rothmasque"
SlashCmdList.ROTHMASQUE = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""

  if cmd == "" or cmd == "help" then
    RS:Log("/rothmasque status")
    RS:Log("/rothmasque rescan")
    RS:Log("/rothmasque skins [filter]")
    RS:Log("/rothmasque auto [on|off]")
    return
  end

  local core = RS

  if cmd == "status" then
    local cfg = GetCfg(core)
    local ok = GetMasque() and "YES" or "NO"
    RS:Log("Masque detected:", ok)
    RS:Log("Bridge enabled:", (cfg and cfg.enabled) and "YES" or "NO")
    RS:Log("Groups:", "action=", Groups.action and "YES" or "NO", "bags=", Groups.bags and "YES" or "NO")
    RS:Log("Last scan:", Stats.lastScan)
    RS:Log("Buttons:", "action=", Stats.actionButtons, "bags=", Stats.bagButtons)
    return
  end

  if cmd == "rescan" then
    core:ApplyModule(Module)
    return
  end

  if cmd == "auto" then
    local cfg = GetCfg(core)
    if not cfg then return end
    rest = (rest or ""):lower()
    if rest == "on" or rest == "1" or rest == "true" then
      cfg.autoApply = true
    elseif rest == "off" or rest == "0" or rest == "false" then
      cfg.autoApply = false
    else
      cfg.autoApply = not cfg.autoApply
    end
    RS:Log("Masque auto-apply:", cfg.autoApply and "ON" or "OFF")
    core:ApplyModule(Module)
    return
  end

  if cmd == "skins" then
    local msq = GetMasque()
    if not msq or type(msq.GetSkins) ~= "function" then
      RS:Log("Masque not available")
      return
    end

    local filter = (rest or "")
    filter = filter ~= "" and filter:lower() or nil

    local skins = msq:GetSkins()
    local keys = {}
    for k in pairs(skins or {}) do
      if not filter or tostring(k):lower():find(filter, 1, true) then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys)

    RS:Log("Masque skins:", #keys)
    for i = 1, math.min(#keys, 50) do
      RS:Log(" -", keys[i])
    end
    if #keys > 50 then
      RS:Log("...", (#keys - 50), "more")
    end
    return
  end

  RS:Log("Unknown command.")
end

RS:RegisterModule(Module.name, Module)
