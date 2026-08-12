# Agent guide: Roth_Skinner

## Start here

[`Roth_Skinner.toc`](Roth_Skinner.toc) loads `Core.lua`, the `Themes/AshBlood/theme.lua` theme, then modules in explicit order: DevTools/options/doctor, optional Masque modules, example tooltip, fonts, panels/widget policies, Blizzard Settings skin, FX, and Roth Mode. `Core.lua` creates `_G.RothSkinner`/`ns.RothSkinner`, the SavedVariables defaults, `CoreFrame`, module registry, event router, apply queue, and `/rothskin` command surface.

## Runtime map

- `RS:RegisterTheme`/`_SetActiveTheme`/`SetActiveTheme` own theme registration and selection. The AshBlood theme is a token/asset provider; it should not own module lifecycle.
- `RS:RegisterModule` records module contracts (`name`, `enabled`, `events`, `OnEnable`, `OnDisable`, `Apply`, `OnEvent`, etc.). `RS:ApplyAll` calls `ApplyModule`; module failures are counted and can session-disable a module after the configured limit.
- `RS:RunOrQueue`/`RunBudgeted`/`Throttle` defer expensive or protected work. `CoreFrame` registers only `ADDON_LOADED`, `PLAYER_LOGIN`, and `PLAYER_REGEN_ENABLED`, then dynamically registers module events through `RegisterModuleEvents`.
- Options, Doctor, DevTools, FontPolicy, WidgetPolicy, NineSlice, Blizzard Settings, FX, Roth Mode, and Masque files each register one module against the shared `RS` core. `FX_Options.lua`, `RothMode_Options.lua`, `OptionsPanel.lua`, `Masque_Options.lua`, and `DoctorPanel.lua` register Blizzard Settings pages at login.
- Slash surfaces: `/rothskin` (`status`, `debug`, `trace`, `tail`, `clearlog`, `stats`, `inspect`, `theme`, `themes`, `modules`, `enable`, `disable`, `claims`, `apply`, `doctor`, `reseterrors`, `export`, `import`), `/rothmasque` (`status`, `rescan`, `skins`, `auto`), and `/rslog` (viewer, `clear`, `filter`). These are separate handlers in `Core.lua:1334-1357`, `Modules/Masque_Integration.lua:228-230`, and `Modules/DevTools.lua:120-121`.

## State and dependencies

`RothSkinnerDB` holds active theme, module enablement, theme/module options, FX/Roth Mode/font/Masque settings, logs, statistics, and export/import payloads. Module health/session-disabled maps, claims, queue/timers, original font snapshots, and hooked-frame guards are transient. `Masque` is the sole TOC `OptionalDeps`; it is looked up with `LibStub("Masque", true)` and all Masque modules must degrade cleanly when absent. There are no required external addons.

## Change routing

- Core lifecycle/DB/queue/module health: `Core.lua` (`RS:RegisterModule`, `ApplyModule`, `ApplyAll`, event router).
- Theme tokens/assets: `Themes/AshBlood/theme.lua`; keep the theme data-only and update `RS:MediaPath` consumers if paths change.
- Widget/panel/settings skinning: `WidgetPolicy_*`, `NineSlice_Panels.lua`, `Blizzard_SettingsSkin.lua`.
- FX: `FX_Frames.lua` for overlay creation, `FX_Faders.lua` for alpha state, `FX_Dynamics.lua` for event pulses, `FX_Options.lua` for settings.
- Global Roth Mode: `RothMode_Global.lua` and `RothMode_Options.lua`; preserve its periodic ticker and root discovery.
- Fonts and Masque: `FontPolicy.lua` plus `MasqueBridge.lua`/`Masque_Integration.lua`/`Masque_Options.lua`.
- Diagnostics and user control: `DoctorPanel.lua`, `DevTools.lua`, `OptionsPanel.lua`, and slash parsing in `Core.lua`.

## Invariants/risks

- Module application is guarded and idempotent. A failed module may be session-disabled; do not bypass `_RecordModuleError` or reapply blindly from UI.
- Skinning Blizzard frames, fonts, NineSlice objects, secure action buttons, and Masque surfaces can taint/protected-call. Respect `InCombatLockdown`, queue/defer protected mutations, and restore originals on module disable.
- `RothMode_Global` has a 2.5-second ticker and FX modules react to combat/loot/victory events; preserve throttles and avoid per-frame scans.
- Claims/`RS:Claim` prevent two modules from owning the same frame/property. Check existing claims before adding hooks or duplicated mutation.
- Settings pages load at/after `PLAYER_LOGIN`; no module should assume `Settings` is present during file load.

## Verification

Static checks:

```powershell
Get-Content _Addons/Roth_Skinner/Roth_Skinner.toc
rg -n "RothSkinnerDB|RegisterModule|ApplyModule|ApplyAll|InCombatLockdown|Masque|Settings.Register|SlashCmdList" _Addons/Roth_Skinner
```

In-game: `/rothskin help`, status/modules/themes/doctor/devtools, switch AshBlood theme, enable/disable one module family at a time, verify restore, reload/login, enter/leave combat, open Blizzard Settings, test fonts/NineSlice/FX/Roth Mode, and test both Masque installed and absent. Inspect module health/error counters and BugGrabber for taint/protected-action failures.

## Unknowns

Blizzard frame topology and Masque API availability are build/addon-version dependent. The module contracts and deferral paths are code-truth; exact skin coverage and safe hook timing require the target client.
