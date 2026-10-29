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
        ffaAutoLootEnabled = true,
        ffaAutoLootLocked = false,
        ffaAutoLootPos = nil,
        silentTagClicks = true,

        Campfire = {
            enabled = true,
            locked = false,
            sound = true,
            soundFile = "Interface\\AddOns\\EllesmereUI\\media\\sounds\\heroism.ogg",
            testMode = false,
            scale = 1.0,
            alpha = 1.0,
            pos = nil,
        },

        Swapper = {
            enabled = true,
            locked = false,
            showHUD = false,
            dummyName = "",
            hudX = 0,
            hudY = -180,
        },

        XP = {
            enabled = true,
            locked = false,
            showPercentage = true,
            showFeedback = true,
            showRested = true,
            showZeroXp = true,
            showMobInfo = false,
            showEfficiency = true,
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
            toastPos = nil,
        },

        WaypointBridge = {
            enabled = true,
            showStepSummary = true,
            colorByType = true,
        },

        PartyRXP = {
            enabled = true,
            showHUD = true,
            showSelf = true,
            showGroupRemaining = true,
            clickToTag = true,
            townCycleSync = true,
            autoShareTownQuests = true,
            scale = 100,
            locked = false,
            pos = nil,
        },
    },
    char = {
        lastSpell = nil,
        lastMobName = nil,
        _migratedFromLegacy = false,
        XPBar = {
            sessionStartTime = nil,
            sessionStartXP = nil,
            sessionGainedXP = 0,
            lastHeartbeat = nil,
            levelBasePlayed = nil,
            levelDingSessionSec = 0,
            isManuallyPaused = false,
            manualPauseStart = nil,
            neglectedSec = 0,
            lastXPTime = nil,
            isAutoPaused = false,
        },
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

--- Unified frame draggable & lock behavior with Shift-Right-Click toggle and optional click-through propagation.
-- @param frame Frame: The frame to make draggable/lockable
-- @param getDbFn function: Returns the module db table containing the lock key and position data
-- @param opts table:
--   - moduleTag string: Prefix for chat messages (e.g. "[EFHelper XP]")
--   - lockKey string: Key in db for lock state (defaults to "locked")
--   - propagateClicksWhenLocked boolean: Whether to propagate clicks when locked (defaults to true)
--   - onSavePos function(frame, db): Callback to persist new coordinates
--   - isTestModeFn function(): Optional boolean returning whether test/preview mode is active
--   - onRightClickUnlocked function(frame, db): Optional callback when right-clicked without Shift while unlocked
--   - onLockChanged function(frame, isLocked, db): Optional callback after lock state toggles
--   - onMouseUp function(frame, button, db): Optional callback for other mouse-up actions (when not dragging)
function UI.MakeMovable(frame, getDbFn, opts)
    if not frame or type(getDbFn) ~= "function" then return end
    opts = opts or {}
    local lockKey = opts.lockKey or "locked"
    local propagateLocked = (opts.propagateClicksWhenLocked ~= false)

    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    local function IsLocked()
        local db = getDbFn()
        local testMode = opts.isTestModeFn and opts.isTestModeFn()
        return (db and db[lockKey] == true) and not testMode
    end

    frame:SetScript("OnMouseDown", function(self, button)
        if propagateLocked then
            if IsLocked() and not (button == "RightButton" and IsShiftKeyDown()) then
                if self.SetPropagateMouseClicks then
                    self:SetPropagateMouseClicks(true)
                end
            else
                if self.SetPropagateMouseClicks then
                    self:SetPropagateMouseClicks(false)
                end
            end
        end
    end)

    frame:SetScript("OnDragStart", function(self)
        if IsLocked() then return end
        self._isDragging = true
        self:StartMoving()
    end)

    frame:SetScript("OnDragStop", function(self)
        if not self._isDragging then return end
        self._isDragging = false
        self._wasDragged = true
        self:StopMovingOrSizing()
        local db = getDbFn()
        if opts.onSavePos and db then
            opts.onSavePos(self, db)
        end
    end)

    frame:SetScript("OnMouseUp", function(self, button)
        local wasDragged = self._wasDragged
        self._wasDragged = false
        local db = getDbFn()

        if button == "RightButton" and IsShiftKeyDown() then
            if db then
                db[lockKey] = not db[lockKey]
                local isLocked = db[lockKey]
                local tag = opts.moduleTag or "[EFHelper]"
                local lockLabel = propagateLocked and "|cffff5555Locked (click-through)|r" or "|cffff5555Locked|r"
                print(string.format("|cff0cd29f%s|r Frame is now %s.", tag, isLocked and lockLabel or "|cff55ff55Unlocked|r"))
                if opts.onLockChanged then
                    opts.onLockChanged(self, isLocked, db)
                end
            end
        elseif not wasDragged then
            if button == "RightButton" and not IsLocked() and opts.onRightClickUnlocked then
                opts.onRightClickUnlocked(self, db)
            elseif opts.onMouseUp then
                opts.onMouseUp(self, button, db)
            end
        end

        if propagateLocked and self.SetPropagateMouseClicks then
            self:SetPropagateMouseClicks(false)
        end
    end)
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

    -- One-time migration from legacy EFHelperCharDB into AceDB char/profile
    if type(_G.EFHelperCharDB) == "table" and not self.db.char._migratedFromLegacy then
        local legacy = _G.EFHelperCharDB
        if legacy.lastSpell then self.db.char.lastSpell = legacy.lastSpell end
        if legacy.lastMobName then self.db.char.lastMobName = legacy.lastMobName end
        if legacy.campfirePoint and not self.db.profile.Campfire.pos then
            self.db.profile.Campfire.pos = legacy.campfirePoint
        end
        if legacy.xpBarPoint and not self.db.profile.XPBar.pos then
            self.db.profile.XPBar.pos = legacy.xpBarPoint
        end
        if type(legacy.XPBar) == "table" then
            self.db.char.XPBar = self.db.char.XPBar or {}
            for k, v in pairs(legacy.XPBar) do
                if self.db.char.XPBar[k] == nil or self.db.char.XPBar[k] == 0 or self.db.char.XPBar[k] == false then
                    self.db.char.XPBar[k] = v
                end
            end
        end
        self.db.char._migratedFromLegacy = true
    end

    -- Sync per-character tagging overrides into active profile on login
    if self.db.char.lastSpell then self.db.profile.lastSpell = self.db.char.lastSpell end
    if self.db.char.lastMobName then self.db.profile.lastMobName = self.db.char.lastMobName end
end

function EFHelper:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateFFAAutoLootWidget")
    self:RegisterEvent("GROUP_ROSTER_UPDATE", "UpdateFFAAutoLootWidget")
    self:RegisterEvent("PARTY_LOOT_METHOD_CHANGED", "UpdateFFAAutoLootWidget")
    self:RegisterEvent("CVAR_UPDATE", "OnCVarUpdate")
    self:UpdateFFAAutoLootWidget()
end

-- ----------------------------------------------------------------------------
-- Lightweight Free-For-All (FFA) Auto-Loot Toggle Widget
-- ----------------------------------------------------------------------------
local function IsAutoLootEnabled()
    local val
    if GetCVar then
        local ok, res = pcall(GetCVar, "autoLootDefault")
        if ok then val = res end
    elseif C_CVar and C_CVar.GetCVar then
        local ok, res = pcall(C_CVar.GetCVar, "autoLootDefault")
        if ok then val = res end
    end
    return tostring(val) == "1"
end

local function SetAutoLootEnabled(enable)
    local targetVal = enable and "1" or "0"
    if SetCVar then
        pcall(SetCVar, "autoLootDefault", targetVal)
    elseif C_CVar and C_CVar.SetCVar then
        pcall(C_CVar.SetCVar, "autoLootDefault", targetVal)
    end
end

local function IsGroupFreeForAll()
    if not IsInGroup() then
        return false
    end
    return C_PartyInfo.GetLootMethod() == 0
end

function EFHelper:GetOrCreateFFAAutoLootButton()
    if self.ffaAutoLootBtn then
        return self.ffaAutoLootBtn
    end

    local btn = UI.CreateBackdropFrame("Button", "EFHelperFFAAutoLootButton", UIParent, 124, 22)
    btn:SetFrameStrata("MEDIUM")
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("LeftButtonUp")

    local pos = self.db and self.db.profile and self.db.profile.ffaAutoLootPos
    if pos and pos.point then
        btn:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or -90)
    else
        btn:SetPoint("TOP", UIParent, "TOP", 0, -90)
    end

    -- Left status indicator bar
    local accent = btn:CreateTexture(nil, "ARTWORK")
    accent:SetSize(3, 14)
    accent:SetPoint("LEFT", btn, "LEFT", 5, 0)
    accent:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.accent = accent

    -- Status dot
    local dot = btn:CreateTexture(nil, "ARTWORK")
    dot:SetSize(6, 6)
    dot:SetPoint("LEFT", accent, "RIGHT", 5, 0)
    dot:SetTexture("Interface\\Buttons\\WHITE8X8")
    btn.dot = dot

    -- Text label
    local label = btn:CreateFontString(nil, "OVERLAY")
    UI.SetupFontString(label, 11, "OUTLINE")
    label:SetPoint("LEFT", dot, "RIGHT", 6, 0)
    label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    label:SetJustifyH("LEFT")
    btn.label = label

    UI.MakeMovable(btn, function() return self.db and self.db.profile end, {
        moduleTag = "[EFHelper FFA Loot]",
        lockKey = "ffaAutoLootLocked",
        propagateClicksWhenLocked = false,
        onSavePos = function(f, prof)
            local point, _, relPoint, x, y = f:GetPoint()
            prof.ffaAutoLootPos = {
                point = point,
                relPoint = relPoint,
                x = math.floor((x or 0) + 0.5),
                y = math.floor((y or 0) + 0.5),
            }
        end,
    })

    btn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            local newState = not IsAutoLootEnabled()
            SetAutoLootEnabled(newState)
            self:RefreshFFAAutoLootVisual()
        end
    end)

    btn:Hide()
    self.ffaAutoLootBtn = btn
    return btn
