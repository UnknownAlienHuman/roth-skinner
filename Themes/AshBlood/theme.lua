--[[
Theme pack: AshBlood (placeholder)

This theme intentionally ships with minimal, replaceable assets.
Artists can replace textures in Media/ without changing module code.

Token contract (core expectation)
- theme.tokens.colors.* = {r,g,b,a}
- theme.tokens.fonts.* = font paths
- theme.tokens.textures.* = texture paths

Modules should treat all tokens as optional and always have safe fallbacks.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local function C(r, g, b, a)
  return { r = r, g = g, b = b, a = a }
end

local Theme = {
  name = "AshBlood",
  version = "0.1.2",
  author = "Roth UI",

  tokens = {
    colors = {
      -- Panels / general surfaces
      panelBg      = C(0.06, 0.06, 0.065, 0.55),
      panelBorder  = C(0.40, 0.08, 0.06, 0.90),
      panelInset   = C(0.00, 0.00, 0.00, 0.18),

      -- Text
      text         = C(0.92, 0.90, 0.85, 1.00),
      mutedText    = C(0.65, 0.62, 0.58, 1.00),

      -- Accents
      accentBlood  = C(0.78, 0.10, 0.07, 1.00),
      accentEmber  = C(1.00, 0.52, 0.12, 1.00),
      accentAsh    = C(0.25, 0.25, 0.27, 1.00),

      -- Highlights
      hover        = C(1.00, 0.36, 0.16, 0.18),
      press        = C(1.00, 0.20, 0.12, 0.25),
    },

    fonts = {
      primary = "Fonts\\FRIZQT__.TTF",
      header  = "Fonts\\MORPHEUS.TTF",
      mono    = "Fonts\\ARIALN.TTF",
    },

    textures = {
      -- Placeholder textures (artists replace later)
      panel  = RS:MediaPath("Media\\textures\\panel.tga"),
      border = RS:MediaPath("Media\\textures\\border.tga"),
      glow   = RS:MediaPath("Media\\textures\\glow.tga"),
    },
  },
}

function Theme:OnActivate(core)
  -- Hook point for future (e.g., registering LibSharedMedia).
  core:Debug("Theme", self.name, "activated")
end

RS:RegisterTheme(Theme.name, Theme)
