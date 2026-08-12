--[[
Module: RothMode_Global

Purpose
- Provide broad, theme-consistent recolor/reskin coverage for Blizzard UI widgets
  that are NOT part of our dedicated skin modules (action bars, unit frames, etc.).
- This is a "policy pass": we tint / darken common widget templates and panel
  containers, without trying to replace every atlas/texture.

Design constraints
- Conservative (avoid taint / protected frames): no secure template manipulation.
- Budgeted: only scans selected roots and uses depth/budget limits.
- Idempotent: creates minimal helper textures once, updates colors as config/theme changes.

Coverage (initial)
- UIPanel-like containers: NineSlice, backdrop-ish regions, inner fill + gradient.
- Legacy templates: three-piece buttons, checkboxes, sliders, editboxes, dropdown lists.
- Popups & special frames: GameMenu, StaticPopup*, ColorPicker, frames in UISpecialFrames.

Configuration
- RS.db.profile.rothmode

Notes
- This module intentionally does NOT depend on any external addon or code.
--]]

local _, ns = ...
local RS = (ns and ns.RothSkinner) or _G.RothSkinner
if not RS then return end

local Module = {
  name = "RothMode_Global",
  version = "0.5.0",
  priority = 55,
  enabledByDefault = true,
  events = { "PLAYER_LOGIN" },
  targets = {
    claims = { "RothMode:Global" },
  },
}

-- -----------------------------------------------------------------------------
-- Config helpers
-- -----------------------------------------------------------------------------

local function Clamp01(x)
  x = tonumber(x) or 0
  if x < 0 then return 0 end
  if x > 1 then return 1 end
  return x
end

local function CopyColor(dst, src)
  if type(src) ~= "table" then return dst end
  dst = dst or {}
  dst.r = src.r or src[1] or dst.r
  dst.g = src.g or src[2] or dst.g
  dst.b = src.b or src[3] or dst.b
  if src.a ~= nil then dst.a = src.a elseif src[4] ~= nil then dst.a = src[4] end
  return dst
end

local function Scale(c, k)
  k = Clamp01(k or 1)
  return {
    r = Clamp01((c.r or 1) * k),
    g = Clamp01((c.g or 1) * k),
    b = Clamp01((c.b or 1) * k),
    a = (c.a ~= nil) and c.a or 1,
  }
end

local function GetCfg(core)
  local p = core.db and core.db.profile
  return (p and p.rothmode) or {}
end

local function ThemeColors(theme)
  local t = theme and theme.tokens
  local c = t and t.colors
  return c or {}
end

local function EffectivePalette(core, theme)
  local cfg = GetCfg(core)
  local k = Clamp01(cfg.intensity or 0.85)

  local themeC = ThemeColors(theme)

  -- Base defaults (fallback even if theme tokens missing)
  local fallback = {
    border = { r = 0.40, g = 0.08, b = 0.06, a = 0.90 },
    bg     = { r = 0.06, g = 0.06, b = 0.065, a = 0.55 },
    inset  = { r = 0.00, g = 0.00, b = 0.00, a = 0.18 },
    accent = { r = 1.00, g = 0.36, b = 0.16, a = 0.18 },
  }

  local out = {
    border = CopyColor({}, fallback.border),
    bg     = CopyColor({}, fallback.bg),
    inset  = CopyColor({}, fallback.inset),
    accent = CopyColor({}, fallback.accent),
  }

  local c = cfg.colors
  local useTheme = true
  if type(c) == "table" and c.useTheme == false then
    useTheme = false
  end

  if useTheme then
    -- Use theme tokens if present
    out.border = CopyColor(out.border, themeC.panelBorder or themeC.border)
    out.bg     = CopyColor(out.bg, themeC.panelBg or themeC.bg)
    out.inset  = CopyColor(out.inset, themeC.panelInset or themeC.inset)
    out.accent = CopyColor(out.accent, themeC.hover or themeC.accent)
  else
    -- Use user overrides
    out.border = CopyColor(out.border, c and c.border)
    out.bg     = CopyColor(out.bg, c and c.bg)
    out.inset  = CopyColor(out.inset, c and c.inset)
    out.accent = CopyColor(out.accent, c and c.accent)
  end

  -- Apply intensity scaling to the structural colors (not to accent by default)
  out.border = Scale(out.border, k)
  out.bg     = Scale(out.bg, k)
  out.inset  = Scale(out.inset, k)

  return out
end

