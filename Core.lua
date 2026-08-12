--[[
Roth_Skinner Core (Retail 12.0+)

Core responsibilities
- Themes: tokens + asset paths (no concrete design logic).
- Modules: lifecycle, event routing, apply pipeline.
- Safety: combat-lockdown queue for any potentially protected changes.
- Diagnostics: ring-buffer log + per-module tracing + frame inspection helpers.

Design responsibilities
- Implemented by modules (Blizzard UI families / specific frames / FX layers).

Architecture inspiration
- Similar separation to oUF: framework core + external "layouts".
  Here: skinner core + external "skin modules" + theme packs.

NOTE
- WoW uses Lua 5.1. Keep code 5.1-compatible (no goto, etc.).
--]]

local ADDON_NAME, ns = ...
ns = ns or {}

local unpack = unpack or table.unpack

local CoreFrame = CreateFrame("Frame")
local RS = {}
_G.RothSkinner = RS
ns.RothSkinner = RS

RS.name = "Roth_Skinner"
RS.version = "0.6.1"



-- Session-only module health (auto-disable unstable modules)
RS._sessionDisabled = RS._sessionDisabled or {}
RS._moduleErrorCount = RS._moduleErrorCount or {}
RS._moduleLastError = RS._moduleLastError or {}
RS._moduleLastErrorTime = RS._moduleLastErrorTime or {}
RS._moduleErrorLimit = 3

-- -----------------------------------------------------------------------------
-- SavedVariables
-- -----------------------------------------------------------------------------

local DEFAULTS = {
  profile = {
    activeTheme = "AshBlood",
    debug = false,



    ui = {
      devMode = true,
    },

    -- Optional Masque bridge.
    -- Purpose: register Blizzard button frames into Masque groups so the user can apply any Masque skin.
    -- NOTE: we do NOT bundle Masque; it is treated as an optional dependency.
    masque = {
      enabled = true,

      -- Coverage
      actionBars = true, -- ActionButton / MultiBar* / Pet / Stance / Possess / Override
      bagBar = true,     -- Backpack + character bag slots

      -- Optional convenience (uses Masque group internal API if enabled).
      autoApply = false,
      skinActionBars = "DiabolicUI ActionButton",
      skinBagBar = "DiabolicUI BagButton",
    },


    -- Roth Mode: global recolor & lightweight reskin pass (used by RothMode_Global module).
    -- Policy-only config: modules implement concrete visuals / textures.
    rothmode = {
      enabled = true,

      -- Multiplies effective RGB for affected textures (0..1). Lower = darker.
      intensity = 0.88,

      -- Desaturate affected textures when supported.
      desaturate = true,

      -- Coverage toggles.
      panels = true,    -- main Blizzard panels (UIPanelWindows)
      buttons = true,
      controls = true,
      dropdowns = true,
      popups = true,
      tooltips = true,

      -- Also hook frames listed in UISpecialFrames (ESC-closable dialogs).
      -- Default OFF to avoid touching addon windows.
      specialFrames = false,

      -- Optional color overrides (if colors.useTheme=true, theme tokens win).
      colors = {
        useTheme = true,
        border = { r = 0.40, g = 0.08, b = 0.06, a = 0.90 },
        bg     = { r = 0.06, g = 0.06, b = 0.065, a = 0.55 },
        inset  = { r = 0.00, g = 0.00, b = 0.00, a = 0.18 },
        accent = { r = 1.00, g = 0.36, b = 0.16, a = 0.18 },
      },

      -- Gradient overlay used on panels (optional).
      gradient = {
        enabled = true,
        orientation = "VERTICAL", -- VERTICAL | HORIZONTAL
        from = { r = 0.00, g = 0.00, b = 0.00, a = 0.00 },
        to   = { r = 0.00, g = 0.00, b = 0.00, a = 0.22 },
        applyToPanels = true,
        applyToButtons = false,
      },
    },

    -- FX layer: reusable frame decorations + faders.
    -- This is development-heavy; expect many knobs while we iterate on style.
    fx = {
      frames = {
        enabled = true,
        border = true,
        borderSize = 1,
        borderAlpha = 0.90,
        glow = true,
        glowSize = 6,
        glowAlpha = 0.28,
        glowPulse = false,
        glowPulsePeriod = 1.60,
        -- Color source:
        --  - "theme": use theme tokens
        --  - "override": use colors below
        colorSource = "theme",
        colors = {
          border = { r = 0.40, g = 0.08, b = 0.06, a = 0.90 },
          glow   = { r = 1.00, g = 0.36, b = 0.16, a = 0.28 },
        },
      },

      faders = {
        enabled = true,
        activeAlpha = 1.00,
        inactiveAlpha = 0.35,
        fadeIn = 0.10,
        fadeOut = 0.22,
        onlyOutOfCombat = true,
        keepActiveWhenFocused = true,

        -- Coverage
        panels = true,
        popups = true,
        dropdownLists = true,
        tooltips = true,
      },

      dynamics = {
        enabled = true,

        -- Event toggles
        onEnterCombat = true,
        onLeaveCombat = false,
        onLoot = true,
        onVictory = true, -- ENCOUNTER_END success

        -- Targets
        actionBars = true,
        bagBar = true,
        globalOverlay = false,

        -- Throttle (seconds)
        throttleLoot = 1.0,
        throttleVictory = 2.0,

        -- Visuals
        flashDuration = 0.35,
        flashAlpha = 0.65,
        flashScale = 1.03,

        glowDuration = 0.75,
        glowAlpha = 0.30,

        -- Color source:
        --  - "theme": use theme accent tokens
        --  - "override": use colors below
        colorSource = "theme",
        colors = {
          combat = { r = 1.00, g = 0.36, b = 0.16, a = 1.00 },
          loot   = { r = 0.35, g = 0.80, b = 0.25, a = 1.00 },
          victory= { r = 1.00, g = 0.82, b = 0.00, a = 1.00 },
        },
      },

      perf = {
        -- Limits for frame scanning passes.
        maxDepth = 3,
        maxNodes = 2500,
        chunkSize = 250,
      },
    },

    -- Per-module trace switches. If true, show detailed logs.
    trace = {}, -- [moduleName]=true

    -- Module enable flags.
    modules = {}, -- [moduleName]=true/false

    -- Log ring buffer
    log = {
      max = 800,
      entries = {}, -- { {t=GetTime(), lvl="INFO"|"DEBUG"|"TRACE"|"ERROR"|"WARN", mod="Core"|..., msg="..."}, ... }
    },

    -- Per-module runtime stats (for debugging / profiling skin coverage)
    stats = {
      modules = {}, -- [moduleName] = { lastApply=GetTime(), lastApplyMS=ms, lastError="...", counters={k=v} }
    },
  },
}

