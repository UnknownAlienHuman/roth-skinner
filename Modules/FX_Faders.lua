--[[
Module: FX_Faders

Purpose
- Add mouseover-driven fading for Blizzard UI panels/popups/tooltips.
- Helps achieve a "HUD-first" feel: windows are less visually loud until interacted with.

Config
- db.profile.fx.faders.*

Notes
- Uses per-frame AnimationGroup to avoid depending on UIFrameFade.
- Hooks via HookScript, does not overwrite existing scripts.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "FX_Faders",
  version = "0.5.0",
  priority = 61,
  enabledByDefault = true,
  events = { "PLAYER_LOGIN", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" },
}

local InCombat = false

local function GetCfg(core)
  local p = core.db and core.db.profile
  local fx = p and p.fx
  return (fx and fx.faders) or {}
end

local function IsDescendantOf(obj, parent)
  local f = obj
  while f do
    if f == parent then return true end
    f = f.GetParent and f:GetParent() or nil
  end
  return false
end

local function GetMouseInFrame(frame)
  if not frame or not frame.IsShown or not frame:IsShown() then return false end
  if frame.IsMouseOver and frame:IsMouseOver() then return true end
  local mf = _G.GetMouseFocus and _G.GetMouseFocus() or nil
  if mf and IsDescendantOf(mf, frame) then return true end
  return false
end

local function EnsureFader(frame)
  if not frame or not frame.CreateAnimationGroup then return nil end
  if frame.__rsFX_Fader then return frame.__rsFX_Fader end

  local ag = frame:CreateAnimationGroup()
  local a = ag:CreateAnimation("Alpha")
  a:SetOrder(1)

  local f = {
    ag = ag,
    anim = a,
    target = nil,
  }
  frame.__rsFX_Fader = f
  return f
end

local function FadeTo(frame, target, duration)
  if not frame or not frame.SetAlpha then return end
  target = tonumber(target)
  if not target then return end
  duration = tonumber(duration) or 0

  local fader = EnsureFader(frame)
  if not fader then
    frame:SetAlpha(target)
    return
  end

  if duration <= 0 then
    if fader.ag and fader.ag.Stop then fader.ag:Stop() end
    frame:SetAlpha(target)
    fader.target = target
    return
  end

  if fader.ag:IsPlaying() then
    fader.ag:Stop()
  end

  local cur = frame.GetAlpha and frame:GetAlpha() or 1
  fader.anim:SetFromAlpha(cur)
  fader.anim:SetToAlpha(target)
  fader.anim:SetDuration(duration)
  fader.target = target
  fader.ag:Play()
end

local function ApplyToFrame(core, frame)
  if not frame or not frame.GetObjectType then return end
  if frame.IsForbidden and frame:IsForbidden() then return end

  local cfg = GetCfg(core)
  if not cfg.enabled then return end

  if not core:FrameOnce(frame, "FX_Faders:Hook") then return end

  -- Initialize alpha state
  local active = tonumber(cfg.activeAlpha) or 1
  local inactive = tonumber(cfg.inactiveAlpha) or 0.35

  local function UpdateState(forceActive)
    local wantActive = forceActive and true or false
    if not wantActive then
      if cfg.onlyOutOfCombat and InCombat then
        wantActive = true
      else
        wantActive = GetMouseInFrame(frame)
      end
    end

    if not wantActive and cfg.keepActiveWhenFocused and type(_G.GetCurrentKeyBoardFocus) == "function" then
      local kf = _G.GetCurrentKeyBoardFocus()
      if kf and IsDescendantOf(kf, frame) then
        wantActive = true
      end
    end

    local target = wantActive and active or inactive
    local dur = wantActive and (tonumber(cfg.fadeIn) or 0.10) or (tonumber(cfg.fadeOut) or 0.22)
    FadeTo(frame, target, dur)

    core:StatInc(Module.name, wantActive and "fadeIn" or "fadeOut", 1)
  end

  frame:HookScript("OnEnter", function()
    core:Throttle("FX_Faders:Enter:" .. tostring(frame), 0.01, function()
      UpdateState(true)
    end)
  end)

  frame:HookScript("OnLeave", function()
    core:Throttle("FX_Faders:Leave:" .. tostring(frame), 0.01, function()
      -- Defer one tick so GetMouseFocus() is stable.
      if _G.C_Timer and _G.C_Timer.After then
        _G.C_Timer.After(0, function() UpdateState(false) end)
      else
        UpdateState(false)
      end
    end)
  end)

  frame:HookScript("OnShow", function()
    core:Throttle("FX_Faders:Show:" .. tostring(frame), 0.01, function()
      UpdateState(false)
    end)
  end)

  -- Apply immediately if visible
  if frame.IsShown and frame:IsShown() then
    UpdateState(false)
  end

  core:StatInc(Module.name, "hooked", 1)
end

local function ScanUIPanels(core)
  if type(_G.UIPanelWindows) ~= "table" then return end
  for name, _ in pairs(_G.UIPanelWindows) do
    local f = _G[name]
    if f and f.GetObjectType and f:GetObjectType() == "Frame" then
      ApplyToFrame(core, f)
    end
  end
end

local function ScanPopups(core)
  for _, f in ipairs({
    _G.GameMenuFrame,
    _G.StaticPopup1,
    _G.StaticPopup2,
    _G.StaticPopup3,
    _G.StaticPopup4,
    _G.ColorPickerFrame,
    _G.SettingsPanel,
  }) do
    if f then ApplyToFrame(core, f) end
  end
end

local function ScanDropdownLists(core)
  for _, f in ipairs({ _G.DropDownList1, _G.DropDownList2, _G.DropDownList3, _G.DropDownList4 }) do
    if f then ApplyToFrame(core, f) end
  end
end

local function ScanTooltips(core)
  for _, f in ipairs({ _G.GameTooltip, _G.ItemRefTooltip, _G.ShoppingTooltip1, _G.ShoppingTooltip2, _G.EmbeddedItemTooltip }) do
    if f then ApplyToFrame(core, f) end
  end
end

function Module:OnEvent(core, event)
  if event == "PLAYER_REGEN_DISABLED" then
    InCombat = true
  elseif event == "PLAYER_REGEN_ENABLED" then
    InCombat = false
  end

  -- Update visible faders when combat state changes.
  if event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    core:Throttle("FX_Faders:CombatFlip", 0.05, function()
      local cfg = GetCfg(core)
      if not cfg.enabled then return end

      local frames = {
        _G.GameMenuFrame,
        _G.StaticPopup1,
        _G.StaticPopup2,
        _G.StaticPopup3,
        _G.StaticPopup4,
        _G.ColorPickerFrame,
        _G.SettingsPanel,
        _G.DropDownList1,
        _G.DropDownList2,
        _G.DropDownList3,
        _G.DropDownList4,
        _G.GameTooltip,
        _G.ItemRefTooltip,
        _G.ShoppingTooltip1,
        _G.ShoppingTooltip2,
        _G.EmbeddedItemTooltip,
      }
      for _, fr in ipairs(frames) do
        if fr and fr.__rsFX_Fader and fr.IsShown and fr:IsShown() then
          local active = tonumber(cfg.activeAlpha) or 1
          local inactive = tonumber(cfg.inactiveAlpha) or 0.35
          local target = (cfg.onlyOutOfCombat and InCombat) and active or (GetMouseInFrame(fr) and active or inactive)
          FadeTo(fr, target, 0)
        end
      end
    end)
  end
end

function Module:Apply(core)
  local cfg = GetCfg(core)
  if not cfg.enabled then return end

  if cfg.panels then ScanUIPanels(core) end
  if cfg.popups then ScanPopups(core) end
  if cfg.dropdownLists then ScanDropdownLists(core) end
  if cfg.tooltips then ScanTooltips(core) end

  core:StatInc(Module.name, "applyRuns", 1)
end

RS:RegisterModule(Module.name, Module)
