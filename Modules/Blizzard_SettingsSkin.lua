--[[
Module: Blizzard_SettingsSkin

Goal
- Apply a Diablo-ish dark theme to Blizzard Settings/Options panels:
  - window frame (NineSlice)
  - category list background
  - search box and section headers

Scope
- Targeted: SettingsPanel (Retail) and InterfaceOptionsFrame (legacy) only.
- Does not aim to restyle every widget (that is handled by widget policy modules).

Why needed
- Settings/Options are the most visible example of Blizzard template usage
  (frames, borders, insets, list rows, etc.).

Implementation
- Hook OnShow; skin the container and a few known subframes.
- Keep heuristics conservative; do not assume exact child names.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "Blizzard_SettingsSkin",
  version = "0.3.0",
  priority = 35,
  enabledByDefault = true,

  events = { "PLAYER_LOGIN" },
  blizzardAddons = { "Blizzard_Settings" },

  targets = {
    claims = { "Blizzard:SettingsSkin" },
  },
}

local function SetColorTexture(tex, r, g, b, a)
  if tex and tex.SetColorTexture then
    tex:SetColorTexture(r, g, b, a or 1)
  end
end

local function SetVertex(tex, r, g, b, a)
  if tex and tex.SetVertexColor then
    tex:SetVertexColor(r, g, b, a or 1)
  end
end

local function GetColors(theme)
  local t = theme and theme.tokens
  local c = t and t.colors
  return {
    border = c and c.panelBorder or { r=0.40,g=0.08,b=0.06,a=0.90 },
    bg     = c and c.panelBg     or { r=0.06,g=0.06,b=0.065,a=0.92 },
    inset  = c and c.panelInset  or { r=0.00,g=0.00,b=0.00,a=0.25 },
    text   = c and c.text        or { r=0.92,g=0.90,b=0.85,a=1.00 },
    muted  = c and c.mutedText   or { r=0.65,g=0.62,b=0.58,a=1.00 },
  }
end

local function SkinSearchBox(core, theme, box)
  if not box then return end
  local cc = GetColors(theme)

  if not core:FrameOnce(box, "RSSettings:Search") then return end

  -- Multiple variants exist (EditBox itself vs wrapper frame)
  local wrapper = box
  if box.GetObjectType and box:GetObjectType() == "EditBox" then
    local p = box.GetParent and box:GetParent()
    if p and p.GetObjectType and p:GetObjectType() == "Frame" then
      wrapper = p
    end
  end

  if wrapper.Left and wrapper.Middle and wrapper.Right then
    SetVertex(wrapper.Left, cc.border.r, cc.border.g, cc.border.b, 0.85)
    SetVertex(wrapper.Right, cc.border.r, cc.border.g, cc.border.b, 0.85)
    SetVertex(wrapper.Middle, cc.inset.r, cc.inset.g, cc.inset.b, cc.inset.a)
  end

  if wrapper.SetBackdrop then
    wrapper:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    wrapper:SetBackdropColor(cc.inset.r, cc.inset.g, cc.inset.b, cc.inset.a)
    wrapper:SetBackdropBorderColor(cc.border.r, cc.border.g, cc.border.b, cc.border.a)
  end

  core:StatInc(Module.name, "searchBox", 1)
end

local function SkinBackdropFrame(core, theme, f)
  if not f or not f.SetBackdrop then return end
  if not core:FrameOnce(f, "RSSettings:Backdrop") then return end
  local cc = GetColors(theme)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  f:SetBackdropColor(cc.bg.r, cc.bg.g, cc.bg.b, cc.bg.a)
  f:SetBackdropBorderColor(cc.border.r, cc.border.g, cc.border.b, cc.border.a)
  core:StatInc(Module.name, "backdrop", 1)
end

local function TrySkinKnownParts(core, theme, panel)
  local cc = GetColors(theme)

  -- Window frame
  if panel.NineSlice then
    core:ColorNineSlice(panel, cc.border.r, cc.border.g, cc.border.b, cc.border.a)
    core:StatInc(Module.name, "nineSlice", 1)
  end

  -- Some settings panels have explicit background textures
  if panel.Background and panel.Background.SetColorTexture then
    panel.Background:SetColorTexture(cc.bg.r, cc.bg.g, cc.bg.b, cc.bg.a)
    core:StatInc(Module.name, "background", 1)
  end

  -- Search box (varies)
  if panel.SearchBox then SkinSearchBox(core, theme, panel.SearchBox) end
  if panel.Search and panel.Search.Box then SkinSearchBox(core, theme, panel.Search.Box) end
  if panel.SearchBoxFrame then SkinSearchBox(core, theme, panel.SearchBoxFrame) end

  -- Left category list background (heuristic)
  local left = panel.CategoryList or panel.Categories or panel.LeftPanel or panel.Navigation
  if left then
    SkinBackdropFrame(core, theme, left)
  end

  -- Right content scroll background (heuristic)
  local right = panel.Container or panel.ScrollFrame or panel.RightPanel
  if right then
    if right.NineSlice then
      core:ColorNineSlice(right, cc.border.r, cc.border.g, cc.border.b, cc.border.a)
      core:StatInc(Module.name, "nineSlice", 1)
    else
      SkinBackdropFrame(core, theme, right)
    end
  end

  -- Close button (UIPanelCloseButton) highlight tone
  if panel.CloseButton and panel.CloseButton.GetNormalTexture then
    local n = panel.CloseButton:GetNormalTexture()
    if n and n.SetVertexColor then
      n:SetVertexColor(cc.border.r, cc.border.g, cc.border.b, 0.85)
    end
  end

  core:Trace(Module.name, "skinned panel", (panel.GetName and panel:GetName()) or tostring(panel))
end

local function Hook(core)
  if _G.SettingsPanel then
    core:HookOnShow(_G.SettingsPanel, "SettingsPanelSkin", function(panel)
      local st = core:GetStats(Module.name)
      if st then st.counters = {} end
      TrySkinKnownParts(core, core:GetTheme(), panel)
    end)
  end

  if _G.InterfaceOptionsFrame then
    core:HookOnShow(_G.InterfaceOptionsFrame, "InterfaceOptionsSkin", function(panel)
      local st = core:GetStats(Module.name)
      if st then st.counters = {} end
      TrySkinKnownParts(core, core:GetTheme(), panel)
    end)
  end
end

function Module:OnEnable(core)
  core:Claim("Blizzard:SettingsSkin", self.name)
  Hook(core)
end

function Module:OnAddonLoaded(core)
  core:Throttle("SettingsSkin:Rehook", 0.05, function()
    Hook(core)
  end)
end

function Module:OnEvent(core, event)
  if event == "PLAYER_LOGIN" then
    Hook(core)
  end
end

RS:RegisterModule(Module.name, Module)
