# Comprehensive Addon Audit & PR: Roth_Skinner

**Target Addon:** `Roth_Skinner` (`C:\Development\WoWDevAddons\_Addons\Roth_Skinner`)  
**Target Environment:** World of Warcraft: Midnight — Retail 12.1 (`Interface: 120100`, Build `69497`)  
**Knowledge Base References:** `_Info/KB` (`RT-AUDIT-001`, `RT-AUDIT-002`, `BlizzardUI_Taint_Debug_Cookbook`, `Addon_SavedVariables`)  
**Remote Git Reference:** `github-roth-skinner` (`main` and `fix/retail-12-1-combat-queue-2026-08-29`)  
**Auditor:** Neomorph Addon Workspace Automated Auditor  
**Date:** 2026-09-08  

---

## 1. Executive Summary & Architecture Overview

`Roth_Skinner` is the foundational visual styling framework for the Roth UI ecosystem. Inspired by decoupled architectures such as oUF, it establishes a strict separation of concerns:
- **Core (`Core.lua`):** Manages addon lifecycle, SavedVariables persistence (`RothSkinnerDB`), the module and theme registries, claim arbitrations, deferred execution queues, and developer diagnostics (`/rothskin`).
- **Themes (`Themes/AshBlood/theme.lua`):** Pure data providers exposing visual tokens (colors, font paths, textures) with no procedural logic or lifecycle ownership.
- **Skinning & Policy Modules (`Modules/*`):** Targeted feature packs implementing visual adjustments for Blizzard UI surfaces (`NineSlice_Panels`, `WidgetPolicy_Basics`, `WidgetPolicy_Controls`, `Blizzard_SettingsSkin`), global recolor passes (`RothMode_Global`), dynamic FX overlays and faders (`FX_Frames`, `FX_Faders`, `FX_Dynamics`), and optional third-party skinning hooks (`MasqueBridge`, `Masque_Integration`).

### Upstream Git Synchronization Analysis
Comparing local `HEAD:_Addons/Roth_Skinner` against `remotes/github-roth-skinner/main` reveals that the primary branch is currently identical (synchronized at commit `4f6521d`). 

However, remote branch `remotes/github-roth-skinner/fix/retail-12-1-combat-queue-2026-08-29` contains 8 commits addressing Retail 12.1 combat transitions:
- `e5bf92a fix: recheck combat lockdown between queued chunks`
- `c2a383e chore: target Retail 12.1.0`
- `4dd8c95 docs: index the Retail combat queue owner`
- `dc8c57f docs: document the Retail queue ownership boundary`
- `ee7e9e1 chore: move Retail smoke tests into pull request`
- `c09636a test: cover combat transitions between queued chunks`
- `d88adc0 ci: validate the Retail combat queue overlay`
- `33ce46e chore: remove GitHub Actions validation`

### Critical Evaluation of Upstream Remote Branch
The upstream branch attempted to solve combat re-entrancy during zero-delay chunk continuation (`C_Timer.After(0, RunQueueChunk)`) by introducing an external monkey-patch overlay file, `Core_12_1.lua`. 
While the re-check logic itself is valid, implementing it as a separate overlay file introduced severe architectural flaws:
1. **Violation of RT-AUDIT-002 (Single Runtime Owner):** `Core_12_1.lua` registers a standalone `resumeFrame` on `PLAYER_REGEN_ENABLED`, while `Core.lua`'s `CoreFrame` continues to listen to `PLAYER_REGEN_ENABLED` and flushes its own orphaned `pending` queue. Two competing frames listen to the same event for the same addon.
2. **Unaddressed Critical Bug (Dead `PLAYER_LOGIN` Event Routing):** The upstream branch missed that `Core.lua`'s `PLAYER_LOGIN` handler returns early without calling `RouteEventToModules()`, which breaks 11 modules at login (disabling Blizzard Settings registration for Options, Doctor, FX, and Masque).
3. **Unaddressed Frame Contamination & Taint Risks:** Direct mutation of Blizzard UI frame tables (`frame.__RothSkinner = t`) was left untouched.
4. **Unaddressed Corrupted SavedVariables Recovery (RT-AUDIT-001):** The `DeepCopy` routine does not guard against non-table `dst` types when merging schema defaults.

