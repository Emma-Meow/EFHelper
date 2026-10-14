-- ----------------------------------------------------------------------------
-- EFHelper_Core.lua
-- Core Framework, Lifecycle & Shared Utilities for WoW Forever (12.0 Midnight)
-- ----------------------------------------------------------------------------
local addonName, addonTable = ...
local AceAddon = LibStub("AceAddon-3.0")
local EFHelper = AceAddon:NewAddon(addonTable, "EFHelper", "AceEvent-3.0", "AceTimer-3.0")
_G.EFHelper = EFHelper

-- ----------------------------------------------------------------------------
-- Database Defaults (AceDB-3.0)
-- ----------------------------------------------------------------------------
local dbDefaults = {
    profile = {
        lastSpell = "none",
        currentProfile = "Tirisfal Glades",
        lastMobName = "",
        activeRouteIndex = nil,
        hudShown = false,
        hudLocked = false,
        hudPosition = nil,

        Campfire = {
            enabled = true,
            sound = true,
            soundFile = "Interface\\AddOns\\EllesmereUI\\media\\sounds\\heroism.ogg",
            testMode = false,
            scale = 1.0,
            alpha = 1.0,
            pos = nil,
        },

        Swapper = {
            enabled = true,
            showHUD = false,
            dummyName = "",
            hudX = 0,
            hudY = -180,
        },

        XP = {
            enabled = true,
            showPercentage = true,
            showFeedback = true,
            showRested = true,
            showZeroXp = true,
            fontSize = 18,
            posX = 0,
            posY = 130,
            groupPredictor = true,
            formulaModel = "standard",
            logVersion = 2,
            testLogs = {},
        },

        XPBar = {
            enabled = true,
            locked = false,
            width = 480,
            height = 18,
            scale = 1.0,
            posX = 0,
            posY = -220,
            hideBlizzardBar = false,
            rateMode = "rolling",
            rollingWindowHours = 2.0,
            autoPauseEnabled = true,
        },

        TrainSpells = {
            enabled = true,
            showSpellbookTab = true,
            showLevelUpToast = true,
            toastDuration = 4.0,
            sound = true,
            hideHigherLevels = false,
        },
    },
    char = {
        lastSpell = nil,
        currentProfile = nil,
        lastMobName = nil,
        activeRouteIndex = nil,
        hudShown = nil,
    },
}

-- ----------------------------------------------------------------------------
-- Shared Utilities (EFHelper.Utils)
-- ----------------------------------------------------------------------------
EFHelper.Utils = {}
local Utils = EFHelper.Utils

local issecretvalue = _G.issecretvalue
local canaccessvalue = _G.canaccessvalue

--- Checks whether a value is protected/restricted by Blizzard's Secret Values engine
function Utils.IsSecret(val)
    if val == nil then return false end
    if type(issecretvalue) == "function" and issecretvalue(val) then
        return true
    end
    if type(canaccessvalue) == "function" and not canaccessvalue(val) then
        return true
    end
    -- Fallback safety probe: comparing secret value with "" triggers an exception
    local ok = pcall(function() local _ = (val == "") end)
    if not ok then
        return true
    end
    return false
end

function Utils.Trim(s)
    if not s or Utils.IsSecret(s) then return "" end
    if strtrim then
        local ok, res = pcall(strtrim, s)
        if ok and res and not Utils.IsSecret(res) then return res end
    end
    local ok, res = pcall(function() return s:match("^%s*(.-)%s*$") end)
    if ok and res and not Utils.IsSecret(res) then return res end
    return ""
end

--- Returns the full [Firstname] [Lastname] with realm suffix stripped.
-- Fully protected against secret string values in restricted instances/dungeons.
function Utils.GetUnitName(unit)
    if not unit or not UnitExists(unit) then return nil end
    local ok, rawName = pcall(function()
        return (GetUnitName and GetUnitName(unit)) or (UnitName and UnitName(unit))
    end)
    if not ok or not rawName or Utils.IsSecret(rawName) then
        return (unit == "target" and "Target") or (unit == "player" and "Player") or tostring(unit)
    end
    if rawName == "" then return nil end
    local ok2, short = pcall(strsplit, "-", rawName)
    if ok2 and short and not Utils.IsSecret(short) then
        local ok3, match = pcall(function() return short:match("^%s*(.-)%s*$") end)
        if ok3 and match and match ~= "" then
            return match
        end
        return short
    end
    return rawName
end

--- Safe chat whisper sender using modern C_ChatInfo
function Utils.SendWhisper(msg, target)
    if not msg or not target or Utils.IsSecret(target) or target == "" then return end
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(msg, "WHISPER", nil, target)
    elseif SendChatMessage then
        SendChatMessage(msg, "WHISPER", nil, target)
    end
end

--- Returns RGB values for class coloring
function Utils.GetClassColor(class)
    if not class then return 1, 1, 1 end
    local c = (C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if c then
        return c.r or 1, c.g or 1, c.b or 1
    end
    return 1, 1, 1
end

--- Returns class-colored string markup
function Utils.FormatClassColored(name, class)
    if not name then return "" end
    local r, g, b = Utils.GetClassColor(class)
    return string.format("|cff%02x%02x%02x%s|r", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255), name)
