--[[
Module: Masque_Options

Purpose
- Adds a dedicated Roth Skinner panel to configure Masque integration.
- Keeps the main OptionsPanel from turning into a mess.

Notes
- Masque itself owns detailed skin configuration. This panel focuses on:
  1) enabling/disabling the bridge
  2) choosing scope (action bars / bag bar)
  3) optional auto-apply of a SkinID to our groups

]]

local _, ns = ...
local RS = ns and ns.RothSkinner or _G.RothSkinner
if not RS then return end

local LibStub = _G.LibStub

local Module = {
  name = "Masque_Options",
  version = "0.5.0",
  priority = 3,
  enabledByDefault = true,
  events = { "PLAYER_LOGIN" },
}

local Panel
local Controls = {}

local function GetMasque()
  if not LibStub then return nil end
  return LibStub("Masque", true)
end

local function GetCfg(core)
  local db = core and core.db and core.db.profile
  return db and db.masque
end

local function CreateTitle(parent, text)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  fs:SetPoint("TOPLEFT", 16, -16)
  fs:SetText(text)
  return fs
end

local function CreateSubTitle(parent, text, anchor)
  local fs = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
  fs:SetText(text)
  return fs
end

local function CreateCheckbox(parent, label)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb.Text:SetText(label)
  return cb
end

local function CreateButton(parent, label, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetText(label)
  b:SetSize(w or 140, 22)
  return b
end

local function CreateEditBox(parent, w)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w or 260, 22)
  e:SetAutoFocus(false)
  e:SetTextInsets(8, 8, 0, 0)
  e:SetMaxLetters(120)
  return e
end

local function OpenMasqueConfig()
  -- Prefer Masque's own slash if it exists.
  if _G.SlashCmdList and _G.SlashCmdList.MASQUE then
    _G.SlashCmdList.MASQUE("")
    return
  end

  -- Settings UI fallback.
  if _G.Settings and _G.Settings.OpenToCategory then
    _G.Settings.OpenToCategory("Masque")
    return
  end

  if _G.InterfaceOptionsFrame_OpenToCategory then
    _G.InterfaceOptionsFrame_OpenToCategory("Masque")
  end
end

