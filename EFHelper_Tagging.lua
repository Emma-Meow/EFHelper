-- ----------------------------------------------------------------------------
-- EFHelper_Tagging.lua
-- Dynamic Tagging Macros, Quick-Select & RestedXP Integration (12.0 Midnight)
-- ----------------------------------------------------------------------------
local addonName, addonTable = ...
local EFHelper = _G.EFHelper or addonTable
local Tagging = EFHelper:NewModule("Tagging", "AceEvent-3.0")
EFHelper.Tagging = Tagging

local Utils = EFHelper.Utils

-- Default macro names
Tagging.defaultMacroName = "EFTag"
Tagging.secondMacroName = "EFTag2"
Tagging.rxpMacroName = "EFHRXP"

-- Compatibility aliases
EFHelper.defaultMacroName = Tagging.defaultMacroName
EFHelper.secondMacroName = Tagging.secondMacroName
EFHelper.rxpMacroName = Tagging.rxpMacroName

-- ----------------------------------------------------------------------------
-- Tagging Spells Configuration
-- ----------------------------------------------------------------------------
Tagging.Spells = {
    { name = "Moonfire", class = "Druid" },
    { name = "Serpent Sting", class = "Hunter" },
    { name = "Arcane Shot", class = "Hunter" },
    { name = "Fire Blast", class = "Mage" },
    { name = "Judgement", class = "Paladin" },
    { name = "Shadow Word: Pain", class = "Priest" },
    { name = "Throw", class = "Rogue" },
    { name = "Sinister Strike", class = "Rogue" },
    { name = "Earth Shock", class = "Shaman" },
    { name = "Curse of Agony", class = "Warlock" },
}
EFHelper.TaggingSpells = Tagging.Spells

-- ----------------------------------------------------------------------------
-- Macro Management
-- ----------------------------------------------------------------------------
--- Creates or updates the dynamic tagging macro.
-- @param macroName string: Name of the macro (max 16 chars)
-- @param mobName string: Name of the mob to target
-- @param spellName string|nil: Name of the spell/ability to cast
-- @param perCharacter boolean: Whether to save as per-character macro
-- @return boolean: success
function Tagging:CreateOrUpdateTaggingMacro(macroName, mobName, spellName, perCharacter)
    if InCombatLockdown and InCombatLockdown() then
        print("|cffff4444[EFHelper]|r Cannot create or edit macros while in combat!")
        return false
    end

    mobName = Utils.Trim(mobName)
    if mobName == "" then
        print("|cffff4444[EFHelper]|r Please enter a mob name.")
        return false
    end

    macroName = Utils.Trim(macroName)
    if macroName == "" then
        macroName = Tagging.defaultMacroName
    end
    if #macroName > 16 then
        macroName = macroName:sub(1, 16)
    end

    local isNone = (not spellName) or (spellName == "") or (spellName:lower() == "none")

    -- Fast tagging macro body: targetexact + cast + ping
    local bodyLines = {}
    table.insert(bodyLines, (not isNone) and ("#showtooltip " .. spellName) or "#showtooltip")
    table.insert(bodyLines, "/cleartarget")
    table.insert(bodyLines, "/targetexact " .. mobName)
    table.insert(bodyLines, "/cleartarget [dead]")
    table.insert(bodyLines, "/startattack [@target, nodead, exists]")
    if not isNone then
        table.insert(bodyLines, "/cast [@target, exists] " .. spellName)
    end
    table.insert(bodyLines, "/ping [@target, exists]")

    local body = table.concat(bodyLines, "\n")
    if #body > 255 then
        print("|cffff4444[EFHelper]|r Macro text exceeds 255 character limit.")
        return false
    end

    -- Icon resolution
    local iconFileID = 134400
    if not isNone and C_Spell then
        if C_Spell.GetSpellTexture then
            local tex = C_Spell.GetSpellTexture(spellName)
            if tex then iconFileID = tex end
        elseif C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spellName)
            if info and info.iconID then iconFileID = info.iconID end
        end
    end

    local existingIndex = GetMacroIndexByName(macroName)
    if existingIndex > 0 then
        EditMacro(existingIndex, macroName, iconFileID, body)
        print(string.format("|cff0cd29f[EFHelper]|r Updated macro '|cffffd100%s|r' for '|cffffd100%s|r'%s.",
            macroName, mobName, (not isNone) and (" with '|cffffd100" .. spellName .. "|r'") or " (target & ping only)"))
    else
        local isPerChar = (perCharacter ~= false) and 1 or nil
        local newIndex = CreateMacro(macroName, iconFileID, body, isPerChar)
        if not newIndex or newIndex == 0 then
            print("|cffff4444[EFHelper]|r Failed to create macro. Macro limit may be reached.")
            return false
        end
        print(string.format("|cff0cd29f[EFHelper]|r Created macro '|cffffd100%s|r' for '|cffffd100%s|r'%s.",
            macroName, mobName, (not isNone) and (" with '|cffffd100" .. spellName .. "|r'") or " (target & ping only)"))
    end

    EFHelper.activeRouteMob = mobName
    if EFHelper.db and EFHelper.db.profile then
        EFHelper.db.profile.lastMobName = mobName
    end
    if EFHelperCharDB then
        EFHelperCharDB.lastMobName = mobName
    end

    return true