end

function Utils.StripFormatting(text)
    if not text or Utils.IsSecret(text) then return "" end
    local ok, res = pcall(function()
        local clean = text:gsub("|c%x%x%x%x%x%x%x%x", "")
        clean = clean:gsub("|r", "")
        clean = clean:gsub("|T.-|t", "")
        return clean:match("^%s*(.-)%s*$") or clean
    end)
    if ok and res and not Utils.IsSecret(res) then return res end
    return ""
end

-- ----------------------------------------------------------------------------
-- Shared UI Kit (EFHelper.UI)
-- ----------------------------------------------------------------------------
EFHelper.UI = {}
local UI = EFHelper.UI
local LSM = LibStub("LibSharedMedia-3.0", true)

if LSM and not LSM:IsValid("font", "Expressway") then
    local knownPath = "Interface\\AddOns\\EllesmereUI\\media\\fonts\\Expressway.TTF"
    pcall(LSM.Register, LSM, "font", "Expressway", knownPath)
end

function UI.GetFont(fontName)
    local name = fontName or "Expressway"
    if LSM then
        local f = LSM:Fetch("font", name, true)
        if f and f ~= "" then return f end
        local defaultKey = LSM:GetDefault("font")
        if defaultKey then
            local defPath = LSM:Fetch("font", defaultKey, true)
            if defPath and defPath ~= "" then return defPath end
        end
    end
    return (GameFontNormal and GameFontNormal.GetFont and GameFontNormal:GetFont()) or "Fonts\\ARIALN.TTF"
end

function UI.SetupFontString(fs, size, outline, fontName)
    if not fs then return end
    local fontPath = UI.GetFont(fontName)
    local flags = outline or "OUTLINE"
    local fontSize = size or 12

    local ok = pcall(fs.SetFont, fs, fontPath, fontSize, flags)
    if not ok then
        local fallback = (GameFontNormal and GameFontNormal.GetFont and GameFontNormal:GetFont()) or "Fonts\\ARIALN.TTF"
        pcall(fs.SetFont, fs, fallback, fontSize, flags)
    end
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.95)
end

function UI.CreateBackdropFrame(frameType, name, parent, width, height)
    local f = CreateFrame(frameType or "Frame", name, parent or UIParent, "BackdropTemplate")
    if width and height then f:SetSize(width, height) end
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.04, 0.05, 0.07, 0.75)
    f:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.8)
    return f
end

-- Backward compatibility aliases
EFHelper.GetFont = UI.GetFont
EFHelper.SetupFontString = UI.SetupFontString

-- ----------------------------------------------------------------------------
-- Lifecycle Hooks
-- ----------------------------------------------------------------------------
function EFHelper:OnInitialize()
    -- Initialize AceDB-3.0
    self.db = LibStub("AceDB-3.0"):New("EFHelperDB", dbDefaults, true)

    -- Support legacy character DB bridge
    EFHelperCharDB = EFHelperCharDB or {}

    -- Sync character overrides if present
    if EFHelperCharDB.lastSpell then self.db.profile.lastSpell = EFHelperCharDB.lastSpell end
    if EFHelperCharDB.currentProfile then self.db.profile.currentProfile = EFHelperCharDB.currentProfile end
    if EFHelperCharDB.lastMobName then self.db.profile.lastMobName = EFHelperCharDB.lastMobName end
    if EFHelperCharDB.activeRouteIndex then self.db.profile.activeRouteIndex = EFHelperCharDB.activeRouteIndex end
    if EFHelperCharDB.hudShown ~= nil then self.db.profile.hudShown = EFHelperCharDB.hudShown end
end

function EFHelper:ToggleConfig(tabIndex)
    if self.Config and self.Config.GetOrCreateWindow then
        local win = self.Config:GetOrCreateWindow()
        if win:IsShown() and not tabIndex then
            win:Hide()
        else
            if tabIndex and self.Config.SelectTab then
                self.Config.SelectTab(tabIndex)
            end
            win:Show()
        end
    end
end

-- ----------------------------------------------------------------------------
-- Master Slash Command (/efh, /efhelper)
-- ----------------------------------------------------------------------------
SLASH_EFHELPER1 = "/efh"
SLASH_EFHELPER2 = "/efhelper"

SlashCmdList["EFHELPER"] = function(msg)
    local raw = msg and msg:lower():match("^%s*(.-)%s*$") or ""
    local mod, action = raw:match("^(%S+)%s*(.*)$")
    mod = mod or ""
    action = action or ""

    if mod == "xpbar" or mod == "bar" then
        if action == "reset" then
            if EFHelper.XPBar and EFHelper.XPBar.ResetSession then
                EFHelper.XPBar:ResetSession()
            end
            return
        elseif action == "lock" then
            if EFHelper.XPBar and EFHelper.XPBar.GetDB then
                local db = EFHelper.XPBar:GetDB()
                db.locked = not db.locked
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[EFHelper XPBar]|r Frame is now %s.", db.locked and "|cffff5555Locked|r" or "|cff55ff55Unlocked|r"))
            end
            return
        end
    end

    EFHelper:ToggleConfig()
end