This PR consolidates the combat queue fix directly into `Core.lua` (eliminating the redundant overlay file and duplicate event owner) while resolving all architectural, taint, and compatibility defects.

---

## 2. Audit Findings & Gap Analysis

### 2.1 Interface & TOC Metadata (Retail 12.1 Compatibility)
- **Finding:** `Roth_Skinner.toc` specifies `## Interface: 120000` (The War Within launch) and version `0.6.1`.
- **Requirement:** Must specify `## Interface: 120100` (Retail 12.1) and declare `## X-Verified-Build: 12.1.0.69497`. Version should be bumped to `0.6.2`.

### 2.2 Critical Bug: Broken `PLAYER_LOGIN` Module Routing
- **File:** `Core.lua:1583-1586`
- **Current Code:**
  ```lua
  if event == "PLAYER_LOGIN" then
    RS:ApplyAll()
    return
  end
  ```
- **Impact:** 
  The early `return` prevents `RouteEventToModules("PLAYER_LOGIN", ...)` from ever executing.
  Eleven modules define `events = { "PLAYER_LOGIN" }` and rely on login initialization:
  - `OptionsPanel.lua`: Never calls `EnsurePanel()` or `RegisterInBlizzardSettings()`. Roth Skinner's main settings panel is missing from Blizzard Settings!
  - `DoctorPanel.lua`: Settings registration never executes.
  - `FX_Options.lua`: Frame and Fader settings panels never register with `Settings.RegisterCanvasLayoutCategory()`.
  - `Masque_Options.lua`: Masque integration settings never register.
  - `Blizzard_SettingsSkin.lua`: Never hooks `SettingsPanel` on login.
  - `NineSlice_Panels.lua` & `WidgetPolicy_Basics.lua`: Delayed login rescans are canceled.
  - `MasqueBridge.lua`: Fails to register the Roth skin into Masque at login.
- **Resolution:**
  ```lua
  if event == "PLAYER_LOGIN" then
    RS:ApplyAll()
    RouteEventToModules(event, ...)
    return
  end
  ```

### 2.3 Event Handler Method Dispatch Mismatch (`mod[event]` vs `mod.OnEvent`)
- **Files:** `Core.lua:1293-1309`, `Modules/DoctorPanel.lua:372`, `Modules/RothMode_Global.lua:648`
- **Finding:**
  `DoctorPanel.lua` defines `function Module:PLAYER_LOGIN(core)` and `RothMode_Global.lua` defines `function Module:PLAYER_LOGIN(core)`. Neither implements `Module:OnEvent(core, event)`.
  In `Core.lua`, `RouteEventToModules` explicitly checks:
  ```lua
  if RS:IsModuleEnabled(mod.name) and type(mod.OnEvent) == "function" then
  ```
  Consequently, `RouteEventToModules` ignores `mod[event]`. Even when `PLAYER_LOGIN` is routed, `RothMode_Global`'s 2.5-second `UISpecialFrames` ticker and initial scan never trigger, and `DoctorPanel` never initializes.
- **Resolution:**
  Update `RouteEventToModules` to resolve either `mod.OnEvent` or `mod[event]`:
  ```lua
  local fn = (type(mod.OnEvent) == "function" and mod.OnEvent)
          or (type(mod[event]) == "function" and mod[event])
  ```

### 2.4 Single Runtime Owner vs Duplicate Overlay (RT-AUDIT-002)
- **Upstream Pattern:**
  The `fix/retail-12-1-combat-queue-2026-08-29` branch introduced `Core_12_1.lua` which instantiated `resumeFrame = CreateFrame("Frame")` registering `PLAYER_REGEN_ENABLED`.
  However, `CoreFrame` in `Core.lua` also registers `PLAYER_REGEN_ENABLED` and calls an internal `FlushQueue()`.
- **Risk:**
  Having two separate frames responding to `PLAYER_REGEN_ENABLED` with two distinct `pending` tables and duplicated queue dispatchers creates fragmented runtime ownership and violates RT-AUDIT-002.
- **Resolution:**
  Consolidate the Retail 12.1 chunk-level combat re-check and single-resume budgeted runner directly into `Core.lua`. `CoreFrame` remains the single runtime owner for all core and module events.