local function EffectiveGradient(core)
  local cfg = GetCfg(core)
  local g = (type(cfg.gradient) == "table") and cfg.gradient or {}

  local out = {
    enabled = (g.enabled ~= false),
    orientation = (g.orientation == "HORIZONTAL") and "HORIZONTAL" or "VERTICAL",
    from = CopyColor({ r = 0, g = 0, b = 0, a = 0.00 }, g.from),
    to   = CopyColor({ r = 0, g = 0, b = 0, a = 0.22 }, g.to),
    applyToPanels = (g.applyToPanels ~= false),
    applyToButtons = (g.applyToButtons == true),
  }

  return out
end

-- -----------------------------------------------------------------------------
-- Widget detection helpers
-- -----------------------------------------------------------------------------

local function SafeDesaturate(tex, enabled)
  -- Avoid touching Masque-managed regions.
  if tex and (tex._MSQ_Button or tex._MSQ_ButtonMask or tex._MSQ_Color or tex._MSQ_Edge or tex._MSQ_Mask or tex._MSQ_RegionMask) then
    return
  end
  if enabled and tex and tex.SetDesaturated then
    tex:SetDesaturated(true)
  end
end

local function SetVertex(tex, c, desat)
  -- Avoid touching Masque-managed regions.
  if tex and (tex._MSQ_Button or tex._MSQ_ButtonMask or tex._MSQ_Color or tex._MSQ_Edge or tex._MSQ_Mask or tex._MSQ_RegionMask) then
    return
  end
  if tex and tex.SetVertexColor and c then
    tex:SetVertexColor(c.r, c.g, c.b, c.a or 1)
    SafeDesaturate(tex, desat)
  end
end

local function SetColorTexture(tex, c)
  -- Avoid touching Masque-managed regions.
  if tex and (tex._MSQ_Button or tex._MSQ_ButtonMask or tex._MSQ_Color or tex._MSQ_Edge or tex._MSQ_Mask or tex._MSQ_RegionMask) then
    return
  end
  if tex and tex.SetColorTexture and c then
    tex:SetColorTexture(c.r, c.g, c.b, c.a or 1)
  end
end

local function NameHas(name, sub)
  if not name or name == "" then return false end
  return name:lower():find(sub, 1, true) ~= nil
end

local function IsBackdropLikeTexture(tex)
  if not tex or not tex.GetName then return false end
  local n = tex:GetName()
  if not n or n == "" then return false end
  -- Conservative: touch only textures that clearly represent borders/backgrounds.
  if NameHas(n, "nineslice") then return true end
  if NameHas(n, "border") then return true end
  if NameHas(n, "background") then return true end
  if NameHas(n, "backdrop") then return true end
  if NameHas(n, "inset") then return true end
  if NameHas(n, "_bg") or NameHas(n, ".bg") then return true end
  return false
end

-- -----------------------------------------------------------------------------
-- Skin primitives
-- -----------------------------------------------------------------------------


local function SetGradientSafe(tex, orientation, fR, fG, fB, fA, tR, tG, tB, tA)
  if not tex then return end
  orientation = orientation or "VERTICAL"
  fR, fG, fB, fA = fR or 0, fG or 0, fB or 0, fA or 0
  tR, tG, tB, tA = tR or 0, tG or 0, tB or 0, tA or 0

  if tex.SetGradientAlpha then
    tex:SetGradientAlpha(orientation, fR, fG, fB, fA, tR, tG, tB, tA)
    return true
  end

  -- Fallback for textures that don't expose SetGradientAlpha (some wrapped UI frameworks do this).
  if tex.SetColorTexture then
    tex:SetColorTexture((fR + tR) * 0.5, (fG + tG) * 0.5, (fB + tB) * 0.5, (fA + tA) * 0.5)
    return false
  end

  return false
end

local function EnsurePanelLayers(core, frame)
  if not frame or not frame.CreateTexture then return nil, nil end

  if not frame.__rsRM_Fill then
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    fill:SetPoint("TOPLEFT", 2, -2)
    fill:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.__rsRM_Fill = fill
  end

  if not frame.__rsRM_Grad then
    local grad = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    grad:SetPoint("TOPLEFT", 2, -2)
    grad:SetPoint("BOTTOMRIGHT", -2, 2)
    grad:SetColorTexture(1, 1, 1, 1)
    frame.__rsRM_Grad = grad
  end

  return frame.__rsRM_Fill, frame.__rsRM_Grad
end

