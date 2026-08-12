--[[
Module: FX_Frames

Purpose
- Provide a global, theme-driven decoration layer for Blizzard panels/popups.
- Adds optional border + outer glow overlay textures.
- Works alongside RothMode_Global (which focuses on recolor + background/gradient).

Design constraints
- No hard dependency on Masque.
- Conservative coverage by default (UIPanelWindows + key popups).
- Safe in combat: visual-only; if the client blocks a specific call, we simply skip.

Config
- db.profile.fx.frames.*

Notes
- This is intentionally a *framework* layer; the look is finalized in theme assets.
- Artists can replace Media/textures/*.tga without changing code.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "FX_Frames",
  version = "0.5.0",
  priority = 60,
  enabledByDefault = true,
  events = { "PLAYER_LOGIN" },
}

local function GetCfg(core)
  local p = core.db and core.db.profile
  local fx = p and p.fx
  return (fx and fx.frames) or {}
end

local function ThemeTokens(theme)
  local t = theme and theme.tokens
  return t or {}
end

local function GetColors(core, theme, cfg)
  local tok = ThemeTokens(theme)
  local tc = tok.colors or {}

  if cfg.colorSource == "override" then
    local c = cfg.colors or {}
    return c.border, c.glow
  end

  -- theme by default
  return (tc.panelBorder or tc.border), (tc.hover or tc.accentEmber or tc.accent)
end

local function GetTextures(core, theme)
  local tok = ThemeTokens(theme)
  local tt = tok.textures or {}
  return {
    border = tt.border or core:MediaPath("Media\\textures\\border.tga"),
    glow = tt.glow or core:MediaPath("Media\\textures\\glow.tga"),
  }
end

local function FadePulse(tex, period)
  if not tex or not tex.CreateAnimationGroup then return end
  if tex.__rsPulse then return end

  local ag = tex:CreateAnimationGroup()
  ag:SetLooping("REPEAT")

  local a1 = ag:CreateAnimation("Alpha")
  a1:SetFromAlpha(0.0)
  a1:SetToAlpha(1.0)
  a1:SetDuration((period or 1.6) * 0.5)
  a1:SetOrder(1)

  local a2 = ag:CreateAnimation("Alpha")
  a2:SetFromAlpha(1.0)
  a2:SetToAlpha(0.0)
  a2:SetDuration((period or 1.6) * 0.5)
  a2:SetOrder(2)

  tex.__rsPulse = ag
end

local function EnsureOverlay(frame, key, layer, subLevel)
  if not frame or not frame.CreateTexture then return nil end
  if frame[key] and frame[key].GetObjectType then return frame[key] end

  local tex = frame:CreateTexture(nil, layer or "BORDER", nil, subLevel or 0)
  frame[key] = tex
  return tex
end

local function ApplyToFrame(core, theme, frame)
  if not frame or not frame.IsForbidden then return end
  if frame:IsForbidden() then return end

  local cfg = GetCfg(core)
  if not cfg.enabled then return end

  -- Only decorate top-level panels (or explicitly included popups), avoid small widgets.
  local w = frame.GetWidth and frame:GetWidth() or 0
  local h = frame.GetHeight and frame:GetHeight() or 0
  if w < 120 or h < 80 then return end

  local t = GetTextures(core, theme)
  local borderC, glowC = GetColors(core, theme, cfg)
  local br, bg, bb, ba = core:UnpackColor(borderC or (cfg.colors and cfg.colors.border) or {1,1,1,1}, cfg.borderAlpha or 1)
  local gr, gg, gb, ga = core:UnpackColor(glowC or (cfg.colors and cfg.colors.glow) or {1,1,1,1}, cfg.glowAlpha or 1)

  local borderSize = tonumber(cfg.borderSize) or 1
  local glowSize = tonumber(cfg.glowSize) or 6

  if cfg.border then
    local border = EnsureOverlay(frame, "__rsFX_Border", "BORDER", 2)
    if border then
      border:ClearAllPoints()
      border:SetPoint("TOPLEFT", frame, -borderSize, borderSize)
      border:SetPoint("BOTTOMRIGHT", frame, borderSize, -borderSize)
      border:SetTexture(t.border)
      border:SetVertexColor(br, bg, bb, ba)
      border:Show()
      core:StatInc(Module.name, "borders", 1)
    end
  elseif frame.__rsFX_Border then
    frame.__rsFX_Border:Hide()
  end

  if cfg.glow then
    local glow = EnsureOverlay(frame, "__rsFX_Glow", "BACKGROUND", -7)
    if glow then
      glow:ClearAllPoints()
      glow:SetPoint("TOPLEFT", frame, -glowSize, glowSize)
      glow:SetPoint("BOTTOMRIGHT", frame, glowSize, -glowSize)
      glow:SetTexture(t.glow)
      glow:SetBlendMode("ADD")
      glow:SetVertexColor(gr, gg, gb, ga)
      glow:Show()

      if cfg.glowPulse then
        FadePulse(glow, cfg.glowPulsePeriod)
        if glow.__rsPulse then glow.__rsPulse:Play() end
      elseif glow.__rsPulse then
        glow.__rsPulse:Stop()
      end

      core:StatInc(Module.name, "glows", 1)
    end
  elseif frame.__rsFX_Glow then
    if frame.__rsFX_Glow.__rsPulse then frame.__rsFX_Glow.__rsPulse:Stop() end
    frame.__rsFX_Glow:Hide()
  end
end

local function AddRoot(core, frame, label)
  if not frame then return end
  if not frame.GetObjectType or frame:GetObjectType() ~= "Frame" then return end

  if not core:FrameOnce(frame, "FX_Frames:Hook") then return end

  frame:HookScript("OnShow", function(f)
    core:Throttle("FX_Frames:OnShow:" .. (label or tostring(f)), 0.02, function()
      ApplyToFrame(core, core:GetTheme(), f)
    end)
  end)
end

local function ScanUIPanels(core)
  if type(_G.UIPanelWindows) ~= "table" then return end
  for name, _ in pairs(_G.UIPanelWindows) do
    local f = _G[name]
    if f and f.GetObjectType and f:GetObjectType() == "Frame" then
      AddRoot(core, f, "UIPanel:" .. name)
    end
  end
end

local function ScanPopups(core)
  AddRoot(core, _G.GameMenuFrame, "GameMenu")
  AddRoot(core, _G.StaticPopup1, "StaticPopup1")
  AddRoot(core, _G.StaticPopup2, "StaticPopup2")
  AddRoot(core, _G.StaticPopup3, "StaticPopup3")
  AddRoot(core, _G.StaticPopup4, "StaticPopup4")
  AddRoot(core, _G.ColorPickerFrame, "ColorPicker")
  AddRoot(core, _G.SettingsPanel, "SettingsPanel")
end

function Module:Apply(core)
  local cfg = GetCfg(core)
  if not cfg.enabled then return end

  local theme = core:GetTheme()

  -- Attach hooks (future shows will be decorated).
  ScanUIPanels(core)
  ScanPopups(core)

  -- Apply immediately to already shown frames.
  local applied = 0

  -- Targeted immediate pass for common roots.
  if type(_G.UIPanelWindows) == "table" then
    for name, _ in pairs(_G.UIPanelWindows) do
      local f = _G[name]
      if f and f.IsShown and f:IsShown() then
        ApplyToFrame(core, theme, f)
        applied = applied + 1
      end
    end
  end

  for _, f in ipairs({ _G.GameMenuFrame, _G.StaticPopup1, _G.StaticPopup2, _G.StaticPopup3, _G.StaticPopup4, _G.ColorPickerFrame, _G.SettingsPanel }) do
    if f and f.IsShown and f:IsShown() then
      ApplyToFrame(core, theme, f)
      applied = applied + 1
    end
  end

  core:StatInc(Module.name, "applyRuns", 1)
  core:StatInc(Module.name, "immediate", applied)
end

RS:RegisterModule(Module.name, Module)