### 2.5 Frame Contamination & Taint Safety
- **Files:** `Core.lua:958-968`, `Modules/NineSlice_Panels.lua:148`, `Modules/WidgetPolicy_Basics.lua:218`, `Modules/WidgetPolicy_Controls.lua:268`
- **Finding:**
  `RS:FrameOnce(frame, key)` writes directly into `frame.__RothSkinner = t`. Modules also clear keys by directly indexing `frame.__RothSkinner[key] = nil`.
  Attaching arbitrary custom tables directly to Blizzard UI frames (such as `SettingsPanel`, `GameMenuFrame`, or secure action buttons skinned through widget policies) risks secure table contamination and UI action forbidden errors during combat lockdown.
- **Resolution:**
  Implement a weak-keyed lookup table `local frameTrackers = setmetatable({}, { __mode = "k" })` inside `Core.lua`.
  Expose `RS:ClearFrameOnce(frame, key)` to allow modules to invalidate caches cleanly without polluting Blizzard frame objects.

### 2.6 SavedVariables Deep-Copy Robustness (RT-AUDIT-001)
- **File:** `Core.lua:221-232`
- **Finding:**
  ```lua
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
  ```
  If a user has an older, corrupted, or migrated SavedVariable where a field that is now a table was previously stored as a boolean or string, `dst = dst or {}` evaluates to the boolean/string. The subsequent loop attempts `dst[k] = ...`, which crashes the addon during `ADDON_LOADED`.
- **Resolution:**
  Enforce type validation: `if type(dst) ~= "table" then dst = {} end` and verify `type(dst[k]) == "table"` before recursing.

### 2.7 Deprecated Mouse Focus APIs
- **Files:** `Core.lua:1248, 1477`, `Modules/FX_Faders.lua:48`
- **Finding:**
  Calling `GetMouseFocus()` directly is deprecated in Retail 11.0+ and 12.1 in favor of `GetMouseFoci()`.
- **Resolution:**
  Adopt the standard fallback wrapper:
  ```lua
  local function SafeGetMouseFocus()
    if GetMouseFoci then
      local foci = GetMouseFoci()
      return foci and foci[1] or nil
    elseif GetMouseFocus then
      return GetMouseFocus()
    end
    return nil
  end
  ```

### 2.8 Unprotected Action Button Scanning in Combat (`Masque_Integration`)
- **File:** `Modules/Masque_Integration.lua:200-245`
- **Finding:**
  `Module:OnEnable`, `Module:OnAddonLoaded`, and `/rothmasque rescan` directly invoked `RunScan(core)` which loops through `ActionButton1..12` and calls `group:AddButton(b)`.
  Invoking this while `InCombatLockdown()` triggers secure action button taint and protected execution failures.
- **Resolution:**
  Wrap all invocations in `core:RunOrQueue("MasqueScan", function() RunScan(core) end)`.

---

## 3. Detailed Pull Request Diffs

### Patch 1: `Roth_Skinner.toc`
Target Interface 120100, bump version to 0.6.2, and declare verified build metadata.

```diff
--- a/_Addons/Roth_Skinner/Roth_Skinner.toc
+++ b/_Addons/Roth_Skinner/Roth_Skinner.toc
@@ -1,8 +1,9 @@
-## Interface: 120000
+## Interface: 120100
 ## Title: Roth Skinner
 ## Notes: Core framework for global UI skinning (themes + modules) for Roth UI.
 ## Author: Roth UI Project
-## Version: 0.6.1
+## Version: 0.6.2
+## X-Verified-Build: 12.1.0.69497
 ## SavedVariables: RothSkinnerDB
 ## OptionalDeps: Masque
```

---

### Patch 2: `Core.lua`
Consolidate Retail 12.1 combat re-check queue into core, route `PLAYER_LOGIN` and `mod[event]`, replace `GetMouseFocus`, protect `DeepCopy` (RT-AUDIT-001), and replace `frame.__RothSkinner` with weak table (RT-AUDIT-002 & Taint).

