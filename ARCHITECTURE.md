# Architecture

`Core.lua` defines the `RothSkinner` namespace, defaults, module lifecycle, baseline apply queue, and diagnostic state. `Core_12_1.lua` loads immediately afterward and is the Retail 12.1 owner of the public `RunOrQueue`, `RunBudgeted`, and `GetQueueSize` contracts. It rechecks `InCombatLockdown()` before every zero-delay chunk and every queued job, then resumes only after `PLAYER_REGEN_ENABLED`.

The TOC then loads the `AshBlood` theme and a sequence of skinning, policy, FX, Roth Mode, options, doctor, developer, and optional Masque modules.

`RothSkinnerDB` holds profile data and active-theme selection. Themes contribute tokens and asset paths; modules implement concrete visual application. The core owns session module-health state and defers work that cannot run immediately.

The key risks are module failures and combat-sensitive frame changes. Test one module family at a time, toggles/restore behavior, optional Masque integration, reload, queued work across combat transitions, and protected/taint behavior.
