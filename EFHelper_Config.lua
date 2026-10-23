-- ----------------------------------------------------------------------------
-- EFHelper_Config.lua
-- Unified Configuration, Settings, and Media Hub for EFHelper
-- Modern Warcraft Dual-Pane Sidebar Layout
-- ----------------------------------------------------------------------------
local addonName, addonTable = ...
local EFHelper = _G.EFHelper or addonTable
local Config = EFHelper:NewModule("Config")
EFHelper.Config = Config
addonTable.Config = Config

local UI = EFHelper.UI
local Utils = EFHelper.Utils

-- ----------------------------------------------------------------------------
-- Options Window State & Navigation
-- ----------------------------------------------------------------------------
local configFrame = nil
local panels = {}
local tabButtons = {}
local selectedMacroName = "EFTag"

local MODULE_TABS = {
    {
        name = "Tagging & Macros",
        subtext = "Targeting & Ping",
        icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    },
    {
        name = "Campfire & Rest",
        subtext = "Tent buff alerts",
        icon = "Interface\\Icons\\Spell_Fire_Fire",
    },
    {
        name = "Raid Swapper",
        subtext = "Out-of-raid alt",
        icon = "Interface\\Icons\\Spell_Shadow_Charm",
    },
    {
        name = "Kill XP Predict",
        subtext = "Solo & Duo combat",
        icon = "Interface\\Icons\\INV_Misc_Book_09",
    },
    {
        name = "Custom XP Bar",
        subtext = "Quest XP & pacing",
        icon = "Interface\\Icons\\Spell_Holy_MindVision",
    },
    {
        name = "Trainer Spells",
        subtext = "Auto-train & toast",
        icon = "Interface\\Icons\\INV_Misc_Book_06",
    },
    {
        name = "Waypoint Bridge",
        subtext = "RXP to WaypointUI",
        icon = "Interface\\Icons\\INV_Misc_Map_01",
    },
}

local function SelectTab(tabIndex)
    for i, panel in ipairs(panels) do
        if i == tabIndex then
            panel:Show()
            if panel.OnRefresh then panel:OnRefresh() end
        else
            panel:Hide()
        end
    end
    for i, btn in ipairs(tabButtons) do
        if btn.SetSelected then
            btn:SetSelected(i == tabIndex)
        else
            if i == tabIndex then btn:Disable() else btn:Enable() end
        end
    end
end
Config.SelectTab = SelectTab

-- Sidebar Button Component
local function CreateSidebarButton(parent, index, data)
    local btn = CreateFrame("Button", "EFHelperSidebarTab" .. index, parent, "BackdropTemplate")
    btn:SetSize(164, 46)
    btn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })

    -- Active gold indicator bar on the left edge
    local indicator = btn:CreateTexture(nil, "OVERLAY")
    indicator:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    indicator:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 1, 1)
    indicator:SetWidth(4)
    indicator:SetColorTexture(1.0, 0.82, 0.0, 1.0)
    indicator:Hide()
    btn.indicator = indicator

    -- Icon texture
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28)
    icon:SetPoint("LEFT", btn, "LEFT", 10, 0)
    icon:SetTexture(data.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    btn.icon = icon

    -- Icon border
    local iconBorder = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    iconBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 1, -1)
    iconBorder:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    iconBorder:SetBackdropBorderColor(0.28, 0.24, 0.16, 0.85)

    -- Title label
    local title = btn:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
    title:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    title:SetJustifyH("LEFT")
    title:SetText(data.name)
    btn.title = title

    -- Subtitle / description
    local sub = btn:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    sub:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    sub:SetJustifyH("LEFT")
    sub:SetText(data.subtext or "")
    btn.sub = sub

    btn.SetSelected = function(self, isSelected)
        self.isSelected = isSelected
        if isSelected then
            self:SetBackdropColor(0.20, 0.16, 0.08, 0.9)
            self:SetBackdropBorderColor(0.85, 0.68, 0.22, 0.95)
            self.title:SetTextColor(1.0, 0.84, 0.0)
            self.sub:SetTextColor(0.85, 0.85, 0.85)
            self.indicator:Show()
            self.icon:SetVertexColor(1.0, 1.0, 1.0)
        else
            self:SetBackdropColor(0.06, 0.07, 0.09, 0.65)
            self:SetBackdropBorderColor(0.18, 0.19, 0.22, 0.7)
            self.title:SetTextColor(0.75, 0.75, 0.75)
            self.sub:SetTextColor(0.45, 0.45, 0.45)
            self.indicator:Hide()
            self.icon:SetVertexColor(0.75, 0.75, 0.75)
        end
    end

    btn:SetScript("OnEnter", function(self)
        if not self.isSelected then
            self:SetBackdropColor(0.12, 0.14, 0.18, 0.85)
            self:SetBackdropBorderColor(0.4, 0.4, 0.45, 0.9)
            self.title:SetTextColor(1.0, 1.0, 1.0)
            self.icon:SetVertexColor(1.0, 1.0, 1.0)
        end
    end)

    btn:SetScript("OnLeave", function(self)
        if not self.isSelected then
            self:SetBackdropColor(0.06, 0.07, 0.09, 0.65)
            self:SetBackdropBorderColor(0.18, 0.19, 0.22, 0.7)
            self.title:SetTextColor(0.75, 0.75, 0.75)
            self.icon:SetVertexColor(0.75, 0.75, 0.75)
        end
    end)

    btn:SetScript("OnClick", function(self)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856)
        SelectTab(index)
    end)

    btn:SetSelected(false)
    return btn
end

-- Helper to set up dropdowns (supporting modern MenuUtil / DropdownButton or fallback)
local function SetupDropdown(button, getSelected, onSelect, options)
    if button.SetupMenu then
        button:SetupMenu(function(owner, rootDescription)
            rootDescription:SetTag("EFHELPER_DROPDOWN_" .. (button:GetName() or "ANON"))
            for _, opt in ipairs(options) do
                local val = type(opt) == "table" and opt.value or opt
                local text = type(opt) == "table" and opt.text or opt
                rootDescription:CreateRadio(
                    text,
                    function() return getSelected() == val end,
                    function()
                        onSelect(val, text)
                        button:SetText(text)
                    end
                )
            end
        end)
    elseif MenuUtil and MenuUtil.CreateContextMenu then
        button:SetScript("OnClick", function(self)
            MenuUtil.CreateContextMenu(self, function(owner, rootDescription)
                for _, opt in ipairs(options) do
                    local val = type(opt) == "table" and opt.value or opt
                    local text = type(opt) == "table" and opt.text or opt
                    rootDescription:CreateRadio(
                        text,
                        function() return getSelected() == val end,
                        function()
                            onSelect(val, text)
                            button:SetText(text)
                        end
                    )
                end
            end)
        end)
    end
end

-- Helper to create styled section titles
local function CreateSectionTitle(parent, text, relativeTo, yOffset)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    if relativeTo and type(relativeTo) == "table" and relativeTo.GetPoint then
        title:SetPoint("TOPLEFT", relativeTo, "BOTTOMLEFT", 0, yOffset or -12)
    else
        title:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, relativeTo or yOffset or -14)
    end
    title:SetText(text)
    return title
end

