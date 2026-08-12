--[[
Module: WidgetPolicy_Basics

Goal
- Apply a conservative style to common widget templates (buttons/editboxes/scrollbars/tabs)
  within major Blizzard panels.

Why separate from NineSlice
- NineSlice recolors the window container.
- Widgets are inside; require targeted handling per template family.

Safety/perf constraints
- No deep recursive scanning of the whole UI tree.
- Operate only on top-level UIPanelWindows frames, one to two levels deep.
- Idempotent: mark skinned widgets to avoid repeated work.

If something looks wrong -> disable this module first.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "WidgetPolicy_Basics",
  version = "0.3.0",
  priority = 40,
  enabledByDefault = true,

  events = { "PLAYER_LOGIN" },

  blizzardAddons = {
    "Blizzard_Settings",
    "Blizzard_CharacterUI",
    "Blizzard_PlayerSpells",
    "Blizzard_Professions",
    "Blizzard_Collections",
    "Blizzard_EncounterJournal",
    "Blizzard_QuestUI",
    "Blizzard_AuctionHouseUI",
  },

  targets = {
    claims = { "Widgets:Basics" },
  },
}

local function SetVertex(tex, c)
  if tex and tex.SetVertexColor and c then
    tex:SetVertexColor(c.r, c.g, c.b, c.a or 1)
  end
end

local function SkinButton(core, theme, btn)
  if not btn or not btn.GetObjectType or btn:GetObjectType() ~= "Button" then return end
  if not core:FrameOnce(btn, "RSWidget:Button") then return end

  local t = theme and theme.tokens
  local border = t and t.colors and t.colors.panelBorder or { r=0.7,g=0.1,b=0.1,a=0.9 }
  local bg = t and t.colors and t.colors.panelBg or { r=0.08,g=0.08,b=0.08,a=0.9 }
  local hover = t and t.colors and t.colors.hover or { r=1,g=0.4,b=0.2,a=0.18 }

  -- Many templates are 3-piece textures
  SetVertex(btn.Left, border)
  SetVertex(btn.Middle, bg)
  SetVertex(btn.Right, border)

  -- If it uses NormalTexture/HighlightTexture, darken them.
  local n = btn.GetNormalTexture and btn:GetNormalTexture()
  if n and n.SetVertexColor then
    n:SetVertexColor(border.r, border.g, border.b, 0.65)
  end
  local h = btn.GetHighlightTexture and btn:GetHighlightTexture()
  if h and h.SetColorTexture then
    h:SetColorTexture(hover.r, hover.g, hover.b, hover.a)
  end

  core:Trace(Module.name, "button", btn:GetName() or tostring(btn))
end

local function SkinEditBox(core, theme, eb)
  if not eb or not eb.GetObjectType or eb:GetObjectType() ~= "EditBox" then return end
  local p = eb.GetParent and eb:GetParent()
  -- Many edit boxes are children of a frame; the actual textured wrapper is the parent.
  local wrapper = p and p.GetObjectType and p:GetObjectType() == "Frame" and p or eb

  if not core:FrameOnce(wrapper, "RSWidget:EditBox") then return end

  local t = theme and theme.tokens
  local border = t and t.colors and t.colors.panelBorder or { r=0.7,g=0.1,b=0.1,a=0.9 }
  local bg = t and t.colors and t.colors.panelInset or { r=0,g=0,b=0,a=0.35 }

  SetVertex(wrapper.Left, border)
  SetVertex(wrapper.Middle, bg)
  SetVertex(wrapper.Right, border)

  if wrapper.SetBackdrop then
    wrapper:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    wrapper:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
    wrapper:SetBackdropBorderColor(border.r, border.g, border.b, border.a)
  end

  core:Trace(Module.name, "editbox", (wrapper.GetName and wrapper:GetName()) or tostring(wrapper))
end

local function SkinScrollBar(core, theme, sb)
  if not sb or not sb.GetObjectType then return end
  local t = theme and theme.tokens
  local border = t and t.colors and t.colors.panelBorder or { r=0.7,g=0.1,b=0.1,a=0.9 }
  local bg = t and t.colors and t.colors.panelInset or { r=0,g=0,b=0,a=0.35 }

  if not core:FrameOnce(sb, "RSWidget:ScrollBar") then return end

  -- Thumb texture is the main visible element
  local thumb = sb.GetThumbTexture and sb:GetThumbTexture()
  if thumb and thumb.SetColorTexture then
    thumb:SetColorTexture(border.r, border.g, border.b, 0.9)
  elseif thumb and thumb.SetVertexColor then
    thumb:SetVertexColor(border.r, border.g, border.b, 0.9)
  end

  -- Track backgrounds if present
  if sb.Track and sb.Track.Background and sb.Track.Background.SetColorTexture then
    sb.Track.Background:SetColorTexture(bg.r, bg.g, bg.b, bg.a)
  end

  core:Trace(Module.name, "scroll", sb:GetName() or tostring(sb))
end

local function SkinTabs(core, theme, tab)
  if not tab or not tab.GetObjectType or tab:GetObjectType() ~= "Button" then return end
  if not tab.GetName then return end
  local name = tab:GetName() or ""
  if not name:find("Tab") then return end
  if not core:FrameOnce(tab, "RSWidget:Tab") then return end

  local t = theme and theme.tokens
  local border = t and t.colors and t.colors.panelBorder or { r=0.7,g=0.1,b=0.1,a=0.9 }
  local bg = t and t.colors and t.colors.panelBg or { r=0.08,g=0.08,b=0.08,a=0.9 }

  SetVertex(tab.Left, border)
  SetVertex(tab.Middle, bg)
  SetVertex(tab.Right, border)

  core:Trace(Module.name, "tab", name)
end

local function WalkChildren(frame, depth, fn)
  if not frame or depth <= 0 then return end
  local children = { frame:GetChildren() }
  for _, ch in ipairs(children) do
    fn(ch)
    WalkChildren(ch, depth - 1, fn)
  end
end

local function SkinPanel(core, theme, panel)
  if not panel then return end
  if not core:FrameOnce(panel, "RSWidget:Panel") then return end

  WalkChildren(panel, 2, function(ch)
    if not ch or not ch.GetObjectType then return end
    local ot = ch:GetObjectType()
    if ot == "Button" then
      SkinTabs(core, theme, ch)
      SkinButton(core, theme, ch)
    elseif ot == "EditBox" then
      SkinEditBox(core, theme, ch)
    elseif ot == "Slider" then
      -- Many scrollbars are Sliders.
      SkinScrollBar(core, theme, ch)
    elseif ot == "Frame" then
      -- Some scrollbars are frames with a ThumbTexture.
      if ch.GetThumbTexture then
        SkinScrollBar(core, theme, ch)
      end
    end
  end)
end

local function Rescan(core)
  local theme = core:GetTheme()
  local t = _G.UIPanelWindows
  if type(t) ~= "table" then return end

  local count = 0
  for frameName in pairs(t) do
    local f = _G[frameName]
    if f then
      count = count + 1
      core:HookOnShow(f, "Widgets:" .. frameName, function(panel)
        SkinPanel(core, core:GetTheme(), panel)
      end)
    end
  end

  core:Trace(Module.name, "scan", "UIPanelWindows", "count=", count)
end

function Module:OnEnable(core)
  core:Debug(self.name, "OnEnable")
  core:Claim("Widgets:Basics", self.name)
  Rescan(core)
end

function Module:OnAddonLoaded(core)
  core:Throttle("Widgets:Rescan", 0.05, function()
    Rescan(core)
  end)
end

function Module:OnThemeChanged(core)
  -- Clear only panel markers; widgets will be recolored on next show.
  local t = _G.UIPanelWindows
  if type(t) == "table" then
    for frameName in pairs(t) do
      local f = _G[frameName]
      if f and f.__RothSkinner then
        f.__RothSkinner["RSWidget:Panel"] = nil
      end
    end
  end
  Rescan(core)
end

function Module:OnEvent(core, event)
  if event == "PLAYER_LOGIN" then
    core:Throttle("Widgets:LoginRescan", 1.2, function()
      Rescan(core)
    end)
  end
end

RS:RegisterModule(Module.name, Module)