local function ApplyPanel(core, theme, frame, pal, grad, desat)
  if not frame then return end

  -- NineSlice containers
  if frame.NineSlice then
    core:ColorNineSlice(frame, pal.border.r, pal.border.g, pal.border.b, pal.border.a)
    core:StatInc(Module.name, "nineSlice", 1)
  end

  local fill, gtex = EnsurePanelLayers(core, frame)
  if fill then
    SetColorTexture(fill, pal.bg)
  end

  if gtex then
    if grad.enabled and grad.applyToPanels then
      if gtex.Show then gtex:Show() end
      if gtex.SetBlendMode then gtex:SetBlendMode("BLEND") end
      SetGradientSafe(gtex, grad.orientation, grad.from.r, grad.from.g, grad.from.b, grad.from.a, grad.to.r, grad.to.g, grad.to.b, grad.to.a)
    else
      if gtex.Hide then gtex:Hide() end
    end
  end

  -- Recolor "backdrop-like" regions if present
  if frame.GetRegions then
    local regions = { frame:GetRegions() }
    for _, r in ipairs(regions) do
      if r and r.GetObjectType and r:GetObjectType() == "Texture" and IsBackdropLikeTexture(r) then
        SetVertex(r, pal.bg, desat)
        core:StatInc(Module.name, "regions", 1)
      end
    end
  end
end

local function ApplyThreePiece(core, obj, pal, desat)
  if not obj or not obj.Left or not obj.Middle or not obj.Right then return false end
  SetVertex(obj.Left, pal.border, desat)
  SetVertex(obj.Middle, pal.bg, desat)
  SetVertex(obj.Right, pal.border, desat)
  return true
end


local function IsLikelyIconTexture(tex, owner)
  if not tex then return false end
  if owner and type(owner) == "table" then
    local refs = { "icon", "Icon", "IconTexture", "iconTexture", "IconTex" }
    for _, k in ipairs(refs) do
      if owner[k] == tex then
        return true
      end
    end
  end

  -- TexCoords are usually cropped for icons.
  if tex.GetTexCoord then
    local l, r, t, b = tex:GetTexCoord()
    if l and (l > 0 or t > 0 or r < 1 or b < 1) then
      return true
    end
  end

  local t = tex.GetTexture and tex:GetTexture() or nil
  if type(t) == "string" then
    local s = t:lower()
    if s:find("interface/icons") or s:find("/icons/") or s:find("spellbook") then
      return true
    end
  end

  return false
end

local function ApplyButton(core, btn, pal, grad, desat)
  if not btn or not btn.GetObjectType or btn:GetObjectType() ~= "Button" then return end

  if ApplyThreePiece(core, btn, pal, desat) then
    core:StatInc(Module.name, "threePiece", 1)
  end

  local n = btn.GetNormalTexture and btn:GetNormalTexture()
  if n and n.SetVertexColor then
    -- Many Blizzard item/bag buttons use the NormalTexture as the icon.
    if not IsLikelyIconTexture(n, btn) then
      n:SetVertexColor(pal.border.r, pal.border.g, pal.border.b, 0.70)
      SafeDesaturate(n, desat)
    end
  end

  local h = btn.GetHighlightTexture and btn:GetHighlightTexture()
  if h and h.SetColorTexture then
    h:SetColorTexture(pal.accent.r, pal.accent.g, pal.accent.b, pal.accent.a)
  end

  if grad.enabled and grad.applyToButtons then
    local fill, gtex = EnsurePanelLayers(core, btn)
    if fill then
      SetColorTexture(fill, pal.inset)
    end
    if gtex then
      if gtex.Show then gtex:Show() end
      if gtex.SetBlendMode then gtex:SetBlendMode("ADD") end
      SetGradientSafe(gtex, grad.orientation, grad.from.r, grad.from.g, grad.from.b, grad.from.a, grad.to.r, grad.to.g, grad.to.b, grad.to.a)
    end
  end

  core:StatInc(Module.name, "buttons", 1)
end

local function ApplyCheckButton(core, cb, pal, desat)
  if not cb or not cb.GetObjectType or cb:GetObjectType() ~= "CheckButton" then return end

  local n = cb.GetNormalTexture and cb:GetNormalTexture()
  if n then
    SetVertex(n, pal.border, desat)
  end

  local c = cb.GetCheckedTexture and cb:GetCheckedTexture()
  if c then
    SetVertex(c, pal.border, desat)
  end

  local h = cb.GetHighlightTexture and cb:GetHighlightTexture()
  if h and h.SetColorTexture then
    h:SetColorTexture(pal.accent.r, pal.accent.g, pal.accent.b, pal.accent.a)
  end

  core:StatInc(Module.name, "checks", 1)
