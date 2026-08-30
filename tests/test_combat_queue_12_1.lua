local combat = true
local resumeFrame
local scheduled = {}
local errors = {}

local function assertEq(actual, expected, message)
  if actual ~= expected then
    error((message or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

function InCombatLockdown()
  return combat
end

function CreateFrame()
  local frame = { scripts = {} }
  function frame:RegisterEvent(event) self.event = event end
  function frame:SetScript(name, callback) self.scripts[name] = callback end
  resumeFrame = frame
  return frame
end

C_Timer = {
  After = function(_, callback)
    scheduled[#scheduled + 1] = callback
  end,
}

function geterrorhandler()
  return function(message)
    errors[#errors + 1] = tostring(message)
    return message
  end
end

debugprofilestop = nil

local RS = {
  Debug = function() end,
  Error = function(_, ...)
    local parts = {}
    for index = 1, select('#', ...) do
      parts[#parts + 1] = tostring(select(index, ...))
    end
    errors[#errors + 1] = table.concat(parts, " ")
  end,
}

local chunk = assert(loadfile("Core_12_1.lua"))
chunk("Roth_Skinner", { RothSkinner = RS })

assertEq(RS.version, "0.6.2", "overlay version")
assert(resumeFrame and resumeFrame.event == "PLAYER_REGEN_ENABLED", "regen owner was not registered")

local executed = 0
for _ = 1, 45 do
  local result = RS:RunOrQueue("queued-job", function()
    executed = executed + 1
  end)
  assertEq(result, false, "combat job must be queued")
end

local pending, running = RS:GetQueueSize()
assertEq(pending, 45, "initial queue size")
assertEq(running, false, "queue must not run in combat")

combat = false
resumeFrame.scripts.OnEvent()
assertEq(executed, 40, "first chunk budget")
assertEq(#scheduled, 1, "continuation was not scheduled")

pending, running = RS:GetQueueSize()
assertEq(pending, 5, "remaining queue after first chunk")
assertEq(running, true, "queue should own the scheduled continuation")

combat = true
local continuation = table.remove(scheduled, 1)
continuation()
assertEq(executed, 40, "continuation executed after combat started")
pending, running = RS:GetQueueSize()
assertEq(pending, 5, "combat continuation lost queued work")
assertEq(running, false, "combat continuation left queue stuck running")

combat = false
resumeFrame.scripts.OnEvent()
assertEq(executed, 45, "regen did not finish queued work")
pending, running = RS:GetQueueSize()
assertEq(pending, 0, "queue did not drain")
assertEq(running, false, "queue remained running after drain")

local steps = 0
combat = false
assertEq(RS:RunBudgeted("budgeted", function()
  steps = steps + 1
  if steps == 1 then combat = true end
  return steps >= 3
end, { maxStepsPerTick = 10 }), true, "budgeted job did not start")
assertEq(steps, 1, "budgeted loop ignored combat transition")
pending = RS:GetQueueSize()
assertEq(pending, 1, "budgeted resume was not queued exactly once")

combat = false
resumeFrame.scripts.OnEvent()
assertEq(steps, 3, "budgeted job did not resume and finish")
pending = RS:GetQueueSize()
assertEq(pending, 0, "budgeted resume remained queued")
assertEq(#errors, 0, "unexpected errors")

print("PASS: queue and budgeted work recheck combat between chunks and resume exactly once")
