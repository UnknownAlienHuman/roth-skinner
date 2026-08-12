# Architecture

`Core.lua` defines the `RothSkinner` namespace, defaults, module lifecycle, apply queue, and diagnostic state. The TOC then loads the `AshBlood` theme and a sequence of skinning, policy, FX, Roth Mode, options, doctor, developer, and optional Masque modules.

`RothSkinnerDB` holds profile data and active-theme selection. Themes contribute tokens and asset paths; modules implement concrete visual application. The core owns session module-health state and defers work that cannot run immediately.

The key risks are module failures and combat-sensitive frame changes. Test one module family at a time, toggles/restore behavior, optional Masque integration, reload, and combat deferral.
