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
    {
        name = "Party RXP Sync",
        subtext = "Group steps & quests",
        icon = "Interface\\Icons\\Achievement_GuildPerk_Everyones A Hero",
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

function Config:RefreshActivePanel()
    if not configFrame or not configFrame:IsShown() then return end
    for _, panel in ipairs(panels) do
        if panel:IsShown() and panel.OnRefresh then
            panel:OnRefresh()
        end
    end
end

-- Sidebar Button Component
local function CreateSidebarButton(parent, index, data)
    local btn = CreateFrame("Button", "EFHelperSidebarTab" .. index, parent, "BackdropTemplate")
    btn:SetSize(164, 44)
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

-- Helper to create standardized checkboxes with automatic DB binding, auto-stacking & OnRefresh sync
local _cbSeq = 0
local function AddCheckbox(parent, opts)
    local template = opts.template or "InterfaceOptionsCheckButtonTemplate"
    _cbSeq = _cbSeq + 1
    local name = opts.name or (parent:GetName() and (parent:GetName() .. "_" .. (opts.key or "Cb"))) or ("EFHelper_AutoCb_" .. _cbSeq)
    local cb = CreateFrame("CheckButton", name, parent, template)

    local rel = opts.relativeTo or parent._lastCb or parent
    local isFontString = rel and rel.IsObjectType and rel:IsObjectType("FontString")
    local defaultY = (rel == parent or isFontString) and -8 or (parent._cbSpacing or -2)
    local relPoint = (rel == parent) and (opts.relPoint or "TOPLEFT") or (opts.relPoint or "BOTTOMLEFT")
    cb:SetPoint("TOPLEFT", rel, relPoint, opts.x or 0, opts.y or defaultY)
    parent._lastCb = cb

    local txt = cb.Text or (cb:GetName() and _G[cb:GetName() .. "Text"])
    if txt then txt:SetText(opts.label or "") end

    local getDB = opts.getDB or parent._getDB
    local function GetCheckedValue()
        local db = getDB and getDB()
        if opts.get then return opts.get(db) and true or false end
        if not db or not opts.key then return false end
        if opts.default == false then return db[opts.key] == true end
        return db[opts.key] ~= false
    end

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked() and true or false
        local db = getDB and getDB()
        if opts.set then
            opts.set(checked, db, self)
        elseif db and opts.key then
            db[opts.key] = checked
        end
        if opts.onChange then opts.onChange(checked, db, self) end
        if opts.onClick then opts.onClick(self, checked, db) end
    end)

    parent._checkboxes = parent._checkboxes or {}
    table.insert(parent._checkboxes, {
        cb = cb,
        refresh = function() cb:SetChecked(GetCheckedValue()) end,
    })

    return cb
end

local function RefreshCheckboxes(panel)
    if not panel then return end
    if panel._checkboxes then
        for _, entry in ipairs(panel._checkboxes) do
            entry.refresh()
        end
    end
    if panel._sliders then
        for _, entry in ipairs(panel._sliders) do
            entry.refresh()
        end
    end
end

-- Helper to create styled panel headers (title + description)
local function CreatePanelHeader(parent, titleText, descText)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    title:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, -18)
    title:SetText(titleText)

    local desc = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    desc:SetJustifyH("LEFT")
    desc:SetText(descText)

    return desc
end

-- Helper to create standardized action buttons
local function AddButton(parent, opts)
    local btn = CreateFrame("Button", opts.name, parent, opts.template or "UIPanelButtonTemplate")
    btn:SetSize(opts.width or 140, opts.height or 24)
    local rel = opts.relativeTo or parent
    local point = opts.point or "TOPLEFT"
    local relPoint = opts.relPoint or (opts.point == "LEFT" and "RIGHT" or ((rel == parent) and "TOPLEFT" or "BOTTOMLEFT"))
    btn:SetPoint(point, rel, relPoint, opts.x or 0, opts.y or 0)
    if opts.text then btn:SetText(opts.text) end
    if opts.onClick then btn:SetScript("OnClick", opts.onClick) end
    return btn
end

-- Helper to create standardized sliders with automatic DB binding & OnRefresh sync
local function AddSlider(parent, opts)
    local slider = CreateFrame("Slider", opts.name, parent, opts.template or "OptionsSliderTemplate")
    slider:SetSize(opts.width or 210, opts.height or 16)
    local rel = opts.relativeTo or parent
    local point = opts.point or "TOPLEFT"
    local relPoint = opts.relPoint or (opts.point == "LEFT" and "RIGHT" or ((rel == parent) and "TOPLEFT" or "BOTTOMLEFT"))
    slider:SetPoint(point, rel, relPoint, opts.x or 0, opts.y or 0)
    slider:SetMinMaxValues(opts.min or 0, opts.max or 100)
    slider:SetValueStep(opts.step or 1)
    if opts.obeyStep ~= false then slider:SetObeyStepOnDrag(true) end

    local name = slider:GetName()
    if name then
        if opts.lowText and _G[name .. "Low"] then _G[name .. "Low"]:SetText(opts.lowText) end
        if opts.highText and _G[name .. "High"] then _G[name .. "High"]:SetText(opts.highText) end
    end

    local getDB = opts.getDB or parent._getDB
    local function UpdateText(val)
        if name and _G[name .. "Text"] and opts.format then
            _G[name .. "Text"]:SetText(string.format(opts.format, val))
        end
    end

    slider:SetScript("OnValueChanged", function(self, value)
        local step = opts.step or 1
        local val = math.floor(value / step + 0.5) * step
        local db = getDB and getDB()
        if opts.key and db then db[opts.key] = val end
        UpdateText(val)
        if opts.onValueChanged then opts.onValueChanged(val, db, self) end
    end)

    parent._sliders = parent._sliders or {}
    table.insert(parent._sliders, {
        slider = slider,
        refresh = function()
            local db = getDB and getDB()
            local val = (db and opts.key and db[opts.key]) or opts.default or opts.min or 0
            slider:SetValue(val)
            UpdateText(val)
        end,
    })

    return slider