-- ----------------------------------------------------------------------------
-- Panel 1: Tagging & Macros
-- ----------------------------------------------------------------------------
local function CreateTaggingPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    -- Title & Description
    local title = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -18)
    title:SetText("Targeting & Macro Hub")

    local desc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("Creates fast pull/tagging macros with automatic target acquisition and skull ping.")

    -- 1. Mob Name Section
    local mobLabel = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    mobLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
    mobLabel:SetText("Target Mob Name:")

    local mobInput = CreateFrame("EditBox", "EFHelperConfigMobInput", p, "InputBoxTemplate")
    mobInput:SetSize(240, 24)
    mobInput:SetPoint("TOPLEFT", mobLabel, "BOTTOMLEFT", 4, -6)
    mobInput:SetAutoFocus(false)
    mobInput:SetMaxLetters(50)

    local targetBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    targetBtn:SetSize(100, 24)
    targetBtn:SetPoint("LEFT", mobInput, "RIGHT", 10, 0)
    targetBtn:SetText("Get Target")
    targetBtn:SetScript("OnClick", function()
        if UnitExists("target") then
            local targetName = (Utils and Utils.GetUnitName and Utils.GetUnitName("target")) or "Target"
            if targetName and targetName ~= "" then
                mobInput:SetText(targetName)
                mobInput:ClearFocus()
            end
        else
            print("|cffff4444[EFHelper]|r You do not have a target selected.")
        end
    end)

    -- 2. Tagging Ability Section
    local spellLabel = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    spellLabel:SetPoint("TOPLEFT", mobInput, "BOTTOMLEFT", -4, -14)
    spellLabel:SetText("Tagging Ability / Spell:")

    local spellDropdown
    local ok, btn = pcall(CreateFrame, "DropdownButton", "EFHelperConfigSpellDropdown", p, "WowStyle1DropdownTemplate")
    if ok and btn then
        spellDropdown = btn
    else
        spellDropdown = CreateFrame("Button", "EFHelperConfigSpellDropdown", p, "UIPanelButtonTemplate")
    end
    spellDropdown:SetSize(350, 26)
    spellDropdown:SetPoint("TOPLEFT", spellLabel, "BOTTOMLEFT", 4, -6)
    spellDropdown:SetText(EFHelper.selectedSpell or "Select an ability...")

    -- Build dropdown options
    local spellOptions = {
        { value = "none", text = "none (Target & Ping only)" }
    }
    if EFHelper.TaggingSpells then
        for _, s in ipairs(EFHelper.TaggingSpells) do
            local sName = type(s) == "table" and s.name or tostring(s)
            local sClass = type(s) == "table" and s.class and (" (" .. s.class .. ")") or ""
            table.insert(spellOptions, { value = sName, text = sName .. sClass })
        end
    end

    SetupDropdown(
        spellDropdown,
        function()
            return (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.lastSpell) or EFHelper.selectedSpell or "none"
        end,
        function(val, text)
            EFHelper.selectedSpell = val
            if EFHelper.db and EFHelper.db.profile then
                EFHelper.db.profile.lastSpell = val
            end
            if EFHelperCharDB then
                EFHelperCharDB.lastSpell = val
            end
        end,
        spellOptions
    )

    -- 3. Macro Name Selection (EFTag / EFTag2 / EFHRXP)
    local macroLabel = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    macroLabel:SetPoint("TOPLEFT", spellDropdown, "BOTTOMLEFT", -4, -14)
    macroLabel:SetText("Macro Slot:")

    local macroButtons = {}
    local macroNames = { "EFTag", "EFTag2", "EFHRXP" }
    for i, name in ipairs(macroNames) do
        local mBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        mBtn:SetSize(90, 24)
        mBtn:SetPoint("TOPLEFT", macroLabel, "BOTTOMLEFT", (i - 1) * 98 + 4, -6)
        mBtn:SetText(name)
        mBtn:SetScript("OnClick", function()
            selectedMacroName = name
            for _, b in ipairs(macroButtons) do
                b:Enable()
            end
            mBtn:Disable()
        end)
        table.insert(macroButtons, mBtn)
        if name == selectedMacroName then
            mBtn:Disable()
        end
    end

    -- 4. Create / Update Macro Button & Feedback
    local createMacroBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    createMacroBtn:SetSize(180, 28)
    createMacroBtn:SetPoint("TOPLEFT", macroLabel, "BOTTOMLEFT", 4, -38)
    createMacroBtn:SetText("Create / Update Macro")

    local feedback = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    feedback:SetPoint("LEFT", createMacroBtn, "RIGHT", 12, 0)
    feedback:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    feedback:SetJustifyH("LEFT")
    feedback:SetText("")

    createMacroBtn:SetScript("OnClick", function()
        local mobName = mobInput:GetText()
        if not mobName or mobName:match("^%s*$") then
            feedback:SetText("|cffff4444Please enter or target a mob name first.|r")
            return
        end

        local currentSpell = (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.lastSpell) or EFHelper.selectedSpell
        local success = false
        if EFHelper.Tagging and EFHelper.Tagging.CreateOrUpdateTaggingMacro then
            success = EFHelper.Tagging:CreateOrUpdateTaggingMacro(
                selectedMacroName or "EFTag",
                mobName,
                currentSpell,
                true
            )
        elseif EFHelper.CreateOrUpdateTaggingMacro then
            success = EFHelper:CreateOrUpdateTaggingMacro(
                selectedMacroName or "EFTag",
                mobName,
                currentSpell,
                true
            )
        end

        if success then
            if EFHelper.db and EFHelper.db.profile then
                EFHelper.db.profile.lastMobName = mobName
                EFHelper.db.profile.lastSpell = currentSpell
            end
            if EFHelperCharDB then
                EFHelperCharDB.lastMobName = mobName
                EFHelperCharDB.lastSpell = currentSpell
            end
            feedback:SetText(string.format("|cff00ff00Macro '%s' saved! Drag from /m to bar.|r", selectedMacroName or "EFTag"))
        else
            feedback:SetText("|cffff4444Failed to update macro. Check macro limit.|r")
        end
    end)

    -- Hint text
    local hint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", createMacroBtn, "BOTTOMLEFT", 0, -8)
    hint:SetText("Saves to Character Macros (/m). Drag the macro to your action bar.")

    -- 4b. Lightweight FFA Auto-Loot Toggle Setting
    local ffaCb = CreateFrame("CheckButton", "EFHelperConfigFFAAutoLoot", p, "InterfaceOptionsCheckButtonTemplate")
    ffaCb:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", -2, -6)
    _G[ffaCb:GetName() .. "Text"]:SetText("Show Auto-Loot Toggle Button while in Free-For-All Group")
    ffaCb:SetScript("OnClick", function(self)
        if EFHelper.db and EFHelper.db.profile then
            EFHelper.db.profile.ffaAutoLootEnabled = self:GetChecked() and true or false
        end
        if EFHelper.UpdateFFAAutoLootWidget then
            EFHelper:UpdateFFAAutoLootWidget()
        end
    end)
    p.ffaCb = ffaCb

    -- 5. Information Box
    local infoBox = CreateFrame("Frame", nil, p, "BackdropTemplate")
    infoBox:SetPoint("TOPLEFT", ffaCb, "BOTTOMLEFT", 2, -6)
    infoBox:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -20, 14)
    infoBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    infoBox:SetBackdropColor(0.04, 0.05, 0.07, 0.5)
    infoBox:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)

    local infoText = infoBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", infoBox, "TOPLEFT", 10, -8)
    infoText:SetPoint("BOTTOMRIGHT", infoBox, "BOTTOMRIGHT", -10, 8)
    infoText:SetJustifyH("LEFT")
    infoText:SetJustifyV("TOP")
    infoText:SetText(
        "|cffffd100Tagging & Macro Hub Features:|r\n" ..
        "• |cffffffffInstant Tagging|r: Generates a macro that instantly acquires target and casts your selected spell.\n" ..
        "• |cffffffffRaid Ping|r: Automatically drops a skull raid target marker on the target to alert party members.\n" ..
        "• |cffffffffFFA Auto-Loot Toggle|r: Displays a compact floating toggle when party loot is set to Free-For-All.\n" ..
        "• |cffffffffTarget Mirror|r: Press 'Get Target' while targeting any mob to populate the name automatically.\n" ..
        "• Slash commands: |cff00ffff/efh|r (config) or drag the macro from |cff00ffff/m|r directly to your action bar."
    )

    p.mobInput = mobInput
    p.spellDropdown = spellDropdown
    p.feedback = feedback

    p.OnRefresh = function(self)
        local lastMob = (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.lastMobName) or (EFHelperCharDB and EFHelperCharDB.lastMobName)
        if lastMob and self.mobInput:GetText() == "" then
            self.mobInput:SetText(lastMob)
        end
        local lastSpell = (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.lastSpell) or EFHelper.selectedSpell
        if lastSpell then
            self.spellDropdown:SetText(lastSpell)
        end
        if self.ffaCb then
            local enabled = not (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.ffaAutoLootEnabled == false)
            self.ffaCb:SetChecked(enabled)
        end
        self.feedback:SetText("")
    end

    return p
end