```diff
--- a/_Addons/Roth_Skinner/Core.lua
+++ b/_Addons/Roth_Skinner/Core.lua
@@ -31,3 +31,3 @@
 RS.name = "Roth_Skinner"
-RS.version = "0.6.1"
+RS.version = "0.6.2"
 
@@ -220,10 +220,13 @@ local DEFAULTS = {
 
 local function DeepCopy(dst, src)
   if type(src) ~= "table" then return src end
-  dst = dst or {}
+  if type(dst) ~= "table" then dst = {} end
   for k, v in pairs(src) do
     if type(v) == "table" then
+      if type(dst[k]) ~= "table" then
+        dst[k] = {}
+      end
       dst[k] = DeepCopy(dst[k], v)
     elseif dst[k] == nil then
       dst[k] = v
@@ -528,7 +531,10 @@ local pending = {}
 local queueRunning = false
 
 local function Queue(tag, fn, ...)
-  pending[#pending + 1] = { tag = tag, fn = fn, args = { ... } }
+  if type(fn) ~= "function" then return false end
+  pending[#pending + 1] = { tag = tostring(tag or "(no tag)"), fn = fn, args = { ... } }
   RS:Debug("Queued:", tag, "(len=", #pending, ")")
+  return true
 end
 
 local function RunQueueChunk()
+  if InCombatLockdown() then
+    queueRunning = false
+    return
+  end
+
   queueRunning = true
 
   local budget = 40 -- per-tick job budget
   while budget > 0 and #pending > 0 do
+    if InCombatLockdown() then
+      break
+    end
     budget = budget - 1
     local job = table.remove(pending, 1)
-    if job and job.fn then
+    if job and type(job.fn) == "function" then
       SafeCall(job.tag, job.fn, unpack(job.args))
     end
   end
 
-  if #pending > 0 then
+  if #pending == 0 then
+    queueRunning = false
+    return
+  end
+
+  if InCombatLockdown() then
+    queueRunning = false
+    return
+  end
+
+  C_Timer.After(0, RunQueueChunk)
 end
 
 function RS:RunOrQueue(tag, fn, ...)
+  if type(fn) ~= "function" then return false end
   if InCombatLockdown() then
     Queue(tag, fn, ...)
     return false
   end
   return SafeCall(tag, fn, ...)
 end
@@ -569,8 +585,14 @@ function RS:RunBudgeted(tag, stepFn, opts)
   local maxSteps = tonumber(opts.maxStepsPerTick) or 200
   local resumeInCombat = (opts.resumeInCombat ~= false)
+  local resumeQueued = false
 
   local function Tick()
     if InCombatLockdown() then
-      if resumeInCombat then
-        Queue("BudgetedResume:" .. tostring(tag), Tick)
+      if resumeInCombat and not resumeQueued then
+        resumeQueued = true
+        Queue("BudgetedResume:" .. tostring(tag), function()
+          resumeQueued = false
+          Tick()
+        end)
       end
       return
     end
@@ -582,6 +604,16 @@ function RS:RunBudgeted(tag, stepFn, opts)
     while steps < maxSteps do
+      if InCombatLockdown() then
+        if resumeInCombat and not resumeQueued then
+          resumeQueued = true
+          Queue("BudgetedResume:" .. tostring(tag), function()
+            resumeQueued = false
+            Tick()
+          end)
+        end
+        return
+      end
+
       steps = steps + 1
       local done
@@ -957,12 +989,20 @@ end
 
+local frameTrackers = setmetatable({}, { __mode = "k" })
+
 function RS:FrameOnce(frame, key)
   if not frame then return false end
-  local t = frame.__RothSkinner
+  local t = frameTrackers[frame]
   if not t then
     t = {}
-    frame.__RothSkinner = t
+    frameTrackers[frame] = t
   end
   if t[key] then return false end
   t[key] = true
   return true
 end
+
+function RS:ClearFrameOnce(frame, key)
+  if not frame then return end
+  local t = frameTrackers[frame]
+  if t then t[key] = nil end
+end
@@ -1245,6 +1285,14 @@ end
 
+local function SafeGetMouseFocus()
+  if GetMouseFoci then
+    local foci = GetMouseFoci()
+    return foci and foci[1] or nil
+  elseif GetMouseFocus then
+    return GetMouseFocus()
+  end
+  return nil
+end
+
 function RS:InspectFrame(frame, maxDepth)
-  frame = frame or GetMouseFocus()
+  frame = frame or SafeGetMouseFocus()
   if not frame then
@@ -1294,5 +1342,6 @@ local function RouteEventToModules(event, ...)
   for _, mod in ipairs(moduleList) do
-    if RS:IsModuleEnabled(mod.name) and type(mod.OnEvent) == "function" then
+    if RS:IsModuleEnabled(mod.name) then
+      local fn = (type(mod.OnEvent) == "function" and mod.OnEvent)
+              or (type(mod[event]) == "function" and mod[event])
+      if fn then
         if type(mod.events) == "table" then
           local ok = false
           for _, e in ipairs(mod.events) do
             if e == event then ok = true break end
           end
           if ok then
-            SafeCall(mod.name .. ":OnEvent:" .. event, mod.OnEvent, mod, RS, event, ...)
+            SafeCall(mod.name .. ":OnEvent:" .. event, fn, mod, RS, event, ...)
           end
         else
-          SafeCall(mod.name .. ":OnEvent:" .. event, mod.OnEvent, mod, RS, event, ...)
+          SafeCall(mod.name .. ":OnEvent:" .. event, fn, mod, RS, event, ...)
         end
       end
     end
   end
 end
@@ -1476,3 +1525,3 @@ function RS:SlashCommand(msg)
   if cmd == "inspect" then
-    RS:InspectFrame(GetMouseFocus(), tonumber(rest) or 8)
+    RS:InspectFrame(SafeGetMouseFocus(), tonumber(rest) or 8)
     return
   end
@@ -1582,4 +1631,5 @@ CoreFrame:SetScript("OnEvent", function(_, event, ...)
   if event == "PLAYER_LOGIN" then
     RS:ApplyAll()
+    RouteEventToModules(event, ...)
     return
   end
```