end

local function ApplySlider(core, sl, pal, desat)
  if not sl or not sl.GetObjectType or sl:GetObjectType() ~= "Slider" then return end

  local thumb = sl.GetThumbTexture and sl:GetThumbTexture()
  if thumb then
    if thumb.SetColorTexture then
      thumb:SetColorTexture(pal.border.r, pal.border.g, pal.border.b, 0.90)
    elseif thumb.SetVertexColor then
      thumb:SetVertexColor(pal.border.r, pal.border.g, pal.border.b, 0.90)
      SafeDesaturate(thumb, desat)
    end
  end

  -- Try to tint slider track textures
  if sl.GetRegions then
    local regions = { sl:GetRegions() }
    for _, r in ipairs(regions) do
      if r and r.GetObjectType and r:GetObjectType() == "Texture" then
        local name = r.GetName and r:GetName() or ""
        if NameHas(name, "track") or NameHas(name, "background") or NameHas(name, "border") then
          SetVertex(r, pal.inset, desat)
        end
      end
    end
  end

  core:StatInc(Module.name, "sliders", 1)
end

local function ApplyEditBox(core, eb, pal, desat)
  if not eb or not eb.GetObjectType or eb:GetObjectType() ~= "EditBox" then return end

  local wrapper = eb
  local p = eb.GetParent and eb:GetParent()
  if p and p.GetObjectType and p:GetObjectType() == "Frame" and (p.Left or p.Middle or p.Right) then
    wrapper = p
  end

  if wrapper.Left and wrapper.Middle and wrapper.Right then
    SetVertex(wrapper.Left, pal.border, desat)
    SetVertex(wrapper.Right, pal.border, desat)
    SetVertex(wrapper.Middle, pal.inset, desat)
  end

  if wrapper.SetBackdrop then
    wrapper:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    wrapper:SetBackdropColor(pal.inset.r, pal.inset.g, pal.inset.b, pal.inset.a)
    wrapper:SetBackdropBorderColor(pal.border.r, pal.border.g, pal.border.b, pal.border.a)
  end

  core:StatInc(Module.name, "editboxes", 1)
end

local function ApplyDropDownList(core, frame, pal)
  if not frame then return end

  -- Backdrop frame name variants exist; attempt conservative fill only
  ApplyPanel(core, RS:GetTheme(), frame, pal, EffectiveGradient(core), false)
  core:StatInc(Module.name, "dropdownLists", 1)
end

-- -----------------------------------------------------------------------------
-- Budgeted traversal
-- -----------------------------------------------------------------------------

local function WalkChildrenBudget(root, maxDepth, budget, fn)
  if not root or maxDepth <= 0 or budget <= 0 or not root.GetChildren then
    return budget
  end
  local children = { root:GetChildren() }
  for _, ch in ipairs(children) do
    if budget <= 0 then break end
    budget = budget - 1
    fn(ch)
    budget = WalkChildrenBudget(ch, maxDepth - 1, budget, fn)
  end
  return budget
end

-- -----------------------------------------------------------------------------
-- Apply pipeline
-- -----------------------------------------------------------------------------

local knownRoots = {}
local specialNames = {}

local function AddRoot(core, frame, label)
  if not frame or not frame.GetObjectType then return end
  if knownRoots[frame] then return end

  knownRoots[frame] = label or (frame.GetName and frame:GetName()) or "(root)"

  frame:HookScript("OnShow", function()
    core:Throttle("RothMode:OnShow:" .. tostring(knownRoots[frame]), 0.02, function()
      Module:ApplyRoot(core, frame)
    end)
  end)
end

