-- ----------------------------------------------------------------------------
-- EFHelper_XP.lua
-- Solo Kill Experience Predictor & Combat Log Verifier
-- Calculates expected mob kill XP based on Classic linear ZD curves & bonuses.
-- ----------------------------------------------------------------------------
local addonName, addonTable = ...
local EFHelper = _G.EFHelper or addonTable
local XP = EFHelper:NewModule("XP", "AceEvent-3.0")
EFHelper.XP = XP
addonTable.XP = XP

local Utils = EFHelper.Utils
local UI = EFHelper.UI

-- ----------------------------------------------------------------------------
-- Configuration & Database Access
-- ----------------------------------------------------------------------------
function XP:GetDB()
    local db
    if EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.XP then
        db = EFHelper.db.profile.XP
    elseif EFHelperDB and EFHelperDB.XP then
        db = EFHelperDB.XP
    else
        EFHelperDB = EFHelperDB or {}
        EFHelperDB.XP = EFHelperDB.XP or {
            enabled = true,
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
        }
        db = EFHelperDB.XP
    end

    if db.showMobInfo == nil then
        db.showMobInfo = false
    end
    if db.showEfficiency == nil then
        db.showEfficiency = true
    end

    if db.groupPredictor == nil then
        if db.experimentalDuo ~= nil then
            db.groupPredictor = db.experimentalDuo
        else
            db.groupPredictor = true
        end
    end
    if db.formulaModel == nil then
        db.formulaModel = "standard"
    end
    -- Purge deprecated testing data if on legacy log schema
    if db.logVersion ~= 2 then
        db.testLogs = {}
        db.logVersion = 2
    end
    if not db.testLogs then
        db.testLogs = {}
    end

    -- Bridge to global EFHelperDB.XP so external inspection of WTF root works seamlessly
    if EFHelperDB then
        EFHelperDB.XP = EFHelperDB.XP or {}
        EFHelperDB.XP.testLogs = db.testLogs
    end
    return db
end

function XP:GetLogs()
    local db = XP:GetDB()
    if not db.testLogs then
        db.testLogs = {}
    end
    if EFHelperDB then
        EFHelperDB.XP = EFHelperDB.XP or {}
        EFHelperDB.XP.testLogs = db.testLogs
    end
    return db.testLogs
end

function XP:AddLog(entry)
    if not entry then return end
    local logs = XP:GetLogs()
    table.insert(logs, entry)
    while #logs > 200 do
        table.remove(logs, 1)
    end
end

function XP:ClearLogs()
    local db = XP:GetDB()
    db.testLogs = {}
    if EFHelperDB and EFHelperDB.XP then
        EFHelperDB.XP.testLogs = db.testLogs
    end
    return db.testLogs
end

-- ----------------------------------------------------------------------------
-- Zero Difference (ZD) Table & Mathematical Calculations
-- ----------------------------------------------------------------------------
-- Zero Difference lookup table across character level brackets (1-84)
local ZD_TABLE = {
    { maxLevel = 7,  zd = 5 },
    { maxLevel = 9,  zd = 6 },
    { maxLevel = 11, zd = 7 },
    { maxLevel = 15, zd = 8 },
    { maxLevel = 19, zd = 9 },
    { maxLevel = 29, zd = 11 },
    { maxLevel = 39, zd = 12 },
    { maxLevel = 44, zd = 13 },
    { maxLevel = 49, zd = 14 },
    { maxLevel = 54, zd = 15 },
    { maxLevel = 59, zd = 16 },
    { maxLevel = 84, zd = 17 },
}

--- Returns the Zero Difference (ZD) value for a given character level
function XP:GetZeroDifference(charLevel)
    if not charLevel or charLevel < 1 then return 5 end
    for _, entry in ipairs(ZD_TABLE) do
        if charLevel <= entry.maxLevel then
            return entry.zd
        end
    end
    return 17
end

--- Returns the Gray Level threshold for a given character level per Blizzard standard formula
function XP:GetGrayLevel(charLevel)
    if not charLevel or charLevel <= 5 then
        return 0
    elseif charLevel <= 39 then
        return charLevel - math.floor(charLevel / 10) - 5
    elseif charLevel <= 59 then
        return charLevel - math.floor(charLevel / 5) - 1
    else
        return charLevel - 9
    end
end

--- Banker's Rounding (Round-Half-To-Even) matching WoW C++ server engine IEEE 754 standard
local function RoundHalfToEven(val)
    if not val then return 0 end
    local integer = math.floor(val)
    local fraction = val - integer
    if math.abs(fraction - 0.5) < 1e-9 then
        if integer % 2 == 0 then
            return integer
        else
            return integer + 1
        end
    elseif fraction > 0.5 then
        return integer + 1
    else
        return integer
    end
end
XP.RoundHalfToEven = RoundHalfToEven

-- ----------------------------------------------------------------------------
-- Instance & Dungeon Detection Helpers
-- ----------------------------------------------------------------------------
local function GetInstanceInfoSafe()
    if not IsInInstance then return false, "none" end
    local inInstance, instanceType = IsInInstance()
    return inInstance, (instanceType or "none")
end

local function IsIn5ManDungeon()
    local inInstance, instanceType = GetInstanceInfoSafe()
    return inInstance and (instanceType == "party")
end