---

### Patch 3: `Modules/FX_Faders.lua`
Replace legacy `GetMouseFocus()` with Retail-compatible `SafeGetMouseFocus()`.

```diff
--- a/_Addons/Roth_Skinner/Modules/FX_Faders.lua
+++ b/_Addons/Roth_Skinner/Modules/FX_Faders.lua
@@ -47,3 +47,8 @@ local function GetMouseInFrame(frame)
   if frame.IsMouseOver and frame:IsMouseOver() then return true end
-  local mf = _G.GetMouseFocus and _G.GetMouseFocus() or nil
+  local mf = nil
+  if _G.GetMouseFoci then
+    local foci = _G.GetMouseFoci()
+    mf = foci and foci[1] or nil
+  elseif _G.GetMouseFocus then
+    mf = _G.GetMouseFocus()
+  end
   if mf and IsDescendantOf(mf, frame) then return true end
```

---

### Patch 4: `Modules/Masque_Integration.lua`
Wrap button scans in `RunOrQueue` to ensure combat lockdown safety.

```diff
--- a/_Addons/Roth_Skinner/Modules/Masque_Integration.lua
+++ b/_Addons/Roth_Skinner/Modules/Masque_Integration.lua
@@ -204,7 +204,11 @@ function Module:OnAddonLoaded(core, addonName)
   if addonName == "Masque" then
     MSQ = nil
   end
-  RunScan(core)
+  core:RunOrQueue("Masque:OnAddonLoaded", function()
+    RunScan(core)
+  end)
 end
 
 function Module:OnEnable(core)
-  RunScan(core)
+  core:RunOrQueue("Masque:OnEnable", function()
+    RunScan(core)
+  end)
 end
@@ -273,3 +277,5 @@ SlashCmdList.ROTHMASQUE = function(msg)
   if cmd == "rescan" then
-    RunScan(core)
+    core:RunOrQueue("Masque:SlashRescan", function()
+      RunScan(core)
+    end)
     return
   end
```

---

### Patch 5: Cache Invalidation via `ClearFrameOnce`
Prevent direct mutation of `f.__RothSkinner` in policy modules.