local function DeepCopy(dst, src)
  if type(src) ~= "table" then return src end
  dst = dst or {}
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = DeepCopy(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
  return dst
end

local function InitDB()
  if type(_G.RothSkinnerDB) ~= "table" then
    _G.RothSkinnerDB = {}
  end
  _G.RothSkinnerDB = DeepCopy(_G.RothSkinnerDB, DEFAULTS)
  RS.db = _G.RothSkinnerDB

  -- v0.4 migration: rename legacy prototype key -> rothmode (keep user tweaks).
  if type(RS.db.profile.darkmode) == "table" then
    local dm = RS.db.profile.darkmode
    local rm = RS.db.profile.rothmode or {}
    rm.enabled       = (dm.enabled       ~= nil) and dm.enabled       or rm.enabled
    rm.intensity     = (dm.intensity     ~= nil) and dm.intensity     or rm.intensity
    rm.desaturate    = (dm.desaturate    ~= nil) and dm.desaturate    or rm.desaturate
    rm.buttons       = (dm.buttons       ~= nil) and dm.buttons       or rm.buttons
    rm.controls      = (dm.controls      ~= nil) and dm.controls      or rm.controls
    rm.dropdowns     = (dm.dropdowns     ~= nil) and dm.dropdowns     or rm.dropdowns
    rm.popups        = (dm.popups        ~= nil) and dm.popups        or rm.popups
    rm.specialFrames = (dm.specialFrames ~= nil) and dm.specialFrames or rm.specialFrames
    RS.db.profile.rothmode = rm
    RS.db.profile.darkmode = nil
  end

  RS.db.profile.rothmode = RS.db.profile.rothmode or {}
  RS.db.profile.rothmode.colors = RS.db.profile.rothmode.colors or {}
  RS.db.profile.rothmode.gradient = RS.db.profile.rothmode.gradient or {}

  -- v0.4.4+: Masque bridge settings.
  RS.db.profile.masque = DeepCopy(RS.db.profile.masque or {}, DEFAULTS.profile.masque)

  -- v0.5.0+: FX (frames/glows/faders) settings.
  RS.db.profile.fx = DeepCopy(RS.db.profile.fx or {}, DEFAULTS.profile.fx)

  -- Ensure required sub-tables exist.
  RS.db.profile.trace = RS.db.profile.trace or {}
  RS.db.profile.modules = RS.db.profile.modules or {}
  RS.db.profile.log = RS.db.profile.log or { max = 800, entries = {} }
  RS.db.profile.log.entries = RS.db.profile.log.entries or {}
  RS.db.profile.log.max = tonumber(RS.db.profile.log.max) or 800

  RS.db.profile.stats = RS.db.profile.stats or { modules = {} }
  RS.db.profile.stats.modules = RS.db.profile.stats.modules or {}
end

-- ----------------------------------------------------------------------------
-- Stats helpers
-- ----------------------------------------------------------------------------

local function GetModStats(modName)
  local db = RS.db and RS.db.profile and RS.db.profile.stats
  if not db then return nil end
  db.modules = db.modules or {}
  local st = db.modules[modName]
  if not st then
    st = { counters = {} }
    db.modules[modName] = st
  end
  st.counters = st.counters or {}
  return st
end

function RS:StatInc(modName, key, delta)
  local st = GetModStats(modName or "(unknown)")
  if not st then return end
  key = tostring(key or "")
  if key == "" then return end
  delta = tonumber(delta) or 1
  st.counters[key] = (tonumber(st.counters[key]) or 0) + delta
end

function RS:StatSet(modName, key, value)
  local st = GetModStats(modName or "(unknown)")
  if not st then return end
  key = tostring(key or "")
  if key == "" then return end
  st.counters[key] = value
end

function RS:GetStats(modName)
  return GetModStats(modName)
end

function RS:PrintStats(modName)
  if not modName or modName == "" then
    self:Log("Stats: use /rothskin stats <module>")
    return
  end
  local st = GetModStats(modName)
  if not st then
    self:Log("Stats: no data")
    return
  end
  self:Log("Stats:", modName, "lastApply=", st.lastApply or "?", "ms=", st.lastApplyMS or "?", st.lastError and ("error=" .. tostring(st.lastError)) or "")
  local keys = {}
  for k in pairs(st.counters or {}) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    self:Log("  ", k, "=", st.counters[k])
  end
end

function RS:GetStats(modName)
  return GetModStats(modName)
end

-- -----------------------------------------------------------------------------
-- Logging / diagnostics
-- -----------------------------------------------------------------------------

local function tostringall(...)
  local t = {}
  for i = 1, select('#', ...) do
    t[i] = tostring(select(i, ...))
  end
  return table.concat(t, " ")
end

local function PushLog(lvl, mod, msg)
  local db = RS.db and RS.db.profile and RS.db.profile.log
  if not db then return end
  local entries = db.entries
  entries[#entries + 1] = { t = GetTime(), lvl = lvl, mod = mod, msg = msg }
  local max = db.max or 800
  if #entries > max then
    local trim = #entries - max
    for _ = 1, trim do
      table.remove(entries, 1)
    end
  end
end

local function PrintLine(lvl, mod, msg)
  local prefix = "|cffb74bffRothSkinner|r"
  local tag = mod and ("|cff888888[" .. mod .. "]|r") or ""
  local ll = lvl or "INFO"
  local color = "|cffffffff"
  if ll == "ERROR" then color = "|cffff5555"
  elseif ll == "WARN" then color = "|cffffaa00"
  elseif ll == "DEBUG" then color = "|cff888888"
  elseif ll == "TRACE" then color = "|cff66ccff" end
  print(prefix, tag, color .. ll .. "|r", msg)
end

function RS:Log(...)
  local msg = tostringall(...)
  PushLog("INFO", "Core", msg)
  PrintLine("INFO", "Core", msg)
end

function RS:Warn(...)
  local msg = tostringall(...)
  PushLog("WARN", "Core", msg)
  PrintLine("WARN", "Core", msg)
end

function RS:Error(...)
  local msg = tostringall(...)
  PushLog("ERROR", "Core", msg)
  PrintLine("ERROR", "Core", msg)
end

function RS:Debug(...)
  if self.db and self.db.profile and self.db.profile.debug then
    local msg = tostringall(...)
    PushLog("DEBUG", "Core", msg)
    PrintLine("DEBUG", "Core", msg)
  end
end

function RS:Trace(modName, ...)
  local db = self.db and self.db.profile
  if not db then return end
  if not (db.debug or (db.trace and db.trace[modName])) then return end
  local msg = tostringall(...)
  PushLog("TRACE", modName or "?", msg)
  PrintLine("TRACE", modName or "?", msg)
end

function RS:Tail(n, filterMod)
  local db = self.db and self.db.profile and self.db.profile.log
  if not db then return end
  n = tonumber(n) or 40
  local entries = db.entries
  local start = math.max(1, #entries - n + 1)
  for i = start, #entries do
    local e = entries[i]
    if e and (not filterMod or e.mod == filterMod) then
      PrintLine(e.lvl, e.mod, e.msg)
    end
  end
end

function RS:ClearLog()
  local db = self.db and self.db.profile and self.db.profile.log
  if not db then return end
  db.entries = {}
  self:Log("Log cleared")
end

local SafeCall

-- -----------------------------------------------------------------------------
-- Throttle helper
-- -----------------------------------------------------------------------------

-- Throttles a function by key.
-- If repeating=true, runs on a ticker every `seconds`.
-- Otherwise, schedules a single run after `seconds` and coalesces calls.
local throttles = {} -- [key] = {ticker|pending}

function RS:Throttle(key, seconds, fn, repeating)
  if type(key) ~= "string" or key == "" then return end
  seconds = tonumber(seconds) or 0.2
  if type(fn) ~= "function" then return end

  if repeating then
    if throttles[key] and throttles[key].ticker then return end
    local t = C_Timer.NewTicker(seconds, function()
      SafeCall("Throttle:" .. key, fn)
    end)
    throttles[key] = { ticker = t }
    return
  end

  if throttles[key] and throttles[key].pending then
    -- already scheduled
    return
  end
  throttles[key] = { pending = true }
  C_Timer.After(seconds, function()
    local st = throttles[key]
    if st then st.pending = nil end
    SafeCall("Throttle:" .. key, fn)
  end)
end

function RS:CancelThrottle(key)
  local st = throttles[key]
  if not st then return end
  if st.ticker then
    st.ticker:Cancel()
  end
  throttles[key] = nil
end

SafeCall = function(tag, fn, ...)
  local ok, err = xpcall(fn, geterrorhandler(), ...)
  if not ok then
    RS:Error(tostring(tag or "(no tag)"), err)
  end
  return ok, err
end

-- -----------------------------------------------------------------------------
-- Claims / Ownership (conflict diagnostics)
-- -----------------------------------------------------------------------------

local claims = {} -- [key] = moduleName

function RS:Claim(key, moduleName)
  if type(key) ~= "string" or key == "" then return false end
  moduleName = moduleName or "(unknown)"

  local owner = claims[key]
  if owner and owner ~= moduleName then
    self:Warn("CONFLICT target already claimed:", key, "owner=", owner, "request=", moduleName)
    return false, owner
  end
  claims[key] = moduleName
  return true
end

function RS:GetClaimOwner(key)
  return claims[key]
end

function RS:ListClaims()
  local out = {}
  for k, v in pairs(claims) do
    out[#out + 1] = { k = k, v = v }
  end
  table.sort(out, function(a, b) return a.k < b.k end)
  for _, row in ipairs(out) do
    self:Log("Claim:", row.k, "=>", row.v)
  end
  self:Log("Claims total:", #out)
end

-- -----------------------------------------------------------------------------
-- Combat-safe queue
-- -----------------------------------------------------------------------------

local pending = {}
local queueRunning = false

local function Queue(tag, fn, ...)
  pending[#pending + 1] = { tag = tag, fn = fn, args = { ... } }
  RS:Debug("Queued:", tag, "(len=", #pending, ")")
end

local function RunQueueChunk()
  queueRunning = true

  local budget = 40 -- per-tick job budget
  while budget > 0 and #pending > 0 do
    budget = budget - 1
    local job = table.remove(pending, 1)
    if job and job.fn then
      SafeCall(job.tag, job.fn, unpack(job.args))
    end
  end

  if #pending > 0 then
    C_Timer.After(0, RunQueueChunk)
  else
    queueRunning = false
  end
end

function RS:RunOrQueue(tag, fn, ...)
  if InCombatLockdown() then
    Queue(tag, fn, ...)
    return false
  end
  return SafeCall(tag, fn, ...)
end


-- Run a step function in small time slices (prevents long UI stutters).
-- stepFn() must return true when complete.
-- opts: { perTickMS=number, maxStepsPerTick=number, resumeInCombat=bool }
function RS:RunBudgeted(tag, stepFn, opts)
  if type(stepFn) ~= "function" then return false end
  opts = opts or {}
  local perTickMS = tonumber(opts.perTickMS) or 2.5
  local maxSteps = tonumber(opts.maxStepsPerTick) or 200
  local resumeInCombat = (opts.resumeInCombat ~= false)

  local function Tick()
    if InCombatLockdown() then
      if resumeInCombat then
        Queue("BudgetedResume:" .. tostring(tag), Tick)
      end
      return
    end

    local t0 = debugprofilestop and debugprofilestop() or nil
    local steps = 0

    while steps < maxSteps do
      steps = steps + 1
      local done
      local ok, err = xpcall(function()
        done = stepFn()
      end, geterrorhandler())

      if not ok then
        self:Error("Budgeted job failed:", tostring(tag), err)
        return
      end

      if done then
        return
      end

      if t0 and (debugprofilestop() - t0) >= perTickMS then
        break
      end
    end

    C_Timer.After(0, Tick)
  end

  Tick()
  return true
end

local function FlushQueue()
  if #pending == 0 or queueRunning then return end
  if InCombatLockdown() then return end
  RunQueueChunk()
end

function RS:GetQueueSize()
  return #pending, queueRunning
end

-- -----------------------------------------------------------------------------
-- Theme registry
-- -----------------------------------------------------------------------------

local themes = {}
local activeThemeName
local activeTheme

function RS:RegisterTheme(name, theme)
  assert(type(name) == "string" and name ~= "", "RegisterTheme: name must be a non-empty string")
  assert(type(theme) == "table", "RegisterTheme: theme must be a table")
  theme.name = theme.name or name
  themes[name] = theme
  self:Trace("Core", "Theme registered:", name)
end

function RS:GetTheme()
  return activeTheme
end

function RS:GetThemeName()
  return activeThemeName
end

-- opts:
--   noApply:  skip ApplyAll
--   noNotify: skip OnThemeChanged notifications
--   silent:   suppress info log
function RS:_SetActiveTheme(name, opts)
  opts = opts or {}
  if not themes[name] then
    self:Warn("Unknown theme:", name)
    return false
  end

  activeThemeName = name
  activeTheme = themes[name]

  if self.db and self.db.profile then
    self.db.profile.activeTheme = name
  end

  if not opts.silent then
    self:Log("Active theme:", name)
  end

  self:RunOrQueue("ThemeActivate:" .. name, function()
    if type(activeTheme.OnActivate) == "function" then
      activeTheme:OnActivate(self)
    end
    if not opts.noNotify then
      self:NotifyModules("OnThemeChanged", activeTheme)
    end
    if not opts.noApply then
      self:ApplyAll()
    end
  end)

  return true
end

function RS:SetActiveTheme(name)
  return self:_SetActiveTheme(name, nil)
end

function RS:ListThemes()
  local keys = {}
  for k in pairs(themes) do keys[#keys + 1] = k end
  table.sort(keys)
  for _, k in ipairs(keys) do
    self:Log("Theme:", k)
  end
  self:Log("Themes total:", #keys)
end

-- Returns a sorted list of registered theme names.
function RS:GetThemeNames()
  local keys = {}
  for k in pairs(themes) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

function RS:MediaPath(relative)
  if not relative or relative == "" then
    return string.format("Interface\\AddOns\\%s\\", self.name)
  end
  return string.format("Interface\\AddOns\\%s\\%s", self.name, relative)
end

-- -----------------------------------------------------------------------------
-- Module registry + lifecycle
-- -----------------------------------------------------------------------------

local modules = {}
local moduleList = {}

local eventRefs = {} -- [event]=count
local CORE_EVENTS = {
  ADDON_LOADED = true,
  PLAYER_LOGIN = true,
  PLAYER_REGEN_ENABLED = true,
}

local function SortModules()
  table.sort(moduleList, function(a, b)
    local pa = tonumber(a.priority) or 100
    local pb = tonumber(b.priority) or 100
    if pa == pb then
      return (a.name or "") < (b.name or "")
    end
    return pa < pb
  end)
end

local function EnsureEnabledState(mod)
  local db = RS.db and RS.db.profile
  if not db then return end
  if db.modules[mod.name] == nil then
    db.modules[mod.name] = (mod.enabledByDefault ~= false)
  end
end

local function RegisterModuleEvents(mod)
  if type(mod.events) ~= "table" then return end
  for _, ev in ipairs(mod.events) do
    if type(ev) == "string" and ev ~= "" and not CORE_EVENTS[ev] then
      eventRefs[ev] = (eventRefs[ev] or 0) + 1
      if eventRefs[ev] == 1 then
        CoreFrame:RegisterEvent(ev)
        RS:Trace(mod.name, "RegisterEvent:", ev)
      end
    end
  end
end

local function UnregisterModuleEvents(mod)
  if type(mod.events) ~= "table" then return end
  for _, ev in ipairs(mod.events) do
    if type(ev) == "string" and ev ~= "" and not CORE_EVENTS[ev] then
      local c = (eventRefs[ev] or 0) - 1
      if c <= 0 then
        eventRefs[ev] = nil
        CoreFrame:UnregisterEvent(ev)
        RS:Trace(mod.name, "UnregisterEvent:", ev)
      else
        eventRefs[ev] = c
      end
    end
  end
end

function RS:RegisterModule(name, mod)
  -- Backwards-compatible signature: RegisterModule(moduleTable)
  if type(name) == "table" and mod == nil then
    mod = name
    name = mod.name
  end

  assert(type(name) == "string" and name ~= "", "RegisterModule: name must be a non-empty string")
  assert(type(mod) == "table", "RegisterModule: module must be a table")

  if modules[name] then
    self:Warn("Module already registered:", name)
    return false
  end

  mod.name = mod.name or name
  mod.version = mod.version or "0"
  mod.priority = mod.priority or 100

  mod.events = mod.events or nil
  mod.blizzardAddons = mod.blizzardAddons or mod.addons or nil

  mod.__rsEnabled = false
  mod.__rsInited = false

  modules[name] = mod
  moduleList[#moduleList + 1] = mod
  SortModules()

  EnsureEnabledState(mod)

  self:Trace("Core", "Module registered:", name, "prio=", mod.priority)

  if RS._ready and type(mod.OnInit) == "function" then
    self:RunOrQueue("ModuleInit:" .. name, mod.OnInit, mod, self)
    mod.__rsInited = true
  end

  return true
end

function RS:GetModule(name)
  return modules[name]
end

-- Returns module names in current priority order.
function RS:GetModuleNames()
  local out = {}
  for _, m in ipairs(moduleList) do
    out[#out + 1] = m.name
  end
  return out
end



function RS:IsModuleSessionDisabled(name)
  return self._sessionDisabled and self._sessionDisabled[name] and true or false
end

function RS:ClearModuleSessionDisabled(name)
  if self._sessionDisabled then self._sessionDisabled[name] = nil end
end

function RS:ResetSessionDisables()
  if self._sessionDisabled then
    for k in pairs(self._sessionDisabled) do self._sessionDisabled[k] = nil end
  end
  if self._moduleErrorCount then
    for k in pairs(self._moduleErrorCount) do self._moduleErrorCount[k] = nil end
  end
end

function RS:GetModuleHealth(name)
  return {
    disabled = self:IsModuleSessionDisabled(name),
    errors = (self._moduleErrorCount and self._moduleErrorCount[name]) or 0,
    lastError = (self._moduleLastError and self._moduleLastError[name]) or nil,
    lastErrorTime = (self._moduleLastErrorTime and self._moduleLastErrorTime[name]) or nil,
    limit = self._moduleErrorLimit or 3,
  }
end

function RS:_RecordModuleError(name, err)
  name = name or "(unknown)"
  local c = (self._moduleErrorCount and self._moduleErrorCount[name]) or 0
  c = c + 1
  self._moduleErrorCount[name] = c
  self._moduleLastError[name] = tostring(err)
  self._moduleLastErrorTime[name] = GetTime()

  local limit = self._moduleErrorLimit or 3
  if c >= limit and not self:IsModuleSessionDisabled(name) then
    self._sessionDisabled[name] = true
    self:Error("Module auto-disabled for this session (repeated errors):", name, "count=", c)
  end
end

function RS:_RecordModuleSuccess(name)
  -- small decay to avoid permanent penalty if module stabilizes
  local c = (self._moduleErrorCount and self._moduleErrorCount[name]) or 0
  if c > 0 then
    self._moduleErrorCount[name] = c - 1
  end
end
function RS:IsModuleEnabled(name)
  local mod = modules[name]
  if not mod then return false end
  if self:IsModuleSessionDisabled(name) then return false end
  local db = self.db and self.db.profile
  if not db then return (mod.enabledByDefault ~= false) end
  return db.modules[name] ~= false
end

local function StartModule(mod)
  if not mod or mod.__rsEnabled then return end
  if not RS:IsModuleEnabled(mod.name) then return end

  RegisterModuleEvents(mod)
  local theme = RS:GetTheme()

  if not mod.__rsInited and type(mod.OnInit) == "function" then
    RS:RunOrQueue("ModuleInit:" .. mod.name, mod.OnInit, mod, RS)
    mod.__rsInited = true
  end

  if type(mod.OnEnable) == "function" then
    RS:RunOrQueue("ModuleEnable:" .. mod.name, mod.OnEnable, mod, RS, theme)
  end

  mod.__rsEnabled = true
end

local function StopModule(mod)
  if not mod or not mod.__rsEnabled then return end
  UnregisterModuleEvents(mod)
  if type(mod.OnDisable) == "function" then
    RS:RunOrQueue("ModuleDisable:" .. mod.name, mod.OnDisable, mod, RS)
  end
  mod.__rsEnabled = false
end

function RS:EnableModule(name)
  local mod = modules[name]
  if not mod then return false end
  self:ClearModuleSessionDisabled(name)
  if self.db and self.db.profile then
    self.db.profile.modules[name] = true
  end
  StartModule(mod)
  self:ApplyModule(mod)
  return true
end

function RS:DisableModule(name)
  local mod = modules[name]
  if not mod then return false end
  if self.db and self.db.profile then
    self.db.profile.modules[name] = false
  end
  StopModule(mod)
  return true
end

function RS:ListModules()
  for _, mod in ipairs(moduleList) do
    local on = self:IsModuleEnabled(mod.name)
    local started = mod.__rsEnabled and "started" or "stopped"
    self:Log(string.format("Module: %s (%s, %s)", mod.name, on and "enabled" or "disabled", started))
  end
  self:Log("Modules total:", #moduleList)
end

function RS:NotifyModules(method, ...)
  for _, mod in ipairs(moduleList) do
    if self:IsModuleEnabled(mod.name) and type(mod[method]) == "function" then
      SafeCall(mod.name .. ":" .. method, mod[method], mod, self, ...)
    end
  end
end

-- -----------------------------------------------------------------------------
-- Apply pipeline + helpers
-- -----------------------------------------------------------------------------

function RS:FrameOnce(frame, key)
  if not frame then return false end
  local t = frame.__RothSkinner
  if not t then
    t = {}
    frame.__RothSkinner = t
  end
  if t[key] then return false end
  t[key] = true
  return true
end

function RS:GetFrame(path)
  if type(path) == "table" then return path end
  if type(path) ~= "string" or path == "" then return nil end

  local first, rest = path:match("^([%w_]+)%.?(.*)$")
  local obj = _G[first]
  if not obj then return nil end
  if rest == "" then return obj end

  for part in rest:gmatch("([%w_]+)") do
    if type(obj) ~= "table" then return nil end
    obj = obj[part]
    if not obj then return nil end
  end
  return obj
end

function RS:UnpackColor(c, defaultA)
  if type(c) ~= "table" then
    return 1, 1, 1, defaultA or 1
  end
  if c.r ~= nil then
    return c.r or 1, c.g or 1, c.b or 1, (c.a ~= nil and c.a or (defaultA or 1))
  end
  return c[1] or 1, c[2] or 1, c[3] or 1, (c[4] ~= nil and c[4] or (defaultA or 1))
end

function RS:ColorNineSlice(frameOrNineSlice, r, g, b, a)
  local nsObj = frameOrNineSlice
  if not nsObj then return end
  if nsObj.NineSlice then nsObj = nsObj.NineSlice end

  local keys = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
    "Center",
  }

  for _, k in ipairs(keys) do
    local tex = nsObj[k]
    if tex and tex.SetVertexColor then
      tex:SetVertexColor(r, g, b, a or 1)
    end
  end
end

function RS:HookOnShow(frame, key, fn)
  if not frame or not frame.HookScript or type(fn) ~= "function" then return end
  local hookKey = "OnShow:" .. (key or "")
  if not self:FrameOnce(frame, hookKey) then return end

  frame:HookScript("OnShow", function(f)
    self:RunOrQueue("OnShow:" .. (key or tostring(f)), fn, f)
  end)

  if frame.IsShown and frame:IsShown() then
    self:RunOrQueue("OnShowImmediate:" .. (key or tostring(frame)), fn, frame)
  end
end

function RS:ApplyModule(mod)
  if not mod or not self:IsModuleEnabled(mod.name) then return end
  local theme = self:GetTheme()
  if type(mod.Apply) ~= "function" then return end

  self:RunOrQueue("Apply:" .. mod.name, function()
    local st = GetModStats(mod.name)
    if st then
      st.lastApply = GetTime()
      st.lastError = nil
    end

    local t0 = debugprofilestop and debugprofilestop() or nil
    local ok, err = xpcall(function()
      mod.Apply(mod, self, theme)
    end, geterrorhandler())

    if t0 and st then
      st.lastApplyMS = (debugprofilestop() - t0)
    end

    if not ok then
      if st then st.lastError = tostring(err) end
    self:_RecordModuleError(mod.name, err)
      self:Error("Apply module failed:", mod.name, err)
      return
    end


    -- session health tracking
    self:_RecordModuleSuccess(mod.name)

    if st and st.lastApplyMS then
      self:Trace(mod.name, string.format("apply ms=%.2f", st.lastApplyMS))
    else
      self:Trace(mod.name, "applied")
    end
  end)
end

function RS:ApplyAll()
  local theme = self:GetTheme()
  if not theme then
    self:Debug("ApplyAll skipped: no active theme")
    return
  end

  for _, mod in ipairs(moduleList) do
    if self:IsModuleEnabled(mod.name) then
      self:ApplyModule(mod)
    end
  end
end



-- -----------------------------------------------------------------------------
-- Import / Export (dev)
-- -----------------------------------------------------------------------------

local function URLEncode(s)
  s = tostring(s or "")
  s = s:gsub("%%", "%%%%")
  s = s:gsub("[^%w%-%_%.%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return s
end

local function URLDecode(s)
  s = tostring(s or "")
  s = s:gsub("%+", " ")
  s = s:gsub("%%(%x%x)", function(h)
    return string.char(tonumber(h, 16))
  end)
  return s
end

local function EncodeColor(c)
  if type(c) ~= "table" then return nil end
  local r, g, b, a = RS:UnpackColor(c, 1)
  return string.format("c:%.3f,%.3f,%.3f,%.3f", r, g, b, a)
end

local function DecodeColor(s)
  local r, g, b, a = s:match("^c:([%d%.%-]+),([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)$")
  r, g, b, a = tonumber(r), tonumber(g), tonumber(b), tonumber(a)
  if not r or not g or not b or not a then return nil end
  return { r = r, g = g, b = b, a = a }
end

local function ParseScalar(s)
  if s == "true" then return true end
  if s == "false" then return false end
  local n = tonumber(s)
  if n ~= nil then return n end
  return s
end

local function SetDeep(root, path, value)
  if type(root) ~= "table" or type(path) ~= "string" then return end
  local parts = {}
  for p in path:gmatch("([%w_]+)") do
    parts[#parts + 1] = p
  end
  if #parts == 0 then return end
  local t = root
  for i = 1, #parts - 1 do
    local k = parts[i]
    if type(t[k]) ~= "table" then t[k] = {} end
    t = t[k]
  end
  t[parts[#parts]] = value
end

local function Flatten(out, prefix, t, depth)
  depth = (depth or 0) + 1
  if depth > 6 then return end
  if type(t) ~= "table" then return end

  for k, v in pairs(t) do
    local key = prefix .. tostring(k)

    if type(v) == "table" then
      -- color tables
      if (v.r ~= nil or v[1] ~= nil) and (v.g ~= nil or v[2] ~= nil) and (v.b ~= nil or v[3] ~= nil) then
        local enc = EncodeColor(v)
        if enc then
          out[#out + 1] = key .. "=" .. URLEncode(enc)
        end
      else
        Flatten(out, key .. ".", v, depth)
      end
    elseif type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
      out[#out + 1] = key .. "=" .. URLEncode(tostring(v))
    end
  end
end

function RS:ExportSettings()
  if not self.db or not self.db.profile then return "" end
  local p = self.db.profile
  local out = {}

  out[#out + 1] = "ver=" .. URLEncode(self.version or "")
  out[#out + 1] = "theme=" .. URLEncode(p.activeTheme or "")
  out[#out + 1] = "devMode=" .. URLEncode(tostring((p.ui and p.ui.devMode) and true or false))

  Flatten(out, "rm.", p.rothmode or {})
  Flatten(out, "fx.", p.fx or {})
  Flatten(out, "msq.", p.masque or {})

  return "RSX1|" .. table.concat(out, ";")
end

function RS:ImportSettings(s)
  if type(s) ~= "string" or s == "" then return false, "empty" end
  if not self.db or not self.db.profile then return false, "no db" end

  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s:sub(1, 5) ~= "RSX1|" then
    return false, "bad header"
  end

  local payload = s:sub(6)
  local p = self.db.profile

  for pair in payload:gmatch("([^;]+)") do
    local k, v = pair:match("^([^=]+)=(.*)$")
    if k and v then
      k = k:gsub("^%s+", ""):gsub("%s+$", "")
      v = URLDecode(v)

      local val
      if v:sub(1,2) == "c:" then
        val = DecodeColor(v)
      else
        val = ParseScalar(v)
      end

      if k == "theme" and type(val) == "string" and val ~= "" then
        p.activeTheme = val
      elseif k == "devMode" then
        p.ui = p.ui or {}
        p.ui.devMode = (val == true)
      elseif k:sub(1,3) == "rm." then
        p.rothmode = p.rothmode or {}
        SetDeep(p.rothmode, k:sub(4), val)
      elseif k:sub(1,3) == "fx." then
        p.fx = p.fx or {}
        SetDeep(p.fx, k:sub(4), val)
      elseif k:sub(1,4) == "msq." then
        p.masque = p.masque or {}
        SetDeep(p.masque, k:sub(5), val)
      end
    end
  end

  self:_SetActiveTheme(p.activeTheme or "AshBlood", { noApply = true, silent = true })
  self:ApplyAll()
  return true
end


-- -----------------------------------------------------------------------------
-- Frame inspection helpers (dev)
-- -----------------------------------------------------------------------------

local function SafeName(obj)
  if not obj then return "(nil)" end
  if obj.GetName then
    local n = obj:GetName()
    if n and n ~= "" then return n end
  end
  return tostring(obj)
end

function RS:InspectFrame(frame, maxParents)
  frame = frame or GetMouseFocus()
  if not frame then
    self:Log("Inspect: no frame")
    return
  end

  self:Log("Inspect:", SafeName(frame), "type=", frame.GetObjectType and frame:GetObjectType() or "?")
  self:Log("Shown=", frame.IsShown and frame:IsShown() or "?", "Strata=", frame.GetFrameStrata and frame:GetFrameStrata() or "?", "Level=", frame.GetFrameLevel and frame:GetFrameLevel() or "?")

  if frame.NineSlice then
    self:Log("Has NineSlice")
  end
  if frame.SetBackdrop then
    self:Log("Has Backdrop API")
  end

  -- Regions summary
  if frame.GetRegions then
    local regions = { frame:GetRegions() }
    local tex, font, other = 0, 0, 0
    for _, r in ipairs(regions) do
      if r and r.GetObjectType then
        local t = r:GetObjectType()
        if t == "Texture" then tex = tex + 1
        elseif t == "FontString" then font = font + 1
        else other = other + 1 end
      end
    end
    self:Log("Regions:", "Texture=", tex, "FontString=", font, "Other=", other, "Total=", #regions)
  end

  -- Parent chain
  maxParents = tonumber(maxParents) or 8
  local p = frame
  for i = 1, maxParents do
    p = p.GetParent and p:GetParent() or nil
    if not p then break end
    self:Log("Parent[" .. i .. "]:", SafeName(p), p.GetObjectType and p:GetObjectType() or "?")
  end
end

-- -----------------------------------------------------------------------------
-- Event routing
-- -----------------------------------------------------------------------------

local function RouteEventToModules(event, ...)
  for _, mod in ipairs(moduleList) do
    if RS:IsModuleEnabled(mod.name) and type(mod.OnEvent) == "function" then
      if type(mod.events) == "table" then
        local ok = false
        for _, e in ipairs(mod.events) do
          if e == event then ok = true break end
        end
        if ok then
          SafeCall(mod.name .. ":OnEvent:" .. event, mod.OnEvent, mod, RS, event, ...)
        end
      else
        SafeCall(mod.name .. ":OnEvent:" .. event, mod.OnEvent, mod, RS, event, ...)
      end
    end
  end
end

local function HandleAddonLoaded(loadedName)
  for _, mod in ipairs(moduleList) do
    if RS:IsModuleEnabled(mod.name) then
      local list = mod.blizzardAddons
      if type(list) == "table" then
        for _, aName in ipairs(list) do
          if aName == loadedName then
            if type(mod.OnAddonLoaded) == "function" then
              RS:RunOrQueue(mod.name .. ":OnAddonLoaded:" .. aName, mod.OnAddonLoaded, mod, RS, aName)
            end
            RS:ApplyModule(mod)
            break
          end
        end
      end
    end
  end
end

-- -----------------------------------------------------------------------------
-- Slash commands
-- -----------------------------------------------------------------------------

local function PrintHelp()
  RS:Log("Commands:")
  RS:Log("/rothskin status")
  RS:Log("/rothskin debug [on|off|toggle]")
  RS:Log("/rothskin trace <module>|all [on|off|toggle]")
  RS:Log("/rothskin tail [N] [module]")
  RS:Log("/rothskin clearlog")
  RS:Log("/rothskin stats <module>|all")
  RS:Log("/rothskin inspect [parents]")
  RS:Log("/rothskin theme <name>")
  RS:Log("/rothskin themes")
  RS:Log("/rothskin modules")
  RS:Log("/rothskin enable <module>")
  RS:Log("/rothskin disable <module>")
  RS:Log("/rothskin claims")
  RS:Log("/rothskin apply")
  RS:Log("/rothskin doctor")
  RS:Log("/rothskin reseterrors")
  RS:Log("/rothskin export")
  RS:Log("/rothskin import <string>")
end

SLASH_ROTHSKINNER1 = "/rothskin"
SlashCmdList.ROTHSKINNER = function(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd, rest = msg:match("^(%S+)%s*(.*)$")
  cmd = cmd and cmd:lower() or ""

  if cmd == "" or cmd == "help" then
    PrintHelp()
    return
  end

  

  if cmd == "doctor" then
    RS:Log("Doctor:")
    for _, name in ipairs(RS:GetModuleNames()) do
      local h = RS:GetModuleHealth(name)
      if h.disabled or (h.errors and h.errors > 0) then
        RS:Log(" -", name, h.disabled and "[DISABLED]" or "", "errors=", h.errors or 0, h.lastError and ("last=" .. tostring(h.lastError)) or "")
      end
    end
    RS:Log("Use the Doctor settings page for export/import and full status.")
    return
  end

  if cmd == "reseterrors" then
    RS:ResetSessionDisables()
    RS:Log("Session error state cleared.")
    return
  end

  if cmd == "export" then
    RS:Log(RS:ExportSettings())
    return
  end

  if cmd == "import" then
    local ok, err = RS:ImportSettings(rest)
    RS:Log(ok and "Import OK" or ("Import failed: " .. tostring(err)))
    return
  end
if cmd == "debug" then
    local r = (rest or ""):lower()
    if r == "" or r == "toggle" then
      RS.db.profile.debug = not RS.db.profile.debug
    elseif r == "on" or r == "1" or r == "true" then
      RS.db.profile.debug = true
    elseif r == "off" or r == "0" or r == "false" then
      RS.db.profile.debug = false
    end
    RS:Log("Debug:", RS.db.profile.debug and "ON" or "OFF")
    return
  end

  if cmd == "trace" then
    local modName, mode = rest:match("^(%S+)%s*(.*)$")
    modName = modName or ""
    mode = (mode or ""):lower()
    if modName == "" then
      RS:Log("trace: missing module name")
      return
    end

    local function setTrace(k)
      if mode == "" or mode == "toggle" then
        RS.db.profile.trace[k] = not RS.db.profile.trace[k]
      elseif mode == "on" or mode == "1" or mode == "true" then
        RS.db.profile.trace[k] = true
      elseif mode == "off" or mode == "0" or mode == "false" then
        RS.db.profile.trace[k] = false
      end
      RS:Log("Trace", k .. ":", RS.db.profile.trace[k] and "ON" or "OFF")
    end

    if modName == "all" then
      for _, m in ipairs(moduleList) do
        setTrace(m.name)
      end
    else
      setTrace(modName)
    end
    return
  end

  if cmd == "tail" then
    local a, b = rest:match("^(%S*)%s*(.*)$")
    local n = tonumber(a)
    if n then
      RS:Tail(n, b ~= "" and b or nil)
    else
      RS:Tail(40, a ~= "" and a or nil)
    end
    return
  end

  if cmd == "clearlog" then
    RS:ClearLog()
    return
  end

  if cmd == "stats" then
    rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if rest == "" then
      RS:Log("Stats: specify module name or 'all'")
      RS:Log("Modules:", table.concat(RS:GetModuleNames(), ", "))
      return
    end
    if rest:lower() == "all" then
      for _, name in ipairs(RS:GetModuleNames()) do
        local st = RS:GetStats(name)
        if st then
          RS:Log("Stats:", name, "ms=", st.lastApplyMS or "?", st.lastError and ("error=" .. tostring(st.lastError)) or "")
        end
      end
      return
    end
    RS:PrintStats(rest)
    return
  end

  if cmd == "inspect" then
    RS:InspectFrame(GetMouseFocus(), tonumber(rest) or 8)
    return
  end

  if cmd == "status" then
    local qlen, running = RS:GetQueueSize()
    RS:Log("Version:", RS.version)
    RS:Log("Active theme:", RS:GetThemeName() or "(none)")
    RS:Log("Queue:", qlen, running and "(running)" or "(idle)")
    RS:ListModules()
    return
  end

  if cmd == "themes" then
    RS:ListThemes()
    return
  end

  if cmd == "theme" then
    if rest == "" then
      RS:Log("Active theme:", RS:GetThemeName() or "(none)")
      return
    end
    RS:SetActiveTheme(rest)
    return
  end

  if cmd == "modules" then
    RS:ListModules()
    return
  end

  if cmd == "enable" then
    if rest ~= "" then RS:EnableModule(rest) end
    return
  end

  if cmd == "disable" then
    if rest ~= "" then RS:DisableModule(rest) end
    return
  end

  if cmd == "claims" then
    RS:ListClaims()
    return
  end

  if cmd == "apply" then
    RS:ApplyAll()
    return
  end

  RS:Log("Unknown command:", cmd)
  PrintHelp()
end

-- -----------------------------------------------------------------------------
-- Core init
-- -----------------------------------------------------------------------------

CoreFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local loaded = ...

    if loaded == ADDON_NAME then
      InitDB()
      RS._ready = true

      -- Initialize registered modules.
      for _, mod in ipairs(moduleList) do
        EnsureEnabledState(mod)
        if type(mod.OnInit) == "function" then
          RS:RunOrQueue("ModuleInit:" .. mod.name, mod.OnInit, mod, RS)
          mod.__rsInited = true
        end
      end

      -- Theme selection (themes should be registered by now via TOC load order).
      local themeName = (RS.db.profile and RS.db.profile.activeTheme) or DEFAULTS.profile.activeTheme
      if themes[themeName] then
        RS:_SetActiveTheme(themeName, { noApply = true, noNotify = true, silent = true })
      else
        for k in pairs(themes) do
          RS:_SetActiveTheme(k, { noApply = true, noNotify = true, silent = true })
          break
        end
      end

      -- Start enabled modules once theme exists.
      for _, mod in ipairs(moduleList) do
        if RS:IsModuleEnabled(mod.name) then
          StartModule(mod)
        end
      end

      RS:NotifyModules("OnThemeChanged", RS:GetTheme())

      RS:Log("Loaded", RS.name, "v" .. RS.version, "theme=", RS:GetThemeName() or "(none)")

      return
    end

    HandleAddonLoaded(loaded)
    return
  end

  if event == "PLAYER_LOGIN" then
    RS:ApplyAll()
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    FlushQueue()
    RouteEventToModules(event, ...)
    return
  end

  RouteEventToModules(event, ...)
end)

CoreFrame:RegisterEvent("ADDON_LOADED")
CoreFrame:RegisterEvent("PLAYER_LOGIN")
CoreFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