--- Calculates predicted solo kill XP for a target mob.
-- Supports 0.4x dungeon modifier for 5-man instances.
-- Returns:
--   predictedXP: integer (0 if gray or boss)
--   isGray: boolean (true if level difference >= ZD or mobLevel <= grayLevel)
--   levelDiff: integer (mobLevel - charLevel)
--   isBoss: boolean (true if skull mob / level -1)
--   rawSolo: number (unrounded float XP for group calculations)
function XP:CalculatePredictedXP(charLevel, mobLevel, classification)
    if not charLevel or charLevel < 1 then charLevel = 1 end
    if not mobLevel then return 0, false, 0, false, 0 end

    -- Boss / Skull mob check
    if mobLevel < 0 then
        return 0, false, 99, true, 0
    end

    local baseMultiplier = 1.0
    if classification == "elite" or classification == "rareelite" or classification == "worldboss" then
        baseMultiplier = 2.0
    end

    -- Dungeon farming nerf modifier: 0.4x XP for mobs inside 5-man dungeons
    local isDungeon = IsIn5ManDungeon()
    local dungeonMod = isDungeon and 0.44 or 1.0
    local totalMobMod = baseMultiplier * dungeonMod

    if mobLevel <= charLevel then
        local diff = charLevel - mobLevel
        local zd = XP:GetZeroDifference(charLevel)
        local grayLevel = XP:GetGrayLevel(charLevel)

        -- Gray / Trivial check: mob is at or below Gray Level threshold, OR diff meets/exceeds ZD
        if mobLevel <= grayLevel or diff >= zd then
            return 0, true, -diff, false, 0
        end

        -- Linear dropoff formula: (45 + 5 * moblevel) * (1 - (charlevel - moblevel) / zd)
        local baseKillXP = (mobLevel * 5) + 45
        local scaled = baseKillXP * (1 - (diff / zd))
        local rawSolo = scaled * totalMobMod
        local finalXP = RoundHalfToEven(rawSolo)
        return math.max(0, finalXP), false, -diff, false, rawSolo
    else
        -- Higher level mob formula: Base XP is determined by character level
        -- (Char Level * 5) + 45 * (1 + 0.05 * (Mob Level - Char Level))
        local diff = mobLevel - charLevel
        -- Higher level mob XP bonus caps at +4 levels per Classic mechanics (Orange/Red boundary)
        local cappedDiff = math.min(diff, 4)
        local charBaseXP = (charLevel * 5) + 45
        local scaled = charBaseXP * (1 + (0.05 * cappedDiff))
        local rawSolo = scaled * totalMobMod
        local finalXP = RoundHalfToEven(rawSolo)
        return math.max(0, finalXP), false, diff, false, rawSolo
    end
end

--- Retrieves active party members, levels, and roster synchronization status (2-5 members).
-- Returns nil if solo, in raid, or party > 5.
function XP:GetPartyRoster()
    if IsInRaid() then return nil end
    local numMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    if numMembers < 2 or numMembers > 5 then return nil end

    local playerLevel = UnitLevel("player")
    if not playerLevel or (Utils and Utils.IsSecret and Utils.IsSecret(playerLevel)) or playerLevel < 1 then return nil end

    local playerName = (Utils and Utils.GetUnitName and Utils.GetUnitName("player")) or "Player"
    local members = {
        {
            unit = "player",
            name = playerName,
            level = playerLevel,
            isPlayer = true,
            isConnected = true,
        }
    }
    local sumLevels = playerLevel
    local isSyncing = false
    local hasOffline = false

    for i = 1, numMembers - 1 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local isConn = UnitIsConnected(unit)
            if not isConn then
                hasOffline = true
            end
            local lvl = UnitLevel(unit)
            if not lvl or (Utils and Utils.IsSecret and Utils.IsSecret(lvl)) or lvl <= 0 then
                isSyncing = true
                lvl = 0
            end
            local name = (Utils and Utils.GetUnitName and Utils.GetUnitName(unit)) or ("Party " .. i)
            table.insert(members, {
                unit = unit,
                name = name,
                level = lvl,
                isPlayer = false,
                isConnected = isConn,
            })
            sumLevels = sumLevels + lvl
        else
            isSyncing = true
        end
    end

    if #members < numMembers then
        isSyncing = true
    end

    return {
        count = #members,
        sumLevels = sumLevels,
        playerLevel = playerLevel,
        isSyncing = isSyncing,
        hasOffline = hasOffline,
        members = members,
    }
end

--- Checks if the party group predictor is currently eligible and active (2-5 players)
function XP:IsGroupActive()
    local db = XP:GetDB()
    if not db.enabled or not db.groupPredictor then
        return false
    end
    if IsInRaid() then
        return false
    end
    local inInstance, instanceType = GetInstanceInfoSafe()
    if inInstance and instanceType ~= "party" then
        return false
    end
    local numMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    return (numMembers >= 2 and numMembers <= 5)
end

-- Backward compatibility alias
function XP:IsDuoGroupActive()
    return XP:IsGroupActive()
end