function Module:ApplyRoot(core, root)
  if not root then return end

  local cfg = GetCfg(core)
  if not cfg or not cfg.enabled then return end

  local theme = core:GetTheme()
  local pal = GetPalette(core, theme)
  local grad = cfg.gradient or {}
  local desat = cfg.desaturate and true or false

  -- Root itself: always treat as a panel candidate.
  ApplyPanel(core, root, pal, grad)

  local function IsLikelyPanelFrame(f)
    if not f or type(f) ~= "table" then return false end
    if f == root then return true end

    -- Skip most tiny utility frames.
    local w = (f.GetWidth and f:GetWidth()) or 0
    local h = (f.GetHeight and f:GetHeight()) or 0
    if w > 0 and h > 0 and (w < 60 or h < 40) then
      return false
    end

    -- Strong signals: 9-slice/backdrop usage.
    if f.NineSlice or f.backdropInfo or f.Backdrop or f.Bg then
      return true
    end

    local n = f.GetName and f:GetName() or ""
    n = tostring(n or "")
    if n ~= "" then
      local ln = n:lower()
      if ln:find("frame") or ln:find("panel") or ln:find("dialog") or ln:find("inset") then
        return true
      end
      -- Avoid action buttons and item buttons here.
      if ln:find("button") or ln:find("itembutton") then
        return false
      end
    end

    return false
  end

  local maxNodes = cfg.maxNodes or 400
  local maxDepth = cfg.maxDepth or 5

  -- Time-sliced walker: protects FPS and avoids long spikes.
  local stack = { { f = root, d = 0 } }
  local walked = 0
  local token = (root.__rsRM_WalkToken or 0) + 1
  root.__rsRM_WalkToken = token

  local function Pop()
    local it = stack[#stack]
    stack[#stack] = nil
    return it
  end

  local function Push(f, d)
    if not f then return end
    stack[#stack + 1] = { f = f, d = d }
  end

  local function Step()
    if root.__rsRM_WalkToken ~= token then
      return true -- cancelled by a newer walk
    end

    local it = Pop()
    if not it then
      return true
    end

    walked = walked + 1
    if walked > maxNodes then
      return true
    end

    local f = it.f
    local d = it.d

    if f and f.GetObjectType then
      local t = f:GetObjectType()

      if t == "Frame" then
        if IsLikelyPanelFrame(f) then
          ApplyPanel(core, f, pal, grad)
        end
      elseif t == "Button" then
        if cfg.applyToButtons then
          ApplyButton(core, f, pal, grad, desat)
        end
      elseif t == "Texture" then
        if IsBackdropLikeTexture(f) then
          TintTexture(core, f, pal, desat)
        end
      end

      -- Walk children.
      if d < maxDepth and f.GetChildren then
        local children = { f:GetChildren() }
        for i = #children, 1, -1 do
          Push(children[i], d + 1)
        end
      end

      -- Walk regions (textures) for frames/buttons.
      if (t == "Frame" or t == "Button") and f.GetRegions then
        local regions = { f:GetRegions() }
        for i = 1, #regions do
          local r = regions[i]
          if r and r.GetObjectType and r:GetObjectType() == "Texture" then
            if IsBackdropLikeTexture(r) then
              TintTexture(core, r, pal, desat)
            end
          end
        end
      end
    end

    return false
  end

  core:RunBudgeted(self.name .. ":Walk:" .. tostring(root), Step, {
    perTickMS = cfg.perTickMS or 2.5,
    maxStepsPerTick = cfg.maxStepsPerTick or 200,
  })
end

function Module:Apply(core, theme)
  local cfg = GetCfg(core)
  if not cfg.enabled then return end

  -- Panels: Blizzard frames registered in UIPanelWindows.
  if cfg.panels ~= false then
    ScanUIPanelWindows(core)
  end

  -- Popups / high-visibility dialogs.
  if cfg.popups ~= false then
    AddRoot(core, _G.GameMenuFrame, "GameMenu")
    AddRoot(core, _G.StaticPopup1, "StaticPopup1")
    AddRoot(core, _G.StaticPopup2, "StaticPopup2")
    AddRoot(core, _G.StaticPopup3, "StaticPopup3")
    AddRoot(core, _G.StaticPopup4, "StaticPopup4")
    AddRoot(core, _G.ColorPickerFrame, "ColorPicker")
    AddRoot(core, _G.SettingsPanel, "SettingsPanel")
  end

  -- Optional: addon / utility frames that register into UISpecialFrames.
  if cfg.specialFrames then
    ScanSpecialFrames(core)
  end

  if cfg.dropdowns ~= false then
    HookDropDownLists(core)
  end

  -- Apply to already-visible roots
  for f in pairs(knownRoots) do
    if f and f.IsShown and f:IsShown() then
      self:ApplyRoot(core, f)
    end
  end
end
function Module:PLAYER_LOGIN(core)
  -- Initial scan.
  self:Apply(core)

  -- Follow-up scans only matter if we opted into UISpecialFrames coverage.
  local cfg = GetCfg(core)
  if not cfg.specialFrames then return end
  if not _G.C_Timer or not _G.C_Timer.NewTicker then return end

  local ticksLeft = 8
  _G.C_Timer.NewTicker(2.5, function(t)
    ticksLeft = ticksLeft - 1
    ScanSpecialFrames(core)
    if ticksLeft <= 0 then t:Cancel() end
  end)
end

RS:RegisterModule(Module.name, Module)

