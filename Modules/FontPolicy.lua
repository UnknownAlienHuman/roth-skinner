--[[
Module: FontPolicy

Goal
- Provide a *global* text feel consistent with the active theme.
- Avoid high-risk changes: no frame repositioning, no secure attribute edits.

Approach
- Operate on a curated list of global FontObjects.
- Store original font+color and restore on disable.

Notes
- FontObjects are shared; a single change affects many widgets.
- This module is designed to be conservative by default.
--]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local Module = {
  name = "FontPolicy",
  version = "0.3.0",
  priority = 10,
  enabledByDefault = true,

  targets = {
    claims = { "Fonts:Global" },
  },
}

local originals = {} -- [fontObject] = {path,size,flags,r,g,b,a,sr,sg,sb,sa,sox,soy}

local FONT_OBJECTS = {
  -- Game fonts
  "GameFontNormal",
  "GameFontNormalSmall",
  "GameFontNormalLarge",
  "GameFontNormalHuge",
  "GameFontHighlight",
  "GameFontHighlightSmall",
  "GameFontHighlightLarge",
  "GameFontDisable",
  "GameFontGreen",
  "GameFontRed",
  "GameFontWhite",
  "GameFontBlack",

  -- System fonts
  "SystemFont_Tiny",
  "SystemFont_Small",
  "SystemFont_Med1",
  "SystemFont_Med2",
  "SystemFont_Med3",
  "SystemFont_Large",
  "SystemFont_Huge1",
  "SystemFont_Huge2",
  "SystemFont_Huge4",

  -- Variants with shadow
  "SystemFont_Shadow_Small",
  "SystemFont_Shadow_Med1",
  "SystemFont_Shadow_Med2",
  "SystemFont_Shadow_Large",

  -- Numbers
  "NumberFontNormal",
  "NumberFontNormalSmall",
  "NumberFontNormalLarge",
}

local function StoreOriginal(obj)
  if not obj or originals[obj] then return end
  local path, size, flags = obj:GetFont()
  local r, g, b, a = obj:GetTextColor()
  local sr, sg, sb, sa = obj:GetShadowColor()
  local sox, soy = obj:GetShadowOffset()
  originals[obj] = {
    path = path, size = size, flags = flags,
    r = r, g = g, b = b, a = a,
    sr = sr, sg = sg, sb = sb, sa = sa,
    sox = sox, soy = soy,
  }
end

local function RestoreAll(core)
  for obj, o in pairs(originals) do
    if obj and o then
      if o.path and o.size then
        obj:SetFont(o.path, o.size, o.flags)
      end
      if o.r then
        obj:SetTextColor(o.r, o.g, o.b, o.a)
      end
      if o.sr then
        obj:SetShadowColor(o.sr, o.sg, o.sb, o.sa)
        obj:SetShadowOffset(o.sox or 0, o.soy or 0)
      end
    end
  end
  core:Trace(Module.name, "restore", "done")
end

local function ApplyAll(core, theme)
  if not theme or not theme.tokens then return end

  local t = theme.tokens
  local text = t.colors and t.colors.text or { r = 1, g = 1, b = 1, a = 1 }
  local muted = t.colors and t.colors.mutedText or text
  local primary = t.fonts and t.fonts.primary
  local header = t.fonts and t.fonts.header

  for _, name in ipairs(FONT_OBJECTS) do
    local obj = _G[name]
    if obj and obj.SetFont and obj.GetFont then
      StoreOriginal(obj)

      local path, size, flags = obj:GetFont()
      -- Conservative: keep size/flags; only swap font path for a subset.
      local newPath = primary
      if name:find("Huge") or name:find("Large") then
        newPath = header or primary
      end

      if newPath and path ~= newPath then
        obj:SetFont(newPath, size or 12, flags)
      end

      -- Color policy
      if name == "GameFontDisable" then
        obj:SetTextColor(muted.r, muted.g, muted.b, 0.65)
      elseif name:find("Shadow") then
        obj:SetTextColor(text.r, text.g, text.b, text.a)
        obj:SetShadowColor(0, 0, 0, 0.85)
        obj:SetShadowOffset(1, -1)
      else
        obj:SetTextColor(text.r, text.g, text.b, text.a)
        -- Small shadow for readability on dark panels.
        obj:SetShadowColor(0, 0, 0, 0.75)
        obj:SetShadowOffset(1, -1)
      end

      core:Trace(Module.name, "font", name, "=>", newPath or "(keep)")
    end
  end
end

function Module:OnEnable(core)
  core:Debug(self.name, "OnEnable")
  core:Claim("Fonts:Global", self.name)
end

function Module:Apply(core, theme)
  core:RunOrQueue(self.name .. ":Apply", function()
    ApplyAll(core, theme)
  end)
end

function Module:OnDisable(core)
  core:RunOrQueue(self.name .. ":Disable", function()
    RestoreAll(core)
  end)
end

function Module:OnThemeChanged(core, theme)
  -- Re-apply with new tokens.
  self:Apply(core, theme)
end

RS:RegisterModule(Module.name, Module)
