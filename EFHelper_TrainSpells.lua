-- ----------------------------------------------------------------------------
-- EFHelper_TrainSpells.lua
-- Trainer Abilities Spellbook Tab & Level-Up Toast Module for WoW Forever
-- ----------------------------------------------------------------------------
local addonName, addonTable = ...
local EFHelper = _G.EFHelper or addonTable
local TrainSpells = EFHelper:NewModule("TrainSpells", "AceEvent-3.0", "AceTimer-3.0")
EFHelper.TrainSpells = TrainSpells
addonTable.TrainSpells = TrainSpells

local UI = EFHelper.UI
local Utils = EFHelper.Utils

-- ----------------------------------------------------------------------------
-- Constants & Class Mapping
-- ----------------------------------------------------------------------------
local CLASS_TOKEN_MAP = {
    ["WARRIOR"] = "Warrior",
    ["PALADIN"] = "Paladin",
    ["HUNTER"] = "Hunter",
    ["ROGUE"] = "Rogue",
    ["PRIEST"] = "Priest",
    ["SHAMAN"] = "Shaman",
    ["MAGE"] = "Mage",
    ["WARLOCK"] = "Warlock",
    ["DRUID"] = "Druid",
}

-- ----------------------------------------------------------------------------
-- Currency & Formatting Helpers
-- ----------------------------------------------------------------------------
function TrainSpells:FormatCost(copper, isGray)
    if not copper or copper <= 0 then
        return isGray and "|cff8888880|cff666666c|r|r" or "0|cffeda55fc|r"
    end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100

    local parts = {}
    local gFmt = isGray and "|cff888888%d|cff666666g|r|r" or "%d|cffffd100g|r"
    local sFmt = isGray and "|cff888888%d|cff666666s|r|r" or "%d|cffc7c7cfs|r"
    local cFmt = isGray and "|cff888888%d|cff666666c|r|r" or "%d|cffeda55fc|r"

    if g > 0 then table.insert(parts, string.format(gFmt, g)) end
    if s > 0 then table.insert(parts, string.format(sFmt, s)) end
    if c > 0 or #parts == 0 then table.insert(parts, string.format(cFmt, c)) end

    return table.concat(parts, " ")
end

function TrainSpells:GetPlayerClassName()
    local _, classToken = UnitClass("player")
    return CLASS_TOKEN_MAP[classToken] or "Warrior"
end

local function GetSpellKey(spell)
    if not spell then return "" end
    if spell.spellID then
        return tostring(spell.spellID)
    end
    return string.format("%s#%d", spell.name or "", spell.rank or 0)
end

local function SetSpellSelected(selectedTable, spell, isSelected)
    if not spell then return end
    local key = GetSpellKey(spell)
    selectedTable[key] = isSelected or nil
    local nameRankKey = string.format("%s#%d", spell.name or "", spell.rank or 0)
    selectedTable[nameRankKey] = isSelected or nil
end

function TrainSpells:GetSpellIcon(spellName, spellID)
    local id = (type(spellName) == "number" and spellName) or spellID
    if id then
        local tex = (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id))
            or (GetSpellTexture and GetSpellTexture(id))
        if tex then return tex end

        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(id)
            if info and info.iconID and info.iconID ~= 0 then return info.iconID end
        end
    end
    return "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function QuerySpellSubtext(spellID)
    if not spellID then return nil end
    local sub = nil
    if C_Spell and C_Spell.GetSpellSubtext then
        local ok, res = pcall(C_Spell.GetSpellSubtext, spellID)
        if ok and res and res ~= "" then sub = res end
    end
    if not sub and GetSpellSubtext then
        local ok, res = pcall(GetSpellSubtext, spellID)
        if ok and res and res ~= "" then sub = res end
    end
    if not sub and GetSpellInfo then
        local ok, _, rankStr = pcall(GetSpellInfo, spellID)
        if ok and rankStr and rankStr ~= "" then sub = rankStr end
    end
    return sub
end

local function QuerySpellName(spellID)
    if not spellID then return nil end
    local name = nil
    if C_Spell and C_Spell.GetSpellName then
        local ok, res = pcall(C_Spell.GetSpellName, spellID)
        if ok and res and res ~= "" then name = res end
    end
    if not name and GetSpellInfo then
        local ok, res = pcall(GetSpellInfo, spellID)
        if ok and res and res ~= "" then name = res end
    end
    return name
end

function TrainSpells:ResolveSpellData(spell)
    if not spell or not spell.spellID or spell._resolved then return end
    local authenticName = QuerySpellName(spell.spellID)
    if authenticName and authenticName ~= "" then
        spell.name = authenticName
        local sub = QuerySpellSubtext(spell.spellID)
        if sub then
            local actualRank = tonumber(sub:match("[Rr]ank%s*(%d+)"))
            if actualRank and actualRank > 0 then
                spell.rank = actualRank
            end
        end
        spell._resolved = true
    end
end

function TrainSpells:ResolveAllClassSpells()
    local className = self:GetPlayerClassName()
    local classData = EFHelper_TrainerData and EFHelper_TrainerData[className]
    if not classData then return end
    for _, spell in ipairs(classData) do
        self:ResolveSpellData(spell)
    end
end

function TrainSpells:GetDB()
    if EFHelper.db and EFHelper.db.profile then
        if not EFHelper.db.profile.TrainSpells then
            EFHelper.db.profile.TrainSpells = {
                enabled = true,
                showSpellbookTab = true,
                showLevelUpToast = true,
                toastDuration = 4.0,
                sound = true,
                hideHigherLevels = false,
                autoTrain = true,
            }
        end
        local db = EFHelper.db.profile.TrainSpells
        if db.autoTrain == nil then db.autoTrain = true end
        return db
    end
    return {
        enabled = true,
        showSpellbookTab = true,
        showLevelUpToast = true,
        toastDuration = 4.0,
        sound = true,
        hideHigherLevels = false,
        autoTrain = true,
    }
end

-- ----------------------------------------------------------------------------
-- Lifecycle & Event Registration
-- ----------------------------------------------------------------------------
function TrainSpells:OnInitialize()
    self.isSpellbookHooked = false
    self.isTrainerOpen = false
    self.trainSession = nil
end

function TrainSpells:OnEnable()
    local db = self:GetDB()
    if not db.enabled then return end

    self:RegisterEvent("PLAYER_LEVEL_UP")
    self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")
    self:RegisterEvent("LEARNED_SPELL_IN_SKILL_LINE", "OnSpellsChanged")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnSpellsChanged")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")

    -- Trainer interaction events
    self:RegisterEvent("TRAINER_SHOW")
    self:RegisterEvent("TRAINER_UPDATE")
    self:RegisterEvent("TRAINER_CLOSED")

    -- Try hooking spellbook immediately or wait for Blizzard_PlayerSpells
    self:HookSpellBookFrame()
    self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
end

function TrainSpells:PLAYER_REGEN_DISABLED()
    self:HideSpellbookPanel()
    if self.trainSession then
        self.trainSession = nil
    end
end

function TrainSpells:OnDisable()
    self:UnregisterAllEvents()
    self.isTrainerOpen = false
    self.trainSession = nil
    if self.tabButton then self.tabButton:Hide() end
    if self.panel then self.panel:Hide() end
    if self.toastFrame then self.toastFrame:Hide() end
    if self.trainerButton then self.trainerButton:Hide() end
end