-- ----------------------------------------------------------------------------
-- Panel 2: Campfire & Buffs
-- ----------------------------------------------------------------------------
local function CreateCampfirePanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local Campfire = addonTable.Campfire or EFHelper.Campfire

    -- Title & Description
    local title = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -18)
    title:SetText("Campfire HUD & Floating Alerts")

    local desc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("Shows active campfire benefits in equivalent WoW buffs below the Minimap, and alerts when near a tent.")

    -- 1. Enable Checkbox
    local enableCb = CreateFrame("CheckButton", "EFHelperConfigCampfireEnable", p, "InterfaceOptionsCheckButtonTemplate")
    enableCb:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
    _G[enableCb:GetName() .. "Text"]:SetText("Enable Campfire HUD & Tent Alerts Module")
    enableCb:SetScript("OnClick", function(self)
        if Campfire then
            local db = Campfire:GetDB()
            db.enabled = self:GetChecked()
            if db.enabled then
                Campfire:Enable()
            else
                Campfire:Disable()
            end
            p:OnRefresh()
        end
    end)
    p.enableCb = enableCb

    -- Status Box
    local statusBox = CreateFrame("Frame", nil, p, "BackdropTemplate")
    statusBox:SetPoint("TOPLEFT", enableCb, "BOTTOMLEFT", 0, -10)
    statusBox:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    statusBox:SetHeight(74)
    statusBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    statusBox:SetBackdropColor(0.04, 0.05, 0.07, 0.5)
    statusBox:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)

    local statusText = statusBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", statusBox, "TOPLEFT", 10, -8)
    statusText:SetPoint("BOTTOMRIGHT", statusBox, "BOTTOMRIGHT", -10, 8)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("TOP")
    p.statusText = statusText

    -- Control Buttons
    -- 1. Test Mode Toggle Button
    local testBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    testBtn:SetSize(180, 26)
    testBtn:SetPoint("TOPLEFT", statusBox, "BOTTOMLEFT", 0, -14)
    testBtn:SetText("Toggle HUD Test Mode")

    local testStatus = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    testStatus:SetPoint("LEFT", testBtn, "RIGHT", 12, 0)
    p.testStatus = testStatus

    testBtn:SetScript("OnClick", function()
        if Campfire and Campfire.ToggleTestMode then
            local active = Campfire:ToggleTestMode()
            p:OnRefresh()
            if active then
                print("|cff0cd29f[EFHelper]|r Campfire HUD test mode |cff00ff00enabled|r. Drag HUD to reposition.")
            elseif active == false then
                print("|cff0cd29f[EFHelper]|r Campfire HUD test mode |cffff4444disabled|r.")
            end
        end
    end)

    -- 2. Reset Position Button
    local resetBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    resetBtn:SetSize(180, 26)
    resetBtn:SetPoint("TOPLEFT", testBtn, "BOTTOMLEFT", 0, -8)
    resetBtn:SetText("Reset HUD Position")
    resetBtn:SetScript("OnClick", function()
        if Campfire and Campfire.ResetPosition then
            Campfire:ResetPosition()
            print("|cff0cd29f[EFHelper]|r Campfire HUD position reset to below Minimap.")
        end
    end)

    local resetDesc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    resetDesc:SetPoint("LEFT", resetBtn, "RIGHT", 12, 0)
    resetDesc:SetText("Returns HUD anchor to below the Minimap.")

    -- 3. Print Active Buffs Button
    local printBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    printBtn:SetSize(180, 26)
    printBtn:SetPoint("TOPLEFT", resetBtn, "BOTTOMLEFT", 0, -8)
    printBtn:SetText("Print Buffs to Chat")
    printBtn:SetScript("OnClick", function()
        if Campfire and Campfire.PrintBuffs then
            Campfire:PrintBuffs()
        end
    end)

    local printDesc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    printDesc:SetPoint("LEFT", printBtn, "RIGHT", 12, 0)
    printDesc:SetText("Prints detected campfire buffs and stats to chat.")

    -- 4. Tooltip Debug Dump Button
    local dumpBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    dumpBtn:SetSize(180, 26)
    dumpBtn:SetPoint("TOPLEFT", printBtn, "BOTTOMLEFT", 0, -8)
    dumpBtn:SetText("Tooltip Debug Scan")
    dumpBtn:SetScript("OnClick", function()
        if Campfire and Campfire.DumpDebug then
            Campfire:DumpDebug()
        end
    end)

    local dumpDesc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    dumpDesc:SetPoint("LEFT", dumpBtn, "RIGHT", 12, 0)
    dumpDesc:SetText("Scans GameTooltip and outputs raw text lines for debugging.")

    -- 5. Information Box
    local infoBox = CreateFrame("Frame", nil, p, "BackdropTemplate")
    infoBox:SetPoint("TOPLEFT", dumpBtn, "BOTTOMLEFT", 0, -14)
    infoBox:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -20, 14)
    infoBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    infoBox:SetBackdropColor(0.04, 0.05, 0.07, 0.5)
    infoBox:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)

    local infoText = infoBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", infoBox, "TOPLEFT", 10, -8)
    infoText:SetPoint("BOTTOMRIGHT", infoBox, "BOTTOMRIGHT", -10, 8)
    infoText:SetJustifyH("LEFT")
    infoText:SetJustifyV("TOP")
    infoText:SetText(
        "|cffffd100Campfire HUD & Resting Mechanics:|r\n" ..
        "• |cffffffffCamp Benefits|r: Detects active campfire aura to confirm you are accumulating Rested XP.\n" ..
        "• |cffffffffNearby Campfire|r: Identifies proximity to any player-placed campfire or cosy tent.\n" ..
        "• |cffffffffBoosted Rest|r: Monitors tent rest buff cooldowns to optimize your resting cycles.\n" ..
        "• |cffffffffHUD Position|r: Sits below the Minimap by default. Enable Test Mode to drag anywhere.\n" ..
        "• Configuration: Use the controls above to toggle the module, test position, or print detected buffs."
    )

    p.OnRefresh = function(self)
        if not Campfire then return end

        local db = Campfire:GetDB()
        local isEnabled = (db.enabled ~= false)

        if self.enableCb then
            self.enableCb:SetChecked(isEnabled)
        end

        if not isEnabled then
            self.statusText:SetText("|cffff4444Campfire & Tent Alerts Module is Disabled.|r\nCheck the box above to enable campfire HUD and proximity tent alerts.")
            self.testStatus:SetText("|cff888888[Disabled]|r")
            testBtn:Disable()
            resetBtn:Disable()
            printBtn:Disable()
            dumpBtn:Disable()
            return
        end

        testBtn:Enable()
        resetBtn:Enable()
        printBtn:Enable()
        dumpBtn:Enable()

        local hasCampBenefits = Campfire.FindPlayerCampfireAura and (Campfire:FindPlayerCampfireAura() ~= nil)
        local hasNearby = Campfire.PlayerHasAura and Campfire:PlayerHasAura(Campfire.CAMPFIRE_NEARBY_SPELL_ID, Campfire.CAMPFIRE_NEARBY_NAME)
        local hasBoosted = Campfire.PlayerHasAura and Campfire:PlayerHasAura(Campfire.BOOSTED_REST_SPELL_ID, Campfire.BOOSTED_REST_NAME)

        local lines = {
            string.format("|cffffd100Camp Benefits:|r %s", hasCampBenefits and "|cff00ff00Active (Resting)|r" or "|cff888888Inactive|r"),
            string.format("|cffffd100Nearby Campfire:|r %s", hasNearby and "|cff00ff00Detected|r" or "|cff888888None|r"),
            string.format("|cffffd100Boosted Rest (Tent Cooldown):|r %s", hasBoosted and "|cffff4444Active (Already rested)|r" or "|cff00ff00Available|r"),
        }
        self.statusText:SetText(table.concat(lines, "\n"))

        if Campfire.isTestMode then
            self.testStatus:SetText("|cff00ff00[Test Mode: Active]|r")
        else
            self.testStatus:SetText("|cff888888[Test Mode: Inactive]|r")
        end
    end

    return p
end

