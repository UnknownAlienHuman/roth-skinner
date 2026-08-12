--[[
Module: FX_Dynamics

Purpose
- Event-driven FX layer for Roth UI.
- Plays short pulses / flashes / glows on registered targets in reaction to gameplay events.

Design goals
- Visual-only (no protected changes), safe in combat.
- Conservative defaults: target only Blizzard bar containers by name.
- Development-friendly: rich logging + test buttons via FX_Options.

Config
- db.profile.fx.dynamics.*

Events
- PLAYER_REGEN_DISABLED: "enter combat" pulse
- PLAYER_REGEN_ENABLED: optional "leave combat" pulse
- LOOT_READY / CHAT_MSG_LOOT: loot pulse (throttled)
- ENCOUNTER_END: victory pulse on success (throttled)

Notes
- We deliberately avoid parsing loot strings; we just react to the event.
- Targets are resolved from globals by name; if frames do not exist, they are skipped.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "FX_Dynamics",
  version = "0.5.1",
  priority = 70,
  enabledByDefault = true,
  events = {
    "PLAYER_LOGIN",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
    "LOOT_READY",
    "CHAT_MSG_LOOT",
    "ENCOUNTER_END",
  },
}

-- -----------------------------------------------------------------------------
-- Config helpers
-- -----------------------------------------------------------------------------

local function GetCfg(core)
  local p = core.db and core.db.profile
  local fx = p and p.fx
  fx = fx or {}
  fx.dynamics = fx.dynamics or {}
  return fx.dynamics
end

local function ThemeColor(theme, key)
  local t = theme and theme.tokens
  local c = t and t.colors
  if not c then return nil end

  if key == "combat" then
    return c.accentEmber or c.hover or c.panelBorder
  elseif key == "loot" then
    return c.accentAsh or c.text or c.panelBorder
  elseif key == "victory" then
    return c.accentBlood or c.accentEmber or c.panelBorder
  end

  return c.panelBorder or c.text
end

local function PickColor(core, cfg, theme, key)
  local src = cfg.colorSource or "theme"
  if src == "override" and cfg.colors and cfg.colors[key] then
    return core:UnpackColor(cfg.colors[key], 1)
  end
  local c = ThemeColor(theme, key)
  if c then
    return core:UnpackColor(c, 1)
  end
  -- fallback
  return 1, 0.35, 0.16, 1
end

local function Clamp01(x)
  x = tonumber(x) or 0
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

-- -----------------------------------------------------------------------------
-- Targets
-- -----------------------------------------------------------------------------

local TARGETS_ACTIONBARS = {
  -- retail names (best-effort; some may not exist in specific UI states)
  "MainMenuBar",
  "MainMenuBarArtFrame",
  "ActionBarController",
  "MultiBarBottomLeft",
  "MultiBarBottomRight",
  "MultiBarLeft",
  "MultiBarRight",
  "PetActionBarFrame",
  "StanceBar",
  "PossessBarFrame",
  "OverrideActionBar",
  "ExtraActionBarFrame",
  "ZoneAbilityFrame",
}

local TARGETS_BAGBAR = {
  -- bag buttons: use a container if present, otherwise pulse the buttons
  "MainMenuBarBackpackButton",
  "CharacterBag0Slot",
  "CharacterBag1Slot",
  "CharacterBag2Slot",
  "CharacterBag3Slot",
}

local function ResolveTargets(core, cfg)
  Module._targets = Module._targets or {}
  local out = Module._targets
  -- clear previous
  for k in pairs(out) do out[k] = nil end

  local added = 0
  local function AddFrame(key, frame)
    if frame and frame.GetObjectType and frame.GetObjectType(frame) then
      out[key] = frame
      added = added + 1
    end
  end

  if cfg.actionBars ~= false then
    for _, name in ipairs(TARGETS_ACTIONBARS) do
      local f = core:GetFrame(name)
      if f then AddFrame("AB:" .. name, f) end
    end
  end

  if cfg.bagBar ~= false then
    for _, name in ipairs(TARGETS_BAGBAR) do
      local f = core:GetFrame(name)
      if f then AddFrame("BAG:" .. name, f) end
    end
  end

  if cfg.globalOverlay then
    AddFrame("UIParent", UIParent)
  end

  core:StatInc(Module.name, "targets", added)
  core:Trace(Module.name, "targets resolved:", added)
  return out
end

-- -----------------------------------------------------------------------------
-- Effect primitives
-- -----------------------------------------------------------------------------

local function EnsureLayer(core, frame)
  if not frame then return nil end
  frame.__rsFXDyn = frame.__rsFXDyn or {}
  local st = frame.__rsFXDyn

  if st.layer and st.layer.GetParent and st.layer:GetParent() == frame then
    return st
  end

  local layer = CreateFrame("Frame", nil, frame)
  layer:SetAllPoints(frame)
  layer:SetFrameLevel((frame.GetFrameLevel and frame:GetFrameLevel() or 1) + 20)
  layer:Hide()

  local tex = layer:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints(layer)
  tex:SetTexture(core:MediaPath("Media/textures/glow.tga"))
  tex:SetBlendMode("ADD")
  tex:SetAlpha(0)

  -- optional shadow (normal blend)
  local shadow = layer:CreateTexture(nil, "BACKGROUND")
  shadow:SetAllPoints(layer)
  shadow:SetColorTexture(0, 0, 0, 0)
  shadow:SetAlpha(0)

  -- animation group
  local ag = tex:CreateAnimationGroup()
  ag:SetToFinalAlpha(true)

  local a1 = ag:CreateAnimation("Alpha")
  a1:SetOrder(1)

  local a2 = ag:CreateAnimation("Alpha")
  a2:SetOrder(2)

  local s1 = ag:CreateAnimation("Scale")
  s1:SetOrder(1)

  local s2 = ag:CreateAnimation("Scale")
  s2:SetOrder(2)

  ag:SetScript("OnPlay", function() layer:Show() end)
  ag:SetScript("OnFinished", function() tex:SetAlpha(0); shadow:SetAlpha(0); layer:Hide() end)

  st.layer = layer
  st.tex = tex
  st.shadow = shadow
  st.ag = ag
  st.a1, st.a2 = a1, a2
  st.s1, st.s2 = s1, s2

  return st
end

local function PlayPulse(core, frame, r, g, b, intensity, cfg)
  local st = EnsureLayer(core, frame)
  if not st then return end

  local flashDur = tonumber(cfg.flashDuration) or 0.35
  local flashA = Clamp01(tonumber(cfg.flashAlpha) or 0.65)
  local flashScale = tonumber(cfg.flashScale) or 1.03

  local glowDur = tonumber(cfg.glowDuration) or 0.75
  local glowA = Clamp01(tonumber(cfg.glowAlpha) or 0.30)

  -- combine: short bright flash + longer afterglow
  local total1 = flashDur
  local total2 = glowDur

  st.tex:SetVertexColor(r * intensity, g * intensity, b * intensity, 1)

  st.shadow:SetAlpha(0)

  st.ag:Stop()

  st.a1:SetDuration(total1)
  st.a1:SetFromAlpha(0)
  st.a1:SetToAlpha(flashA)

  st.a2:SetDuration(total2)
  st.a2:SetFromAlpha(flashA)
  st.a2:SetToAlpha(0)

  st.s1:SetDuration(total1)
  st.s1:SetScale(flashScale, flashScale)

  st.s2:SetDuration(total2)
  st.s2:SetScale(1 / flashScale, 1 / flashScale)

  -- ensure baseline scale
  if st.layer.SetScale then st.layer:SetScale(1) end

  st.ag:Play()

  core:StatInc(Module.name, "pulses", 1)
end

-- -----------------------------------------------------------------------------
-- Dispatch
-- -----------------------------------------------------------------------------

local lastLoot = 0
local lastVictory = 0

function Module:Fire(core, theme, kind)
  local cfg = GetCfg(core)
  if cfg.enabled == false then return end

  local intensity = Clamp01(tonumber(core.db.profile.rothmode and core.db.profile.rothmode.intensity) or 0.88)

  local r, g, b = 1, 0.35, 0.16
  if kind == "combat" then
    r, g, b = (function()
      local rr, gg, bb = PickColor(core, cfg, theme, "combat")
      return rr, gg, bb
    end)()
  elseif kind == "loot" then
    r, g, b = (function()
      local rr, gg, bb = PickColor(core, cfg, theme, "loot")
      return rr, gg, bb
    end)()
  elseif kind == "victory" then
    r, g, b = (function()
      local rr, gg, bb = PickColor(core, cfg, theme, "victory")
      return rr, gg, bb
    end)()
  else
    local rr, gg, bb = PickColor(core, cfg, theme, "combat")
    r, g, b = rr, gg, bb
  end

  local targets = ResolveTargets(core, cfg)
  local count = 0
  for key, frame in pairs(targets) do
    if frame and frame.IsShown and frame:IsShown() then
      PlayPulse(core, frame, r, g, b, intensity, cfg)
      count = count + 1
      core:Trace(Module.name, "pulse", kind, "->", key)
    else
      -- still allow hidden frames if desired later; keep conservative now
    end
  end
  core:StatInc(Module.name, "fires", 1)
  core:StatInc(Module.name, "targetsFired", count)
end

function Module:Test(core, kind)
  local theme = core:GetTheme()
  self:Fire(core, theme, kind or "combat")
end

-- -----------------------------------------------------------------------------
-- Event handling
-- -----------------------------------------------------------------------------

function Module:OnEvent(core, event, ...)
  local cfg = GetCfg(core)
  if cfg.enabled == false then return end
  local theme = core:GetTheme()

  if event == "PLAYER_LOGIN" then
    ResolveTargets(core, cfg)
    return
  end

  if event == "PLAYER_REGEN_DISABLED" then
    if cfg.onEnterCombat ~= false then
      self:Fire(core, theme, "combat")
    end
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    if cfg.onLeaveCombat then
      self:Fire(core, theme, "combat")
    end
    return
  end

  if event == "LOOT_READY" or event == "CHAT_MSG_LOOT" then
    if cfg.onLoot == false then return end
    local now = GetTime()
    local thr = tonumber(cfg.throttleLoot) or 1.0
    if (now - lastLoot) < thr then return end
    lastLoot = now
    self:Fire(core, theme, "loot")
    return
  end

  if event == "ENCOUNTER_END" then
    if cfg.onVictory == false then return end
    local _, _, _, _, success = ...
    if success ~= 1 and success ~= true then return end
    local now = GetTime()
    local thr = tonumber(cfg.throttleVictory) or 2.0
    if (now - lastVictory) < thr then return end
    lastVictory = now
    self:Fire(core, theme, "victory")
    return
  end
end

function Module:Apply(core, theme)
  -- no persistent visuals; only updates targets/stats
  local cfg = GetCfg(core)
  if cfg.enabled == false then return end
  ResolveTargets(core, cfg)
end

RS:RegisterModule(Module.name, Module)