function TrainSpells:OnAddonLoaded(event, loadedAddon)
    if loadedAddon == "Blizzard_PlayerSpells" then
        if self.tabButton then
            self.tabButton:Hide()
            self.tabButton = nil
        end
        self.isSpellbookHooked = false
        self:HookSpellBookFrame()
    elseif loadedAddon == "Blizzard_SpellBook" then
        self:HookSpellBookFrame()
    elseif loadedAddon == "Blizzard_TrainerUI" then
        if self.isTrainerOpen and not (IsTradeskillTrainer and IsTradeskillTrainer()) then
            self:AttachTrainerFrameButton()
        end
    end
end

function TrainSpells:OnSpellsChanged()
    self:ResolveAllClassSpells()
    self:MarkKnownSpellsDirty()
end

-- ----------------------------------------------------------------------------
-- Feature 2: Level-Up Toast Popup (Unmovable, Brief Banner)
-- ----------------------------------------------------------------------------
function TrainSpells:PLAYER_LEVEL_UP(event, newLevel)
    local db = self:GetDB()
    if self.panel and self.panel:IsShown() then
        self:UpdateSpellList()
    end

    if not db.enabled or not db.showLevelUpToast then return end
    self:ShowLevelUpToast(newLevel)
end

local toastFrame = nil
local toastFadeTimer = nil

function TrainSpells:GetOrCreateToastFrame()
    if toastFrame then return toastFrame end

    local f = CreateFrame("Frame", "EFHelper_LevelUpToastFrame", UIParent, "BackdropTemplate")
    f:SetSize(360, 100)
    f:SetPoint("TOP", UIParent, "TOP", 0, -140)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetClampedToScreen(true)
    f:EnableMouse(false)

    -- Unmovable: No dragging scripts attached
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.04, 0.07, 0.12, 0.92)
    f:SetBackdropBorderColor(0.85, 0.70, 0.25, 0.85)

    -- Top Header: "You've Reached"
    local topHeader = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    topHeader:SetPoint("TOP", f, "TOP", 0, -8)
    topHeader:SetText("You've Reached")
    f.topHeader = topHeader

    -- Level Title: "Level 9"
    local levelTitle = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    levelTitle:SetPoint("TOP", topHeader, "BOTTOM", 0, -2)
    levelTitle:SetText("|cffffd100Level 9|r")
    f.levelTitle = levelTitle

    -- Glowing divider line
    local divider = f:CreateTexture(nil, "ARTWORK")
    divider:SetSize(320, 1)
    divider:SetPoint("TOP", levelTitle, "BOTTOM", 0, -6)
    divider:SetColorTexture(0.85, 0.70, 0.25, 0.7)
    f.divider = divider

    -- Gold pip dot in center
    local pip = f:CreateTexture(nil, "OVERLAY")
    pip:SetSize(6, 6)
    pip:SetPoint("CENTER", divider, "CENTER", 0, 0)
    pip:SetColorTexture(1.0, 0.85, 0.35, 1.0)
    f.pip = pip

    -- Spell Icon (38x38)
    local iconFrame = CreateFrame("Frame", nil, f, "BackdropTemplate")
    iconFrame:SetSize(38, 38)
    iconFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -50)
    iconFrame:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    iconFrame:SetBackdropBorderColor(0.85, 0.70, 0.25, 0.9)
    f.iconFrame = iconFrame

    local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    f.iconTex = iconTex

    -- Small Book Overlay Badge at bottom-left of icon (matches Image 3)
    local bookBadge = iconFrame:CreateTexture(nil, "OVERLAY")
    bookBadge:SetSize(14, 14)
    bookBadge:SetPoint("BOTTOMLEFT", iconFrame, "BOTTOMLEFT", -3, -3)
    bookBadge:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    f.bookBadge = bookBadge

    -- Upper Line: "New Ability Trainable!" (Green font)
    local upperText = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    upperText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 10, -2)
    upperText:SetText("|cff00ff00New Ability Trainable!|r")
    f.upperText = upperText

    -- Lower Line: Ability Name & Rank + Cost
    local lowerText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    lowerText:SetPoint("TOPLEFT", upperText, "BOTTOMLEFT", 0, -4)
    lowerText:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    lowerText:SetJustifyH("LEFT")
    lowerText:SetText("|cffffd100Word of Glory|r — 40s")
    f.lowerText = lowerText

    -- Additional spells counter (if multiple spells unlock at this level)
    local extraText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    extraText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 6)
    extraText:SetText("")
    f.extraText = extraText

    f:Hide()
    toastFrame = f
    self.toastFrame = f
    return f
end