-- ----------------------------------------------------------------------------
-- Panel 3: Raid Subgroup Swapper
-- ----------------------------------------------------------------------------
local function CreateSwapperPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local Swapper = addonTable.Swapper or EFHelper.Swapper

    -- Title & Description
    local title = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -18)
    title:SetText("Raid Subgroup Swapper")

    local desc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("Executes combat raid swaps via a dummy character stationed outside the raid instance.")

    -- Dummy Character Name Input
    local dummyLabel = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    dummyLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
    dummyLabel:SetText("Dummy Character Name (Out-of-Raid Alt):")

    local dummyInput = CreateFrame("EditBox", "EFHelperConfigDummyInput", p, "InputBoxTemplate")
    dummyInput:SetSize(240, 24)
    dummyInput:SetPoint("TOPLEFT", dummyLabel, "BOTTOMLEFT", 4, -6)
    dummyInput:SetAutoFocus(false)
    dummyInput:SetMaxLetters(40)

    dummyInput:SetScript("OnEnterPressed", function(self)
        local text = self:GetText():match("^%s*(.-)%s*$") or ""
        if Swapper then
            local db = Swapper:GetDB()
            db.dummyName = text
        end
        self:ClearFocus()
        print("|cff00ff00[EFHelper Swapper]|r Dummy character saved: |cffffd100" .. text .. "|r")
    end)
    dummyInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
        p:OnRefresh()
    end)

    local targetDummyBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    targetDummyBtn:SetSize(100, 24)
    targetDummyBtn:SetPoint("LEFT", dummyInput, "RIGHT", 10, 0)
    targetDummyBtn:SetText("Get Target")
    targetDummyBtn:SetScript("OnClick", function()
        if UnitExists("target") then
            local tName = (Utils and Utils.GetUnitName and Utils.GetUnitName("target")) or "Target"
            if tName and tName ~= "" then
                dummyInput:SetText(tName)
                if Swapper then
                    local db = Swapper:GetDB()
                    db.dummyName = tName
                end
                dummyInput:ClearFocus()
                print("|cff00ff00[EFHelper Swapper]|r Dummy character set to: |cffffd100" .. tName .. "|r")
            end
        else
            print("|cffff4444[EFHelper]|r You do not have a target selected.")
        end
    end)

    -- Actions & Toggles
    local toggleHudBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    toggleHudBtn:SetSize(160, 26)
    toggleHudBtn:SetPoint("TOPLEFT", dummyInput, "BOTTOMLEFT", -4, -14)
    toggleHudBtn:SetText("Toggle Selection HUD")
    toggleHudBtn:SetScript("OnClick", function()
        if Swapper and Swapper.ToggleHUD then
            Swapper:ToggleHUD()
            p:OnRefresh()
        end
    end)

    local clearSlotsBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    clearSlotsBtn:SetSize(130, 26)
    clearSlotsBtn:SetPoint("LEFT", toggleHudBtn, "RIGHT", 10, 0)
    clearSlotsBtn:SetText("Clear Selections")
    clearSlotsBtn:SetScript("OnClick", function()
        if Swapper and Swapper.ClearSlots then
            Swapper:ClearSlots()
        end
    end)

    -- Info & Macro Guide Box
    local guideBox = CreateFrame("Frame", nil, p, "BackdropTemplate")
    guideBox:SetPoint("TOPLEFT", toggleHudBtn, "BOTTOMLEFT", 0, -14)
    guideBox:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -20, 14)
    guideBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    guideBox:SetBackdropColor(0.04, 0.05, 0.07, 0.5)
    guideBox:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)

    local guideText = guideBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    guideText:SetPoint("TOPLEFT", guideBox, "TOPLEFT", 10, -10)
    guideText:SetPoint("BOTTOMRIGHT", guideBox, "BOTTOMRIGHT", -10, 10)
    guideText:SetJustifyH("LEFT")
    guideText:SetJustifyV("TOP")
    guideText:SetText(
        "|cffffd100How to Use (Macro Setup):|r\n" ..
        "• |cff00ff00Macro 1:|r |cffffffff/efswap 1|r  (hover over Player 1 raid frame or target)\n" ..
        "• |cff00ff00Macro 2:|r |cffffffff/efswap 2|r  (hover over Player 2 raid frame or target)\n" ..
        "• |cff00ff00Macro 3:|r |cffffffff/efswap exec|r  (whispers the dummy to swap them)\n\n" ..
        "|cffffd100Dummy Character Requirements:|r\n" ..
        "• Must be inside the raid group, but |cffff4444parked outside the raid instance|r.\n" ..
        "• Must be promoted to |cff00ffffRaid Assistant|r or |cff00ffffRaid Leader|r.\n" ..
        "• Any member of the raid is authorized to request swaps."
    )

    p.OnRefresh = function(self)
        if Swapper then
            local db = Swapper:GetDB()
            dummyInput:SetText(db.dummyName or "")
        end
    end

    return p
end