local function EnsurePanel(core)
  if Panel then return Panel end

  local p = CreateFrame("Frame", "RothSkinnerMasqueOptionsPanel", UIParent)
  p.name = "Roth Skinner - Masque"
  p:Hide()

  local title = CreateTitle(p, "Roth Skinner - Masque")

  local intro = p:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  intro:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  intro:SetText("Bridge Roth Skinner to Masque.\nIf Masque is installed, this registers Blizzard button frames into Masque groups so you can apply skins.")

  local status = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  status:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -10)
  status:SetText("Masque: (unknown)")
  Controls.status = status

  local scopeLabel = CreateSubTitle(p, "Bridge Scope", status)

  local scroll = CreateFrame("ScrollFrame", nil, p, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", scopeLabel, "BOTTOMLEFT", 0, -6)
  scroll:SetPoint("BOTTOMRIGHT", -34, 16)
  Controls.scroll = scroll

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(1, 1)
  scroll:SetScrollChild(content)
  Controls.content = content

  local y = -4

  local enabled = CreateCheckbox(content, "Enable Masque integration")
  enabled:SetPoint("TOPLEFT", 0, y)
  Controls.enabled = enabled
  y = y - 30

  local actionBars = CreateCheckbox(content, "Register Blizzard action bars (ActionButton/MultiBar/Pet/Stance/etc.)")
  actionBars:SetPoint("TOPLEFT", 0, y)
  Controls.actionBars = actionBars
  y = y - 30

  local bagBar = CreateCheckbox(content, "Register Blizzard bag bar (Backpack + bag slots)")
  bagBar:SetPoint("TOPLEFT", 0, y)
  Controls.bagBar = bagBar
  y = y - 34

  local auto = CreateCheckbox(content, "Auto-apply SkinID to Roth groups (advanced; uses Masque internal group API)")
  auto:SetPoint("TOPLEFT", 0, y)
  Controls.autoApply = auto
  y = y - 34

  local skinLabel = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  skinLabel:SetPoint("TOPLEFT", 0, y)
  skinLabel:SetText("Auto-apply SkinIDs")
  y = y - 26

  local actionLbl = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  actionLbl:SetPoint("TOPLEFT", 0, y)
  actionLbl:SetText("ActionBars SkinID")

  local actionEB = CreateEditBox(content, 320)
  actionEB:SetPoint("LEFT", actionLbl, "RIGHT", 12, 0)
  Controls.skinAction = actionEB
  y = y - 28

  local bagLbl = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  bagLbl:SetPoint("TOPLEFT", 0, y)
  bagLbl:SetText("BagBar SkinID")

  local bagEB = CreateEditBox(content, 320)
  bagEB:SetPoint("LEFT", bagLbl, "RIGHT", 28, 0)
  Controls.skinBag = bagEB
  y = y - 38

  local btnApply = CreateButton(content, "Rescan / Apply", 140)
  btnApply:SetPoint("TOPLEFT", 0, y)
  Controls.apply = btnApply

  local btnMasque = CreateButton(content, "Open Masque", 140)
  btnMasque:SetPoint("LEFT", btnApply, "RIGHT", 8, 0)
  Controls.openMasque = btnMasque

  local btnList = CreateButton(content, "List skins (chat)", 160)
  btnList:SetPoint("LEFT", btnMasque, "RIGHT", 8, 0)
  Controls.listSkins = btnList

  y = y - 34

  local tip = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  tip:SetPoint("TOPLEFT", 0, y)
  tip:SetText("Tip: use /rothmasque skins <filter> to print skin names (limited to 50 lines).\nRecommended: leave auto-apply off and pick skins inside Masque.")
  y = y - 48

  content:SetWidth(560)
  content:SetHeight(-y + 20)

  local function Refresh(core)
    local cfg = GetCfg(core)
    local msq = GetMasque()

    if Controls.status then
      if msq then
        local n = 0
        if type(msq.GetSkins) == "function" then
          local skins = msq:GetSkins() or {}
          for _ in pairs(skins) do n = n + 1 end
        end
        Controls.status:SetText("Masque: detected (skins: " .. n .. ")")
      else
        Controls.status:SetText("Masque: not installed")
      end
    end

    if not cfg then return end

    Controls.enabled:SetChecked(cfg.enabled and true or false)
    Controls.actionBars:SetChecked(cfg.actionBars and true or false)
    Controls.bagBar:SetChecked(cfg.bagBar and true or false)
    Controls.autoApply:SetChecked(cfg.autoApply and true or false)

    Controls.skinAction:SetText(cfg.skinActionBars or "")
    Controls.skinBag:SetText(cfg.skinBagBar or "")
  end

  local function SaveAndApply(core)
    local cfg = GetCfg(core)
    if not cfg then return end

    cfg.enabled = Controls.enabled:GetChecked() and true or false
    cfg.actionBars = Controls.actionBars:GetChecked() and true or false
    cfg.bagBar = Controls.bagBar:GetChecked() and true or false
    cfg.autoApply = Controls.autoApply:GetChecked() and true or false

    cfg.skinActionBars = (Controls.skinAction:GetText() or "")
    cfg.skinBagBar = (Controls.skinBag:GetText() or "")

    core:ApplyAll()
    Refresh(core)
  end

  enabled:SetScript("OnClick", function() SaveAndApply(core) end)
  actionBars:SetScript("OnClick", function() SaveAndApply(core) end)
  bagBar:SetScript("OnClick", function() SaveAndApply(core) end)
  auto:SetScript("OnClick", function() SaveAndApply(core) end)

  actionEB:SetScript("OnEnterPressed", function(self) self:ClearFocus() SaveAndApply(core) end)
  bagEB:SetScript("OnEnterPressed", function(self) self:ClearFocus() SaveAndApply(core) end)

  btnApply:SetScript("OnClick", function() SaveAndApply(core) end)
  btnMasque:SetScript("OnClick", function() OpenMasqueConfig() end)
  btnList:SetScript("OnClick", function() if _G.SlashCmdList and _G.SlashCmdList.ROTHMASQUE then _G.SlashCmdList.ROTHMASQUE("skins") end end)

  p:SetScript("OnShow", function() Refresh(core) end)

  Panel = p
  return p
end

local function RegisterInBlizzardSettings(core)
  local p = EnsurePanel(core)

  if _G.Settings and _G.Settings.RegisterCanvasLayoutCategory and _G.Settings.RegisterAddOnCategory then
    local category = _G.Settings.RegisterCanvasLayoutCategory(p, p.name)
    category.ID = p.name
    _G.Settings.RegisterAddOnCategory(category)
    core:Trace(Module.name, "Registered via Settings API")
    return
  end

  if _G.InterfaceOptions_AddCategory then
    _G.InterfaceOptions_AddCategory(p)
    core:Trace(Module.name, "Registered via InterfaceOptions")
  end
end

function Module:OnEvent(core, event)
  if event == "PLAYER_LOGIN" then
    RegisterInBlizzardSettings(core)
  end
end

RS:RegisterModule(Module.name, Module)