function TrainSpells:ShowLevelUpToast(newLevel, isTest)
    if not newLevel then return end
    local className = self:GetPlayerClassName()
    local data = EFHelper_TrainerData and EFHelper_TrainerData[className]

    -- Find unlocked spells for this level
    local unlocked = {}
    if data then
        for _, spell in ipairs(data) do
            if spell.level == newLevel then
                table.insert(unlocked, spell)
            end
        end
    end

    local f = self:GetOrCreateToastFrame()
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    if f.Raise then f:Raise() end
    f.levelTitle:SetText(string.format("|cffffd100Level %d|r", newLevel))

    if #unlocked == 0 then
        -- Find next level that has trainer abilities
        local nextUnlockLvl = nil
        if data then
            for _, spell in ipairs(data) do
                if spell.level > newLevel then
                    if not nextUnlockLvl or spell.level < nextUnlockLvl then
                        nextUnlockLvl = spell.level
                    end
                end
            end
        end

        f.iconTex:SetTexture("Interface\\Icons\\INV_Misc_Book_06")
        f.upperText:SetText("|cffffffffLevel Up!|r")
        if nextUnlockLvl then
            f.lowerText:SetText(string.format("|cffaaaaaa0 trainable abilities (Next at Level %d)|r", nextUnlockLvl))
        else
            f.lowerText:SetText("|cffaaaaaa0 trainable abilities at this level|r")
        end
        f:SetHeight(98)
        f.extraText:SetText("")
        f.extraText:Hide()
    else
        local firstSpell = unlocked[1]
        local rankStr = firstSpell.rank and string.format(" (Rank %d)", firstSpell.rank) or ""
        local costStr = self:FormatCost(firstSpell.cost)

        f.iconTex:SetTexture(self:GetSpellIcon(firstSpell.name, firstSpell.spellID))

        if firstSpell.rank and firstSpell.rank > 1 then
            f.upperText:SetText("|cff00ff00New Rank Trainable!|r")
        else
            f.upperText:SetText("|cff00ff00New Ability Trainable!|r")
        end

        f.lowerText:SetText(string.format("|cffffd100%s%s|r — Cost: %s", firstSpell.name, rankStr, costStr))

        if #unlocked > 1 then
            f:SetHeight(115)
            f.extraText:SetText(string.format("|cff88ccee+ %d other trainable %s at level %d (View Spellbook)|r", #unlocked - 1, (#unlocked - 1 == 1 and "ability" or "abilities"), newLevel))
            f.extraText:Show()
        else
            f:SetHeight(98)
            f.extraText:SetText("")
            f.extraText:Hide()
        end
    end

    -- Play sound if enabled or in test mode
    local db = self:GetDB()
    if db.sound or isTest then
        if SOUNDKIT and SOUNDKIT.UI_EPICLOOT_TOAST then
            PlaySound(SOUNDKIT.UI_EPICLOOT_TOAST)
        elseif PlaySound then
            pcall(PlaySound, 63971)
        end
    end

    -- Cancel previous fade timer & clear Blizzard fade cache
    if toastFadeTimer then
        toastFadeTimer:Cancel()
        toastFadeTimer = nil
    end
    if UIFrameFadeRemoveFrame then
        pcall(UIFrameFadeRemoveFrame, f)
    end

    f:Show()
    f:SetAlpha(1.0)
    if UIFrameFadeIn then
        pcall(UIFrameFadeIn, f, 0.2, 0.6, 1.0)
    end

    -- Auto-fade out after duration
    local duration = db.toastDuration or 4.0
    toastFadeTimer = C_Timer.NewTimer(duration, function()
        if f:IsShown() then
            if UIFrameFadeOut then
                pcall(UIFrameFadeOut, f, 0.75, 1.0, 0)
                C_Timer.After(0.75, function()
                    if f:GetAlpha() <= 0.05 then f:Hide() end
                end)
            else
                f:Hide()
            end
        end
    end)
end

function TrainSpells:TestToast(level)
    local testLvl = level or UnitLevel("player") or 10
    print(string.format("|cff0cd29f[EFHelper]|r Testing Trainer Toast notification (Level %d)...", testLvl))
    self:ShowLevelUpToast(testLvl, true)
end

-- ----------------------------------------------------------------------------
-- Feature 1: Spellbook Custom Tab & Trainable Spells List
-- ----------------------------------------------------------------------------
local spellbookPanel = nil
local spellRows = {}
local ROW_HEIGHT = 38
TrainSpells.selectedSpells = {}

-- Cache of trained spells: [spellName] = highestRank (number) or true (unranked)
local knownSpells = {}
local isKnownSpellsDirty = true

function TrainSpells:MarkKnownSpellsDirty()
    isKnownSpellsDirty = true
    if self.panel and self.panel:IsShown() then
        self:UpdateSpellList()
    end
end

-- Verify which class spells from EFHelper_TrainerData are known by the player
function TrainSpells:ScanKnownSpells()
    wipe(knownSpells)
    local className = self:GetPlayerClassName()
    local classData = EFHelper_TrainerData and EFHelper_TrainerData[className]
    if not classData then
        isKnownSpellsDirty = false
        return
    end

    for _, spell in ipairs(classData) do
        if spell.spellID then
            self:ResolveSpellData(spell)
            local isKnown = false
            if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
                local ok, res = pcall(C_SpellBook.IsSpellInSpellBook, spell.spellID)
                if ok and res then isKnown = true end
            end
            if not isKnown and IsPlayerSpell then
                local ok, res = pcall(IsPlayerSpell, spell.spellID)
                if ok and res then isKnown = true end
            end
            if not isKnown and IsSpellKnown then
                local ok, res = pcall(IsSpellKnown, spell.spellID)
                if ok and res then isKnown = true end
            end
            -- Unranked ability fallback by name (never for ranked spells!)
            if not isKnown and not spell.rank and C_SpellBook and C_SpellBook.IsSpellInSpellBook then
                local ok, res = pcall(C_SpellBook.IsSpellInSpellBook, spell.name)
                if ok and res then isKnown = true end
            end

            if isKnown then
                if spell.rank then
                    knownSpells[spell.name] = math.max(knownSpells[spell.name] or 0, spell.rank)
                else
                    knownSpells[spell.name] = true
                end
            end
        end
    end

    isKnownSpellsDirty = false
end

-- Check if a spell from EFHelper_TrainerData has already been trained
-- "ranks require the previous ranks so you can assume all previous ranks to the current one are trained."
function TrainSpells:IsSpellTrained(spell)
    if isKnownSpellsDirty then
        self:ScanKnownSpells()
    end

    local known = knownSpells[spell.name]
    if not known then
        return false -- Spell not in spellbook at all -> not trained
    end

    -- Unranked ability (e.g. Purify, Judgement, racials)
    if not spell.rank then
        return true -- Known in spellbook -> already trained
    end

    -- Ranked ability:
    -- If player knows Rank K, all ranks <= K are assumed trained!
    if type(known) == "number" then
        return spell.rank <= known
    elseif known == true then
        -- In spellbook without specific rank subtext; assume at least Rank 1 is trained
        return spell.rank == 1
    end

    return false
end

function TrainSpells:HookSpellBookFrame()
    if self.isSpellbookHooked then return end

    -- Modern PlayerSpellsFrame
    local parentFrame = _G.PlayerSpellsFrame
    if parentFrame then
        self:AttachToPlayerSpells(parentFrame)
        self.isSpellbookHooked = true
        return
    end

    -- Legacy SpellBookFrame
    if _G.SpellBookFrame then
        self:AttachToLegacySpellBook(_G.SpellBookFrame)
        self.isSpellbookHooked = true
        return
    end
end

function TrainSpells:UpdateSpellbookTabsClickability(isPanelOpen)
    if InCombatLockdown and InCombatLockdown() then return end

    -- Helper to hook and enable/restore a tab button
    local function ProcessTab(tab)
        if not tab then return end
        if not tab._efHooked then
            tab._efHooked = true
            tab:HookScript("OnClick", function(self)
                if InCombatLockdown and InCombatLockdown() then return end
                if spellbookPanel and spellbookPanel:IsShown() then
                    local wasSelected = self.isSelected
                    TrainSpells:HideSpellbookPanel()
                    if wasSelected and PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
                        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
                    end
                end
            end)
        end

        if isPanelOpen then
            if tab.SetEnabled and not tab:IsEnabled() then
                tab._efWasDisabled = true
                tab:SetEnabled(true)
            end
        else
            if tab._efWasDisabled then
                tab._efWasDisabled = nil
                if tab.SetEnabled then
                    tab:SetEnabled(false)
                end
            end
        end
    end

    -- 1. Modern PlayerSpellsFrame / SpellBookFrame CategoryTabSystem (Spec tabs: General, Holy, Prot, Ret)
    local playerSpellsFrame = _G.PlayerSpellsFrame
    local targetParent = playerSpellsFrame and (playerSpellsFrame.SpellBookFrame or playerSpellsFrame)
    if targetParent and targetParent.CategoryTabSystem then
        local catSystem = targetParent.CategoryTabSystem
        if catSystem.tabs then
            for _, tab in ipairs(catSystem.tabs) do
                ProcessTab(tab)
            end
        end
        if catSystem.GetChildren then
            for _, child in ipairs({ catSystem:GetChildren() }) do
                if child:IsObjectType("Button") then
                    ProcessTab(child)
                end
            end
        end
    end

    -- 2. Legacy SpellBookFrame tabs
    local spellBookFrame = _G.SpellBookFrame
    if spellBookFrame then
        for i = 1, 5 do
            local tab = _G["SpellBookFrameTabButton" .. i]
            ProcessTab(tab)
        end
        for i = 1, 8 do
            local tab = _G["SpellBookSkillLineTab" .. i]
            ProcessTab(tab)
        end
    end
end

function TrainSpells:HideSpellbookPanel()
    if spellbookPanel and spellbookPanel:IsShown() then
        spellbookPanel:Hide()
        self:UpdateButtonState()
        if not (InCombatLockdown and InCombatLockdown()) then
            self:UpdateSpellbookTabsClickability(false)
        end
    end
end

function TrainSpells:UpdateButtonState()
    if not self.tabButton then return end
    local isOpen = (spellbookPanel and spellbookPanel:IsShown())
    if isOpen then
        self.tabButton:SetBackdropBorderColor(1.0, 0.85, 0.25, 1.0)
        if self.tabButton.icon then self.tabButton.icon:SetVertexColor(1.0, 1.0, 1.0) end
    else
        self.tabButton:SetBackdropBorderColor(0.65, 0.52, 0.30, 0.8)
        if self.tabButton.icon then self.tabButton.icon:SetVertexColor(0.85, 0.85, 0.85) end
    end
end

function TrainSpells:CreateSpellBookTabButton(parentFrame)
    local btn = CreateFrame("Button", "EFHelper_SpellBookTrainerButton", parentFrame, "BackdropTemplate")
    btn:SetSize(36, 36)
    btn:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    btn:SetBackdropBorderColor(0.65, 0.52, 0.30, 0.8)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", btn, "TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -2, 2)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    hl:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)

    local pushed = btn:CreateTexture(nil, "BORDER")
    pushed:SetColorTexture(0, 0, 0, 0.4)
    pushed:SetAllPoints()
    btn:SetPushedTexture(pushed)

    btn:SetScript("OnClick", function()
        TrainSpells:ToggleSpellbookPanel()
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Trainable Abilities", 1, 0.82, 0)
        GameTooltip:AddLine("Click to view upcoming class trainer abilities, ranks, and costs.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    self.tabButton = btn
    return btn
end

function TrainSpells:AttachToPlayerSpells(playerSpellsFrame)
    if self.tabButton then return end
    local targetParent = playerSpellsFrame.SpellBookFrame or playerSpellsFrame
    local btn = self:CreateSpellBookTabButton(targetParent)

    -- Position: at top, offset to the left of the spec tabs
    local function LayoutButtonPosition()
        if InCombatLockdown and InCombatLockdown() then return end
        if btn._positioned then return end
        btn:ClearAllPoints()
        if targetParent.CategoryTabSystem then
            btn:SetPoint("RIGHT", targetParent.CategoryTabSystem, "LEFT", -8, 0)
        else
            btn:SetPoint("TOPLEFT", targetParent, "TOPLEFT", 22, -18)
        end
        btn._positioned = true
    end
    LayoutButtonPosition()
    targetParent:HookScript("OnShow", LayoutButtonPosition)

    -- Hook Hide on parent frame so our panel hides when spellbook closes
    playerSpellsFrame:HookScript("OnHide", function()
        TrainSpells:HideSpellbookPanel()
    end)

    -- Hook category tabs to close panel when switching tabs
    if targetParent.SetTab then
        hooksecurefunc(targetParent, "SetTab", function()
            if not (InCombatLockdown and InCombatLockdown()) then
                TrainSpells:HideSpellbookPanel()
            end
        end)
    end
    if targetParent.CategoryTabSystem then
        if targetParent.CategoryTabSystem.SetTab then
            hooksecurefunc(targetParent.CategoryTabSystem, "SetTab", function()
                if not (InCombatLockdown and InCombatLockdown()) then
                    TrainSpells:HideSpellbookPanel()
                end
            end)
        end
        local function HookCategoryButtons()
            if InCombatLockdown and InCombatLockdown() then return end
            if spellbookPanel and spellbookPanel:IsShown() then
                TrainSpells:UpdateSpellbookTabsClickability(true)
            end
        end
        targetParent.CategoryTabSystem:HookScript("OnShow", HookCategoryButtons)
    end

    if playerSpellsFrame.SpecFrame then
        playerSpellsFrame.SpecFrame:HookScript("OnShow", function()
            if not (InCombatLockdown and InCombatLockdown()) then
                TrainSpells:HideSpellbookPanel()
            end
        end)
    end
    if playerSpellsFrame.TalentsFrame then
        playerSpellsFrame.TalentsFrame:HookScript("OnShow", function()
            if not (InCombatLockdown and InCombatLockdown()) then
                TrainSpells:HideSpellbookPanel()
            end
        end)
    end
end

function TrainSpells:AttachToLegacySpellBook(spellBookFrame)
    if self.tabButton then return end
    local btn = self:CreateSpellBookTabButton(spellBookFrame)
    btn:SetPoint("TOPLEFT", spellBookFrame, "TOPLEFT", 68, -36)

    spellBookFrame:HookScript("OnHide", function()
        TrainSpells:HideSpellbookPanel()
    end)

    -- Hook legacy tab buttons & side skill line tabs
    for i = 1, 5 do
        local tab = _G["SpellBookFrameTabButton" .. i]
        if tab and not tab._efHooked then
            tab._efHooked = true
            tab:HookScript("OnClick", function()
                if not (InCombatLockdown and InCombatLockdown()) then
                    TrainSpells:HideSpellbookPanel()
                end
            end)
        end
    end
    for i = 1, 8 do
        local tab = _G["SpellBookSkillLineTab" .. i]
        if tab and not tab._efHooked then
            tab._efHooked = true
            tab:HookScript("OnClick", function()
                if not (InCombatLockdown and InCombatLockdown()) then
                    TrainSpells:HideSpellbookPanel()
                end
            end)
        end
    end
end

function TrainSpells:ToggleSpellSelection(spell)
    local key = GetSpellKey(spell)
    local isNowSelected = not self.selectedSpells[key]
    SetSpellSelected(self.selectedSpells, spell, isNowSelected)

    self:UpdateSpellList()
    self:UpdateTrainerFrameButton()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON then
        PlaySound(isNowSelected and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    end
end

function TrainSpells:SelectAllTrainable()
    local className = self:GetPlayerClassName()
    local allSpells = (EFHelper_TrainerData and EFHelper_TrainerData[className]) or {}
    local playerLevel = UnitLevel("player") or 1

    for _, spell in ipairs(allSpells) do
        if not self:IsSpellTrained(spell) and playerLevel >= spell.level then
            SetSpellSelected(self.selectedSpells, spell, true)
        end
    end
    self:UpdateSpellList()
    self:UpdateTrainerFrameButton()
end

function TrainSpells:ClearSelected()
    wipe(self.selectedSpells)
    self:UpdateSpellList()
    self:UpdateTrainerFrameButton()
end

function TrainSpells:GetSelectedTotalCost()
    local className = self:GetPlayerClassName()
    local allSpells = (EFHelper_TrainerData and EFHelper_TrainerData[className]) or {}
    local playerLevel = UnitLevel("player") or 1
    local totalCost = 0
    local selectedCount = 0

    for _, spell in ipairs(allSpells) do
        if not self:IsSpellTrained(spell) and playerLevel >= spell.level then
            local key = GetSpellKey(spell)
            if self.selectedSpells[key] then
                totalCost = totalCost + (spell.cost or 0)
                selectedCount = selectedCount + 1
            end
        end
    end

    return totalCost, selectedCount
end

function TrainSpells:GetOrCreatePanel()
    if spellbookPanel then return spellbookPanel end

    local parentFrame = (_G.PlayerSpellsFrame and _G.PlayerSpellsFrame.SpellBookFrame)
        or _G.PlayerSpellsFrame
        or _G.SpellBookFrame
        or UIParent

    -- Parchment overlay panel snugly contained within spellbook frame
    local f = CreateFrame("Frame", "EFHelper_TrainSpellsPanel", parentFrame, "BackdropTemplate")
    f:Hide()
    f:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 14, -54)
    f:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -14, 46)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)

    -- Solid warm parchment background (1.0 alpha eliminates background ghosting)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.08, 0.07, 0.05, 1.0)
    f:SetBackdropBorderColor(0.65, 0.52, 0.30, 0.9)

    -- Header Title
    local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -12)
    title:SetText("Trainable Class Abilities")
    f.title = title

    -- Subtitle: Overhauled cost information
    local subtitle = f:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    subtitle:SetText("")
    f.subtitle = subtitle

    -- [Select All] Button
    local selectAllBtn = CreateFrame("Button", nil, f)
    selectAllBtn:SetSize(72, 18)
    selectAllBtn:SetPoint("LEFT", subtitle, "RIGHT", 14, 0)
    local selectAllText = selectAllBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    selectAllText:SetPoint("CENTER")
    selectAllText:SetText("|cffffd200[Select All]|r")
    selectAllBtn.text = selectAllText
    selectAllBtn:SetScript("OnClick", function()
        TrainSpells:SelectAllTrainable()
    end)
    selectAllBtn:SetScript("OnEnter", function(self)
        self.text:SetText("|cffffff00[Select All]|r")
    end)
    selectAllBtn:SetScript("OnLeave", function(self)
        self.text:SetText("|cffffd200[Select All]|r")
    end)
    f.selectAllBtn = selectAllBtn

    -- [Clear] Button
    local clearBtn = CreateFrame("Button", nil, f)
    clearBtn:SetSize(52, 18)
    clearBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 4, 0)
    local clearText = clearBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    clearText:SetPoint("CENTER")
    clearText:SetText("|cffaaaaaa[Clear]|r")
    clearBtn.text = clearText
    clearBtn:SetScript("OnClick", function()
        TrainSpells:ClearSelected()
    end)
    clearBtn:SetScript("OnEnter", function(self)
        self.text:SetText("|cffffffff[Clear]|r")
    end)
    clearBtn:SetScript("OnLeave", function(self)
        self.text:SetText("|cffaaaaaa[Clear]|r")
    end)
    f.clearBtn = clearBtn

    -- [Train Selected] Button
    local trainSelectedBtn = CreateFrame("Button", nil, f)
    trainSelectedBtn:SetSize(96, 18)
    trainSelectedBtn:SetPoint("LEFT", clearBtn, "RIGHT", 4, 0)
    local trainSelectedText = trainSelectedBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    trainSelectedText:SetPoint("CENTER")
    trainSelectedText:SetText("|cff666666[Train Selected]|r")
    trainSelectedBtn.text = trainSelectedText
    trainSelectedBtn:SetScript("OnClick", function()
        TrainSpells:TrainSelectedSpells(true)
    end)
    trainSelectedBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if TrainSpells.isTrainerOpen and not (IsTradeskillTrainer and IsTradeskillTrainer()) then
            GameTooltip:AddLine("Train Selected Spells", 0.2, 1.0, 0.2)
            GameTooltip:AddLine("Click to immediately purchase all selected available spells at this trainer.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Train Selected Spells", 0.7, 0.7, 0.7)
            GameTooltip:AddLine("Class trainer is not open. Visit your class trainer to train spells.", 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    trainSelectedBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    f.trainSelectedBtn = trainSelectedBtn

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    closeBtn:SetScript("OnClick", function()
        TrainSpells:HideSpellbookPanel()
    end)

    -- Search Box (slightly bigger: 170x24)
    local searchBox = CreateFrame("EditBox", "EFHelper_TrainerSearchBox", f, "SearchBoxTemplate")
    searchBox:SetSize(170, 24)
    searchBox:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -14, -8)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(eb)
        SearchBoxTemplate_OnTextChanged(eb)
        TrainSpells:UpdateSpellList()
    end)
    f.searchBox = searchBox

    -- Filter Checkbox: "Hide Higher Levels" (slightly bigger: 24x24)
    local hideCb = CreateFrame("CheckButton", "EFHelper_TrainerHideCb", f, "UICheckButtonTemplate")
    hideCb:SetSize(24, 24)
    hideCb:SetPoint("RIGHT", searchBox, "LEFT", -120, 0)
    _G[hideCb:GetName() .. "Text"]:SetText("Hide Higher Levels")
    hideCb:SetScript("OnClick", function(cb)
        local db = TrainSpells:GetDB()
        db.hideHigherLevels = cb:GetChecked()
        TrainSpells:UpdateSpellList()
    end)
    f.hideCb = hideCb

    -- Divider below header
    local div = f:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -48)
    div:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -48)
    div:SetHeight(1)
    div:SetColorTexture(0.5, 0.4, 0.25, 0.6)

    -- Scroll Frame
    local scrollFrame = CreateFrame("ScrollFrame", "EFHelper_TrainerScrollFrame", f, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -52)
    scrollFrame:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -30, 8)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function()
            TrainSpells:UpdateSpellList()
        end)
    end)
    f.scrollFrame = scrollFrame

    -- Dynamic Row Construction
    local contentFrame = CreateFrame("Frame", nil, f)
    contentFrame:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    contentFrame:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0, 0)
    f.contentFrame = contentFrame

    -- Create reusable row pool (up to 20 rows, 36px height)
    for i = 1, 20 do
        local row = CreateFrame("Button", "EFHelper_TrainerRow" .. i, contentFrame, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT - 2) -- 36px
        row:SetPoint("LEFT", contentFrame, "LEFT", 4, 0)
        row:SetPoint("RIGHT", contentFrame, "RIGHT", -4, 0)
        if i == 1 then
            row:SetPoint("TOP", contentFrame, "TOP", 0, 0)
        else
            row:SetPoint("TOP", spellRows[i - 1], "BOTTOM", 0, -2)
        end

        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row:SetBackdropColor(0.06, 0.05, 0.04, 0.45)
        row:SetBackdropBorderColor(0.25, 0.20, 0.15, 0.5)

        -- Selection Checkbox indicator frame (18x18)
        local checkFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
        checkFrame:SetSize(18, 18)
        checkFrame:SetPoint("LEFT", row, "LEFT", 6, 0)
        checkFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        checkFrame:SetBackdropColor(0.04, 0.04, 0.04, 0.8)
        checkFrame:SetBackdropBorderColor(0.5, 0.4, 0.25, 0.8)
        row.checkFrame = checkFrame

        local checkTex = checkFrame:CreateTexture(nil, "OVERLAY")
        checkTex:SetSize(18, 18)
        checkTex:SetPoint("CENTER", checkFrame, "CENTER", 0, 0)
        checkTex:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
        checkTex:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        row.checkTex = checkTex

        -- Spell Icon (slightly bigger: 30x30)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(30, 30)
        icon:SetPoint("LEFT", checkFrame, "RIGHT", 6, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon

        -- Spell Name & Rank
        local nameText = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        nameText:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        -- Subtitle: Talent tag
        local subText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        subText:SetPoint("LEFT", nameText, "RIGHT", 8, 0)
        subText:SetJustifyH("LEFT")
        row.subText = subText

        -- Level Requirement
        local levelText = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        levelText:SetPoint("RIGHT", row, "RIGHT", -115, 0)
        levelText:SetJustifyH("RIGHT")
        row.levelText = levelText

        -- Cost
        local costText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        costText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        costText:SetJustifyH("RIGHT")
        row.costText = costText

        -- Left click row to toggle selection
        row:RegisterForClicks("LeftButtonUp")
        row:SetScript("OnClick", function(self, button)
            if button == "LeftButton" and self.spellData then
                local playerLevel = UnitLevel("player") or 1
                if playerLevel >= self.spellData.level then
                    TrainSpells:ToggleSpellSelection(self.spellData)
                end
            end
        end)

        -- Hover Highlight & Tooltip
        row:SetScript("OnEnter", function(self)
            if self.isSelected then
                self:SetBackdropColor(0.24, 0.18, 0.08, 0.92)
            else
                self:SetBackdropColor(0.16, 0.13, 0.08, 0.75)
            end
            if self.spellData then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.spellData.name, 1, 0.82, 0)
                if self.spellData.rank then
                    GameTooltip:AddLine(string.format("Rank %d", self.spellData.rank), 1, 1, 1)
                end
                GameTooltip:AddLine(string.format("Required Level: %d", self.spellData.level), 0.8, 0.8, 0.8)
                GameTooltip:AddLine("Training Cost: " .. TrainSpells:FormatCost(self.spellData.cost), 1, 1, 1)
                if self.spellData.isTalent then
                    GameTooltip:AddLine("|cff33ccffLearned via Talents (Trainer provides higher ranks)|r", 0.2, 0.8, 1)
                end
                local pLvl = UnitLevel("player") or 1
                if pLvl >= self.spellData.level then
                    GameTooltip:AddLine("|cff00ff00Click to select/deselect for cost sum|r", 0.4, 1.0, 0.4)
                else
                    GameTooltip:AddLine("|cff888888Requires higher level to train|r", 0.6, 0.6, 0.6)
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            if self.isSelected then
                self:SetBackdropColor(0.20, 0.16, 0.06, 0.85)
            else
                self:SetBackdropColor(0.06, 0.05, 0.04, 0.45)
            end
            GameTooltip:Hide()
        end)

        spellRows[i] = row
    end

    -- Recalculate layout if panel size changes
    f:SetScript("OnSizeChanged", function()
        TrainSpells:UpdateSpellList()
    end)
    f:SetScript("OnShow", function()
        if not (InCombatLockdown and InCombatLockdown()) then
            TrainSpells:UpdateSpellbookTabsClickability(true)
        end
    end)
    f:SetScript("OnHide", function()
        if not (InCombatLockdown and InCombatLockdown()) then
            TrainSpells:UpdateSpellbookTabsClickability(false)
        end
    end)

    spellbookPanel = f
    self.panel = f
    return f
