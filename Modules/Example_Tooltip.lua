--[[
Example module: Tooltip

Purpose
- Demonstrate module contract and safe skinning.
- Tooltips are insecure; safe target for early iterations.

This module is intentionally conservative.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "Example_Tooltip",
  version = "0.3.0",
  priority = 20,
  enabledByDefault = true,

  events = { "PLAYER_LOGIN" },

  targets = {
    frames = { "GameTooltip", "ItemRefTooltip" },
  },
}

local function SkinTooltip(core, theme, tooltip)
  if not tooltip or not theme or not theme.tokens then return end

  if not core:FrameOnce(tooltip, "RSTooltip:Skinned") then
    return
  end

  local t = theme.tokens
  local bg = t.colors.panelBg
  local border = t.colors.panelBorder

  core:Trace(Module.name, "apply", tooltip:GetName() or tostring(tooltip))

  -- Backdrop-based tooltips (classic) OR custom frames that provide it.
  if tooltip.SetBackdropColor and tooltip.SetBackdropBorderColor then
    tooltip:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
    tooltip:SetBackdropBorderColor(border.r, border.g, border.b, border.a)
  end

  -- NineSlice-based tooltips (modern).
  core:ColorNineSlice(tooltip, border.r, border.g, border.b, border.a)

  -- Subtle inner fill (does not touch templates).
  local inner = tooltip.__rsInner
  if not inner then
    inner = tooltip:CreateTexture(nil, "BACKGROUND", nil, 0)
    inner:SetPoint("TOPLEFT", 2, -2)
    inner:SetPoint("BOTTOMRIGHT", -2, 2)
    tooltip.__rsInner = inner
  end
  if inner.SetColorTexture then
    inner:SetColorTexture(bg.r, bg.g, bg.b, bg.a)
  end
end

function Module:OnEnable(core, theme)
  core:Debug(self.name, "OnEnable")

  if _G.GameTooltip then
    core:HookOnShow(_G.GameTooltip, self.name, function(tt)
      SkinTooltip(core, core:GetTheme(), tt)
    end)
  end

  if _G.ItemRefTooltip then
    core:HookOnShow(_G.ItemRefTooltip, self.name, function(tt)
      SkinTooltip(core, core:GetTheme(), tt)
    end)
  end

  core:Claim("Tooltip", self.name)
end

function Module:OnThemeChanged(core, theme)
  if _G.GameTooltip and _G.GameTooltip:IsShown() then
    core:RunOrQueue(self.name .. ":ThemeChanged:GameTooltip", SkinTooltip, core, theme, _G.GameTooltip)
  end
  if _G.ItemRefTooltip and _G.ItemRefTooltip:IsShown() then
    core:RunOrQueue(self.name .. ":ThemeChanged:ItemRefTooltip", SkinTooltip, core, theme, _G.ItemRefTooltip)
  end
end

function Module:OnEvent(core, event, ...)
  if event == "PLAYER_LOGIN" then
    core:ApplyModule(self)
  end
end

RS:RegisterModule(Module.name, Module)