end

function EFHelper:RefreshFFAAutoLootVisual()
    local btn = self.ffaAutoLootBtn
    if not btn then return end

    local isOn = IsAutoLootEnabled()
    btn:SetBackdropColor(0.05, 0.06, 0.08, 0.88)
    if isOn then
        btn:SetBackdropBorderColor(0.18, 0.55, 0.32, 0.90)
        btn.accent:SetVertexColor(0.20, 0.90, 0.45, 1.0)
        btn.dot:SetVertexColor(0.20, 0.90, 0.45, 1.0)
        btn.label:SetText("|cffc8d0dcAutoLoot:|r |cff33ee77ON|r")
    else
        btn:SetBackdropBorderColor(0.60, 0.22, 0.22, 0.90)
        btn.accent:SetVertexColor(0.95, 0.32, 0.32, 1.0)
        btn.dot:SetVertexColor(0.95, 0.32, 0.32, 1.0)
        btn.label:SetText("|cffc8d0dcAutoLoot:|r |cffff5555OFF|r")
    end
end

function EFHelper:UpdateFFAAutoLootWidget()
    local enabled = not (self.db and self.db.profile and self.db.profile.ffaAutoLootEnabled == false)
    if enabled and IsGroupFreeForAll() then
        local btn = self:GetOrCreateFFAAutoLootButton()
        self:RefreshFFAAutoLootVisual()
        btn:Show()
    elseif self.ffaAutoLootBtn then
        self.ffaAutoLootBtn:Hide()
    end
end

function EFHelper:OnCVarUpdate(_, cvarName)
    if not cvarName or Utils.IsSecret(cvarName) then
        if self.ffaAutoLootBtn and self.ffaAutoLootBtn:IsShown() then
            self:RefreshFFAAutoLootVisual()
        end
        return
    end
    local lower = tostring(cvarName):lower()
    if lower == "autolootdefault" or lower == "auto_loot_default_text" then
        if self.ffaAutoLootBtn and self.ffaAutoLootBtn:IsShown() then
            self:RefreshFFAAutoLootVisual()
        end
    end
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