end

function TrainSpells:ToggleSpellbookPanel()
    if InCombatLockdown and InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[EFHelper]|r Cannot open Trainer Abilities in combat.")
        end
        return
    end
    local f = self:GetOrCreatePanel()
    if f:IsShown() then
        f:Hide()
    else
        local db = self:GetDB()
        if f.hideCb then f.hideCb:SetChecked(db.hideHigherLevels == true) end
        self:MarkKnownSpellsDirty()
        f:Show()
        self:UpdateSpellList()
    end
    self:UpdateButtonState()
end

function TrainSpells:GetFilteredSpells()
    local className = self:GetPlayerClassName()
    local allSpells = (EFHelper_TrainerData and EFHelper_TrainerData[className]) or {}
    local playerLevel = UnitLevel("player") or 1
    local db = self:GetDB()

    local searchFilter = ""
    if self.panel and self.panel.searchBox then
        searchFilter = (self.panel.searchBox:GetText() or ""):lower():match("^%s*(.-)%s*$")
    end

    local filtered = {}

    for _, spell in ipairs(allSpells) do
        self:ResolveSpellData(spell)
        local match = true

        -- 1. Exclude spells that HAVE already been trained
        if self:IsSpellTrained(spell) then
            match = false
        end

        -- 2. Level filter: Hide higher levels if checked
        if match and db.hideHigherLevels and spell.level > playerLevel then
            match = false
        end

        -- 3. Search text filter
        if match and searchFilter ~= "" then
            local spellNameLower = spell.name:lower()
            local levelStr = tostring(spell.level)
            if not spellNameLower:find(searchFilter, 1, true) and not levelStr:find(searchFilter, 1, true) then
                match = false
            end
        end

        if match then
            table.insert(filtered, spell)
        end
    end

    return filtered, className, allSpells