**`Modules/NineSlice_Panels.lua`:**
```diff
--- a/_Addons/Roth_Skinner/Modules/NineSlice_Panels.lua
+++ b/_Addons/Roth_Skinner/Modules/NineSlice_Panels.lua
@@ -147,4 +147,4 @@ function Module:OnThemeChanged(core)
     for _, name in ipairs(list) do
       local f = _G[name]
-      if f and f.__RothSkinner then
-        f.__RothSkinner["RSNineSlice:Skinned"] = nil
-      end
+      if f then
+        core:ClearFrameOnce(f, "RSNineSlice:Skinned")
+      end
     end
```

**`Modules/WidgetPolicy_Basics.lua`:**
```diff
--- a/_Addons/Roth_Skinner/Modules/WidgetPolicy_Basics.lua
+++ b/_Addons/Roth_Skinner/Modules/WidgetPolicy_Basics.lua
@@ -217,4 +217,4 @@ function Module:OnThemeChanged(core)
     for frameName in pairs(t) do
       local f = _G[frameName]
-      if f and f.__RothSkinner then
-        f.__RothSkinner["RSWidget:Panel"] = nil
-      end
+      if f then
+        core:ClearFrameOnce(f, "RSWidget:Panel")
       end
     end
```

**`Modules/WidgetPolicy_Controls.lua`:**
```diff
--- a/_Addons/Roth_Skinner/Modules/WidgetPolicy_Controls.lua
+++ b/_Addons/Roth_Skinner/Modules/WidgetPolicy_Controls.lua
@@ -267,4 +267,4 @@ function Module:OnThemeChanged(core)
-  if _G.SettingsPanel and _G.SettingsPanel.__RothSkinner then
-    _G.SettingsPanel.__RothSkinner["RSWidget:Panel"] = nil
+  if _G.SettingsPanel then
+    core:ClearFrameOnce(_G.SettingsPanel, "RSWidget:Panel")
   end
```

---

## 4. Verification & Testing Strategy

### In-Engine Test Matrix
1. **Login & Settings Panel Registration:**
   - Execute `/reload` or enter the world.
   - Verify that `OptionsPanel`, `DoctorPanel`, `Masque_Options`, and `FX_Options` appear under Blizzard's Game Settings -> AddOns list without errors.
   - Execute `/rothskin status`, `/rothskin doctor`, and `/rslog`.
2. **Combat Lockdown Continuity:**
   - Queue skin changes during active combat (e.g. toggle a module or switch theme via `/rothskin theme AshBlood` during combat).
   - Enter combat, execute `/rothmasque rescan`. Confirm no protected execution errors occur and changes are deferred to `pending`.
   - Exit combat (`PLAYER_REGEN_ENABLED`). Verify all deferred chunks execute cleanly and queue drains to 0.
   - Test combat transitions occurring *between* zero-delay chunks: verify the queue pauses and resumes on subsequent combat drop.
3. **Weak Table Taint Verification:**
   - Skin action buttons and unit frame popups.
   - Inspect frame tables using `/dump ActionButton1.__RothSkinner` to confirm `__RothSkinner` is NOT injected onto the frame object.
   - Test spell casting and action button clicks during combat lockdown; verify zero taint log entries in `taint.log`.
4. **SavedVariables Migration:**
   - Test loading with corrupted profile values (e.g., set `RothSkinnerDB.profile.fx = true` in WTF).
   - Confirm `DeepCopy` recovers cleanly to table structures without Lua errors.

---

## 5. Action Items & Next Steps

1. **Apply Patches 1 through 5** directly to the local files in `C:\Development\WoWDevAddons\_Addons\Roth_Skinner`.
2. **Close/Supersede Remote Branch `fix/retail-12-1-combat-queue-2026-08-29`:**
   - The remote branch introduced an unwanted secondary runtime owner (`Core_12_1.lua`). By consolidating the combat chunk safety logic directly into `Core.lua`, `Core_12_1.lua` is rendered completely unnecessary.
3. **Run Architecture Tests:**
   - Execute `.\tools\audit-addon-architecture.ps1` to update `docs/addon-architecture.json` and ensure architecture validation passes.
4. **Push Unified Commit to Remote `main`:**
   - Commit all changes under message: `Roth_Skinner: Retail 12.1 compatibility, single runtime owner consolidation, and login routing fix`.
