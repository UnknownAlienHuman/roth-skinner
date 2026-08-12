# Roth_Skinner

Core framework for a global UI reskin in WoW Retail (12.0+).

## Architectural model
- **Core** (this addon): themes + module lifecycle + safe apply queue + diagnostics.
- **Theme packs**: token tables + asset paths (no logic).
- **Modules**: implement actual skinning for specific Blizzard UI families/frames.

This mirrors the *idea* behind oUF (core + external layouts), but for **visual skinning**...

## FX layer (v0.5.0+)
- **FX_Frames**: optional border + outer glow overlays for Blizzard panels/popups.
- **FX_Faders**: mouseover-driven transparency for panels/popups/tooltips.
- **FX_Options**: Settings pages...

## Current project documentation

- Interface: `120000`; version: `0.6.1`; saved variables: `RothSkinnerDB`; optional dependency: `Masque` (not bundled).
- Install by copying `Roth_Skinner` to `World of Warcraft/_retail_/Interface/AddOns/`, then restart or `/reload`.
- Configure the active theme plus enabled skinning, FX, Roth Mode, font, and optional Masque modules in addon settings.
- Development status: no older active tracker was present; the repository now records smoke testing for theme application, module toggles, options, and combat-deferred changes in [todo.md](todo.md).
- [Architecture](ARCHITECTURE.md) · [Code index](CODE_INDEX.md) · [Code graph](CODE_GRAPH.md)

## License

Licensed under the [MIT License](LICENSE). Bundled third-party components remain under their own notices.
