-- Roth_Skinner
-- Retail 12.1 combat-safe execution queue.
--
-- Core.lua's original chunk runner only checked combat before the first flush.
-- Combat can begin between zero-delay chunks, so every chunk and every job must
-- re-check lockdown. This overlay is loaded immediately after Core.lua and
-- replaces the public queue/budget APIs before themes or modules register work.

local ADDON_NAME, ns = ...
local RS = (ns and ns.RothSkinner) or _G.RothSkinner
if not RS then
  return
end

RS.version = "0.6.2"

local unpack = unpack or table.unpack
local pending = {}
local queueRunning = false
local resumeFrame = CreateFrame("Frame")

local function SafeCall(tag, fn, ...)
  local args = { ... }
  local ok, result = xpcall(function()
    return fn(unpack(args))
  end, geterrorhandler())

  if not ok then
    RS:Error(tostring(tag or "(no tag)"), result)
  end

  return ok, result
end

local function Queue(tag, fn, ...)
  if type(fn) ~= "function" then
    return false
  end

  pending[#pending + 1] = {
    tag = tostring(tag or "(no tag)"),
    fn = fn,
    args = { ... },
  }
  RS:Debug("Queued:", tag, "(len=", #pending, ")")
  return true
end

local function RunQueueChunk()
  if InCombatLockdown() then
    queueRunning = false
    return
  end

  queueRunning = true
  local budget = 40

  while budget > 0 and #pending > 0 do
    if InCombatLockdown() then
      break
    end

    budget = budget - 1
    local job = table.remove(pending, 1)
    if job and type(job.fn) == "function" then
      SafeCall(job.tag, job.fn, unpack(job.args))
    end
  end

  if #pending == 0 then
    queueRunning = false
    return
  end

  if InCombatLockdown() then
    queueRunning = false
    return
  end

  C_Timer.After(0, RunQueueChunk)
end

local function FlushQueue()
  if queueRunning or #pending == 0 or InCombatLockdown() then
    return
  end
  RunQueueChunk()
end

function RS:RunOrQueue(tag, fn, ...)
  if type(fn) ~= "function" then
    return false
  end

  if InCombatLockdown() then
    Queue(tag, fn, ...)
    return false
  end

  return SafeCall(tag, fn, ...)
end

function RS:GetQueueSize()
  return #pending, queueRunning
end

function RS:RunBudgeted(tag, stepFn, opts)
  if type(stepFn) ~= "function" then
    return false
  end

  opts = opts or {}
  local perTickMS = tonumber(opts.perTickMS) or 2.5
  local maxSteps = tonumber(opts.maxStepsPerTick) or 200
  local resumeAfterCombat = opts.resumeInCombat ~= false
  local resumeQueued = false

  local function Tick()
    if InCombatLockdown() then
      if resumeAfterCombat and not resumeQueued then
        resumeQueued = true
        Queue("BudgetedResume:" .. tostring(tag), function()
          resumeQueued = false
          Tick()
        end)
      end
      return
    end

    local started = debugprofilestop and debugprofilestop() or nil
    local steps = 0

    while steps < maxSteps do
      if InCombatLockdown() then
        if resumeAfterCombat and not resumeQueued then
          resumeQueued = true
          Queue("BudgetedResume:" .. tostring(tag), function()
            resumeQueued = false
            Tick()
          end)
        end
        return
      end

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

      if started and (debugprofilestop() - started) >= perTickMS then
        break
      end
    end

    C_Timer.After(0, Tick)
  end

  Tick()
  return true
end

resumeFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
resumeFrame:SetScript("OnEvent", FlushQueue)