end

function TrainSpells:UpdateSpellList()
    local f = self.panel
    if not f or not f:IsShown() then return end

    local filtered, className = self:GetFilteredSpells()
    local playerLevel = UnitLevel("player") or 1
    local selectedCost, selectedCount = self:GetSelectedTotalCost()

    -- Overhauled Subtitle: Sum of selected spells (redundant level and remaining counts removed)
    f.title:SetText(string.format("%s Trainer Abilities", className))
    f.subtitle:SetText(string.format("Training Cost: %s  |cffaaaaaa(%d selected)|r", self:FormatCost(selectedCost), selectedCount))

    if f.trainSelectedBtn then
        if self.isTrainerOpen and not (IsTradeskillTrainer and (IsTradeskillTrainer() == true or IsTradeskillTrainer() == 1)) then
            f.trainSelectedBtn.text:SetText("|cff00ff00[Train Selected]|r")
        else
            f.trainSelectedBtn.text:SetText("|cff666666[Train Selected]|r")
        end
    end

    local numEntries = #filtered
    local availableHeight = f.scrollFrame:GetHeight()
    if not availableHeight or availableHeight <= 0 then availableHeight = 260 end
    local numVisibleRows = math.min(#spellRows, math.max(1, math.floor(availableHeight / ROW_HEIGHT)))

    FauxScrollFrame_Update(f.scrollFrame, numEntries, numVisibleRows, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(f.scrollFrame)

    for i = 1, #spellRows do
        local row = spellRows[i]
        local dataIndex = offset + i

        if i <= numVisibleRows and dataIndex <= numEntries then
            local spell = filtered[dataIndex]
            row.spellData = spell

            -- Set Icon (resolves authentic icon FileID via spellID)
            local iconTex = self:GetSpellIcon(spell.name, spell.spellID)
            row.icon:SetTexture(iconTex)

            -- Format Name & Rank
            local rankText = spell.rank and string.format(" |cffffd200(Rank %d)|r", spell.rank) or ""
            local isAvailable = (playerLevel >= spell.level)
            local key = GetSpellKey(spell)
            local isSelected = (self.selectedSpells[key] == true)
            row.isSelected = isSelected

            if isAvailable then
                row.icon:SetDesaturated(false)
                row.icon:SetAlpha(1.0)
                -- 3. Trainable spells have green name text!
                row.nameText:SetText(string.format("|cff20ff20%s|r%s", spell.name, rankText))
                row.levelText:SetText(string.format("|cff20ff20Level %d|r", spell.level))
                row.costText:SetText(self:FormatCost(spell.cost))

                -- Checkbox indicator and selection highlighting
                row.checkFrame:Show()
                if isSelected then
                    row.checkTex:Show()
                    row.checkFrame:SetBackdropBorderColor(1.0, 0.85, 0.25, 1.0)
                    row:SetBackdropColor(0.20, 0.16, 0.06, 0.85)
                    row:SetBackdropBorderColor(0.95, 0.80, 0.25, 0.95)
                else
                    row.checkTex:Hide()
                    row.checkFrame:SetBackdropBorderColor(0.4, 0.35, 0.25, 0.6)
                    row:SetBackdropColor(0.06, 0.05, 0.04, 0.45)
                    row:SetBackdropBorderColor(0.25, 0.20, 0.15, 0.5)
                end
            else
                -- Grayed out for locked/higher level ranks
                row.icon:SetDesaturated(true)
                row.icon:SetAlpha(0.4)
                row.nameText:SetText(string.format("|cff888888%s|r|cff666666%s|r", spell.name, rankText))
                row.levelText:SetText(string.format("|cff888888Level %d|r", spell.level))
                row.costText:SetText(self:FormatCost(spell.cost, true))

                -- Locked spells cannot be trained yet
                row.checkFrame:Hide()
                row.checkTex:Hide()
                row:SetBackdropColor(0.04, 0.04, 0.04, 0.3)
                row:SetBackdropBorderColor(0.18, 0.18, 0.18, 0.3)
            end

            -- Talent tag
            if spell.isTalent then
                row.subText:SetText("|cff33ccff[Talent]|r")
            else
                row.subText:SetText("")
            end

            row:Show()
        else
            row.spellData = nil
            row.isSelected = false
            row:Hide()
        end
    end
end

-- ----------------------------------------------------------------------------
-- Feature 3: Auto-Training & Class Trainer Integration
-- ----------------------------------------------------------------------------
local function IsClassTrainer()
    -- Check if trainer window is used for a profession / trade skill
    -- Returns true for tradeskills (Blacksmithing, Tailoring, etc.), false for class trainers
    if IsTradeskillTrainer and (IsTradeskillTrainer() == true or IsTradeskillTrainer() == 1) then
        return false
    end
    return true
end

-- Robust parser supporting both modern WoW (category at return 2) and classic (category at return 3)
local function ParseTrainerServiceInfo(i)
    if not GetTrainerServiceInfo then return nil, nil, nil end
    local r1, r2, r3, r4, r5 = GetTrainerServiceInfo(i)
    if not r1 then return nil, nil, nil end

    local name = r1
    local category, rankStr

    -- Detect API layout:
    -- Modern WoW: r1 = name, r2 = category ("available", "unavailable", "used", "header")
    -- Legacy Classic: r1 = name, r2 = rank, r3 = category
    if r2 == "available" or r2 == "unavailable" or r2 == "used" or r2 == "header" then
        category = r2
        rankStr = (type(r5) == "string" and r5) or (type(r4) == "string" and r4) or ""
    elseif r3 == "available" or r3 == "unavailable" or r3 == "used" or r3 == "header" then
        rankStr = (type(r2) == "string" and r2) or ""
        category = r3
    else
        category = r2
        rankStr = (type(r5) == "string" and r5) or ""
    end

    -- Check if name itself contains rank, e.g. "Seal of Fury (Rank 1)"
    local cleanName, embeddedRank = name:match("^(.-)%s*%([Rr]ank%s*(%d+)%)")
    if cleanName and embeddedRank then
        name = cleanName
        if rankStr == "" or not rankStr:find("Rank") then
            rankStr = "Rank " .. embeddedRank
        end
    end

    return name, category, rankStr
end

local function GetTrainerRefButton()
    local trainerFrame = _G.ClassTrainerFrame or _G.TrainerFrame
    if not trainerFrame then return nil, nil end
    local refBtn = _G.ClassTrainerTrainButton
        or (trainerFrame.TrainButton)
        or (_G.TrainerFrame and _G.TrainerFrame.TrainButton)
    return trainerFrame, refBtn
end

function TrainSpells:TRAINER_SHOW()
    if not IsClassTrainer() then
        self.isTrainerOpen = false
        if self.trainerButton then self.trainerButton:Hide() end
        return
    end

    self.isTrainerOpen = true

    -- Rescan known spells to ensure accurate trained state
    self:MarkKnownSpellsDirty()
    self:ScanKnownSpells()

    -- Hook trainer updates to refresh button
    if not self.isTrainerFrameHooked and ClassTrainerFrame_Update then
        self.isTrainerFrameHooked = true
        hooksecurefunc("ClassTrainerFrame_Update", function()
            if TrainSpells.isTrainerOpen and IsClassTrainer() then
                TrainSpells:UpdateTrainerFrameButton()
            end
        end)
    end

    -- Attach / Show "Train Selected" button underneath Blizzard's Train button
    self:AttachTrainerFrameButton()

    -- Also update spellbook panel train button if open
    if self.panel and self.panel.trainSelectedBtn then
        self.panel.trainSelectedBtn.text:SetText("|cff00ff00[Train Selected]|r")
    end

    -- When exactly 0 spells are selected, assume the player opts for manual training.
    -- The trainer window simply remains open for old-fashioned training, with the addon not intervening in any way.
    if not next(self.selectedSpells) then
        return
    end

    -- Auto-train selected abilities if enabled in config
    local db = self:GetDB()
    if db.enabled and db.autoTrain ~= false then
        -- Ensure available filter is enabled so selected spells are shown
        if SetTrainerServiceTypeFilter and GetTrainerServiceTypeFilter then
            pcall(function()
                if not GetTrainerServiceTypeFilter("available") then
                    SetTrainerServiceTypeFilter("available", 1)
                end
            end)
        end

        C_Timer.After(0.15, function()
            if self.isTrainerOpen and IsClassTrainer() and next(self.selectedSpells) then
                self:TrainSelectedSpells(false)
            end
        end)
    end
end

function TrainSpells:TRAINER_UPDATE()
    if not self.isTrainerOpen or not IsClassTrainer() then return end
    self:UpdateTrainerFrameButton()
end

function TrainSpells:TRAINER_CLOSED()
    self.isTrainerOpen = false
    self.trainSession = nil
    if self.trainerButton then
        self.trainerButton:Hide()
    end
    if self.panel and self.panel.trainSelectedBtn then
        self.panel.trainSelectedBtn.text:SetText("|cff666666[Train Selected]|r")
    end
end

function TrainSpells:AttachTrainerFrameButton()
    if InCombatLockdown and InCombatLockdown() then return end
    local trainerFrame, refBtn = GetTrainerRefButton()
    if not trainerFrame then
        C_Timer.After(0.05, function()
            if self.isTrainerOpen and IsClassTrainer() and not (InCombatLockdown and InCombatLockdown()) then
                self:AttachTrainerFrameButton()
            end
        end)
        return
    end

    local btn = self.trainerButton
    if not btn then
        btn = CreateFrame("Button", "EFHelper_TrainerTrainSelectedButton", trainerFrame, "UIPanelButtonTemplate")
        local fs = btn:GetFontString()
        if fs then
            fs:SetFontObject("GameFontNormalSmall")
        end
        btn:SetText("Train Selected")
        btn:SetScript("OnClick", function()
            TrainSpells:TrainSelectedSpells(true)
        end)

        btn:SetScript("OnEnter", function(selfBtn)
            GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Train Selected Abilities", 1, 0.82, 0)
            local count, cost = TrainSpells:GetTrainerAvailableSelectedInfo()
            if count > 0 then
                GameTooltip:AddLine(string.format("Purchase %d selected abilities for %s.", count, TrainSpells:FormatCost(cost)), 1, 1, 1, true)
            else
                GameTooltip:AddLine("No selected abilities are currently trainable.", 0.7, 0.7, 0.7, true)
                GameTooltip:AddLine("Open your Spellbook Trainer tab to select abilities.", 0.6, 0.6, 0.6, true)
            end
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        self.trainerButton = btn
    end

    btn:SetParent(trainerFrame)
    btn:ClearAllPoints()

    -- Position directly UNDERNEATH the Blizzard "Train" button
    if refBtn then
        local w = math.max(100, refBtn:GetWidth() or 80)
        local h = refBtn:GetHeight() or 22
        btn:SetSize(w, h)
        btn:SetPoint("TOPRIGHT", refBtn, "BOTTOMRIGHT", 0, -2)
        btn:SetFrameLevel(refBtn:GetFrameLevel() + 1)
    else
        btn:SetSize(100, 22)
        btn:SetPoint("BOTTOMRIGHT", trainerFrame, "BOTTOMRIGHT", -6, -26)
    end

    self:UpdateTrainerFrameButton()
    btn:Show()
end

function TrainSpells:UpdateTrainerFrameButton()
    if InCombatLockdown and InCombatLockdown() then return end
    if not self.trainerButton then return end
    if not self.isTrainerOpen or not IsClassTrainer() then
        self.trainerButton:Hide()
        return
    end

    local count, cost = self:GetTrainerAvailableSelectedInfo()
    if count > 0 then
        self.trainerButton:SetText(string.format("Train Selected (%d)", count))
        self.trainerButton:Enable()
    else
        self.trainerButton:SetText("Train Selected")
        self.trainerButton:Disable()
    end
    self.trainerButton:Show()

    if self.panel and self.panel.trainSelectedBtn then
        self.panel.trainSelectedBtn.text:SetText("|cff00ff00[Train Selected]|r")
    end
end

function TrainSpells:GetTrainerAvailableSelectedInfo()
    if not self.isTrainerOpen or not IsClassTrainer() then return 0, 0 end

    local numServices = GetNumTrainerServices and GetNumTrainerServices() or 0
    local count = 0
    local totalCost = 0

    for i = 1, numServices do
        local name, category, rankStr = ParseTrainerServiceInfo(i)
        if name and (category == "available" or category == 1 or category == true) then
            local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
            local serviceSpellID = nil
            if link then
                local idStr = link:match("spell:(%d+)") or link:match("enchant:(%d+)")
                serviceSpellID = tonumber(idStr)
            end

            local isSelected = self:IsTrainerServiceSelected(i, name, rankStr, serviceSpellID)
            if isSelected then
                local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
                count = count + 1
                totalCost = totalCost + cost
            end
        end
    end

    return count, totalCost
end

function TrainSpells:IsTrainerServiceSelected(serviceIndex, serviceName, serviceRank, serviceSpellID)
    if not serviceName then return false end

    -- 1. Direct match by spellID if present in link
    if serviceSpellID then
        local key = tostring(serviceSpellID)
        if self.selectedSpells[key] then
            return true, { spellID = serviceSpellID, name = serviceName }
        end
    end

    -- Parse numeric rank from serviceRank string (e.g. "Rank 1" -> 1)
    local serviceRankNum = nil
    if serviceRank and type(serviceRank) == "string" then
        serviceRankNum = tonumber(serviceRank:match("[Rr]ank%s*(%d+)")) or tonumber(serviceRank:match("(%d+)"))
    end

    local nameTrimmed = serviceName:lower():match("^%s*(.-)%s*$")

    -- 2. Match against EFHelper_TrainerData for player's class
    local className = self:GetPlayerClassName()
    local classData = (EFHelper_TrainerData and EFHelper_TrainerData[className]) or {}

    for _, entry in ipairs(classData) do
        self:ResolveSpellData(entry)
        local entryNameTrimmed = (entry.name or ""):lower():match("^%s*(.-)%s*$")
        if entryNameTrimmed == nameTrimmed then
            local rankMatch = false
            if not entry.rank and not serviceRankNum then
                rankMatch = true
            elseif entry.rank and serviceRankNum and entry.rank == serviceRankNum then
                rankMatch = true
            end

            if rankMatch then
                local keyID = GetSpellKey(entry)
                local keyNameRank = string.format("%s#%d", entry.name, entry.rank or 0)

                if self.selectedSpells[keyID] or self.selectedSpells[keyNameRank] then
                    return true, entry
                end
            end
        end
    end

    return false
end

function TrainSpells:TrainSelectedSpells(isManual)
    if not self.isTrainerOpen then
        if isManual then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[EFHelper]|r No class trainer window is open.")
        end
        return
    end

    if InCombatLockdown and InCombatLockdown() then
        if isManual then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[EFHelper]|r Cannot train spells while in combat.")
        end
        return
    end

    if not IsClassTrainer() then
        if isManual then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444[EFHelper]|r Auto-train only works with class trainers.")
        end
        return
    end

    if not next(self.selectedSpells) then
        if isManual then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffd100[EFHelper]|r No spells are selected to train. Select spells in the Trainer Abilities tab or click [Select All].")
        end
        return
    end

    -- Expand collapsed headers so all services are accessible
    if ExpandTrainerSkillLine then
        pcall(ExpandTrainerSkillLine, 0)
    end

    -- Ensure available filter is enabled so available spells are shown
    if SetTrainerServiceTypeFilter and GetTrainerServiceTypeFilter then
        pcall(function()
            if not GetTrainerServiceTypeFilter("available") then
                SetTrainerServiceTypeFilter("available", 1)
            end
        end)
    end

    if self.trainSession then
        return
    end

    self.trainSession = {
        isManual = isManual,
        pass = 0,
        maxPasses = 6,
        trainedSpells = {}, -- [name#rank] = cost
        totalCost = 0,
        trainedCount = 0,
    }

    self:ExecuteTrainPass()
end

function TrainSpells:ExecuteTrainPass()
    if not self.isTrainerOpen or not self.trainSession then
        return
    end

    local session = self.trainSession
    session.pass = session.pass + 1

    local numServices = GetNumTrainerServices and GetNumTrainerServices() or 0
    if numServices <= 0 then
        self:FinishTrainSession()
        return
    end

    local playerMoney = GetMoney and GetMoney() or 0
    local passTrainedCount = 0

    -- Loop DESCENDING: buying a service causes subsequent indices in the trainer
    -- to shift; looping from highest to lowest guarantees no index is ever skipped!
    for i = numServices, 1, -1 do
        if not self.isTrainerOpen then break end

        local name, category, rankStr = ParseTrainerServiceInfo(i)
        if name and (category == "available" or category == 1 or category == true) then
            local cost = GetTrainerServiceCost and GetTrainerServiceCost(i) or 0
            if playerMoney >= cost then
                local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
                local serviceSpellID = nil
                if link then
                    local idStr = link:match("spell:(%d+)") or link:match("enchant:(%d+)")
                    serviceSpellID = tonumber(idStr)
                end

                local isSelected, spellEntry = self:IsTrainerServiceSelected(i, name, rankStr, serviceSpellID)
                if isSelected then
                    local identifier = string.format("%s#%s", name, rankStr or "")
                    if not session.trainedSpells[identifier] then
                        session.trainedSpells[identifier] = cost
                        session.totalCost = session.totalCost + cost
                        session.trainedCount = session.trainedCount + 1
                        passTrainedCount = passTrainedCount + 1
                        playerMoney = playerMoney - cost

                        -- Purchase trainer service
                        BuyTrainerService(i)
                    end
                end
            end
        end
    end

    -- If any spells were trained in this pass, wait 0.25s for the server to unlock
    -- subsequent cascading ranks, then execute the next pass (up to maxPasses)
    if passTrainedCount > 0 and session.pass < session.maxPasses then
        C_Timer.After(0.25, function()
            if self.isTrainerOpen and self.trainSession then
                self:ExecuteTrainPass()
            end
        end)
    else
        self:FinishTrainSession()
    end
end

function TrainSpells:FinishTrainSession()
    local session = self.trainSession
    self.trainSession = nil

    if not session then return end

    if session.trainedCount > 0 then
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_QUEST_LIST_COMPLETE then
            PlaySound(SOUNDKIT.IG_QUEST_LIST_COMPLETE)
        end

        local costStr = self:FormatCost(session.totalCost)
        local msg = string.format("|cff00ff00[EFHelper]|r Successfully trained %d %s for %s.",
            session.trainedCount,
            session.trainedCount == 1 and "ability" or "abilities",
            costStr)
        DEFAULT_CHAT_FRAME:AddMessage(msg)

        -- Rescan spellbook and remove newly trained abilities from selectedSpells
        self:MarkKnownSpellsDirty()
        self:ScanKnownSpells()
        local className = self:GetPlayerClassName()
        local allSpells = (EFHelper_TrainerData and EFHelper_TrainerData[className]) or {}
        for _, spell in ipairs(allSpells) do
            if self:IsSpellTrained(spell) then
                SetSpellSelected(self.selectedSpells, spell, nil)
            end
        end
    elseif session.isManual then
        local _, selectedCount = self:GetSelectedTotalCost()
        if selectedCount == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EFHelper]|r No abilities are currently selected to train. Open your Spellbook Trainer tab to select abilities.")
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[EFHelper]|r No selected abilities are currently trainable (already trained, required level not met, or insufficient gold).")
        end
    end

    self:UpdateTrainerFrameButton()
    if self.panel and self.panel:IsShown() then
        self:UpdateSpellList()
    end
end