-- ----------------------------------------------------------------------------
-- Panel 4: Solo & Duo Kill XP Predictor
-- ----------------------------------------------------------------------------
local function CreateXPPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local XP = addonTable.XP or EFHelper.XP

    -- Title & Description
    local title = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -18)
    title:SetText("Kill XP Predictor (Solo & Party 2–5)")

    local desc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("Calculates predicted kill experience for targeted hostile mobs based on classic ZD formulas, 2–5 player party scaling, and dungeon modifiers.")

    -- 1. Enable Checkbox
    local enableCb = CreateFrame("CheckButton", "EFHelperConfigXPEnable", p, "InterfaceOptionsCheckButtonTemplate")
    enableCb:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
    _G[enableCb:GetName() .. "Text"]:SetText("Enable Kill XP HUD")
    enableCb:SetScript("OnClick", function(self)
        if XP then
            local db = XP:GetDB()
            db.enabled = self:GetChecked()
            XP:UpdateActiveState()
            XP:UpdateHUD()
        end
    end)

    -- 2. Show XP Percentage Checkbox
    local pctCb = CreateFrame("CheckButton", "EFHelperConfigXPPct", p, "InterfaceOptionsCheckButtonTemplate")
    pctCb:SetPoint("TOPLEFT", enableCb, "BOTTOMLEFT", 0, -2)
    _G[pctCb:GetName() .. "Text"]:SetText("Show XP Percentage relative to level (e.g. 1.5%)")
    pctCb:SetScript("OnClick", function(self)
        if XP then
            local db = XP:GetDB()
            db.showPercentage = self:GetChecked()
            XP:UpdateHUD()
        end
    end)

    -- 3. Rested XP Potential Checkbox
    local restedCb = CreateFrame("CheckButton", "EFHelperConfigXPRested", p, "InterfaceOptionsCheckButtonTemplate")
    restedCb:SetPoint("TOPLEFT", pctCb, "BOTTOMLEFT", 0, -2)
    _G[restedCb:GetName() .. "Text"]:SetText("Show Rested XP Bonus in Display (+X Rested)")
    restedCb:SetScript("OnClick", function(self)
        if XP then
            local db = XP:GetDB()
            db.showRested = self:GetChecked()
            XP:UpdateHUD()
        end
    end)

    -- 4. Show Mob & Group Info Tags Checkbox
    local mobInfoCb = CreateFrame("CheckButton", "EFHelperConfigXPMobInfo", p, "InterfaceOptionsCheckButtonTemplate")
    mobInfoCb:SetPoint("TOPLEFT", restedCb, "BOTTOMLEFT", 0, -2)
    _G[mobInfoCb:GetName() .. "Text"]:SetText("Show Mob & Group Tags (e.g. [Party 2], [Dungeon 0.4x], [Elite])")
    mobInfoCb:SetScript("OnClick", function(self)
        if XP then
            local db = XP:GetDB()
            db.showMobInfo = self:GetChecked()
            XP:UpdateHUD()
        end
    end)

    -- 5. Show XP Efficiency & Expected HP Checkbox
    local effCb = CreateFrame("CheckButton", "EFHelperConfigXPEff", p, "InterfaceOptionsCheckButtonTemplate")
    effCb:SetPoint("TOPLEFT", mobInfoCb, "BOTTOMLEFT", 0, -2)
    _G[effCb:GetName() .. "Text"]:SetText("Show XP Efficiency & Expected Mob HP (2nd line: Eff & Actual / Expected HP)")
    effCb:SetScript("OnClick", function(self)
        if XP then
            local db = XP:GetDB()
            db.showEfficiency = self:GetChecked()
            XP:UpdateHUD()
        end
    end)

    -- 6. Show 0 XP Gray Warning Checkbox
    local zeroXpCb = CreateFrame("CheckButton", "EFHelperConfigXPZero", p, "InterfaceOptionsCheckButtonTemplate")
    zeroXpCb:SetPoint("TOPLEFT", effCb, "BOTTOMLEFT", 0, -2)
    _G[zeroXpCb:GetName() .. "Text"]:SetText("Show '0 XP (Trivial / Gray)' warning on trivial mobs")
    zeroXpCb:SetScript("OnClick", function(self)
        if XP then
            local db = XP:GetDB()
            db.showZeroXp = self:GetChecked()
            XP:UpdateHUD()
        end
    end)

    -- 7. Print Kill Feedback in Chat Checkbox
    local feedbackCb = CreateFrame("CheckButton", "EFHelperConfigXPFeedback", p, "InterfaceOptionsCheckButtonTemplate")
    feedbackCb:SetPoint("TOPLEFT", zeroXpCb, "BOTTOMLEFT", 0, -2)
    _G[feedbackCb:GetName() .. "Text"]:SetText("Print Kill Feedback in Chat (Diagnostic verification upon mob death)")
    feedbackCb:SetScript("OnClick", function(self)
        if XP then
            local db = XP:GetDB()
            db.showFeedback = self:GetChecked()
        end
    end)

    -- 8. Party Group XP Predictor Checkbox (2-5 Players)
    local groupCb = CreateFrame("CheckButton", "EFHelperConfigXPGroup", p, "InterfaceOptionsCheckButtonTemplate")
    groupCb:SetPoint("TOPLEFT", feedbackCb, "BOTTOMLEFT", 0, -2)
    _G[groupCb:GetName() .. "Text"]:SetText("|cffffd100[Party]|r Enable Party Group XP Predictor (2–5 Players)")
    groupCb:SetScript("OnClick", function(self)
        if XP then
            local db = XP:GetDB()
            db.groupPredictor = self:GetChecked()
            db.experimentalDuo = db.groupPredictor
            XP:UpdateActiveState()
            XP:UpdateHUD()
        end
    end)

    -- 9. Weighting Model Selector
    local modelBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    modelBtn:SetSize(230, 24)
    modelBtn:SetPoint("TOPLEFT", groupCb, "BOTTOMLEFT", 4, -6)
    modelBtn:SetText("Model: Standard (L+2)/(ΣL+2n)")
    p.modelBtn = modelBtn

    local modelDesc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    modelDesc:SetPoint("LEFT", modelBtn, "RIGHT", 10, 0)
    modelDesc:SetText("Click to toggle Laplace (L+1)/(ΣL+n)")

    modelBtn:SetScript("OnClick", function()
        if XP then
            local db = XP:GetDB()
            if db.formulaModel == "laplace" then
                db.formulaModel = "standard"
            else
                db.formulaModel = "laplace"
            end
            p:OnRefresh()
            XP:UpdateHUD()
            print("|cff00ccff[EFHelper XP]|r Switched formula model to: |cffffd100" .. db.formulaModel .. "|r")
        end
    end)

    -- 10. Test Logs Controls
    local clearLogsBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    clearLogsBtn:SetSize(140, 24)
    clearLogsBtn:SetPoint("TOPLEFT", modelBtn, "BOTTOMLEFT", 0, -6)
    clearLogsBtn:SetText("Clear Test Logs")

    local logsCountText = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    logsCountText:SetPoint("LEFT", clearLogsBtn, "RIGHT", 10, 0)
    p.logsCountText = logsCountText

    clearLogsBtn:SetScript("OnClick", function()
        if XP and XP.ClearLogs then
            XP:ClearLogs()
        elseif EFHelperDB and EFHelperDB.XP then
            EFHelperDB.XP.testLogs = {}
        end
        p:OnRefresh()
        print("|cff00ccff[EFHelper XP]|r Saved test logs cleared.")
    end)

    -- 11. Action Buttons (Preview Test Mode & Reset Position)
    local testBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    testBtn:SetSize(140, 24)
    testBtn:SetPoint("TOPLEFT", clearLogsBtn, "BOTTOMLEFT", 0, -8)
    testBtn:SetText("Preview Display")
    p.testBtn = testBtn
    testBtn:SetScript("OnClick", function()
        if XP then
            XP.isTestMode = not XP.isTestMode
            if XP.ApplyLockState then
                XP:ApplyLockState()
            end
            XP:UpdateHUD()
            testBtn:SetText(XP.isTestMode and "Stop Preview" or "Preview Display")
        end
    end)

    local resetPosBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    resetPosBtn:SetSize(140, 24)
    resetPosBtn:SetPoint("LEFT", testBtn, "RIGHT", 12, 0)
    resetPosBtn:SetText("Reset Position")
    resetPosBtn:SetScript("OnClick", function()
        if XP then
            local db = XP:GetDB()
            db.posX = 0
            db.posY = 130
            if XP.hud then
                XP.hud:ClearAllPoints()
                XP.hud:SetPoint("CENTER", UIParent, "CENTER", 0, 130)
            end
            print("|cff0cd29f[EFHelper XP]|r Display position reset to center.")
        end
    end)

    -- Information Box
    local infoBox = CreateFrame("Frame", nil, p, "BackdropTemplate")
    infoBox:SetPoint("TOPLEFT", testBtn, "BOTTOMLEFT", 0, -10)
    infoBox:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -20, 14)
    infoBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    infoBox:SetBackdropColor(0.04, 0.05, 0.07, 0.5)
    infoBox:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)

    local infoText = infoBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", infoBox, "TOPLEFT", 10, -8)
    infoText:SetPoint("BOTTOMRIGHT", infoBox, "BOTTOMRIGHT", -10, 8)
    infoText:SetJustifyH("LEFT")
    infoText:SetJustifyV("TOP")
    infoText:SetText(
        "|cffffd100Kill XP Predictor Notes:|r\n" ..
        "• Displays |cffffffffonly for hostile/attackable NPC targets|r in open world and 5-man dungeons.\n" ..
        "• |cffccccccEfficiency & Expected HP|r: Computes |cffffffff(XP / ExpectedHP) * 100|r and compares actual vs. expected HP.\n" ..
        "• |cffffd100Party Predictor (2–5 Players)|r: Calculates individual player base pools, share weighting, and group bonus.\n" ..
        "• |cffffa500Dungeon Modifier (0.4x)|r: Automatically applies the dungeon farming anti-nerf multiplier inside 5-man instances.\n" ..
        "• Left-click and drag the text while visible to reposition it anywhere on your screen.\n" ..
        "• Slash commands: |cff00ffff/efxp logs|r (view recorded kill stats), |cff00ffff/efxp clearlogs|r (clear recorded logs)."
    )

    p.OnRefresh = function(self)
        if XP then
            local db = XP:GetDB()
            enableCb:SetChecked(db.enabled ~= false)
            pctCb:SetChecked(db.showPercentage ~= false)
            restedCb:SetChecked(db.showRested ~= false)
            mobInfoCb:SetChecked(db.showMobInfo == true)
            effCb:SetChecked(db.showEfficiency ~= false)
            zeroXpCb:SetChecked(db.showZeroXp ~= false)
            feedbackCb:SetChecked(db.showFeedback ~= false)
            groupCb:SetChecked(db.groupPredictor ~= false)
            local isLaplace = (db.formulaModel == "laplace")
            modelBtn:SetText(isLaplace and "Model: Laplace (L+1)/(ΣL+n)" or "Model: Standard (L+2)/(ΣL+2n)")
            local logs = (XP and XP.GetLogs and XP:GetLogs()) or (EFHelperDB and EFHelperDB.XP and EFHelperDB.XP.testLogs) or {}
            local logCount = #logs
            logsCountText:SetText(string.format("Recorded Kills: |cffffd100%d|r (WTF)", logCount))
            testBtn:SetText(XP.isTestMode and "Stop Preview" or "Preview Display")
        end
    end

    return p
end