end

-- Compatibility bridge
function EFHelper:CreateOrUpdateTaggingMacro(macroName, mobName, spellName, perCharacter)
    return Tagging:CreateOrUpdateTaggingMacro(macroName, mobName, spellName, perCharacter)
end

-- ----------------------------------------------------------------------------
-- Quick Select Slash Command (/efhq)
-- ----------------------------------------------------------------------------
SLASH_EFHELPERQUICK1 = "/efhq"
SlashCmdList["EFHELPERQUICK"] = function(msg)
    local raw = Utils.Trim(msg)
    local dbSpell = (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.lastSpell) or EFHelper.selectedSpell or "none"
    local ability = (raw == "") and dbSpell or ((raw:lower() == "none") and "none" or raw)

    if not UnitExists("target") then
        print("|cffff4444[EFHelper]|r You must have a target selected to use quick select.")
        return
    end

    local targetName = Utils.GetUnitName("target")
    if not targetName or targetName == "" then
        print("|cffff4444[EFHelper]|r Could not determine target name.")
        return
    end

    local success = Tagging:CreateOrUpdateTaggingMacro(Tagging.defaultMacroName, targetName, ability, true)
    if success then
        EFHelper.selectedSpell = ability
        if EFHelper.db and EFHelper.db.profile then
            EFHelper.db.profile.lastMobName = targetName
            EFHelper.db.profile.lastSpell = ability
        end
        if EFHelperCharDB then
            EFHelperCharDB.lastMobName = targetName
            EFHelperCharDB.lastSpell = ability
        end
        if EFHelper.Config and EFHelper.Config.frame then
            local f = EFHelper.Config.frame
            if f.mobInput then f.mobInput:SetText(targetName) end
            if f.spellDropdown then f.spellDropdown:SetText(ability) end
        end
    end
end

-- ----------------------------------------------------------------------------
-- RestedXP (RXPGuides) Integration
-- ----------------------------------------------------------------------------
local isUpdatingRXP = false

local function EnsurePing(btn)
    if InCombatLockdown and InCombatLockdown() then return end
    local text = btn:GetAttribute("macrotext")
    if type(text) == "string" and not text:find("/ping") then
        isUpdatingRXP = true
        if not text:find("/cleartarget %[dead%]") then
            text = text .. "\n/cleartarget [dead]"
        end
        text = text .. "\n/ping [@target, exists]"
        btn:SetAttribute("macrotext", text)
        isUpdatingRXP = false
    end
end

local function HookRXPButton(btn)
    if not btn then return end
    EnsurePing(btn)

    if not btn._efHookedAttr then
        btn._efHookedAttr = true
        hooksecurefunc(btn, "SetAttribute", function(self, attr, val)
            if isUpdatingRXP or (InCombatLockdown and InCombatLockdown()) then return end
            if attr == "macrotext" and type(val) == "string" and not val:find("/ping") then
                EnsurePing(self)
            end
        end)
    end

    if not btn._efHookedClick then
        btn._efHookedClick = true
        btn:HookScript("PostClick", function(self, button, isDown)
            if isDown then return end
            local tName = self.targetData and self.targetData.name
            if not tName or tName == "" then return end

            local spell = (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.lastSpell) or EFHelper.selectedSpell
            Tagging:CreateOrUpdateTaggingMacro(Tagging.rxpMacroName, tName, spell, true)
        end)
    end
end

function Tagging:HookAllRXPButtons()
    local targetFrame = _G.RXPTargetFrame
    if not targetFrame or not targetFrame.enemyTargetButtons then return end
    for _, btn in ipairs(targetFrame.enemyTargetButtons) do
        HookRXPButton(btn)
    end
end

function Tagging:InitRXP()
    local targetFrame = _G.RXPTargetFrame
    if targetFrame and not targetFrame._efHooked then
        targetFrame._efHooked = true
        targetFrame:HookScript("OnShow", function() Tagging:HookAllRXPButtons() end)
    end

    local RXP = LibStub and LibStub("AceAddon-3.0", true) and LibStub("AceAddon-3.0"):GetAddon("RXPGuides", true)
    if RXP then
        local targeting = RXP:GetModule("Targeting", true) or RXP.targeting
        if targeting and targeting.UpdateTargetFrame and not targeting._efHooked then
            targeting._efHooked = true
            hooksecurefunc(targeting, "UpdateTargetFrame", function() Tagging:HookAllRXPButtons() end)
        end
    end

    Tagging:HookAllRXPButtons()
end

-- ----------------------------------------------------------------------------
-- Lifecycle (AceEvent-3.0)
-- ----------------------------------------------------------------------------
function Tagging:OnInitialize()
    self:RegisterEvent("ADDON_LOADED", function(event, name)
        if name == "RXPGuides" then Tagging:InitRXP() end
    end)
    self:RegisterEvent("PLAYER_LOGIN", function()
        Tagging:InitRXP()
        if C_Timer and C_Timer.After then
            C_Timer.After(1, function() Tagging:InitRXP() end)
            C_Timer.After(3, function() Tagging:InitRXP() end)
        end
    end)
end