end

-- Helper to create styled info/guide/status backdrop boxes
local function AddInfoBox(parent, textOrOpts, relativeTo, yOffset)
    local opts = type(textOrOpts) == "table" and textOrOpts or { text = textOrOpts, relativeTo = relativeTo, y = yOffset }
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local rel = opts.relativeTo or parent._lastCb or parent
    local relPoint = (rel == parent) and "TOPLEFT" or "BOTTOMLEFT"
    box:SetPoint("TOPLEFT", rel, relPoint, opts.x or 0, opts.y or -10)
    if opts.height then
        box:SetHeight(opts.height)
        box:SetPoint("RIGHT", parent, "RIGHT", -20, 0)
    else
        box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -20, opts.bottom or 14)
    end
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    box:SetBackdropColor(0.04, 0.05, 0.07, 0.5)
    box:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.6)

    local infoText = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    infoText:SetPoint("TOPLEFT", box, "TOPLEFT", 10, -8)
    infoText:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -10, 8)
    infoText:SetJustifyH("LEFT")
    infoText:SetJustifyV("TOP")
    if opts.text then infoText:SetText(opts.text) end

    box.text = infoText
    return box
end

-- ----------------------------------------------------------------------------
-- Panel 1: Tagging & Macros
-- ----------------------------------------------------------------------------
local function CreateTaggingPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    -- Title & Description
    local desc = CreatePanelHeader(p, "Targeting & Macro Hub", "Creates fast pull/tagging macros with automatic target acquisition and skull ping.")

    -- 1. Mob Name Section
    local mobLabel = p:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    mobLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
    mobLabel:SetText("Target Mob Name:")

    local mobInput = CreateFrame("EditBox", "EFHelperConfigMobInput", p, "InputBoxTemplate")
    mobInput:SetSize(240, 24)
    mobInput:SetPoint("TOPLEFT", mobLabel, "BOTTOMLEFT", 4, -6)
    mobInput:SetAutoFocus(false)
    mobInput:SetMaxLetters(50)

    local targetBtn = AddButton(p, {
        width = 100, height = 24,
        point = "LEFT", relativeTo = mobInput, x = 10,
        text = "Get Target",
        onClick = function()
            if UnitExists("target") then
                local targetName = (Utils and Utils.GetUnitName and Utils.GetUnitName("target")) or "Target"
                if targetName and targetName ~= "" then
                    mobInput:SetText(targetName)
                    mobInput:ClearFocus()
                end
            else
                print("|cffff4444[EFHelper]|r You do not have a target selected.")
            end
        end,
    })

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
            if EFHelper.db then
                if EFHelper.db.profile then EFHelper.db.profile.lastSpell = val end
                if EFHelper.db.char then EFHelper.db.char.lastSpell = val end
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
    local createMacroBtn = AddButton(p, {
        width = 180, height = 28,
        relativeTo = macroLabel, x = 4, y = -38,
        text = "Create / Update Macro",
        onClick = function()
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
                if EFHelper.db then
                    if EFHelper.db.profile then
                        EFHelper.db.profile.lastMobName = mobName
                        EFHelper.db.profile.lastSpell = currentSpell
                    end
                    if EFHelper.db.char then
                        EFHelper.db.char.lastMobName = mobName
                        EFHelper.db.char.lastSpell = currentSpell
                    end
                end
                feedback:SetText(string.format("|cff00ff00Macro '%s' saved! Drag from /m to bar.|r", selectedMacroName or "EFTag"))
            else
                feedback:SetText("|cffff4444Failed to update macro. Check macro limit.|r")
            end
        end,
    })

    local feedback = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    feedback:SetPoint("LEFT", createMacroBtn, "RIGHT", 12, 0)
    feedback:SetPoint("RIGHT", p, "RIGHT", -20, 0)
    feedback:SetJustifyH("LEFT")
    feedback:SetText("")

    -- Hint text
    local hint = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", createMacroBtn, "BOTTOMLEFT", 0, -8)
    hint:SetText("Saves to Character Macros (/m). Drag the macro to your action bar.")

    -- 4b. Lightweight FFA Auto-Loot Toggle Setting
    p._getDB = function() return EFHelper.db and EFHelper.db.profile end
    local ffaCb = AddCheckbox(p, {
        name = "EFHelperConfigFFAAutoLoot",
        label = "Show Auto-Loot Toggle Button while in Free-For-All Group",
        relativeTo = hint,
        x = -2,
        y = -6,
        key = "ffaAutoLootEnabled",
        onChange = function()
            if EFHelper.UpdateFFAAutoLootWidget then EFHelper:UpdateFFAAutoLootWidget() end
        end,
    })
    p.ffaCb = ffaCb

    -- 4c. Silent RXP Button Target Updates
    local silentCb = AddCheckbox(p, {
        name = "EFHelperConfigSilentTagClicks",
        label = "Silent Macro Updates on RXP Target Button Clicks",
        key = "silentTagClicks",
    })
    p.silentCb = silentCb

    -- 5. Information Box
    AddInfoBox(p, {
        text = "|cffffd100Tagging & Macro Hub Features:|r\n" ..
            "• |cffffffffInstant Tagging|r: Generates a macro that instantly acquires target and casts your selected spell.\n" ..
            "• |cffffffffRaid Ping|r: Automatically drops a skull raid target marker on the target to alert party members.\n" ..
            "• |cffffffffFFA Auto-Loot Toggle|r: Displays a compact floating toggle when party loot is set to Free-For-All.\n" ..
            "• |cffffffffTarget Mirror|r: Press 'Get Target' while targeting any mob to populate the name automatically.\n" ..
            "• Slash commands: |cff00ffff/efh|r (config) or drag the macro from |cff00ffff/m|r directly to your action bar.",
        relativeTo = silentCb,
        x = 2,
        y = -6,
    })

    p.mobInput = mobInput
    p.spellDropdown = spellDropdown
    p.feedback = feedback
    p.hint = hint

    p.OnRefresh = function(self)
        RefreshCheckboxes(self)
        local lastMob = (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.lastMobName) or (EFHelper.db and EFHelper.db.char and EFHelper.db.char.lastMobName)
        if lastMob and self.mobInput:GetText() == "" then
            self.mobInput:SetText(lastMob)
        end
        local lastSpell = (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.lastSpell) or EFHelper.selectedSpell
        if lastSpell then
            self.spellDropdown:SetText(lastSpell)
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
    local desc = CreatePanelHeader(p, "Campfire HUD & Floating Alerts", "Shows active campfire benefits in equivalent WoW buffs below the Minimap, and alerts when near a tent.")

    -- 1. Enable Checkbox
    p._getDB = function() return Campfire and Campfire:GetDB() end
    local enableCb = AddCheckbox(p, {
        name = "EFHelperConfigCampfireEnable",
        label = "Enable Campfire HUD & Tent Alerts Module",
        relativeTo = desc,
        key = "enabled",
        onChange = function(checked)
            if Campfire then
                if checked then Campfire:Enable() else Campfire:Disable() end
                p:OnRefresh()
            end
        end,
    })
    p.enableCb = enableCb

    -- Status Box
    local statusBox = AddInfoBox(p, { relativeTo = enableCb, y = -10, height = 74 })
    p.statusText = statusBox.text

    -- Control Buttons
    -- 1. Test Mode Toggle Button
    local testBtn = AddButton(p, {
        width = 180, height = 26,
        relativeTo = statusBox, y = -14,
        text = "Toggle HUD Test Mode",
        onClick = function()
            if Campfire and Campfire.ToggleTestMode then
                local active = Campfire:ToggleTestMode()
                p:OnRefresh()
                if active then
                    print("|cff0cd29f[EFHelper]|r Campfire HUD test mode |cff00ff00enabled|r. Drag HUD to reposition.")
                elseif active == false then
                    print("|cff0cd29f[EFHelper]|r Campfire HUD test mode |cffff4444disabled|r.")
                end
            end
        end,
    })

    local testStatus = p:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    testStatus:SetPoint("LEFT", testBtn, "RIGHT", 12, 0)
    p.testStatus = testStatus

    -- 2. Reset Position Button
    local resetBtn = AddButton(p, {
        width = 180, height = 26,
        relativeTo = testBtn, y = -8,
        text = "Reset HUD Position",
        onClick = function()
            if Campfire and Campfire.ResetPosition then
                Campfire:ResetPosition()
                print("|cff0cd29f[EFHelper]|r Campfire HUD position reset to below Minimap.")
            end
        end,
    })

    local resetDesc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    resetDesc:SetPoint("LEFT", resetBtn, "RIGHT", 12, 0)
    resetDesc:SetText("Returns HUD anchor to below the Minimap.")

    -- 3. Print Active Buffs Button
    local printBtn = AddButton(p, {
        width = 180, height = 26,
        relativeTo = resetBtn, y = -8,
        text = "Print Buffs to Chat",
        onClick = function()
            if Campfire and Campfire.PrintBuffs then
                Campfire:PrintBuffs()
            end
        end,
    })

    local printDesc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    printDesc:SetPoint("LEFT", printBtn, "RIGHT", 12, 0)
    printDesc:SetText("Prints detected campfire buffs and stats to chat.")

    -- 4. Tooltip Debug Dump Button
    local dumpBtn = AddButton(p, {
        width = 180, height = 26,
        relativeTo = printBtn, y = -8,
        text = "Tooltip Debug Scan",
        onClick = function()
            if Campfire and Campfire.DumpDebug then
                Campfire:DumpDebug()
            end
        end,
    })

    local dumpDesc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    dumpDesc:SetPoint("LEFT", dumpBtn, "RIGHT", 12, 0)
    dumpDesc:SetText("Scans GameTooltip and outputs raw text lines for debugging.")

    -- 5. Information Box
    AddInfoBox(p,
        "|cffffd100Campfire HUD & Resting Mechanics:|r\n" ..
        "• |cffffffffCamp Benefits|r: Detects active campfire aura to confirm you are accumulating Rested XP.\n" ..
        "• |cffffffffNearby Campfire|r: Identifies proximity to any player-placed campfire or cosy tent.\n" ..
        "• |cffffffffBoosted Rest|r: Monitors tent rest buff cooldowns to optimize your resting cycles.\n" ..
        "• |cffffffffHUD Position|r: Sits below the Minimap by default. Enable Test Mode to drag anywhere.\n" ..
        "• Configuration: Use the controls above to toggle the module, test position, or print detected buffs.",
        dumpBtn, -14
    )

    p.OnRefresh = function(self)
        if not Campfire then return end

        local db = Campfire:GetDB()
        local isEnabled = (db.enabled ~= false)
        RefreshCheckboxes(self)

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
    local desc = CreatePanelHeader(p, "Raid Subgroup Swapper", "Executes combat raid swaps via a dummy character stationed outside the raid instance.")

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

    local targetDummyBtn = AddButton(p, {
        width = 100, height = 24,
        point = "LEFT", relativeTo = dummyInput, x = 10,
        text = "Get Target",
        onClick = function()
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
        end,
    })

    -- Actions & Toggles
    local toggleHudBtn = AddButton(p, {
        width = 160, height = 26,
        relativeTo = dummyInput, x = -4, y = -14,
        text = "Toggle Selection HUD",
        onClick = function()
            if Swapper and Swapper.ToggleHUD then
                Swapper:ToggleHUD()
                p:OnRefresh()
            end
        end,
    })

    local clearSlotsBtn = AddButton(p, {
        width = 130, height = 26,
        point = "LEFT", relativeTo = toggleHudBtn, x = 10,
        text = "Clear Selections",
        onClick = function()
            if Swapper and Swapper.ClearSlots then
                Swapper:ClearSlots()
            end
        end,
    })

    -- Info & Macro Guide Box
    AddInfoBox(p,
        "|cffffd100How to Use (Macro Setup):|r\n" ..
        "• |cff00ff00Macro 1:|r |cffffffff/efswap 1|r  (hover over Player 1 raid frame or target)\n" ..
        "• |cff00ff00Macro 2:|r |cffffffff/efswap 2|r  (hover over Player 2 raid frame or target)\n" ..
        "• |cff00ff00Macro 3:|r |cffffffff/efswap exec|r  (whispers the dummy to swap them)\n\n" ..
        "|cffffd100Dummy Character Requirements:|r\n" ..
        "• Must be inside the raid group, but |cffff4444parked outside the raid instance|r.\n" ..
        "• Must be promoted to |cff00ffffRaid Assistant|r or |cff00ffffRaid Leader|r.\n" ..
        "• Any member of the raid is authorized to request swaps.",
        toggleHudBtn, -14
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
    local desc = CreatePanelHeader(p, "Kill XP Predictor (Solo & Party 2–5)", "Calculates predicted kill experience for targeted hostile mobs based on classic ZD formulas, 2–5 player party scaling, and dungeon modifiers.")

    p._getDB = function() return XP and XP:GetDB() end

    -- 1-8. Checkboxes (Auto-stacked)
    local enableCb = AddCheckbox(p, {
        name = "EFHelperConfigXPEnable",
        label = "Enable Kill XP HUD",
        relativeTo = desc,
        key = "enabled",
        onClick = function()
            if XP then XP:UpdateActiveState(); XP:UpdateHUD() end
        end,
    })
    AddCheckbox(p, {
        name = "EFHelperConfigXPPct",
        label = "Show XP Percentage relative to level (e.g. 1.5%)",
        key = "showPercentage",
        onClick = function() if XP then XP:UpdateHUD() end end,
    })
    AddCheckbox(p, {
        name = "EFHelperConfigXPRested",
        label = "Show Rested XP Bonus in Display (+X Rested)",
        key = "showRested",
        onClick = function() if XP then XP:UpdateHUD() end end,
    })
    AddCheckbox(p, {
        name = "EFHelperConfigXPMobInfo",
        label = "Show Mob & Group Tags (e.g. [Party 2], [Dungeon 0.4x], [Elite])",
        key = "showMobInfo",
        default = false,
        onClick = function() if XP then XP:UpdateHUD() end end,
    })
    AddCheckbox(p, {
        name = "EFHelperConfigXPEff",
        label = "Show XP Efficiency & Expected Mob HP (2nd line: Eff & Actual / Expected HP)",
        key = "showEfficiency",
        onClick = function() if XP then XP:UpdateHUD() end end,
    })
    AddCheckbox(p, {
        name = "EFHelperConfigXPZero",
        label = "Show '0 XP (Trivial / Gray)' warning on trivial mobs",
        key = "showZeroXp",
        onClick = function() if XP then XP:UpdateHUD() end end,
    })
    AddCheckbox(p, {
        name = "EFHelperConfigXPFeedback",
        label = "Print Kill Feedback in Chat (Diagnostic verification upon mob death)",
        key = "showFeedback",
    })
    local groupCb = AddCheckbox(p, {
        name = "EFHelperConfigXPGroup",
        label = "|cffffd100[Party]|r Enable Party Group XP Predictor (2–5 Players)",
        key = "groupPredictor",
        onClick = function(_, checked, db)
            if db then db.experimentalDuo = checked end
            if XP then XP:UpdateActiveState(); XP:UpdateHUD() end
        end,
    })

    -- 9. Weighting Model Selector
    local modelBtn = AddButton(p, {
        width = 230, height = 24,
        relativeTo = groupCb, x = 4, y = -6,
        text = "Model: Standard (L+2)/(ΣL+2n)",
        onClick = function()
            if XP then
                local db = XP:GetDB()
                db.formulaModel = (db.formulaModel == "laplace") and "standard" or "laplace"
                p:OnRefresh()
                XP:UpdateHUD()
                print("|cff00ccff[EFHelper XP]|r Switched formula model to: |cffffd100" .. db.formulaModel .. "|r")
            end
        end,
    })
    p.modelBtn = modelBtn

    local modelDesc = p:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    modelDesc:SetPoint("LEFT", modelBtn, "RIGHT", 10, 0)
    modelDesc:SetText("Click to toggle Laplace (L+1)/(ΣL+n)")

    -- 10. Test Logs Controls
    local clearLogsBtn = AddButton(p, {
        width = 140, height = 24,
        relativeTo = modelBtn, y = -6,
        text = "Clear Test Logs",
        onClick = function()
            if XP and XP.ClearLogs then
                XP:ClearLogs()
            elseif EFHelperDB and EFHelperDB.XP then
                EFHelperDB.XP.testLogs = {}
            end
            p:OnRefresh()
            print("|cff00ccff[EFHelper XP]|r Saved test logs cleared.")
        end,
    })

    local logsCountText = p:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    logsCountText:SetPoint("LEFT", clearLogsBtn, "RIGHT", 10, 0)
    p.logsCountText = logsCountText

    -- 11. Action Buttons (Preview Test Mode & Reset Position)
    local testBtn = AddButton(p, {
        width = 140, height = 24,
        relativeTo = clearLogsBtn, y = -8,
        text = "Preview Display",
        onClick = function()
            if XP then
                XP.isTestMode = not XP.isTestMode
                XP:UpdateHUD()
                testBtn:SetText(XP.isTestMode and "Stop Preview" or "Preview Display")
            end
        end,
    })
    p.testBtn = testBtn

    local resetPosBtn = AddButton(p, {
        width = 140, height = 24,
        point = "LEFT", relativeTo = testBtn, x = 12,
        text = "Reset Position",
        onClick = function()
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
        end,
    })

    -- Information Box
    AddInfoBox(p,
        "|cffffd100Kill XP Predictor Notes:|r\n" ..
        "• Displays |cffffffffonly for hostile/attackable NPC targets|r in open world and 5-man dungeons.\n" ..
        "• |cffccccccEfficiency & Expected HP|r: Computes |cffffffff(XP / ExpectedHP) * 100|r and compares actual vs. expected HP.\n" ..
        "• |cffffd100Party Predictor (2–5 Players)|r: Calculates individual player base pools, share weighting, and group bonus.\n" ..
        "• |cffffa500Dungeon Modifier (0.4x)|r: Automatically applies the dungeon farming anti-nerf multiplier inside 5-man instances.\n" ..
        "• Left-click and drag the text while visible to reposition it anywhere on your screen.\n" ..
        "• Slash commands: |cff00ffff/efxp logs|r (view recorded kill stats), |cff00ffff/efxp clearlogs|r (clear recorded logs).",
        testBtn, -10
    )

    p.OnRefresh = function(self)
        if XP then
            local db = XP:GetDB()
            RefreshCheckboxes(self)
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
    local desc = CreatePanelHeader(p, "Custom Experience Bar", "High-information experience bar with completed quest XP overlay, dual clocks, and pace forecasting.")

    p._getDB = function() return XPBar and XPBar:GetDB() end
    p._cbSpacing = -4

    -- 1-5. Checkboxes (Auto-stacked)
    local enableCb = AddCheckbox(p, {
        name = "EFHelperConfigXPBarEnable",
        label = "Enable Custom Experience Bar",
        relativeTo = desc,
        key = "enabled",
        onClick = function(_, checked)
            if XPBar then if checked then XPBar:Enable() else XPBar:Disable() end end
        end,
    })
    AddCheckbox(p, {
        name = "EFHelperConfigXPBarLock",
        label = "Lock Position (prevents dragging)",
        key = "locked",
        default = false,
    })
    AddCheckbox(p, {
        name = "EFHelperConfigXPBarBlizz",
        label = "Hide Default Blizzard XP Bar (StatusTrackingBarManager)",
        key = "hideBlizzardBar",
        default = false,
        onClick = function() if XPBar then XPBar:UpdateBlizzardBarVisibility() end end,
    })
    AddCheckbox(p, {
        name = "EFHelperConfigXPBarRolling",
        label = "Use Rolling Window for XP/Hour (uncheck for Total Session)",
        get = function(db) return db and db.rateMode ~= "total" end,
        set = function(checked, db) if db then db.rateMode = checked and "rolling" or "total" end end,
        onClick = function()
            if XPBar then
                if p.OnRefresh then p.OnRefresh(p) end
                XPBar:UpdateClockDisplay(true)
            end
        end,
    })
    local autoPauseCb = AddCheckbox(p, {
        name = "EFHelperConfigXPBarAutoPause",
        label = "Auto-pause XP rate after 10m idle (neglects 6 of 10 minutes)",
        key = "autoPauseEnabled",
    })

    -- 6. Construct Scale Slider (0.5x to 2.0x)
    local scaleSlider = AddSlider(p, {
        name = "EFHelperConfigXPBarScale",
        relativeTo = autoPauseCb, x = 10, y = -20,
        min = 0.5, max = 2.0, step = 0.05,
        lowText = "0.5x", highText = "2.0x",
        format = "Construct Scale: %.2fx",
        key = "scale", default = 1.0,
        onValueChanged = function() if XPBar then XPBar:ApplyLayout() end end,
    })

    -- 7. Rolling Window Size Slider (1.0h to 6.0h)
    local windowSlider = AddSlider(p, {
        name = "EFHelperConfigXPBarWindow",
        point = "LEFT", relativeTo = scaleSlider, x = 30,
        min = 1.0, max = 6.0, step = 0.5,
        lowText = "1.0h", highText = "6.0h",
        format = "Rolling Window: %.1f hrs",
        key = "rollingWindowHours", default = 2.0,
        onValueChanged = function() if XPBar then XPBar:UpdateClockDisplay(true) end end,
    })

    -- 8. Action Buttons (Reset Session & Reset Position)
    local resetSessionBtn = AddButton(p, {
        width = 140, height = 24,
        relativeTo = scaleSlider, x = -10, y = -22,
        text = "Reset Session",
        onClick = function()
            if XPBar and XPBar.ResetSession then XPBar:ResetSession() end
        end,
    })

    local resetPosBtn = AddButton(p, {
        width = 140, height = 24,
        point = "LEFT", relativeTo = resetSessionBtn, x = 12,
        text = "Reset Position",
        onClick = function()
            if XPBar then
                local db = XPBar:GetDB()
                db.pos = nil
                db.scale = 1.0
                XPBar:ApplyLayout()
                if scaleSlider then scaleSlider:SetValue(1.0) end
                print("|cff00ffff[EFHelper XPBar]|r Position and scale reset to default center.")
            end
        end,
    })

    -- 9. Information Box
    AddInfoBox(p,
        "|cffffd100XP Bar Controls & Long-Session Pacing:|r\n" ..
        "• |cff8060ffPurple Section|r: Current character XP. |cffff9900Orange Section|r: Completed quests XP ready for turn-in.\n" ..
        "• |cffffffffShift + Left-Click bar|r: Toggle |cffffaa00Pause / Resume|r on session tracking.\n" ..
        "• |cffffffffRolling Window|r: Prevents metric inertia by averaging over the last N hours instead of whole session.\n" ..
        "• |cffffffffAutopause|r: Neglects 6 of 10 idle minutes if AFK, preserving long-session rate integrity.\n" ..
        "• |cffffffffShift-Right-Click bar|r: Toggle position Lock/Unlock. |cffffffffDrag|r to reposition when unlocked.\n" ..
        "• Slash commands: |cff00ffff/efh xpbar reset|r (reset session XP/hr), |cff00ffff/efh xpbar lock|r (lock/unlock position).",
        resetSessionBtn, -12
    )

    p.OnRefresh = function(self)
        if XPBar then
            local db = XPBar:GetDB()
            RefreshCheckboxes(self)
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
    p._getDB = function() return TrainSpells and TrainSpells:GetDB() end

    local enableCb = AddCheckbox(p, {
        name = "EFHelperConfigTrainSpellsEnable",
        label = "Enable Train Spells Module",
        template = "UICheckButtonTemplate",
        relativeTo = p,
        x = 20,
        y = -34,
        key = "enabled",
        onClick = function(_, checked)
            if TrainSpells then
                if checked then TrainSpells:Enable() else TrainSpells:Disable() end
            end
        end,
    })
    AddCheckbox(p, {
        name = "EFHelperConfigTrainSpellsTabEnable",
        label = "Show 'Trainable Spells' Button in Spellbook",
        template = "UICheckButtonTemplate",
        y = -4,
        key = "showSpellbookTab",
        onClick = function(_, checked)
            if TrainSpells and TrainSpells.tabButton then
                if checked then TrainSpells.tabButton:Show() else TrainSpells.tabButton:Hide() end
            end
        end,
    })
    AddCheckbox(p, {
        name = "EFHelperConfigTrainSpellsToastEnable",
        label = "Show Level-Up Trainer Toast Notification",
        template = "UICheckButtonTemplate",
        y = -4,
        key = "showLevelUpToast",
    })
    AddCheckbox(p, {
        name = "EFHelperConfigTrainSpellsSoundEnable",
        label = "Play Sound on Level-Up Toast",
        template = "UICheckButtonTemplate",
        y = -4,
        key = "sound",
    })
    local autoTrainCb = AddCheckbox(p, {
        name = "EFHelperConfigTrainSpellsAutoTrainEnable",
        label = "Auto-Train Selected Spells at Class Trainer",
        template = "UICheckButtonTemplate",
        y = -4,
        key = "autoTrain",
    })

    -- Section 2: Toast Duration Slider
    local sec2 = CreateSectionTitle(p, "Toast Notification Pacing", autoTrainCb, -10)

    local durationSlider = AddSlider(p, {
        name = "EFHelperConfigToastDurationSlider",
        relativeTo = sec2, x = 8, y = -16,
        min = 2.0, max = 8.0, step = 0.5,
        lowText = "2.0s", highText = "8.0s",
        format = "Duration: %.1fs",
        key = "toastDuration", default = 4.0,
    })

    -- Section 3: Interactive Action Buttons
    local testToastBtn = AddButton(p, {
        width = 140, height = 24,
        relativeTo = durationSlider, x = -8, y = -18,
        text = "Test Toast",
        onClick = function()
            local mod = EFHelper.TrainSpells or addonTable.TrainSpells or TrainSpells
            if mod and mod.TestToast then
                mod:TestToast()
            else
                print("|cffff4444[EFHelper]|r Trainer module is not active.")
            end
        end,
    })

    local openSpellbookBtn = AddButton(p, {
        width = 150, height = 24,
        point = "LEFT", relativeTo = testToastBtn, x = 12,
        text = "Toggle Trainer View",
        onClick = function()
            local mod = EFHelper.TrainSpells or addonTable.TrainSpells or TrainSpells
            if mod and mod.ToggleSpellbookPanel then
                mod:ToggleSpellbookPanel()
            else
                print("|cffff4444[EFHelper]|r Trainer module is not active.")
            end
        end,
    })

    -- Section 4: Information Box
    AddInfoBox(p,
        "|cffffd100Trainer Spells & Auto-Train Features:|r\n" ..
        "• |cffffffffAuto-Train|r: Automatically purchases all selected spells when talking to your class trainer.\n" ..
        "• |cffffffffTrainer Integration|r: Adds a 'Train Selected' button directly to class trainer windows.\n" ..
        "• |cffffffffTrade Safe|r: Strictly ignores tradeskill trainers (never auto-buys profession recipes).\n" ..
        "• |cffffffffSpellbook View|r: View all 1-60 trainable spells, ranks, and gold costs for your class.\n" ..
        "• |cffffffffLevel-Up Toast|r: Compact list of all newly unlocked spells (drag while Test Toast is active to move).\n" ..
        "• Configuration: Use the checkboxes above to toggle auto-training, spellbook tab, and toast alerts.",
        testToastBtn, -12
    )

    p.OnRefresh = function(self)
        if TrainSpells then
            RefreshCheckboxes(self)
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
    local desc = CreatePanelHeader(p, "RestedXP -> WaypointUI 3D Bridge", "Translates your active RestedXP objective into a 3D world beacon in WaypointUI with live step summaries and loop protection.")

    p._getDB = function() return WaypointBridge and WaypointBridge:GetDB() end

    -- 1. Enable Checkbox
    local enableCb = AddCheckbox(p, {
        name = "EFHelperConfigWaypointBridgeEnable",
        label = "Enable RestedXP -> WaypointUI 3D Bridge",
        relativeTo = desc,
        key = "enabled",
        onClick = function(_, checked)
            if WaypointBridge then
                if checked then
                    WaypointBridge:Enable(); WaypointBridge:SyncObjective(true)
                else
                    WaypointBridge:ClearSyncedWaypoint(); WaypointBridge:Disable()
                end
                p:OnRefresh()
            end
        end,
    })
    p.enableCb = enableCb

    -- 2. Show Rich Step Context Summary Checkbox
    local summaryCb = AddCheckbox(p, {
        name = "EFHelperConfigWaypointBridgeSummary",
        label = "Show Step Context Summary (NPCs, Mobs, & Live Objective Progress)",
        key = "showStepSummary",
        onClick = function()
            if WaypointBridge then WaypointBridge:SyncObjective(true); p:OnRefresh() end
        end,
    })
    p.summaryCb = summaryCb

    -- 3. Alter Waypoint Icon & Color by Objective Type Checkbox
    local colorCb = AddCheckbox(p, {
        name = "EFHelperConfigWaypointBridgeColor",
        label = "Alter Waypoint Icon & Color by Objective Type (Kill, Loot, Turn-In, Accept, etc.)",
        key = "colorByType",
        onClick = function()
            if WaypointBridge then WaypointBridge:SyncObjective(true); p:OnRefresh() end
        end,
    })
    p.colorCb = colorCb

    -- 4. Live Status Box
    local statusBox = AddInfoBox(p, { relativeTo = colorCb, y = -8, height = 84 })
    local statusText = statusBox.text
    p.statusText = statusText

    -- 5. Action Buttons
    local syncBtn = AddButton(p, {
        width = 160, height = 26,
        relativeTo = statusBox, y = -10,
        text = "Force Re-Sync Waypoint",
        onClick = function()
            if WaypointBridge and WaypointBridge.SyncObjective then
                WaypointBridge:SyncObjective(true)
                p:OnRefresh()
            end
        end,
    })

    local clearBtn = AddButton(p, {
        width = 160, height = 26,
        point = "LEFT", relativeTo = syncBtn, x = 10,
        text = "Clear Bridge Waypoint",
        onClick = function()
            if WaypointBridge and WaypointBridge.ClearSyncedWaypoint then
                WaypointBridge:ClearSyncedWaypoint()
                p:OnRefresh()
            end
        end,
    })

    -- 6. Information Box
    AddInfoBox(p,
        "|cffffd100Waypoint Bridge Behavior & Design:|r\n" ..
        "• |cffffffffStep Context Summary|r: Extracts associated NPCs (|cff00ffff.target|r), Mobs (|cff00ffff.mob|r), and live quest progress (|cff00ffff.complete|r / |cff00ffff.collect|r) and updates counts in real time.\n" ..
        "• |cffffffffObjective Visuals|r: Customizes the 3D beacon's icon & beam color by action (Kill, Loot, Turn-In, Accept, Train, Flight).\n" ..
        "• |cffffffffSpawn Loop Protection|r: Locks |cff00ffff#loop|r / |cff00ffff.loop|r steps to their 1st coordinate while still updating live kill/loot counters.\n" ..
        "• |cffffffffSuperTrack Guard|r: Prevents RXP's quest tracker from overriding WaypointUI's custom navigation text.",
        syncBtn, -10
    )

    p.OnRefresh = function(self)
        if not WaypointBridge then return end
        local db = WaypointBridge:GetDB()
        local isEnabled = (db.enabled ~= false)
        RefreshCheckboxes(self)

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
-- Panel 8: Party RXP Sync (Group Quest-Tracker HUD & Town-Cycle Alignment)
-- ----------------------------------------------------------------------------
local function CreatePartyRXPPanel(parent)
    local p = CreateFrame("Frame", nil, parent)
    p:SetAllPoints()

    local PartyRXP = addonTable.PartyRXP or EFHelper.PartyRXP
    local WaypointBridge = addonTable.WaypointBridge or EFHelper.WaypointBridge

    local desc = CreatePanelHeader(p, "Party RXP Tracker & Town-Cycle Sync", "Displays a unified group Quest-Tracker HUD with smart Group Remaining totals, 1-click EFHRXP tagging, and post-town quest alignment.")

    p._getDB = function() return PartyRXP and PartyRXP:GetDB() end

    -- 1. Enable Party RXP Sync
    local enableCb = AddCheckbox(p, {
        name = "EFHelperConfigPartyRXPEnable",
        label = "Enable Real-Time Party RXP Step & Objective Progress Sync",
        relativeTo = desc,
        key = "enabled",
        onClick = function()
            if PartyRXP then PartyRXP:UpdateHUD() end
            if WaypointBridge then WaypointBridge:SyncObjective(true) end
            p:OnRefresh()
        end,
    })
    p.enableCb = enableCb

    -- 2. Show Movable Party RXP HUD
    local showHudCb = AddCheckbox(p, {
        name = "EFHelperConfigPartyRXPHUD",
        label = "Show Movable Party RXP HUD when in a Party (Shift+Right-Click to Lock)",
        key = "showHUD",
        onClick = function()
            if PartyRXP then PartyRXP:UpdateHUD() end
            p:OnRefresh()
        end,
    })
    p.showHudCb = showHudCb

    -- 3. Include Own Progress in HUD
    local showSelfCb = AddCheckbox(p, {
        name = "EFHelperConfigPartyRXPSelf",
        label = "Include Your Own Step & Objectives at the Top of the Party HUD",
        key = "showSelf",
        onClick = function()
            if PartyRXP then PartyRXP:UpdateHUD() end
        end,
    })
    p.showSelfCb = showSelfCb

    -- 4. Show Aggregated "Group Remaining" Footer
    local groupRemCb = AddCheckbox(p, {
        name = "EFHelperConfigPartyRXPGroupRem",
        label = "Show Aggregated 'Group Remaining' Footer (Sums Loot Drops / Maxes Shared Kills)",
        key = "showGroupRemaining",
        onClick = function()
            if PartyRXP then PartyRXP:UpdateHUD() end
        end,
    })
    p.groupRemCb = groupRemCb

    -- 5. Click Objective on HUD to Set EFHRXP
    local clickTagCb = AddCheckbox(p, {
        name = "EFHelperConfigPartyRXPClickTag",
        label = "Click Incomplete Objective on HUD Out of Combat to Set 'EFHRXP' Tag Macro",
        key = "clickToTag",
        onClick = function()
            if PartyRXP then PartyRXP:UpdateHUD() end
        end,
    })
    p.clickTagCb = clickTagCb

    -- 6. Town-Cycle Quest Alignment & Auto-Share
    local townSyncCb = AddCheckbox(p, {
        name = "EFHelperConfigPartyRXPTownSync",
        label = "Enable Town-Cycle Quest Alignment & Auto-Share When Leaving Town for Field Steps",
        key = "townCycleSync",
        onClick = function()
            if PartyRXP then PartyRXP:EvaluateTownCycleState(); PartyRXP:UpdateHUD() end
            p:OnRefresh()
        end,
    })
    p.townSyncCb = townSyncCb

    -- 7. HUD Size / Scale Slider
    local scaleSlider = AddSlider(p, {
        name = "EFHelperConfigPartyRXPScale",
        relativeTo = townSyncCb,
        x = 6, y = -18,
        width = 240,
        min = 60, max = 180, step = 5, default = 100,
        lowText = "60%", highText = "180%",
        format = "HUD Size / Scale: %d%%",
        key = "scale",
        onValueChanged = function()
            if PartyRXP then PartyRXP:UpdateHUD() end
        end,
    })
    p.scaleSlider = scaleSlider

    -- 8. Live Status Box
    local statusBox = AddInfoBox(p, { relativeTo = scaleSlider, x = -6, y = -14, height = 68 })
    local statusText = statusBox.text
    p.statusText = statusText

    -- 8. Action Buttons
    local syncBtn = AddButton(p, {
        width = 125, height = 24,
        relativeTo = statusBox, y = -8,
        text = "Force Party Sync",
        onClick = function()
            if PartyRXP and PartyRXP.RequestPartySync then PartyRXP:RequestPartySync() end
            if WaypointBridge and WaypointBridge.SyncObjective then WaypointBridge:SyncObjective(true) end
            p:OnRefresh()
        end,
    })

    local previewBtn = AddButton(p, {
        width = 130, height = 24,
        point = "LEFT", relativeTo = syncBtn, x = 8,
        text = "Preview Party HUD",
        onClick = function(self)
            if PartyRXP and PartyRXP.ToggleTestMode then
                local active = PartyRXP:ToggleTestMode()
                self:SetText(active and "Stop Preview" or "Preview Party HUD")
                p:OnRefresh()
            end
        end,
    })

    local resetPosBtn = AddButton(p, {
        width = 115, height = 24,
        point = "LEFT", relativeTo = previewBtn, x = 8,
        text = "Reset HUD Pos",
        onClick = function()
            if PartyRXP and PartyRXP.ResetPosition then
                PartyRXP:ResetPosition()
                print("|cff0cd29f[EFHelper PartyRXP]|r Party RXP HUD position reset.")
            end
        end,
    })

    local clearMissedBtn = AddButton(p, {
        width = 130, height = 24,
        point = "LEFT", relativeTo = resetPosBtn, x = 8,
        text = "Clear Missed Alerts",
        onClick = function()
            if PartyRXP and PartyRXP.ClearMissedQuests then
                PartyRXP:ClearMissedQuests()
                p:OnRefresh()
            end
        end,
    })

    -- 9. Information Box
    AddInfoBox(p,
        "|cffffd100Party RXP Tracker & Town-Cycle Alignment:|r\n" ..
        "• |cffffffffUnified Group Tracker|r: Lists your progress + each party member's step delta, keeping completed lines in dim green (|cff44aa66✓|r) and highlighting objectives a party member still needs in gold.\n" ..
        "• |cffffffff1-Click EFHRXP Tagging|r: Click any incomplete mob/objective row on the HUD out of combat to set |cff00ffffEFHRXP|r to that mob—even after your own step has advanced.\n" ..
        "• |cffffffffTown-Cycle Sync|r: Detects multi-step town hubs (accepts/turn-ins/vendor/trainer), stays silent while in town, and auto-shares or warns on missed quests when the party heads out to a field step.",
        syncBtn, -8
    )

    p.OnRefresh = function(self)
        if not PartyRXP then return end
        RefreshCheckboxes(self)

        if previewBtn then
            previewBtn:SetText(PartyRXP.isTestMode and "Stop Preview" or "Preview Party HUD")
        end

        local st = PartyRXP.localState or {}
        local myStepStr = st.step and ("Step " .. tostring(st.step)) or "No Active Step"
        local townStr = (PartyRXP.inTownCycle or st.isTownCycle)
            and "|cff00ff99Active (Buffering Town Quests)|r"
            or "|cff888888Field / Inactive|r"

        local partyLines = PartyRXP:GetFormattedPartyLines()
        local partySummary = (#partyLines > 0)
            and table.concat(partyLines, "  |  ")
            or "|cff888888Solo / Waiting for party sync|r"

        local remLine = PartyRXP:BuildGroupRemainingSummary() or "|cff888888No active kill/loot counters on current step|r"

        statusText:SetText(string.format(
            "|cffffd100Local Step:|r |cffffffff%s|r (%s)   |   |cffffd100Town Cycle:|r %s\n" ..
            "|cffffd100Party Roster:|r %s\n%s",
            myStepStr, st.category or "TRAVEL", townStr, partySummary, remLine
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
        tabBtn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 4, -28 - (i - 1) * 48)
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
    panels[8] = CreatePartyRXPPanel(contentArea)

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