-- ----------------------------------------------------------------------------
-- Panel 5: Custom Experience Bar (EFHelper_XPBar)
-- ----------------------------------------------------------------------------
local function CreateXPBarPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local XPBar = addonTable.XPBar or EFHelper.XPBar

    -- Title & Description
    local title = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -18)
    title:SetText("Custom Experience Bar")

    local desc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("High-information experience bar with completed quest XP overlay, dual clocks, and pace forecasting.")

    -- 1. Enable Checkbox
    local enableCb = CreateFrame("CheckButton", "EFHelperConfigXPBarEnable", p, "InterfaceOptionsCheckButtonTemplate")
    enableCb:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
    _G[enableCb:GetName() .. "Text"]:SetText("Enable Custom Experience Bar")
    enableCb:SetScript("OnClick", function(self)
        if XPBar then
            local db = XPBar:GetDB()
            db.enabled = self:GetChecked()
            if db.enabled then
                XPBar:Enable()
            else
                XPBar:Disable()
            end
        end
    end)

    -- 2. Lock Position Checkbox
    local lockCb = CreateFrame("CheckButton", "EFHelperConfigXPBarLock", p, "InterfaceOptionsCheckButtonTemplate")
    lockCb:SetPoint("TOPLEFT", enableCb, "BOTTOMLEFT", 0, -4)
    _G[lockCb:GetName() .. "Text"]:SetText("Lock Position (prevents dragging)")
    lockCb:SetScript("OnClick", function(self)
        if XPBar then
            local db = XPBar:GetDB()
            db.locked = self:GetChecked()
        end
    end)

    -- 3. Hide Blizzard Bar Checkbox
    local blizzCb = CreateFrame("CheckButton", "EFHelperConfigXPBarBlizz", p, "InterfaceOptionsCheckButtonTemplate")
    blizzCb:SetPoint("TOPLEFT", lockCb, "BOTTOMLEFT", 0, -4)
    _G[blizzCb:GetName() .. "Text"]:SetText("Hide Default Blizzard XP Bar (StatusTrackingBarManager)")
    blizzCb:SetScript("OnClick", function(self)
        if XPBar then
            local db = XPBar:GetDB()
            db.hideBlizzardBar = self:GetChecked()
            XPBar:UpdateBlizzardBarVisibility()
        end
    end)

    -- 4. Rolling Window XP/Hour Checkbox
    local rollingCb = CreateFrame("CheckButton", "EFHelperConfigXPBarRolling", p, "InterfaceOptionsCheckButtonTemplate")
    rollingCb:SetPoint("TOPLEFT", blizzCb, "BOTTOMLEFT", 0, -4)
    _G[rollingCb:GetName() .. "Text"]:SetText("Use Rolling Window for XP/Hour (uncheck for Total Session)")
    rollingCb:SetScript("OnClick", function(self)
        if XPBar then
            local db = XPBar:GetDB()
            db.rateMode = self:GetChecked() and "rolling" or "total"
            if p.OnRefresh then p.OnRefresh(p) end
            XPBar:UpdateClockDisplay(true)
        end
    end)

    -- 5. Autopause Checkbox
    local autoPauseCb = CreateFrame("CheckButton", "EFHelperConfigXPBarAutoPause", p, "InterfaceOptionsCheckButtonTemplate")
    autoPauseCb:SetPoint("TOPLEFT", rollingCb, "BOTTOMLEFT", 0, -4)
    _G[autoPauseCb:GetName() .. "Text"]:SetText("Auto-pause XP rate after 10m idle (neglects 6 of 10 minutes)")
    autoPauseCb:SetScript("OnClick", function(self)
        if XPBar then
            local db = XPBar:GetDB()
            db.autoPauseEnabled = self:GetChecked()
        end
    end)

    -- 6. Construct Scale Slider (0.5x to 2.0x)
    local scaleSlider = CreateFrame("Slider", "EFHelperConfigXPBarScale", p, "OptionsSliderTemplate")
    scaleSlider:SetPoint("TOPLEFT", autoPauseCb, "BOTTOMLEFT", 10, -20)
    scaleSlider:SetSize(210, 16)
    scaleSlider:SetMinMaxValues(0.5, 2.0)
    scaleSlider:SetValueStep(0.05)
    _G[scaleSlider:GetName() .. "Low"]:SetText("0.5x")
    _G[scaleSlider:GetName() .. "High"]:SetText("2.0x")
    scaleSlider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value * 20 + 0.5) / 20
        if XPBar then
            local db = XPBar:GetDB()
            db.scale = val
            XPBar:ApplyLayout()
        end
        _G[self:GetName() .. "Text"]:SetText(string.format("Construct Scale: %.2fx", val))
    end)

    -- 7. Rolling Window Size Slider (1.0h to 6.0h)
    local windowSlider = CreateFrame("Slider", "EFHelperConfigXPBarWindow", p, "OptionsSliderTemplate")
    windowSlider:SetPoint("LEFT", scaleSlider, "RIGHT", 30, 0)
    windowSlider:SetSize(210, 16)
    windowSlider:SetMinMaxValues(1.0, 6.0)
    windowSlider:SetValueStep(0.5)
    _G[windowSlider:GetName() .. "Low"]:SetText("1.0h")
    _G[windowSlider:GetName() .. "High"]:SetText("6.0h")
    windowSlider:SetScript("OnValueChanged", function(self, value)
        local val = math.floor(value * 2 + 0.5) / 2
        if XPBar then
            local db = XPBar:GetDB()
            db.rollingWindowHours = val
            XPBar:UpdateClockDisplay(true)
        end
        _G[self:GetName() .. "Text"]:SetText(string.format("Rolling Window: %.1f hrs", val))
    end)

    -- 8. Action Buttons (Reset Session & Reset Position)
    local resetSessionBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    resetSessionBtn:SetSize(140, 24)
    resetSessionBtn:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", -10, -22)
    resetSessionBtn:SetText("Reset Session")
    resetSessionBtn:SetScript("OnClick", function()
        if XPBar and XPBar.ResetSession then
            XPBar:ResetSession()
        end
    end)

    local resetPosBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    resetPosBtn:SetSize(140, 24)
    resetPosBtn:SetPoint("LEFT", resetSessionBtn, "RIGHT", 12, 0)
    resetPosBtn:SetText("Reset Position")
    resetPosBtn:SetScript("OnClick", function()
        if XPBar then
            local db = XPBar:GetDB()
            db.pos = nil
            db.scale = 1.0
            if EFHelperCharDB then
                EFHelperCharDB.xpBarPoint = nil
            end
            XPBar:ApplyLayout()
            if scaleSlider then scaleSlider:SetValue(1.0) end
            print("|cff00ffff[EFHelper XPBar]|r Position and scale reset to default center.")
        end
    end)

    -- 9. Information Box
    local infoBox = CreateFrame("Frame", nil, p, "BackdropTemplate")
    infoBox:SetPoint("TOPLEFT", resetSessionBtn, "BOTTOMLEFT", 0, -12)
    infoBox:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -20, 14)
    infoBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    infoBox:SetBackdropColor(0.04, 0.05, 0.07, 0.5)
    infoBox:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)

    local infoText = infoBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", infoBox, "TOPLEFT", 10, -8)
    infoText:SetPoint("BOTTOMRIGHT", infoBox, "BOTTOMRIGHT", -10, 8)
    infoText:SetJustifyH("LEFT")
    infoText:SetJustifyV("TOP")
    infoText:SetText(
        "|cffffd100XP Bar Controls & Long-Session Pacing:|r\n" ..
        "• |cff8060ffPurple Section|r: Current character XP. |cffff9900Orange Section|r: Completed quests XP ready for turn-in.\n" ..
        "• |cffffffffShift + Left-Click bar|r: Toggle |cffffaa00Pause / Resume|r on session tracking.\n" ..
        "• |cffffffffRolling Window|r: Prevents metric inertia by averaging over the last N hours instead of whole session.\n" ..
        "• |cffffffffAutopause|r: Neglects 6 of 10 idle minutes if AFK, preserving long-session rate integrity.\n" ..
        "• |cffffffffShift-Right-Click bar|r: Toggle position Lock/Unlock. |cffffffffDrag|r to reposition when unlocked.\n" ..
        "• Slash commands: |cff00ffff/efh xpbar reset|r (reset session XP/hr), |cff00ffff/efh xpbar lock|r (lock/unlock position)."
    )

    p.OnRefresh = function(self)
        if XPBar then
            local db = XPBar:GetDB()
            enableCb:SetChecked(db.enabled ~= false)
            lockCb:SetChecked(db.locked == true)
            blizzCb:SetChecked(db.hideBlizzardBar == true)
            rollingCb:SetChecked(db.rateMode ~= "total")
            autoPauseCb:SetChecked(db.autoPauseEnabled ~= false)
            scaleSlider:SetValue(db.scale or 1.0)
            _G[scaleSlider:GetName() .. "Text"]:SetText(string.format("Construct Scale: %.2fx", db.scale or 1.0))
            local winVal = db.rollingWindowHours or 2.0
            windowSlider:SetValue(winVal)
            _G[windowSlider:GetName() .. "Text"]:SetText(string.format("Rolling Window: %.1f hrs", winVal))
            if db.rateMode == "total" then
                windowSlider:SetAlpha(0.4)
                windowSlider:EnableMouse(false)
            else
                windowSlider:SetAlpha(1.0)
                windowSlider:EnableMouse(true)
            end
        end
    end

    return p
end

