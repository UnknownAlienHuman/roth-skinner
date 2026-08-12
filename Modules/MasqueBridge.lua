--[[
Module: MasqueBridge

Purpose
- Optional integration with Masque:
  - If Masque is installed, registers a Roth Skinner Masque skin so Masque-managed buttons
    (action bars, bags, etc.) can match the Roth Diablo theme.

Constraints
- Does not bundle Masque, does not require it, does not copy any third-party skin code.
- Uses only Masque public API (LibStub("Masque", true):AddSkin).

Status
- Textures are placeholders from Roth_Skinner/Media. Replace later with proper Diablo art.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "MasqueBridge",
  version = "0.3.0",
  priority = 5,
  enabledByDefault = true,
  events = { "PLAYER_LOGIN" },
  blizzardAddons = { "Masque" },
}

local registered = false

local function TryRegister(core)
  if registered then return end
  if not _G.LibStub then return end

  local MSQ = _G.LibStub("Masque", true)
  if not MSQ or type(MSQ.AddSkin) ~= "function" then return end

  local theme = core:GetTheme()
  local t = theme and theme.tokens
  local colors = t and t.colors

  local border = colors and colors.panelBorder or { r=0.40, g=0.08, b=0.06, a=0.90 }
  local hover = colors and colors.hover or { r=1.00, g=0.36, b=0.16, a=0.25 }

  local texBorder = t and t.textures and t.textures.border or core:MediaPath("Media\\textures\\border.tga")
  local texPanel  = t and t.textures and t.textures.panel  or core:MediaPath("Media\\textures\\panel.tga")

  -- Minimal Masque skin contract: fields are stable public API.
  -- Values tuned for a square button; artists will replace textures later.
  local skin = {
    Version = core.version,
    Shape = "Square",

    Normal = {
      Width = 36,
      Height = 36,
      TexCoords = { 0, 1, 0, 1 },
      Color = { 1, 1, 1, 1 },
      Texture = texBorder,
      EmptyTexture = texBorder,
      EmptyColor = { 1, 1, 1, 1 },
    },

    Border = {
      Width = 36,
      Height = 36,
      TexCoords = { 0, 1, 0, 1 },
      BlendMode = "BLEND",
      Color = { 1, 1, 1, 1 },
      Texture = texBorder,
    },

    Highlight = {
      Width = 36,
      Height = 36,
      TexCoords = { 0, 1, 0, 1 },
      BlendMode = "ADD",
      Color = { hover.r, hover.g, hover.b, hover.a },
      Texture = "Interface\\ChatFrame\\ChatFrameBackground",
    },

    Backdrop = {
      Width = 36,
      Height = 36,
      TexCoords = { 0, 1, 0, 1 },
      Color = { 1, 1, 1, 1 },
      Texture = texPanel,
    },

    Checked = {
      Width = 36,
      Height = 36,
      TexCoords = { 0, 1, 0, 1 },
      BlendMode = "ADD",
      Color = { border.r, border.g, border.b, 0.25 },
      Texture = "Interface\\ChatFrame\\ChatFrameBackground",
    },

    Icon = {
      Width = 32,
      Height = 32,
      TexCoords = { 0.08, 0.92, 0.08, 0.92 },
    },

    Cooldown = {
      Width = 32,
      Height = 32,
    },

    Flash = {
      Width = 32,
      Height = 32,
      Color = { border.r, border.g, border.b, 0.25 },
      Texture = "Interface\\ChatFrame\\ChatFrameBackground",
    },

    Gloss = { Hide = true },
    Disabled = { Hide = true },
  }

  MSQ:AddSkin("Roth Diabolic (Placeholder)", skin, true)
  registered = true
  core:Log("Masque skin registered: Roth Diabolic (Placeholder)")
end

function Module:OnEnable(core)
  core:Claim("Integration:Masque", self.name)
  TryRegister(core)
end

function Module:OnAddonLoaded(core, loaded)
  if loaded == "Masque" then
    TryRegister(core)
  end
end

function Module:OnEvent(core, event)
  if event == "PLAYER_LOGIN" then
    TryRegister(core)
  end
end

RS:RegisterModule(Module.name, Module)