--- Calculates predicted group kill XP for a target mob in a 2-5 player party.
-- Uses individual player pool Solo_i, configurable weighting, and additive 10% * (n-1) bonus.
-- Returns:
--   totalXP: integer (0 if gray or boss)
--   isGray: boolean
--   levelDiff: integer (mobLevel - charLevel)
--   isBoss: boolean
--   baseShare: integer (player's predicted base share)
--   bonusXP: integer (player's predicted group bonus)
--   rawSolo: number (player's unrounded individual solo pool)
--   weight: number (player's fractional share weight)
--   bonusRate: number (group bonus rate: 0.1 * (n - 1))
function XP:CalculateGroupPredictedXP(charLevel, roster, mobLevel, classification)
    if not charLevel or charLevel < 1 then charLevel = 1 end
    if not mobLevel then return 0, false, 0, false, 0, 0, 0, 0, 0 end
    if not roster or not roster.count or roster.count < 2 then
        local soloXP, isGray, diff, isBoss, rawSolo = XP:CalculatePredictedXP(charLevel, mobLevel, classification)
        return soloXP, isGray, diff, isBoss, soloXP, 0, rawSolo, 1.0, 0
    end

    -- Boss / Skull mob check
    if mobLevel < 0 then
        return 0, false, 99, true, 0, 0, 0, 0, 0
    end

    -- 1. Compute individual solo pool for local player (includes 0.4x dungeon modifier if applicable)
    local soloXP, isGray, diff, isBoss, rawSolo = XP:CalculatePredictedXP(charLevel, mobLevel, classification)
    if isBoss then
        return 0, false, 99, true, 0, 0, 0, 0, 0
    end
    if isGray or (rawSolo and rawSolo <= 0) then
        return 0, true, diff, false, 0, 0, 0, 0, 0
    end

    local db = XP:GetDB()
    local model = db.formulaModel or "standard"
    local n = roster.count
    local sumL = roster.sumLevels

    -- 2. Weight distribution
    local weight = 0
    if model == "laplace" then
        weight = (charLevel + 1) / (sumL + n)
    else -- "standard": (L + 2) / (sumL + 2n)
        weight = (charLevel + 2) / (sumL + 2 * n)
    end

    -- 3. Base share via Banker's Rounding
    local baseShare = RoundHalfToEven(rawSolo * weight)

    -- 4. Group incentive bonus: 10% * (n - 1) via Banker's Rounding
    local bonusRate = 0.10 * (n - 1)
    local bonusXP = (baseShare > 0) and RoundHalfToEven(baseShare * bonusRate) or 0
    local totalXP = baseShare + bonusXP

    return totalXP, false, diff, false, baseShare, bonusXP, rawSolo, weight, bonusRate
end

-- Backward compatibility wrapper for duo calculation
function XP:CalculateDuoPredictedXP(charLevel, partnerLevel, mobLevel, classification)
    local roster = {
        count = 2,
        sumLevels = charLevel + partnerLevel,
        playerLevel = charLevel,
        members = {
            { unit = "player", name = "Player", level = charLevel, isPlayer = true },
            { unit = "party1", name = "Partner", level = partnerLevel, isPlayer = false },
        }
    }
    local totalXP, isGray, levelDiff, isBoss, baseShare, bonusXP, rawSolo, weight, bonusRate =
        XP:CalculateGroupPredictedXP(charLevel, roster, mobLevel, classification)
    return totalXP, isGray, levelDiff, isBoss, baseShare, bonusXP, rawSolo, weight
end

-- ----------------------------------------------------------------------------
-- Target Filtering & Visibility Checks
-- ----------------------------------------------------------------------------
function XP:ShouldShowForTarget()
    local db = XP:GetDB()
    if not db.enabled then return false end

    -- Preview mode bypasses targeting requirements
    if XP.isTestMode then return true end

    -- Instance check: allowed only in open world ("none") or 5-man dungeons ("party")
    local inInstance, instanceType = GetInstanceInfoSafe()
    if inInstance and instanceType ~= "party" then
        return false
    end

    -- Raid check
    if IsInRaid() or instanceType == "raid" then
        return false
    end

    local numMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    if numMembers > 5 then
        return false
    end

    local isGroup = (numMembers >= 2 and numMembers <= 5)
    if isGroup and not db.groupPredictor then
        return false
    end

    -- Target presence & validity
    if not UnitExists("target") then
        return false
    end

    -- NPCs only: ignore player characters and corpses
    if UnitIsPlayer("target") or UnitIsDeadOrGhost("target") then
        return false
    end

    -- Attackable / hostile mobs only
    if not UnitCanAttack("player", "target") then
        return false
    end

    return true
end

-- ----------------------------------------------------------------------------
-- Minimalist Floating Text HUD Frame
-- ----------------------------------------------------------------------------
local xpHudFrame = nil

function XP:GetOrCreateHUD()
    if xpHudFrame then return xpHudFrame end

    local db = XP:GetDB()
    local f = _G["EFHelperXPHUD"] or CreateFrame("Frame", "EFHelperXPHUD", UIParent)
    f:SetSize(460, 48)
    f:SetPoint("CENTER", UIParent, "CENTER", db.posX or 0, db.posY or 130)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    f:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        db.posX = math.floor(x or 0)
        db.posY = math.floor(y or 0)
    end)

    local text = f.text or f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    text:SetJustifyH("CENTER")
    text:ClearAllPoints()
    text:SetPoint("CENTER", f, "CENTER", 0, 0)

    local subText = f.subText or f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subText:SetJustifyH("CENTER")
    subText:ClearAllPoints()
    subText:SetPoint("TOP", text, "BOTTOM", 0, -2)

    local fontSize = db.fontSize or 18
    local subFontSize = math.max(10, fontSize - 5)
    if UI and UI.SetupFontString then
        UI.SetupFontString(text, fontSize, "OUTLINE", "Expressway")
        UI.SetupFontString(subText, subFontSize, "OUTLINE", "Expressway")
    elseif EFHelper and EFHelper.SetupFontString then
        EFHelper:SetupFontString(text, fontSize, "OUTLINE", "Expressway")
        EFHelper:SetupFontString(subText, subFontSize, "OUTLINE", "Expressway")
    end
    f.text = text
    f.subText = subText
    f:Hide()

    xpHudFrame = f
    XP.hud = f
    return f
end

function XP:ApplyFontSettings()
    if not xpHudFrame or not xpHudFrame.text then return end
    local db = XP:GetDB()
    local fontSize = db.fontSize or 18
    local subFontSize = math.max(10, fontSize - 5)
    if UI and UI.SetupFontString then
        UI.SetupFontString(xpHudFrame.text, fontSize, "OUTLINE", "Expressway")
        if xpHudFrame.subText then
            UI.SetupFontString(xpHudFrame.subText, subFontSize, "OUTLINE", "Expressway")
        end
    elseif EFHelper and EFHelper.SetupFontString then
        EFHelper:SetupFontString(xpHudFrame.text, fontSize, "OUTLINE", "Expressway")
        if xpHudFrame.subText then
            EFHelper:SetupFontString(xpHudFrame.subText, subFontSize, "OUTLINE", "Expressway")
        end
    end
end

-- ----------------------------------------------------------------------------
-- XP Percentage Formatter & Target Death Watcher
-- ----------------------------------------------------------------------------
local function FormatXPPercentage(xp)
    local db = XP:GetDB()
    if not db.showPercentage then return "" end
    if not xp or (Utils and Utils.IsSecret and Utils.IsSecret(xp)) or xp <= 0 then return "" end
    local maxXP = UnitXPMax("player")
    if not maxXP or (Utils and Utils.IsSecret and Utils.IsSecret(maxXP)) or maxXP <= 0 then return "" end

    local pct = (xp / maxXP) * 100
    if pct >= 10.0 then
        return string.format(" |cffcccccc(%.1f%%)|r", pct)
    elseif pct >= 1.0 then
        return string.format(" |cffcccccc(%.1f%%)|r", pct)
    elseif pct >= 0.01 then
        return string.format(" |cffcccccc(%.2f%%)|r", pct)
    else
        return " |cffcccccc(<0.01%)|r"
    end
end

-- Dedicated lightweight watcher frame for target death detection using C++ engine filtering.
-- Only registered when an attackable target exists while solo; unregisters immediately on death.
local targetWatcher = CreateFrame("Frame")
targetWatcher:Hide()

targetWatcher:SetScript("OnEvent", function(self, event, unit)
    if UnitIsDeadOrGhost("target") then
        if xpHudFrame and not XP.isTestMode then
            xpHudFrame:Hide()
        end
        self:UnregisterAllEvents()
    end
end)

function XP:WatchTargetDeath(enable)
    if enable then
        if not targetWatcher:IsEventRegistered("UNIT_HEALTH") then
            targetWatcher:RegisterUnitEvent("UNIT_HEALTH", "target")
        end
    else
        targetWatcher:UnregisterAllEvents()
    end
end

-- ----------------------------------------------------------------------------
-- Target Caching & Real-Time HUD Updates
-- ----------------------------------------------------------------------------
local recentTargets = {}
local mostRecentTarget = nil
local lastPlayerXP = nil
local lastReportTime = 0
local lastReportXP = 0
local lastReportMob = nil
local lastCombatLogXP = 0
local lastCombatLogTime = 0
local CACHE_TTL = 180 -- 3-minute sliding TTL eliminates need for in-combat timestamp thrashing

local function PurgeExpiredTargets()
    local now = GetTime()
    for key, entry in pairs(recentTargets) do
        if (now - entry.time) > CACHE_TTL then
            recentTargets[key] = nil
        end
    end
end

local function CacheTarget(mobName, guid, mobLevel, predictedXP, classification, hasRested, groupData)
    if not mobName or not predictedXP or predictedXP <= 0 then return end
    if Utils and Utils.IsSecret then
        if Utils.IsSecret(mobName) then mobName = "Target" end
        if Utils.IsSecret(guid) then guid = nil end
    end
    PurgeExpiredTargets()
    local entry = {
        name = mobName,
        guid = guid,
        level = mobLevel,
        classification = classification,
        predicted = predictedXP,
        wasRested = hasRested,
        time = GetTime(),
        groupData = groupData,
        duoData = groupData, -- backward compatibility alias
    }
    mostRecentTarget = entry
    if guid and guid ~= "" then
        recentTargets[guid] = entry
    end
    if mobName and mobName ~= "" then
        local clean = Utils.Trim(mobName):lower()
        if clean ~= "" then
            recentTargets[clean] = entry
        end
    end
end

local function FindMatchingTarget(mobName, guid)
    local now = GetTime()
    if Utils and Utils.IsSecret then
        if Utils.IsSecret(guid) then guid = nil end
        if Utils.IsSecret(mobName) then mobName = nil end
    end
    if guid and recentTargets[guid] and (now - recentTargets[guid].time) <= CACHE_TTL then
        return recentTargets[guid]
    end
    if mobName then
        local clean = Utils.Trim(mobName):lower()
        if clean ~= "" and recentTargets[clean] and (now - recentTargets[clean].time) <= CACHE_TTL then
            return recentTargets[clean]
        end
    end
    if mostRecentTarget and (now - mostRecentTarget.time) <= CACHE_TTL then
        return mostRecentTarget
    end
    return nil
end

local function ReportFeedback(targetEntry, actualTotal, restedBonus, mobNameFromMsg, groupBonus, actualBase)
    local db = XP:GetDB()
    if not db.enabled then return end

    local now = GetTime()
    local targetDisplayName = (targetEntry and targetEntry.name) or (mobNameFromMsg and Utils.Trim(mobNameFromMsg)) or "Target"

    -- Prevent duplicate reports within 2.0s for the exact same XP amount on the same mob
    if (now - lastReportTime) < 2.0 and lastReportXP == actualTotal then
        if not mobNameFromMsg or not lastReportMob or mobNameFromMsg == lastReportMob or targetDisplayName == lastReportMob then
            return
        end
    end

    -- If this cached target entry has already been reported, prevent duplicate posting
    if targetEntry and targetEntry.isReported and (now - (targetEntry.reportTime or 0)) < 3.0 then
        return
    end

    lastReportTime = now
    lastReportXP = actualTotal
    lastReportMob = targetDisplayName
    if targetEntry then
        targetEntry.isReported = true
        targetEntry.reportTime = now
    end

    restedBonus = restedBonus or 0
    groupBonus = groupBonus or 0
    actualBase = actualBase or (actualTotal - restedBonus - groupBonus)

    local grp = targetEntry and (targetEntry.groupData or targetEntry.duoData)
    local levelText = (targetEntry and targetEntry.level and targetEntry.level > 0) and (" (Lv " .. targetEntry.level .. ")") or ""

    if grp and (grp.isGroup or grp.isDuo) then
        -- --------------------------------------------------------------------
        -- Diagnostic Party Feedback Message for Testing & Bulk Data Verification
        -- --------------------------------------------------------------------
        local predTotal = grp.predTotal or targetEntry.predicted or 0
        local predBase = grp.predBase or 0
        local predBonus = grp.predBonus or 0
        local rawSolo = grp.rawSolo or grp.pool or 0
        local weightPct = (grp.weight or grp.share or 0) * 100
        local partySize = grp.partySize or 2
        local partyLevelsStr = grp.partyLevels and table.concat(grp.partyLevels, ", ") or tostring(grp.c2 or "?")
        local modelName = (grp.model == "laplace") and "Laplace (+1)" or "Standard (+2)"
        local dngStr = grp.isDungeon and " | Dungeon: Yes (0.44x)" or ""

        local isRestedMatch = false
        local effectivePred = predTotal
        local diff = actualTotal - predTotal

        -- Check Rested 2x hypothesis:
        -- If actual is approximately 2x predicted (within +-2 of 2x predicted), assume rested doubled the kill XP
        local restedTarget = predTotal * 2
        local restedDiff = actualTotal - restedTarget
        if predTotal > 0 and (math.abs(restedDiff) < math.abs(diff)) and (math.abs(restedDiff) <= 2) then
            isRestedMatch = true
            effectivePred = restedTarget
            diff = restedDiff
            if restedBonus <= 0 then
                restedBonus = predTotal
                actualBase = math.max(0, actualTotal - restedBonus - groupBonus)
            end
        end

        local matchHeader
        if diff == 0 then
            if isRestedMatch then
                matchHeader = "|cff00ff00[Exact Match! (Rested)]|r"
            else
                matchHeader = "|cff00ff00[Exact Match!]|r"
            end
        elseif math.abs(diff) == 1 or (math.abs(diff) <= 2 and isRestedMatch) then
            local sign = (diff > 0) and "+" or ""
            if isRestedMatch then
                matchHeader = string.format("|cff99ff33[Diff: %s%d (Rested Rounding)]|r", sign, diff)
            else
                matchHeader = string.format("|cff99ff33[Diff: %s%d (Rounding)]|r", sign, diff)
            end
        else
            local sign = (diff > 0) and "+" or ""
            matchHeader = string.format("|cffffa500[Diff: %s%d]|r", sign, diff)
        end

        local restedText = (restedBonus > 0) and string.format(", Rested: +%d", restedBonus) or ""
        local predRestedText = isRestedMatch and string.format(" [x2 Rested: %d XP]", effectivePred) or ""

        if db.showFeedback ~= false then
            print(string.format("|cff00ccff[EFHelper Party XP]|r %s%s: |cffffd100%d XP|r %s",
                targetDisplayName, levelText, actualTotal, matchHeader))
            print(string.format("  Predicted: |cffffffff%d XP|r%s (Base: %d, Bonus: +%d) | Actual: |cffffffff%d XP|r (Base: %d, Bonus: +%d%s)",
                predTotal, predRestedText, predBase, predBonus, actualTotal, actualBase, groupBonus, restedText))
            print(string.format("  Diagnostics: Party (%d): [%s] | Solo Pool: %.1f | Weight: %.1f%% | Model: %s%s",
                partySize, partyLevelsStr, rawSolo, weightPct, modelName, dngStr))
        end

        -- Log to SavedVariables ring buffer for persistent bulk analysis
        XP:AddLog({
            time = (date and date("%Y-%m-%d %H:%M:%S")) or tostring(GetTime()),
            mob = targetDisplayName,
            mobLevel = targetEntry and targetEntry.level or 0,
            partySize = partySize,
            partyLevels = grp.partyLevels or { grp.c1 or 0, grp.c2 or 0 },
            playerLevel = grp.playerLevel or UnitLevel("player"),
            model = grp.model or "standard",
            predTotal = predTotal,
            predBase = predBase,
            predBonus = predBonus,
            actTotal = actualTotal,
            actBase = actualBase,
            actBonus = groupBonus,
            rawSolo = rawSolo,
            weight = string.format("%.3f", grp.weight or grp.share or 0),
            isDungeon = grp.isDungeon or false,
            isRested = isRestedMatch or (restedBonus > 0),
            diff = diff,
        })
    elseif groupBonus > 0 then
        -- Party kill without matched cached target
        if db.showFeedback ~= false then
            local restedText = (restedBonus > 0) and string.format(", Rested: +%d", restedBonus) or ""
            print(string.format("|cff00ccff[EFHelper Party XP]|r %s: |cffffffff%d XP|r (Base: %d, Bonus: +%d%s) |cff888888[Untargeted]|r",
                targetDisplayName, actualTotal, actualBase, groupBonus, restedText))
        end
    else
        -- Standard Solo feedback
        local expected = (targetEntry and targetEntry.predicted) or 0
        local isSoloRested = false
        local soloBaseActual = actualTotal - restedBonus

        -- Check Rested 2x hypothesis for solo
        if expected > 0 and restedBonus <= 0 then
            local restedTarget = expected * 2
            local restedDiff = actualTotal - restedTarget
            local unrestedDiff = actualTotal - expected
            if math.abs(restedDiff) < math.abs(unrestedDiff) and math.abs(restedDiff) <= 2 then
                isSoloRested = true
                restedBonus = expected
                soloBaseActual = actualTotal - restedBonus
            end
        end

        if expected > 0 then
            local diff = soloBaseActual - expected

            -- Log solo test kill
            XP:AddLog({
                time = (date and date("%Y-%m-%d %H:%M:%S")) or tostring(GetTime()),
                mob = targetDisplayName,
                mobLevel = targetEntry and targetEntry.level or 0,
                partySize = 1,
                partyLevels = { UnitLevel("player") },
                playerLevel = UnitLevel("player"),
                model = "solo",
                predTotal = expected,
                predBase = expected,
                predBonus = 0,
                actTotal = actualTotal,
                actBase = soloBaseActual,
                actBonus = 0,
                rawSolo = expected,
                weight = "1.000",
                isDungeon = IsIn5ManDungeon(),
                isRested = (restedBonus > 0) or isSoloRested,
                diff = diff,
            })

            if db.showFeedback ~= false then
                if diff == 0 then
                    if restedBonus > 0 or isSoloRested then
                        print(string.format("|cff00ff00[EFHelper XP]|r %s%s: |cffffd100%d XP|r (+%d Rested) |cff00ff00[Exact match! (Rested)]|r",
                            targetDisplayName, levelText, actualTotal, restedBonus))
                    else
                        print(string.format("|cff00ff00[EFHelper XP]|r %s%s: |cffffd100%d XP|r |cff00ff00[Exact match!]|r",
                            targetDisplayName, levelText, expected))
                    end
                elseif math.abs(diff) == 1 or (math.abs(diff) <= 2 and (restedBonus > 0 or isSoloRested)) then
                    local diffText = (diff > 0) and ("+" .. diff) or tostring(diff)
                    if restedBonus > 0 or isSoloRested then
                        print(string.format("|cff99ff33[EFHelper XP]|r %s%s: Predicted |cffffd100%d XP|r (2x: %d) | Actual |cffffffff%d XP|r (+%d Rested, Diff: %s)",
                            targetDisplayName, levelText, expected, expected * 2, actualTotal, restedBonus, diffText))
                    else
                        print(string.format("|cff99ff33[EFHelper XP]|r %s%s: Predicted |cffffd100%d XP|r | Actual |cffffffff%d XP|r (Diff: %s)",
                            targetDisplayName, levelText, expected, soloBaseActual, diffText))
                    end
                else
                    local diffText = (diff > 0) and ("+" .. diff) or tostring(diff)
                    if restedBonus > 0 or isSoloRested then
                        print(string.format("|cffffa500[EFHelper XP]|r %s%s: Predicted |cffffd100%d XP|r | Actual |cffffffff%d XP|r (+%d Rested, Diff: %s)",
                            targetDisplayName, levelText, expected, soloBaseActual, restedBonus, diffText))
                    else
                        print(string.format("|cffffa500[EFHelper XP]|r %s%s: Predicted |cffffd100%d XP|r | Actual |cffffffff%d XP|r (Diff: %s)",
                            targetDisplayName, levelText, expected, soloBaseActual, diffText))
                    end
                end
            end
        else
            if db.showFeedback ~= false then
                if restedBonus > 0 then
                    print(string.format("|cff0cd29f[EFHelper XP]|r %s: |cffffffff%d XP|r (+%d Rested)",
                        targetDisplayName, soloBaseActual, restedBonus))
                else
                    print(string.format("|cff0cd29f[EFHelper XP]|r %s: |cffffffff%d XP|r",
                        targetDisplayName, soloBaseActual))
                end
            end
        end
    end
end

function XP:UpdateHUD()
    local hud = XP:GetOrCreateHUD()

    if not XP:ShouldShowForTarget() then
        hud:Hide()
        XP:WatchTargetDeath(false)
        return
    end

    local db = XP:GetDB()
    local inInstance, instanceType = GetInstanceInfoSafe()
    local isDungeon = inInstance and (instanceType == "party")

    -- Test mode display
    if XP.isTestMode then
        local previewPct = FormatXPPercentage(165)
        if previewPct == "" then previewPct = " |cffcccccc(1.8%)|r" end
        local dngTag = (isDungeon and db.showMobInfo) and " |cffffa500[Dungeon 0.4x]|r" or ""
        if XP:IsGroupActive() or db.groupPredictor then
            local partyTag = db.showMobInfo and " |cff00ccff[Party Preview]|r" or ""
            hud.text:SetText("|cffffd100+135 XP|r" .. previewPct .. dngTag .. partyTag)
        else
            local restedPreview = db.showRested and " |cff00ffff(+165 Rested)|r" or ""
            hud.text:SetText("|cffffd100+165 XP|r" .. previewPct .. dngTag .. restedPreview)
        end
        if db.showEfficiency then
            hud.text:ClearAllPoints()
            hud.text:SetPoint("CENTER", hud, "CENTER", 0, 7)
            hud.subText:SetText("|cff00ccffXP/HP: 0.225|r |cff888888[Preview Mode]|r")
            hud.subText:Show()
        else
            hud.text:ClearAllPoints()
            hud.text:SetPoint("CENTER", hud, "CENTER", 0, 0)
            hud.subText:SetText("")
            hud.subText:Hide()
        end
        hud:Show()
        return
    end

    local charLevel = UnitLevel("player")
    local mobLevel = UnitLevel("target")
    local classification = UnitClassification("target")

    -- Guard against secret numbers or restricted values in instance environments
    if Utils and Utils.IsSecret then
        if Utils.IsSecret(mobLevel) or Utils.IsSecret(charLevel) then
            hud.text:ClearAllPoints()
            hud.text:SetPoint("CENTER", hud, "CENTER", 0, 0)
            hud.subText:SetText("")
            hud.subText:Hide()
            hud.text:SetText("|cffffd100+?? XP|r |cffffa500[Dungeon 0.4x]|r")
            hud:Show()
            XP:WatchTargetDeath(true)
            return
        end
        if Utils.IsSecret(classification) then
            classification = "normal"
        end
    end

    local mobName = (Utils and Utils.GetUnitName and Utils.GetUnitName("target")) or "Target"
    if Utils and Utils.IsSecret and Utils.IsSecret(mobName) then
        mobName = "Target"
    end

    local isGroupActive = XP:IsGroupActive()
    local xp, isGray, diff, isBoss
    local groupData = nil
    local groupSuffix = ""

    if isGroupActive then
        local roster = XP:GetPartyRoster()
        if not roster then
            xp, isGray, diff, isBoss = XP:CalculatePredictedXP(charLevel, mobLevel, classification)
        elseif roster.isSyncing then
            hud.text:ClearAllPoints()
            hud.text:SetPoint("CENTER", hud, "CENTER", 0, 0)
            hud.subText:SetText("")
            hud.subText:Hide()
            hud.text:SetText("|cffffd100+?? XP|r |cff888888(Syncing party...)|r")
            hud:Show()
            XP:WatchTargetDeath(true)
            return
        else
            local totalXP, gGray, levelDiff, gBoss, baseShare, bonusXP, rawSolo, weight, bonusRate =
                XP:CalculateGroupPredictedXP(charLevel, roster, mobLevel, classification)

            xp = totalXP
            isGray = gGray
            diff = levelDiff
            isBoss = gBoss

            local tag = (roster.count == 2) and "Duo" or string.format("Party %d", roster.count)
            if roster.hasOffline then
                groupSuffix = string.format(" |cffff8800[%s (Offline)]|r", tag)
            else
                groupSuffix = string.format(" |cff00ccff[%s]|r", tag)
            end

            local partyLevels = {}
            for _, m in ipairs(roster.members) do
                table.insert(partyLevels, m.level)
            end

            groupData = {
                isGroup = true,
                partySize = roster.count,
                partyLevels = partyLevels,
                playerLevel = charLevel,
                predTotal = totalXP,
                predBase = baseShare,
                predBonus = bonusXP,
                rawSolo = rawSolo,
                weight = weight,
                bonusRate = bonusRate,
                model = db.formulaModel or "standard",
                isDungeon = isDungeon,
            }
        end
    else
        xp, isGray, diff, isBoss = XP:CalculatePredictedXP(charLevel, mobLevel, classification)
    end

    if isBoss then
        hud.text:ClearAllPoints()
        hud.text:SetPoint("CENTER", hud, "CENTER", 0, 0)
        hud.subText:SetText("")
        hud.subText:Hide()
        hud.text:SetText("|cffff2020?? XP (Boss)|r")
        hud:Show()
        XP:WatchTargetDeath(false)
        return
    end

    if isGray then
        hud.text:ClearAllPoints()
        hud.text:SetPoint("CENTER", hud, "CENTER", 0, 0)
        hud.subText:SetText("")
        hud.subText:Hide()
        if db.showZeroXp then
            local grayMsg = isGroupActive and "|cff8888880 XP (Trivial to Player)|r" or "|cff8888880 XP (Trivial / Gray)|r"
            hud.text:SetText(grayMsg)
            hud:Show()
        else
            hud:Hide()
        end
        XP:WatchTargetDeath(false)
        return
    end

    -- Color coding based on level relationship
    local colorPrefix = "|cffffd100" -- Equal level (Yellow)
    if diff > 0 then
        colorPrefix = (diff >= 3) and "|cffff3333" or "|cffff8800" -- Higher level (Red/Orange)
    elseif diff < 0 then
        colorPrefix = "|cff00ff00" -- Lower level (Green)
    end

    local pctText = FormatXPPercentage(xp)
    local xpString = string.format("%s+%d XP|r", colorPrefix, xp)

    -- Rested XP indicator (Default clean view: XP + Rested)
    local exhaustion = GetXPExhaustion and GetXPExhaustion()
    local hasRested = exhaustion and exhaustion > 0
    if hasRested and db.showRested then
        xpString = xpString .. string.format(" |cff00ffff(+%d Rested)|r", xp)
    end

    if pctText and pctText ~= "" then
        xpString = xpString .. pctText
    end

    -- Additional mob information & group scaling tags (outsourced behind showMobInfo toggle)
    if db.showMobInfo then
        if groupSuffix ~= "" then
            xpString = xpString .. groupSuffix
        end
        if classification == "elite" or classification == "rareelite" or classification == "worldboss" then
            xpString = xpString .. " |cffffd100[Elite]|r"
        end
        if isDungeon then
            xpString = xpString .. " |cffffa500[Dungeon 0.4x]|r"
        end
    end

    hud.text:SetText(xpString)

    -- Optional second line: XP / Max HP Efficiency Comparison
    local maxHp = UnitHealthMax("target")
    local showSub = false
    if db.showEfficiency and xp and xp > 0 and maxHp then
        if not (Utils and Utils.IsSecret and Utils.IsSecret(maxHp)) and maxHp > 0 then
            local ratio = xp / maxHp
            hud.subText:SetText(string.format("|cff00ccffXP/HP: %.3f|r", ratio))
            showSub = true
        end
    end

    if showSub then
        hud.text:ClearAllPoints()
        hud.text:SetPoint("CENTER", hud, "CENTER", 0, 7)
        hud.subText:Show()
    else
        hud.text:ClearAllPoints()
        hud.text:SetPoint("CENTER", hud, "CENTER", 0, 0)
        hud.subText:SetText("")
        hud.subText:Hide()
    end

    hud:Show()

    -- Activate targetWatcher for death detection (engine-filtered to "target" only)
    XP:WatchTargetDeath(true)

    -- Cache target for post-kill combat log verification
    CacheTarget(mobName, UnitGUID("target"), mobLevel, xp, classification, hasRested, groupData)
end

-- ----------------------------------------------------------------------------
-- Post-Kill Verification & Feedback via Combat Log & Player XP Update
-- ----------------------------------------------------------------------------
function XP:CHAT_MSG_COMBAT_XP_GAIN(event, msg)
    local db = XP:GetDB()
    if not db.enabled then return end
    if not msg or msg == "" then return end

    local clean = (Utils and Utils.StripFormatting and Utils.StripFormatting(msg)) or msg
    -- Remove commas inside numbers (e.g. 1,250 -> 1250)
    clean = clean:gsub("(%d),(%d)", "%1%2")

    -- 1. Parse rested bonus if present (e.g. "+60 exp Rested", "+60 Rested", "+60 Ruhe")
    local restedBonus = clean:match("%+(%d+)%s*.-[Rr]ested") or clean:match("%+(%d+)%s*.-[Rr]uhe")
    restedBonus = restedBonus and tonumber(restedBonus) or 0

    -- 2. Parse group bonus if present (e.g. "+1 group bonus", "+2 Gruppenbonus")
    local groupBonus = clean:match("%+(%d+)%s*.-[Gg]roup") or clean:match("%+(%d+)%s*.-[Gg]ruppe")
    groupBonus = groupBonus and tonumber(groupBonus) or 0

    -- 3. Parse mob name if present
    local mobName = clean:match("^(.-)%s+dies") or clean:match("^(.-)%s+stirbt")

    -- 4. Parse actual XP amount from combat log
    local rawXp = clean:match("[Gg]ain%s*(%d+)%s*[Ee]xperience")
        or clean:match("[Gg]ain%s*(%d+)%s*XP")
        or clean:match("erhaltet%s*(%d+)%s*Erfahrung")
        or clean:match("dies,%s*you gain%s*(%d+)")
        or clean:match("(%d+)%s*[Ee]xperience")
        or clean:match("(%d+)%s*XP")
        or clean:match("(%d+)")

    rawXp = rawXp and tonumber(rawXp) or 0
    if rawXp <= 0 then return end

    -- In WoW combat log: "you gain %d experience (+%d bonus)"
    -- The primary number (%d) is ALREADY the total experience awarded!
    -- The bonus in parentheses is a breakdown of how much of that total was bonus.
    local actualTotal = rawXp
    local actualBase = math.max(0, rawXp - groupBonus - restedBonus)

    lastCombatLogXP = actualTotal
    lastCombatLogTime = GetTime()

    local targetEntry = FindMatchingTarget(mobName, nil)
    ReportFeedback(targetEntry, actualTotal, restedBonus, mobName, groupBonus, actualBase)
end

function XP:PLAYER_XP_UPDATE()
    local currentXP = UnitXP("player")
    if lastPlayerXP and currentXP > lastPlayerXP then
        local delta = currentXP - lastPlayerXP
        local now = GetTime()

        -- 1. If CHAT_MSG_COMBAT_XP_GAIN already processed this XP gain within the last 2 seconds, exit immediately
        if delta == lastCombatLogXP and (now - lastCombatLogTime) < 2.0 then
            lastPlayerXP = currentXP
            return
        end

        local targetEntry = FindMatchingTarget(nil, nil)
        -- 2. If the matched target was already reported, exit immediately
        if targetEntry and targetEntry.isReported and (now - (targetEntry.reportTime or 0)) < 3.0 then
            lastPlayerXP = currentXP
            return
        end

        -- 3. Failsafe timer: give CHAT_MSG_COMBAT_XP_GAIN 0.5s to arrive with authentic combat log text
        if C_Timer and C_Timer.After then
            local capturedDelta = delta
            local capturedEntry = targetEntry
            C_Timer.After(0.5, function()
                local timerNow = GetTime()
                -- Check if CHAT_MSG_COMBAT_XP_GAIN handled it in the interim
                if capturedDelta == lastCombatLogXP and (timerNow - lastCombatLogTime) < 2.0 then
                    return
                end
                if capturedEntry and capturedEntry.isReported and (timerNow - (capturedEntry.reportTime or 0)) < 3.0 then
                    return
                end
                if (timerNow - lastReportTime) < 2.0 and lastReportXP == capturedDelta then
                    return
                end

                local grp = capturedEntry and (capturedEntry.groupData or capturedEntry.duoData)
                local partnerBonus = grp and grp.predBonus or 0
                local baseEst = grp and math.max(0, capturedDelta - partnerBonus) or capturedDelta
                ReportFeedback(capturedEntry, capturedDelta, 0, nil, partnerBonus, baseEst)
            end)
        else
            if (now - lastReportTime) >= 1.0 or lastReportXP ~= delta then
                local grp = targetEntry and (targetEntry.groupData or targetEntry.duoData)
                local partnerBonus = grp and grp.predBonus or 0
                local baseEst = grp and math.max(0, delta - partnerBonus) or delta
                ReportFeedback(targetEntry, delta, 0, nil, partnerBonus, baseEst)
            end
        end
    end
    lastPlayerXP = currentXP
end

-- ----------------------------------------------------------------------------
-- Module Lifecycle, Event Registration & Zero-Overhead Sleep Mode
-- ----------------------------------------------------------------------------
local isSleeping = false

function XP:UpdateActiveState()
    local numMembers = GetNumGroupMembers and GetNumGroupMembers() or 0
    local inRaid = IsInRaid()
    local inInstance, instanceType = GetInstanceInfoSafe()
    local db = XP:GetDB()

    local shouldSleep = false

    if not db.enabled then
        shouldSleep = true
    elseif inRaid or instanceType == "raid" then
        shouldSleep = true
    elseif inInstance and instanceType ~= "party" then
        shouldSleep = true
    elseif numMembers > 5 then
        shouldSleep = true
    elseif numMembers >= 2 and not db.groupPredictor then
        shouldSleep = true
    end

    if shouldSleep then
        if not isSleeping then
            isSleeping = true
            XP:WatchTargetDeath(false)
            if xpHudFrame and not XP.isTestMode then
                xpHudFrame:Hide()
            end
            self:UnregisterEvent("PLAYER_TARGET_CHANGED")
            self:UnregisterEvent("UNIT_CLASSIFICATION_CHANGED")
            self:UnregisterEvent("UNIT_MAXHEALTH")
            self:UnregisterEvent("PLAYER_XP_UPDATE")
            self:UnregisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
        end
    else
        if isSleeping then
            isSleeping = false
            self:RegisterEvent("PLAYER_TARGET_CHANGED")
            self:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
            self:RegisterEvent("UNIT_MAXHEALTH")
            self:RegisterEvent("PLAYER_XP_UPDATE")
            self:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
            XP:UpdateHUD()
        else
            XP:UpdateHUD()
        end
    end
end

function XP:OnInitialize()
    self:RegisterEvent("PLAYER_LOGIN")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")
    self:RegisterEvent("PLAYER_LEVEL_UP")

    -- Register solo & group events
    self:RegisterEvent("PLAYER_TARGET_CHANGED")
    self:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
    self:RegisterEvent("UNIT_MAXHEALTH")
    self:RegisterEvent("PLAYER_XP_UPDATE")
    self:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")

    if IsLoggedIn and IsLoggedIn() then
        self:PLAYER_LOGIN()
    end
end

function XP:PLAYER_LOGIN()
    lastPlayerXP = UnitXP("player")
    XP:GetOrCreateHUD()
    XP:ApplyFontSettings()
    XP:UpdateActiveState()
end

function XP:PLAYER_ENTERING_WORLD()
    XP:UpdateActiveState()
end

function XP:GROUP_ROSTER_UPDATE()
    XP:UpdateActiveState()
end

function XP:PLAYER_TARGET_CHANGED()
    pcall(XP.UpdateHUD, XP)
end

function XP:UNIT_CLASSIFICATION_CHANGED(event, unit)
    if unit == "target" then
        pcall(XP.UpdateHUD, XP)
    end
end

function XP:UNIT_MAXHEALTH(event, unit)
    if unit == "target" then
        pcall(XP.UpdateHUD, XP)
    end
end

function XP:PLAYER_LEVEL_UP()
    lastPlayerXP = UnitXP("player")
    pcall(XP.UpdateHUD, XP)
end

-- ----------------------------------------------------------------------------
-- Slash Commands (/efxp)
-- ----------------------------------------------------------------------------
SLASH_EFXP1 = "/efxp"

SlashCmdList["EFXP"] = function(msg)
    local rawMsg = msg and msg:match("^%s*(.-)%s*$") or ""
    local cmd = rawMsg:match("^(%S+)")
    cmd = cmd and cmd:lower() or ""

    if cmd == "logs" or cmd == "testlog" or cmd == "testlogs" then
        local logs = XP:GetLogs()
        local total = #logs
        print(string.format("|cff00ccff[EFHelper XP]|r Recorded Test Kills: |cffffffff%d|r entries.", total))
        if total > 0 then
            local exactCount = 0
            local roundingCount = 0
            local totalAbsDiff = 0
            local partyKills = 0
            local soloKills = 0
            for _, l in ipairs(logs) do
                local d = math.abs(l.diff or 0)
                if d == 0 then
                    exactCount = exactCount + 1
                elseif d == 1 or (d <= 2 and l.isRested) then
                    roundingCount = roundingCount + 1
                end
                totalAbsDiff = totalAbsDiff + d
                if (l.partySize or 1) > 1 then
                    partyKills = partyKills + 1
                else
                    soloKills = soloKills + 1
                end
            end
            local exactPct = (exactCount / total) * 100
            local closePct = ((exactCount + roundingCount) / total) * 100
            local avgDiff = totalAbsDiff / total
            print(string.format("  Exact Matches: |cff00ff00%d/%d (%.1f%%)|r | Within Margin: |cff99ff33%d/%d (%.1f%%)|r | Avg |Diff|: |cffffd100%.2f|r",
                exactCount, total, exactPct, exactCount + roundingCount, total, closePct, avgDiff))
            if partyKills > 0 and soloKills > 0 then
                print(string.format("  Sample Breakdown: Party: |cffffffff%d|r | Solo: |cffffffff%d|r", partyKills, soloKills))
            end
            local last = logs[total]
            local partyLevels = (type(last.partyLevels) == "table") and table.concat(last.partyLevels, ",") or tostring(last.partyLevels or "?")
            local dngTag = last.isDungeon and " [Dungeon 0.4x]" or ""
            local restedTag = last.isRested and " [Rested 2x]" or ""
            local pSize = last.partySize or 1
            local pTag = (pSize > 1) and string.format(", Party %d [%s]", pSize, partyLevels) or " [Solo]"
            print(string.format("  Latest: %s (Lv %d%s%s%s) | Pred: %d XP | Act: %d XP (Diff: %+d)",
                last.mob, last.mobLevel, pTag, dngTag, restedTag, last.predTotal, last.actTotal, last.diff))
        end
    elseif cmd == "clearlogs" then
        XP:ClearLogs()
        print("|cff00ccff[EFHelper XP]|r Recorded test logs cleared.")
    else
        EFHelper:ToggleConfig(4)
    end
end