-- ----------------------------------------------------------------------------
-- Panel 6: Trainer Spells & Level-Up Toast
-- ----------------------------------------------------------------------------
local function CreateTrainSpellsPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local TrainSpells = EFHelper.TrainSpells

    -- Section 1: Core Toggles
    local sec1 = CreateSectionTitle(p, "Trainer Spells & Toast Settings", -14)

    local enableCb = CreateFrame("CheckButton", "EFHelperConfigTrainSpellsEnable", p, "UICheckButtonTemplate")
    enableCb:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -34)
    _G[enableCb:GetName() .. "Text"]:SetText("Enable Train Spells Module")
    enableCb:SetScript("OnClick", function(cb)
        if TrainSpells then
            local db = TrainSpells:GetDB()
            db.enabled = cb:GetChecked()
            if db.enabled then TrainSpells:Enable() else TrainSpells:Disable() end
        end
    end)

    local spellbookTabCb = CreateFrame("CheckButton", "EFHelperConfigTrainSpellsTabEnable", p, "UICheckButtonTemplate")
    spellbookTabCb:SetPoint("TOPLEFT", enableCb, "BOTTOMLEFT", 0, -4)
    _G[spellbookTabCb:GetName() .. "Text"]:SetText("Show 'Trainable Spells' Button in Spellbook")
    spellbookTabCb:SetScript("OnClick", function(cb)
        if TrainSpells then
            local db = TrainSpells:GetDB()
            db.showSpellbookTab = cb:GetChecked()
            if TrainSpells.tabButton then
                if db.showSpellbookTab then TrainSpells.tabButton:Show() else TrainSpells.tabButton:Hide() end
            end
        end
    end)

    local toastCb = CreateFrame("CheckButton", "EFHelperConfigTrainSpellsToastEnable", p, "UICheckButtonTemplate")
    toastCb:SetPoint("TOPLEFT", spellbookTabCb, "BOTTOMLEFT", 0, -4)
    _G[toastCb:GetName() .. "Text"]:SetText("Show Level-Up Trainer Toast Notification")
    toastCb:SetScript("OnClick", function(cb)
        if TrainSpells then
            local db = TrainSpells:GetDB()
            db.showLevelUpToast = cb:GetChecked()
        end
    end)

    local soundCb = CreateFrame("CheckButton", "EFHelperConfigTrainSpellsSoundEnable", p, "UICheckButtonTemplate")
    soundCb:SetPoint("TOPLEFT", toastCb, "BOTTOMLEFT", 0, -4)
    _G[soundCb:GetName() .. "Text"]:SetText("Play Sound on Level-Up Toast")
    soundCb:SetScript("OnClick", function(cb)
        if TrainSpells then
            local db = TrainSpells:GetDB()
            db.sound = cb:GetChecked()
        end
    end)

    local autoTrainCb = CreateFrame("CheckButton", "EFHelperConfigTrainSpellsAutoTrainEnable", p, "UICheckButtonTemplate")
    autoTrainCb:SetPoint("TOPLEFT", soundCb, "BOTTOMLEFT", 0, -4)
    _G[autoTrainCb:GetName() .. "Text"]:SetText("Auto-Train Selected Spells at Class Trainer")
    autoTrainCb:SetScript("OnClick", function(cb)
        if TrainSpells then
            local db = TrainSpells:GetDB()
            db.autoTrain = cb:GetChecked()
        end
    end)

    -- Section 2: Toast Duration Slider
    local sec2 = CreateSectionTitle(p, "Toast Notification Pacing", autoTrainCb, -10)

    local durationSlider = CreateFrame("Slider", "EFHelperConfigToastDurationSlider", p, "OptionsSliderTemplate")
    durationSlider:SetPoint("TOPLEFT", sec2, "BOTTOMLEFT", 8, -16)
    durationSlider:SetMinMaxValues(2.0, 8.0)
    durationSlider:SetValueStep(0.5)
    durationSlider:SetObeyStepOnDrag(true)
    durationSlider:SetWidth(210)
    _G[durationSlider:GetName() .. "Low"]:SetText("2.0s")
    _G[durationSlider:GetName() .. "High"]:SetText("8.0s")
    durationSlider:SetScript("OnValueChanged", function(slider, value)
        if TrainSpells then
            local db = TrainSpells:GetDB()
            db.toastDuration = value
            _G[slider:GetName() .. "Text"]:SetText(string.format("Duration: %.1fs", value))
        end
    end)

    -- Section 3: Interactive Action Buttons
    local testToastBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    testToastBtn:SetSize(140, 24)
    testToastBtn:SetPoint("TOPLEFT", durationSlider, "BOTTOMLEFT", -8, -18)
    testToastBtn:SetText("Test Toast")
    testToastBtn:SetScript("OnClick", function()
        local mod = EFHelper.TrainSpells or addonTable.TrainSpells or TrainSpells
        if mod and mod.TestToast then
            mod:TestToast()
        else
            print("|cffff4444[EFHelper]|r Trainer module is not active.")
        end
    end)

    local openSpellbookBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    openSpellbookBtn:SetSize(150, 24)
    openSpellbookBtn:SetPoint("LEFT", testToastBtn, "RIGHT", 12, 0)
    openSpellbookBtn:SetText("Toggle Trainer View")
    openSpellbookBtn:SetScript("OnClick", function()
        local mod = EFHelper.TrainSpells or addonTable.TrainSpells or TrainSpells
        if mod and mod.ToggleSpellbookPanel then
            mod:ToggleSpellbookPanel()
        else
            print("|cffff4444[EFHelper]|r Trainer module is not active.")
        end
    end)

    -- Section 4: Information Box
    local infoBox = CreateFrame("Frame", nil, p, "BackdropTemplate")
    infoBox:SetPoint("TOPLEFT", testToastBtn, "BOTTOMLEFT", 0, -12)
    infoBox:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -20, 14)
    infoBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    infoBox:SetBackdropColor(0.04, 0.05, 0.07, 0.5)
    infoBox:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)

    local infoText = infoBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", infoBox, "TOPLEFT", 10, -8)
    infoText:SetPoint("BOTTOMRIGHT", infoBox, "BOTTOMRIGHT", -10, 8)
    infoText:SetJustifyH("LEFT")
    infoText:SetJustifyV("TOP")
    infoText:SetText(
        "|cffffd100Trainer Spells & Auto-Train Features:|r\n" ..
        "• |cffffffffAuto-Train|r: Automatically purchases all selected spells when talking to your class trainer.\n" ..
        "• |cffffffffTrainer Integration|r: Adds a 'Train Selected' button directly to class trainer windows.\n" ..
        "• |cffffffffTrade Safe|r: Strictly ignores tradeskill trainers (never auto-buys profession recipes).\n" ..
        "• |cffffffffSpellbook View|r: View all 1-60 trainable spells, ranks, and gold costs for your class.\n" ..
        "• |cffffffffLevel-Up Toast|r: Compact list of all newly unlocked spells (drag while Test Toast is active to move).\n" ..
        "• Configuration: Use the checkboxes above to toggle auto-training, spellbook tab, and toast alerts."
    )

    p.OnRefresh = function(self)
        if TrainSpells then
            local db = TrainSpells:GetDB()
            enableCb:SetChecked(db.enabled ~= false)
            spellbookTabCb:SetChecked(db.showSpellbookTab ~= false)
            toastCb:SetChecked(db.showLevelUpToast ~= false)
            soundCb:SetChecked(db.sound ~= false)
            autoTrainCb:SetChecked(db.autoTrain ~= false)
            local dur = db.toastDuration or 4.0
            durationSlider:SetValue(dur)
            _G[durationSlider:GetName() .. "Text"]:SetText(string.format("Duration: %.1fs", dur))
        end
    end

    return p
end

-- ----------------------------------------------------------------------------
-- Panel 7: Waypoint Bridge (RestedXP -> WaypointUI Translation Layer)
-- ----------------------------------------------------------------------------
local function CreateWaypointBridgePanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local WaypointBridge = addonTable.WaypointBridge or EFHelper.WaypointBridge

    -- Title & Description
    local title = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    title:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -18)
    title:SetText("RestedXP -> WaypointUI 3D Bridge")

    local desc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText("Dynamically translates your active RestedXP objective into a 3D world beacon in WaypointUI without modifying either addon.")

    -- 1. Enable Checkbox
    local enableCb = CreateFrame("CheckButton", "EFHelperConfigWaypointBridgeEnable", p, "InterfaceOptionsCheckButtonTemplate")
    enableCb:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -8)
    _G[enableCb:GetName() .. "Text"]:SetText("Enable RestedXP -> WaypointUI 3D Bridge")
    enableCb:SetScript("OnClick", function(self)
        if WaypointBridge then
            local db = WaypointBridge:GetDB()
            db.enabled = self:GetChecked() and true or false
            if db.enabled then
                WaypointBridge:Enable()
                WaypointBridge:SyncObjective(true)
            else
                WaypointBridge:ClearSyncedWaypoint()
                WaypointBridge:Disable()
            end
            p:OnRefresh()
        end
    end)
    p.enableCb = enableCb

    -- 2. Show Rich Step Context Summary Checkbox
    local summaryCb = CreateFrame("CheckButton", "EFHelperConfigWaypointBridgeSummary", p, "InterfaceOptionsCheckButtonTemplate")
    summaryCb:SetPoint("TOPLEFT", enableCb, "BOTTOMLEFT", 0, -2)
    _G[summaryCb:GetName() .. "Text"]:SetText("Show Step Context Summary (NPCs, Mobs, & Live Objective Progress)")
    summaryCb:SetScript("OnClick", function(self)
        if WaypointBridge then
            local db = WaypointBridge:GetDB()
            db.showStepSummary = self:GetChecked() and true or false
            WaypointBridge:SyncObjective(true)
            p:OnRefresh()
        end
    end)
    p.summaryCb = summaryCb

    -- 3. Alter Waypoint Icon & Color by Objective Type Checkbox
    local colorCb = CreateFrame("CheckButton", "EFHelperConfigWaypointBridgeColor", p, "InterfaceOptionsCheckButtonTemplate")
    colorCb:SetPoint("TOPLEFT", summaryCb, "BOTTOMLEFT", 0, -2)
    _G[colorCb:GetName() .. "Text"]:SetText("Alter Waypoint Icon & Color by Objective Type (Kill, Loot, Turn-In, Accept, etc.)")
    colorCb:SetScript("OnClick", function(self)
        if WaypointBridge then
            local db = WaypointBridge:GetDB()
            db.colorByType = self:GetChecked() and true or false
            WaypointBridge:SyncObjective(true)
            p:OnRefresh()
        end
    end)
    p.colorCb = colorCb

    -- 4. Live Status Box
    local statusBox = CreateFrame("Frame", nil, p, "BackdropTemplate")
    statusBox:SetPoint("TOPLEFT", colorCb, "BOTTOMLEFT", 0, -8)
    statusBox:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    statusBox:SetHeight(92)
    statusBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    statusBox:SetBackdropColor(0.04, 0.05, 0.07, 0.5)
    statusBox:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)

    local statusText = statusBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statusText:SetPoint("TOPLEFT", statusBox, "TOPLEFT", 10, -8)
    statusText:SetPoint("BOTTOMRIGHT", statusBox, "BOTTOMRIGHT", -10, 8)
    statusText:SetJustifyH("LEFT")
    statusText:SetJustifyV("TOP")
    p.statusText = statusText

    -- 5. Action Buttons (Force Re-Sync & Clear Bridge Waypoint)
    local syncBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    syncBtn:SetSize(180, 26)
    syncBtn:SetPoint("TOPLEFT", statusBox, "BOTTOMLEFT", 0, -10)
    syncBtn:SetText("Force Re-Sync Waypoint")
    syncBtn:SetScript("OnClick", function()
        if WaypointBridge and WaypointBridge.SyncObjective then
            WaypointBridge:SyncObjective(true)
            p:OnRefresh()
        end
    end)

    local clearBtn = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    clearBtn:SetSize(180, 26)
    clearBtn:SetPoint("LEFT", syncBtn, "RIGHT", 12, 0)
    clearBtn:SetText("Clear Bridge Waypoint")
    clearBtn:SetScript("OnClick", function()
        if WaypointBridge and WaypointBridge.ClearSyncedWaypoint then
            WaypointBridge:ClearSyncedWaypoint()
            p:OnRefresh()
        end
    end)

    -- 6. Information Box
    local infoBox = CreateFrame("Frame", nil, p, "BackdropTemplate")
    infoBox:SetPoint("TOPLEFT", syncBtn, "BOTTOMLEFT", 0, -10)
    infoBox:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -20, 14)
    infoBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    infoBox:SetBackdropColor(0.04, 0.05, 0.07, 0.5)
    infoBox:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)

    local infoText = infoBox:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", infoBox, "TOPLEFT", 10, -8)
    infoText:SetPoint("BOTTOMRIGHT", infoBox, "BOTTOMRIGHT", -10, 8)
    infoText:SetJustifyH("LEFT")
    infoText:SetJustifyV("TOP")
    infoText:SetText(
        "|cffffd100Waypoint Bridge Behavior & Design:|r\n" ..
        "• |cffffffffStep Context Summary|r: Extracts associated NPCs (|cff00ffff.target|r), Mobs (|cff00ffff.mob|r), and live quest progress (|cff00ffff.complete|r / |cff00ffff.collect|r) and updates counts in real time.\n" ..
        "• |cffffffffObjective Visuals|r: Customizes the 3D beacon's icon & beam color by action (Kill, Loot, Turn-In, Accept, Train, Flight).\n" ..
        "• |cffffffffSpawn Loop Protection|r: Locks |cff00ffff#loop|r / |cff00ffff.loop|r steps to their 1st coordinate while still updating live kill/loot counters.\n" ..
        "• |cffffffffSuperTrack Guard|r: Prevents RXP's quest tracker from overriding WaypointUI's custom navigation text."
    )

    p.OnRefresh = function(self)
        if not WaypointBridge then return end
        local db = WaypointBridge:GetDB()
        local isEnabled = (db.enabled ~= false)
        enableCb:SetChecked(isEnabled)
        summaryCb:SetChecked(db.showStepSummary ~= false)
        colorCb:SetChecked(db.colorByType ~= false)

        local info = WaypointBridge.GetStatusInfo and WaypointBridge:GetStatusInfo() or {}
        local rxpStr = info.rxpLoaded and "|cff00ff00Loaded|r" or "|cffff4444Not Loaded|r"
        local wuiStr = info.wuiLoaded and "|cff00ff00Loaded|r" or "|cffff4444Not Loaded|r"

        if not isEnabled then
            statusText:SetText(string.format(
                "|cffffd100AddOn Status:|r RXPGuides: %s  |  WaypointUI: %s\n" ..
                "|cffff4444Bridge Status: Disabled|r",
                rxpStr, wuiStr
            ))
            syncBtn:Disable()
            clearBtn:Disable()
            return
        end

        syncBtn:Enable()
        clearBtn:Enable()

        local activeLine
        if info.lastMapID and info.lastX and info.lastY then
            local loopTag = info.isLoopLocked and " |cff00ffff[Loop Locked: 1st Point]|r" or ""
            local catTag = info.lastCategory and (" |cff00ff99[" .. info.lastCategory .. "]|r") or ""
            local flatTitle = (info.lastTitle or "Objective"):gsub("\n", "  |cff888888•|r  ")
            activeLine = string.format(
                "|cffffd100Objective:%s|r |cffffffff%s|r\n" ..
                "|cffffd100Coordinates:|r Map |cff00ffff%d|r — |cff00ff00(%.1f, %.1f)|r%s",
                catTag,
                flatTitle,
                info.lastMapID,
                info.lastX,
                info.lastY,
                loopTag
            )
        else
            activeLine = "|cffffd100Synced Objective:|r |cff888888None (Waiting for active RXP waypoint)|r"
        end

        statusText:SetText(string.format(
            "|cffffd100AddOn Status:|r RXPGuides: %s  |  WaypointUI: %s\n%s",
            rxpStr, wuiStr, activeLine
        ))
    end

    return p
end

-- ----------------------------------------------------------------------------
-- Unified Window Builder
-- ----------------------------------------------------------------------------
function Config:GetOrCreateWindow()
    if configFrame then return configFrame end

    -- Main Settings Window (Expanded to 740x500 for modern dual-pane layout)
    local f = CreateFrame("Frame", "EFHelperConfigFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(740, 500)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Title
    f.TitleText:SetText("EFHelper - Settings & Tools")

    -- Hide Blizzard's default inset if present to allow custom dual-pane sidebar layout
    if f.InsetBg then f.InsetBg:Hide() end
    if f.Inset then f.Inset:Hide() end

    -- Left Sidebar Frame
    local sidebar = CreateFrame("Frame", nil, f, "BackdropTemplate")
    sidebar:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -30)
    sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 12)
    sidebar:SetWidth(172)
    sidebar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    sidebar:SetBackdropColor(0.04, 0.045, 0.06, 0.85)
    sidebar:SetBackdropBorderColor(0.2, 0.18, 0.15, 0.75)

    -- Sidebar Header
    local sidebarTitle = sidebar:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sidebarTitle:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -10)
    sidebarTitle:SetText("|cffffd100MODULES|r")

    -- Sidebar Category Buttons
    for i, data in ipairs(MODULE_TABS) do
        local tabBtn = CreateSidebarButton(sidebar, i, data)
        tabBtn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, -28 - (i - 1) * 50)
        table.insert(tabButtons, tabBtn)
    end

    -- Sidebar Version Footer
    local versionText = sidebar:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    versionText:SetPoint("BOTTOM", sidebar, "BOTTOM", 0, 10)
    versionText:SetText("|cff666666EFHelper v" .. (EFHelper.version or "1.0") .. "|r")

    -- Right Inset Content Area
    local contentArea = CreateFrame("Frame", nil, f, "BackdropTemplate")
    contentArea:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, 0)
    contentArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 12)
    contentArea:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    contentArea:SetBackdropColor(0.03, 0.035, 0.045, 0.75)
    contentArea:SetBackdropBorderColor(0.2, 0.18, 0.15, 0.75)

    -- Build sub-panels
    panels[1] = CreateTaggingPanel(contentArea)
    panels[2] = CreateCampfirePanel(contentArea)
    panels[3] = CreateSwapperPanel(contentArea)
    panels[4] = CreateXPPanel(contentArea)
    panels[5] = CreateXPBarPanel(contentArea)
    panels[6] = CreateTrainSpellsPanel(contentArea)
    panels[7] = CreateWaypointBridgePanel(contentArea)

    -- Default to Tab 1
    SelectTab(1)

    f:SetScript("OnShow", function()
        for i = 1, #panels do
            if panels[i] and panels[i]:IsShown() and panels[i].OnRefresh then
                panels[i]:OnRefresh()
            end
        end
    end)

    configFrame = f
    Config.frame = f
    return f
end

function EFHelper:ToggleConfig(tabIndex)
    local win = Config:GetOrCreateWindow()
    if win:IsShown() and not tabIndex then
        win:Hide()
    else
        if tabIndex and panels[tabIndex] then
            SelectTab(tabIndex)
        end
        win:Show()
    end
end
