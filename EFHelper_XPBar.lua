-- ----------------------------------------------------------------------------
-- EFHelper_XPBar.lua
-- Custom Experience Bar with Completed Quests Overlay, Clocks & Rate Forecasting
-- Replicates custom visual layout with Purple XP, Orange Quest XP & session stats.
-- ----------------------------------------------------------------------------
local addonName, addonTable = ...
local EFHelper = _G.EFHelper or addonTable
local XPBar = EFHelper:NewModule("XPBar", "AceEvent-3.0")
EFHelper.XPBar = XPBar
addonTable.XPBar = XPBar

local Utils = EFHelper.Utils
local UI = EFHelper.UI

-- ----------------------------------------------------------------------------
-- Database & Saved Variable Access
-- ----------------------------------------------------------------------------
function XPBar:GetDB()
    if EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.XPBar then
        return EFHelper.db.profile.XPBar
    end
    if EFHelperDB and EFHelperDB.XPBar then
        return EFHelperDB.XPBar
    end
    EFHelperDB = EFHelperDB or {}
    EFHelperDB.XPBar = EFHelperDB.XPBar or {
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
    }
    return EFHelperDB.XPBar
end

function XPBar:GetCharDB()
    EFHelperCharDB = EFHelperCharDB or {}
    EFHelperCharDB.XPBar = EFHelperCharDB.XPBar or {
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
    }
    return EFHelperCharDB.XPBar
end

function XPBar:IsEnabled()
    local db = self:GetDB()
    return db and db.enabled ~= false
end

-- ----------------------------------------------------------------------------
-- Active-Time Minute Ring Buffer (O(1) Rolling Window Engine)
-- ----------------------------------------------------------------------------
local RING_SIZE = 360 -- Supports rolling windows up to 6 hours (360 minutes)
local ringMinute = {}
local ringXP = {}
local runningWindowXP = 0
local lastEvictedMinute = -1

local function InitRingBuffer()
    for i = 1, RING_SIZE do
        ringMinute[i] = -1
        ringXP[i] = 0
    end
    runningWindowXP = 0
    lastEvictedMinute = -1
end

InitRingBuffer()

local function GetActiveSessionSec(charDB, now)
    if not charDB or not charDB.sessionStartTime then return 0 end
    local sessSec = math.max(0, now - charDB.sessionStartTime)
    local totalNeglected = charDB.neglectedSec or 0
    if charDB.isManuallyPaused and charDB.manualPauseStart then
        totalNeglected = totalNeglected + math.max(0, now - charDB.manualPauseStart)
    elseif charDB.isAutoPaused and charDB.lastXPTime then
        local currentIdle = math.max(0, now - charDB.lastXPTime)
        local currentNeglected = 360 + math.max(0, currentIdle - 600)
        totalNeglected = totalNeglected + currentNeglected
    end
    return math.max(0, sessSec - totalNeglected)
end

local function AddXPToRingBuffer(activeSec, delta)
    if not delta or delta <= 0 then return end
    local m = math.floor(activeSec / 60)
    local slot = (m % RING_SIZE) + 1

    if ringMinute[slot] ~= m then
        if ringMinute[slot] ~= -1 then
            runningWindowXP = math.max(0, runningWindowXP - (ringXP[slot] or 0))
        end
        ringMinute[slot] = m
        ringXP[slot] = 0
    end

    ringXP[slot] = (ringXP[slot] or 0) + delta
    runningWindowXP = runningWindowXP + delta
end

local function EvictExpiredRingBuckets(currentMinute, winMinutes)
    local expireLimit = currentMinute - winMinutes
    if expireLimit < lastEvictedMinute then
        lastEvictedMinute = expireLimit
        return
    end
    if expireLimit == lastEvictedMinute then
        return
    end

    if expireLimit - lastEvictedMinute >= RING_SIZE then
        InitRingBuffer()
        lastEvictedMinute = expireLimit
        return
    end

    for m = lastEvictedMinute + 1, expireLimit do
        local slot = (m % RING_SIZE) + 1
        if ringMinute[slot] == m then
            runningWindowXP = math.max(0, runningWindowXP - (ringXP[slot] or 0))
            ringMinute[slot] = -1
            ringXP[slot] = 0
        end
    end
    lastEvictedMinute = expireLimit
end

local function SaveRingSnapshot(charDB)
    if not charDB then return end
    local snap = {}
    for slot = 1, RING_SIZE do
        if ringMinute[slot] and ringMinute[slot] >= 0 and (ringXP[slot] or 0) > 0 then
            snap[#snap + 1] = ringMinute[slot]
            snap[#snap + 1] = ringXP[slot]
        end
    end
    charDB.ringSnapshot = snap
end

local function RestoreRingSnapshot(charDB)
    InitRingBuffer()
    if not charDB or not charDB.ringSnapshot then return end
    local snap = charDB.ringSnapshot
    for i = 1, #snap, 2 do
        local m = snap[i]
        local xp = snap[i + 1]
        if m and xp then
            local slot = (m % RING_SIZE) + 1
            ringMinute[slot] = m
            ringXP[slot] = xp
            runningWindowXP = runningWindowXP + xp
        end
    end
end

-- ----------------------------------------------------------------------------
-- String & Number Formatting Helpers
-- ----------------------------------------------------------------------------
local function FormatNumber(n)
    if not n then return "0" end
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(n)
    end
    local left, num, right = string.match(tostring(n), '^([^%d]*%d)(%d*)(.-)$')
    return left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
end

local function FormatDuration(seconds)
    if not seconds or seconds < 0 then return "0m" end
    if seconds < 60 then
        return string.format("%ds", math.floor(seconds))
    elseif seconds < 3600 then
        return string.format("%dm", math.floor(seconds / 60))
    elseif seconds < 86400 then
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        return string.format("%dh %dm", h, m)
    else
        local d = math.floor(seconds / 86400)
        local h = math.floor((seconds % 86400) / 3600)
        return string.format("%dd %dh", d, h)
    end
end

local function FormatXPHour(xpHour)
    if not xpHour or xpHour <= 0 then
        return "0 XP/Hour"
    elseif xpHour >= 1000000 then
        return string.format("%.1fM XP/Hour", xpHour / 1000000)
    elseif xpHour >= 1000 then
        return string.format("%.1fK XP/Hour", xpHour / 1000)
    else
        return string.format("%d XP/Hour", math.floor(xpHour))
    end
end

-- ----------------------------------------------------------------------------
-- Completed Quest XP Engine (Debounced Coalescing)
-- ----------------------------------------------------------------------------
local cachedQuestXP = 0
local cachedQuestCount = 0
local isQuestDirty = false
local questDebounceTimer = nil

function XPBar:CalculateCompletedQuests()
    local totalXP = 0
    local count = 0
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
                       or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0

    for i = 1, numEntries do
        local questID
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and not info.isHidden then
                questID = info.questID
            end
        elseif GetQuestLogTitle then
            local _, _, _, h, _, _, _, qid = GetQuestLogTitle(i)
            if not h then
                questID = qid
            end
        end

        if questID and questID > 0 then
            local isComplete = false
            if C_QuestLog and C_QuestLog.IsComplete then
                isComplete = C_QuestLog.IsComplete(questID)
            elseif C_QuestLog and C_QuestLog.ReadyForTurnIn then
                isComplete = C_QuestLog.ReadyForTurnIn(questID)
            elseif GetQuestLogTitle then
                local _, _, _, _, _, comp = GetQuestLogTitle(i)
                isComplete = comp == 1 or comp == true
            end

            if isComplete then
                count = count + 1
                local xp = 0
                if GetQuestLogRewardXP then
                    xp = GetQuestLogRewardXP(questID) or 0
                    if xp == 0 then
                        xp = GetQuestLogRewardXP(i) or 0
                    end
                end

                -- Fallback to Questie database if available and native returned 0
                if xp == 0 and _G.Questie and Questie.DB and Questie.DB.GetQuest then
                    local ok, qData = pcall(Questie.DB.GetQuest, Questie.DB, questID)
                    if ok and qData and qData.Experience then
                        xp = qData.Experience
                    end
                end

                totalXP = totalXP + xp
            end
        end
    end

    cachedQuestXP = totalXP
    cachedQuestCount = count
    return totalXP, count
end

function XPBar:GetCompletedQuestsBreakdown()
    local list = {}
    local numEntries = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
                       or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0

    for i = 1, numEntries do
        local questID, title
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(i)
            if info and not info.isHeader and not info.isHidden then
                questID = info.questID
                title = info.title
            end
        elseif GetQuestLogTitle then
            local t, _, _, h, _, _, _, qid = GetQuestLogTitle(i)
            if not h then
                questID = qid
                title = t
            end
        end

        if questID and questID > 0 then
            local isComplete = false
            if C_QuestLog and C_QuestLog.IsComplete then
                isComplete = C_QuestLog.IsComplete(questID)
            elseif C_QuestLog and C_QuestLog.ReadyForTurnIn then
                isComplete = C_QuestLog.ReadyForTurnIn(questID)
            elseif GetQuestLogTitle then
                local _, _, _, _, _, comp = GetQuestLogTitle(i)
                isComplete = comp == 1 or comp == true
            end

            if isComplete then
                local xp = 0
                if GetQuestLogRewardXP then
                    xp = GetQuestLogRewardXP(questID) or 0
                    if xp == 0 then
                        xp = GetQuestLogRewardXP(i) or 0
                    end
                end
                if xp == 0 and _G.Questie and Questie.DB and Questie.DB.GetQuest then
                    local ok, qData = pcall(Questie.DB.GetQuest, Questie.DB, questID)
                    if ok and qData and qData.Experience then
                        xp = qData.Experience
                    end
                end
                table.insert(list, { id = questID, title = title or ("Quest #" .. questID), xp = xp })
            end
        end
    end
    return list
end

function XPBar:RequestQuestUpdate()
    isQuestDirty = true
    if not questDebounceTimer then
        questDebounceTimer = C_Timer.After(0.25, function()
            questDebounceTimer = nil
            if isQuestDirty then
                isQuestDirty = false
                XPBar:CalculateCompletedQuests()
                XPBar:UpdateBarDisplay()
            end
        end)
    end
end

-- ----------------------------------------------------------------------------
-- Session & Level Persistence Across /reload
-- ----------------------------------------------------------------------------
local RELOAD_TIMEOUT_SECONDS = 900 -- 15 minute window for /reload or reconnects
local timePlayedPending = false

function XPBar:RequestTimePlayedSafe(delay)
    if timePlayedPending then return end
    timePlayedPending = true
    C_Timer.After(delay or 1.5, function()
        timePlayedPending = false
        RequestTimePlayed()
    end)
end

function XPBar:TogglePause()
    local charDB = self:GetCharDB()
    local now = time()
    if charDB.isManuallyPaused then
        charDB.isManuallyPaused = false
        if charDB.manualPauseStart then
            local pausedDuration = math.max(0, now - charDB.manualPauseStart)
            charDB.neglectedSec = (charDB.neglectedSec or 0) + pausedDuration
            charDB.manualPauseStart = nil
        end
        charDB.lastXPTime = now
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[EFHelper XPBar]|r Session tracker and XP rate |cff55ff55RESUMED|r.")
    else
        charDB.isManuallyPaused = true
        charDB.manualPauseStart = now
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[EFHelper XPBar]|r Session tracker and XP rate |cffffaa00PAUSED|r.")
    end
    self:UpdateClockDisplay(true)
end

function XPBar:InitSession()
    if self.sessionInitialized then return end
    local charDB = self:GetCharDB()
    local now = time()
    local currXP = UnitXP("player") or 0

    local isResume = charDB.lastHeartbeat and (now - charDB.lastHeartbeat) < RELOAD_TIMEOUT_SECONDS

    if isResume then
        -- Resuming session across /reload
        if not charDB.sessionStartTime then charDB.sessionStartTime = now end
        if not charDB.sessionGainedXP then charDB.sessionGainedXP = 0 end
        RestoreRingSnapshot(charDB)
    else
        -- Fresh gaming session: reset session clock and await authoritative /played
        charDB.sessionStartTime = now
        charDB.sessionGainedXP = 0
        charDB.sessionStartXP = currXP
        charDB.levelBasePlayed = nil
        charDB.levelDingSessionSec = 0
        charDB.isManuallyPaused = false
        charDB.manualPauseStart = nil
        charDB.neglectedSec = 0
        charDB.lastXPTime = now
        charDB.isAutoPaused = false
        charDB.ringSnapshot = nil
        InitRingBuffer()
    end
    -- Clean up legacy rollingHistory from SavedVariables if present
    charDB.rollingHistory = nil
    charDB.lastHeartbeat = now

    self.lastXP = currXP
    self.lastMaxXP = UnitXPMax("player") or 0
    self.sessionInitialized = true

    -- Query /played at the start of each fresh session or if levelBasePlayed is not yet calibrated
    if not isResume or not charDB.levelBasePlayed then
        self:RequestTimePlayedSafe(1.5)
    end
end

function XPBar:ResetSession()
    local charDB = self:GetCharDB()
    local now = time()
    local sessSec = math.max(0, now - (charDB.sessionStartTime or now))
    local dingOffset = charDB.levelDingSessionSec or 0
    local sessAfterDing = math.max(0, sessSec - dingOffset)

    -- Roll current session's level progress into levelBasePlayed before resetting session clocks
    if charDB.levelBasePlayed then
        charDB.levelBasePlayed = charDB.levelBasePlayed + sessAfterDing
    end
    charDB.levelDingSessionSec = 0

    charDB.sessionStartTime = now
    charDB.sessionGainedXP = 0
    charDB.sessionStartXP = UnitXP("player") or 0
    charDB.lastHeartbeat = now
    charDB.isManuallyPaused = false
    charDB.manualPauseStart = nil
    charDB.neglectedSec = 0
    charDB.lastXPTime = now
    charDB.isAutoPaused = false
    charDB.ringSnapshot = nil
    charDB.rollingHistory = nil
    InitRingBuffer()
    self.lastXP = UnitXP("player") or 0
    self.lastMaxXP = UnitXPMax("player") or 0
    self.sessionInitialized = true

    self:UpdateClockDisplay(true)
    self:UpdateBarDisplay()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ffff[EFHelper XPBar]|r Session tracker and XP rate have been reset.")
end

-- ----------------------------------------------------------------------------
-- UI Frame Construction & Layering
-- ----------------------------------------------------------------------------
local barFrame = nil

function XPBar:SavePosition(frame)
    local f = frame or barFrame
    if not f then return end
    local point, _, relPoint, x, y = f:GetPoint()
    if point and relPoint then
        local p = { point, "UIParent", relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
        local db = self:GetDB()
        db.pos = p
        if EFHelperCharDB then
            EFHelperCharDB.xpBarPoint = p
        end
    end
end

function XPBar:RestorePosition(frame)
    local f = frame or barFrame
    if not f then return end
    local db = self:GetDB()
    local p = db.pos or (EFHelperCharDB and EFHelperCharDB.xpBarPoint)
    f:ClearAllPoints()
    if p and type(p) == "table" and p[1] and p[3] and p[4] and p[5] then
        f:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    end
end

function XPBar:GetOrCreateBarFrame()
    if barFrame then return barFrame end
    local db = self:GetDB()

    -- Main Container Frame with 1px border
    local f = CreateFrame("Frame", "EFHelperXPBarFrame", UIParent, "BackdropTemplate")
    f:SetSize(db.width or 480, db.height or 18)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScale(db.scale or 1.0)
    XPBar:RestorePosition(f)

    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    -- Dark navy/charcoal background and black 1px border matching screenshot
    f:SetBackdropColor(0.04, 0.08, 0.14, 0.95)
    f:SetBackdropBorderColor(0.0, 0.0, 0.0, 1.0)

    -- Drag Handlers
    f:SetScript("OnDragStart", function(self)
        local cfg = XPBar:GetDB()
        if not cfg.locked then
            self:StartMoving()
        end
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        XPBar:SavePosition(self)
    end)

    -- Status Bar 1: Completed Quests Bar (Orange / Amber #f59e0b)
    -- Extends from 0 to (currentXP + completedQuestXP)
    local questBar = CreateFrame("StatusBar", nil, f)
    questBar:SetAllPoints(f)
    questBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    questBar:SetStatusBarColor(0.96, 0.58, 0.04, 1.0)
    questBar:SetMinMaxValues(0, 1)
    questBar:SetValue(0)
    questBar:SetFrameLevel(f:GetFrameLevel() + 1)
    f.questBar = questBar

    -- Status Bar 2: Current XP Bar (Purple / Lavender #8060ff)
    -- Rendered directly on top of questBar so purple covers [0..currXP],
    -- and orange automatically shows from [currXP .. currXP + questXP]
    local currBar = CreateFrame("StatusBar", nil, f)
    currBar:SetAllPoints(f)
    currBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    currBar:SetStatusBarColor(0.50, 0.38, 1.00, 1.0)
    currBar:SetMinMaxValues(0, 1)
    currBar:SetValue(0)
    currBar:SetFrameLevel(f:GetFrameLevel() + 2)
    f.currBar = currBar

    -- Text Overlay Frame (ensures text sits cleanly above both fill bars)
    local textOverlay = CreateFrame("Frame", nil, f)
    textOverlay:SetAllPoints(f)
    textOverlay:SetFrameLevel(f:GetFrameLevel() + 5)
    f.textOverlay = textOverlay

    -- Inside-bar text: Left (Character Level)
    local barTextLeft = textOverlay:CreateFontString(nil, "OVERLAY")
    if UI and UI.SetupFontString then
        UI.SetupFontString(barTextLeft, 12, "OUTLINE", "Expressway")
    end
    barTextLeft:SetPoint("LEFT", textOverlay, "LEFT", 6, 0)
    barTextLeft:SetJustifyH("LEFT")
    barTextLeft:SetTextColor(1, 1, 1, 1)
    f.barTextLeft = barTextLeft

    -- Inside-bar text: Center (Current / Max (Remaining))
    local barTextCenter = textOverlay:CreateFontString(nil, "OVERLAY")
    if UI and UI.SetupFontString then
        UI.SetupFontString(barTextCenter, 12, "OUTLINE", "Expressway")
    end
    barTextCenter:SetPoint("CENTER", textOverlay, "CENTER", 0, 0)
    barTextCenter:SetJustifyH("CENTER")
    barTextCenter:SetTextColor(1, 1, 1, 1)
    f.barTextCenter = barTextCenter

    -- Inside-bar text: Right (Current% (Total%))
    local barTextRight = textOverlay:CreateFontString(nil, "OVERLAY")
    if UI and UI.SetupFontString then
        UI.SetupFontString(barTextRight, 12, "OUTLINE", "Expressway")
    end
    barTextRight:SetPoint("RIGHT", textOverlay, "RIGHT", -6, 0)
    barTextRight:SetJustifyH("RIGHT")
    barTextRight:SetTextColor(1, 1, 1, 1)
    f.barTextRight = barTextRight

    -- Top Row: Left (Time this level: Xm)
    local topTextLeft = f:CreateFontString(nil, "OVERLAY")
    if UI and UI.SetupFontString then
        UI.SetupFontString(topTextLeft, 11, "OUTLINE", "Expressway")
    end
    topTextLeft:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 1, 3)
    topTextLeft:SetJustifyH("LEFT")
    topTextLeft:SetTextColor(1, 1, 1, 1)
    f.topTextLeft = topTextLeft

    -- Top Row: Right (Time this session: Xh Ym)
    local topTextRight = f:CreateFontString(nil, "OVERLAY")
    if UI and UI.SetupFontString then
        UI.SetupFontString(topTextRight, 11, "OUTLINE", "Expressway")
    end
    topTextRight:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -1, 3)
    topTextRight:SetJustifyH("RIGHT")
    topTextRight:SetTextColor(1, 1, 1, 1)
    f.topTextRight = topTextRight

    -- Bottom Row: Left (Leveling in: Xm (YK XP/Hour))
    local bottomTextLeft = f:CreateFontString(nil, "OVERLAY")
    if UI and UI.SetupFontString then
        UI.SetupFontString(bottomTextLeft, 11, "OUTLINE", "Expressway")
    end
    bottomTextLeft:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 1, -3)
    bottomTextLeft:SetJustifyH("LEFT")
    bottomTextLeft:SetTextColor(1, 1, 1, 1)
    f.bottomTextLeft = bottomTextLeft

    -- Bottom Row: Right (Completed: 17.5% - Rested: 0.3%)
    local bottomTextRight = f:CreateFontString(nil, "OVERLAY")
    if UI and UI.SetupFontString then
        UI.SetupFontString(bottomTextRight, 11, "OUTLINE", "Expressway")
    end
    bottomTextRight:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -1, -3)
    bottomTextRight:SetJustifyH("RIGHT")
    bottomTextRight:SetTextColor(1, 1, 1, 1)
    f.bottomTextRight = bottomTextRight

    -- Interactive Tooltip Handlers (Streamlined: Completed Quests only)
    f:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP", 0, 14)
        GameTooltip:ClearLines()

        local maxXP = UnitXPMax("player") or 0
        if maxXP <= 0 then maxXP = 1 end
        local questXP = cachedQuestXP or 0
        local questPct = (questXP / maxXP) * 100
        local questList = XPBar:GetCompletedQuestsBreakdown()
        local numCompleted = #questList

        -- Header: Completed Quests count & total XP / %
        GameTooltip:AddDoubleLine(
            string.format("|cffff9900Completed Quests (%d)|r", numCompleted),
            string.format("|cffff9900+%s XP (%.1f%%)|r", FormatNumber(questXP), questPct),
            1, 1, 1, 1, 1, 1
        )

        -- Itemized list capped at 5 entries
        if numCompleted > 0 then
            local showCount = math.min(numCompleted, 5)
            for i = 1, showCount do
                local q = questList[i]
                local rewardStr = (q.xp and q.xp > 0) and string.format("+%s XP", FormatNumber(q.xp)) or "Ready"
                GameTooltip:AddDoubleLine(
                    "  • " .. (q.title or "Unknown Quest"),
                    rewardStr,
                    0.85, 0.85, 0.85, 1, 0.85, 0.2
                )
            end
            if numCompleted > 5 then
                GameTooltip:AddLine(string.format("  |cff888888... and %d more|r", numCompleted - 5))
            end
        else
            GameTooltip:AddLine("  |cff888888No completed quests to turn in|r")
        end

        -- Footer: Short lock/drag/pause tip
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffd100Shift-Click|r: Pause/Resume session tracker", 0.8, 0.8, 0.8)
        local cfg = XPBar:GetDB()
        if cfg.locked then
            GameTooltip:AddLine("|cff777777Right-click to Unlock frame|r", 0.6, 0.6, 0.6)
        else
            GameTooltip:AddLine("|cff777777Drag to Move | Right-click to Lock frame|r", 0.6, 0.6, 0.6)
        end

        GameTooltip:Show()
    end)

    f:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    f:SetScript("OnMouseUp", function(self, button)
        if IsShiftKeyDown() then
            XPBar:TogglePause()
            if self:IsMouseOver() then
                self:GetScript("OnEnter")(self)
            end
            return
        end
        if button == "RightButton" then
            local cfg = XPBar:GetDB()
            cfg.locked = not cfg.locked
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ffff[EFHelper XPBar]|r Frame is now %s.", cfg.locked and "|cffff5555Locked|r" or "|cff55ff55Unlocked|r"))
            if self:IsMouseOver() then
                self:GetScript("OnEnter")(self)
            end
        end
    end)

    barFrame = f
    XPBar.frame = f
    return f
end

-- ----------------------------------------------------------------------------
-- Visual Updates & Clock Ticker
-- ----------------------------------------------------------------------------
local tickerHandle = nil
local lastLevelMin = -1
local lastSessionMin = -1
local lastPauseState = nil
local lastBottomLeftText = nil
local lastBottomRightText = nil

function XPBar:StartClockTicker()
    if tickerHandle then return end
    tickerHandle = C_Timer.NewTicker(2.0, function()
        if not XPBar:IsEnabled() then return end
        XPBar:OnClockTick()
    end)
end

function XPBar:StopClockTicker()
    if tickerHandle then
        tickerHandle:Cancel()
        tickerHandle = nil
    end
end

function XPBar:OnClockTick()
    local now = time()
    local charDB = self:GetCharDB()

    -- 30-Second periodic crash-resilient heartbeat and snapshot
    if not charDB.lastHeartbeat or (now - charDB.lastHeartbeat) >= 30 then
        charDB.lastHeartbeat = now
        SaveRingSnapshot(charDB)
    end

    -- Autopause detection (10 minutes with no XP events)
    local db = self:GetDB()
    if db.autoPauseEnabled ~= false and not charDB.isManuallyPaused then
        local lastXP = charDB.lastXPTime or charDB.sessionStartTime or now
        if not charDB.isAutoPaused and (now - lastXP) >= 600 then
            charDB.isAutoPaused = true
        end
    end

    self:UpdateClockDisplay(false, now)
end

function XPBar:UpdateClockDisplay(force, nowTime)
    if not barFrame or not barFrame:IsShown() then return end
    local now = nowTime or time()
    local charDB = self:GetCharDB()
    local db = self:GetDB()

    -- 1. Session time & pause status indicator
    local sessSec = math.max(0, now - (charDB.sessionStartTime or now))
    local sessMin = math.floor(sessSec / 60)
    local currentPauseState = (charDB.isManuallyPaused and "PAUSED") or (charDB.isAutoPaused and "IDLE") or "ACTIVE"

    if force or sessMin ~= lastSessionMin or currentPauseState ~= lastPauseState then
        lastSessionMin = sessMin
        lastPauseState = currentPauseState
        local pauseTag = ""
        if currentPauseState == "PAUSED" then
            pauseTag = " |cffffaa00[PAUSED]|r"
        elseif currentPauseState == "IDLE" then
            pauseTag = " |cff888888[IDLE]|r"
        end
        barFrame.topTextRight:SetText("Time this session: " .. FormatDuration(sessSec) .. pauseTag)
    end

    -- 2. Level time (pure in-game time: /played baseline + session duration)
    if charDB.levelBasePlayed then
        local dingOffset = charDB.levelDingSessionSec or 0
        local sessAfterDing = math.max(0, sessSec - dingOffset)
        local lvlSec = math.max(0, charDB.levelBasePlayed + sessAfterDing)
        local lvlMin = math.floor(lvlSec / 60)
        if force or lvlMin ~= lastLevelMin then
            lastLevelMin = lvlMin
            barFrame.topTextLeft:SetText("Time this level: " .. FormatDuration(lvlSec))
        end
    else
        if force or lastLevelMin ~= -1 then
            lastLevelMin = -1
            barFrame.topTextLeft:SetText("Time this level: --")
        end
    end

    -- 3. Leveling in countdown & XP/Hour
    local rawMaxXP = UnitXPMax("player") or 0
    if rawMaxXP <= 0 then
        if force or lastBottomLeftText ~= "Max Level reached" then
            lastBottomLeftText = "Max Level reached"
            barFrame.bottomTextLeft:SetText("Max Level reached")
        end
        return
    end

    local currXP = UnitXP("player") or 0
    local maxXP = rawMaxXP
    local remXP = math.max(0, maxXP - currXP)

    -- Effective active duration calculation (accounting for manual pauses and autopause neglect)
    local activeDuration = math.max(1, GetActiveSessionSec(charDB, now))
    local xpHour = 0

    if db.rateMode == "total" then
        local sessXP = charDB.sessionGainedXP or 0
        xpHour = (sessXP / activeDuration) * 3600
    else
        -- Rolling Window Mode (1h to 6h, default 2h) via O(1) Minute Ring Buffer
        local winHours = db.rollingWindowHours or 2.0
        local winMinutes = math.max(60, math.min(360, math.floor(winHours * 60 + 0.5)))
        local winSec = winMinutes * 60

        local currentMinute = math.floor(activeDuration / 60)
        EvictExpiredRingBuckets(currentMinute, winMinutes)

        local effectiveWinDuration = math.min(winSec, activeDuration)
        xpHour = (runningWindowXP / math.max(60, effectiveWinDuration)) * 3600
    end

    local dingStr = "--"
    if charDB.isManuallyPaused then
        dingStr = "--"
    elseif xpHour > 0 and remXP > 0 then
        local secLeft = (remXP / xpHour) * 3600
        if secLeft > 356400 then
            dingStr = ">99h"
        else
            dingStr = FormatDuration(secLeft)
        end
    elseif remXP == 0 then
        dingStr = "Ready!"
    end

    local rateSuffix = ""
    if charDB.isManuallyPaused then
        rateSuffix = " |cffffaa00(Paused)|r"
    elseif charDB.isAutoPaused then
        rateSuffix = " |cff888888(Idle)|r"
    end

    local bottomLeftStr = string.format("Leveling in: %s (%s)%s", dingStr, FormatXPHour(xpHour), rateSuffix)
    if force or bottomLeftStr ~= lastBottomLeftText then
        lastBottomLeftText = bottomLeftStr
        barFrame.bottomTextLeft:SetText(bottomLeftStr)
    end
end

function XPBar:UpdateBarDisplay()
    if not barFrame then return end
    local db = self:GetDB()
    if not db.enabled then
        barFrame:Hide()
        return
    end
    barFrame:Show()

    local charLevel = UnitLevel("player") or 1
    local rawMaxXP = UnitXPMax("player") or 0
    local questXP = cachedQuestXP or 0

    if rawMaxXP <= 0 then
        barFrame.currBar:SetMinMaxValues(0, 1)
        barFrame.currBar:SetValue(1)
        barFrame.questBar:SetMinMaxValues(0, 1)
        barFrame.questBar:SetValue(1)
        barFrame.barTextLeft:SetFormattedText("Level %d", charLevel)
        barFrame.barTextCenter:SetText("Max Level")
        barFrame.barTextRight:SetText("100.0%")
        barFrame.bottomTextLeft:SetText("Max Level reached")
        barFrame.bottomTextRight:SetFormattedText("Completed Quests: |cffff9900%d|r", cachedQuestCount)
        self:UpdateClockDisplay(true)
        return
    end

    local currXP = UnitXP("player") or 0
    local maxXP = rawMaxXP
    local remXP = math.max(0, maxXP - currXP)
    local restedXP = GetXPExhaustion() or 0

    -- 1. Purple current XP bar
    barFrame.currBar:SetMinMaxValues(0, maxXP)
    barFrame.currBar:SetValue(currXP)

    -- 2. Orange quest overlay bar
    local totalWithQuests = math.min(currXP + questXP, maxXP)
    barFrame.questBar:SetMinMaxValues(0, maxXP)
    barFrame.questBar:SetValue(totalWithQuests)

    -- 3. Inside bar text
    barFrame.barTextLeft:SetFormattedText("Level %d", charLevel)
    barFrame.barTextCenter:SetFormattedText("%s / %s (%s)",
        FormatNumber(currXP),
        FormatNumber(maxXP),
        FormatNumber(remXP)
    )

    local currPct = (currXP / maxXP) * 100
    local questPct = (questXP / maxXP) * 100
    local totalPct = currPct + questPct
    barFrame.barTextRight:SetFormattedText("%.1f%% (%.1f%%)", currPct, totalPct)

    -- 4. Context-Aware Bottom Right Status (cleans up redundant % and 0% Rested clutter)
    local bottomRightStr = ""
    if restedXP > 0 then
        local restedPct = (restedXP / maxXP) * 100
        if questXP > 0 then
            bottomRightStr = string.format("Quests: |cffff9900%d|r - Rested: |cff4da6ff%.1f%%|r", cachedQuestCount, restedPct)
        else
            bottomRightStr = string.format("Rested: |cff4da6ff%.1f%%|r", restedPct)
        end
    elseif questXP > 0 then
        bottomRightStr = string.format("Quests Ready: |cffff9900%d|r (+%.1f%%)", cachedQuestCount, questPct)
    else
        bottomRightStr = ""
    end

    if force or bottomRightStr ~= lastBottomRightText then
        lastBottomRightText = bottomRightStr
        barFrame.bottomTextRight:SetText(bottomRightStr)
    end

    -- 5. Clocks update
    self:UpdateClockDisplay(true)
end

function XPBar:ApplyLayout()
    local f = self:GetOrCreateBarFrame()
    local db = self:GetDB()
    f:SetSize(db.width or 480, db.height or 18)
    f:SetScale(db.scale or 1.0)
    self:RestorePosition(f)
end

function XPBar:UpdateBlizzardBarVisibility()
    local db = self:GetDB()
    local hide = db.hideBlizzardBar and db.enabled
    if StatusTrackingBarManager then
        if hide then
            StatusTrackingBarManager:Hide()
            StatusTrackingBarManager:SetAlpha(0)
        else
            StatusTrackingBarManager:Show()
            StatusTrackingBarManager:SetAlpha(1)
        end
    end
    if MainMenuExpBar then
        if hide then
            MainMenuExpBar:Hide()
            MainMenuExpBar:SetAlpha(0)
        else
            MainMenuExpBar:Show()
            MainMenuExpBar:SetAlpha(1)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Lifecycle & Event Handlers
-- ----------------------------------------------------------------------------
function XPBar:OnInitialize()
    self:GetDB()
    self:GetCharDB()
end

function XPBar:OnEnable()
    local db = self:GetDB()
    if not db.enabled then return end

    self:InitSession()
    self:GetOrCreateBarFrame():Show()
    self:ApplyLayout()
    self:UpdateBlizzardBarVisibility()
    self:CalculateCompletedQuests()
    self:UpdateBarDisplay()
    self:StartClockTicker()

    self:RegisterEvent("PLAYER_XP_UPDATE")
    self:RegisterEvent("PLAYER_LEVEL_UP")
    self:RegisterEvent("TIME_PLAYED_MSG")
    self:RegisterEvent("UPDATE_EXHAUSTION")
    self:RegisterEvent("QUEST_LOG_UPDATE")
    self:RegisterEvent("QUEST_WATCH_UPDATE")
    self:RegisterEvent("QUEST_TURNED_IN")
    self:RegisterEvent("QUEST_ACCEPTED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_LOGOUT")
end

function XPBar:OnDisable()
    self:StopClockTicker()
    if barFrame then barFrame:Hide() end
    self:UnregisterAllEvents()
    self:UpdateBlizzardBarVisibility()
end

function XPBar:PLAYER_ENTERING_WORLD()
    self:InitSession()
    self:RequestQuestUpdate()
    self:UpdateBarDisplay()
    self:UpdateBlizzardBarVisibility()
end

function XPBar:PLAYER_XP_UPDATE(event, unit)
    if unit and unit ~= "player" then return end
    local currXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 0
    local charDB = self:GetCharDB()
    local now = time()

    if self.lastXP then
        local delta = 0
        if currXP >= self.lastXP then
            delta = currXP - self.lastXP
        elseif self.lastMaxXP and self.lastMaxXP > 0 then
            -- Ding rollover: XP to finish previous level + current progress into new level
            delta = (self.lastMaxXP - self.lastXP) + currXP
        end

        if delta > 0 then
            charDB.sessionGainedXP = (charDB.sessionGainedXP or 0) + delta

            -- If autopaused, clear autopause and deduct neglected idle time (6m + excess)
            if charDB.isAutoPaused and charDB.lastXPTime then
                local totalIdle = math.max(0, now - charDB.lastXPTime)
                local neglectedThisIdle = 360 + math.max(0, totalIdle - 600)
                charDB.neglectedSec = (charDB.neglectedSec or 0) + neglectedThisIdle
                charDB.isAutoPaused = false
            end

            local activeSec = GetActiveSessionSec(charDB, now)
            AddXPToRingBuffer(activeSec, delta)

            charDB.lastXPTime = now
            charDB.lastHeartbeat = now
            SaveRingSnapshot(charDB)
        end
    end
    self.lastXP = currXP
    self.lastMaxXP = maxXP
    self:UpdateBarDisplay()
end

function XPBar:TIME_PLAYED_MSG(event, totalTimePlayed, timePlayedThisLevel)
    if not timePlayedThisLevel or type(timePlayedThisLevel) ~= "number" then return end
    local charDB = self:GetCharDB()
    local now = time()
    local sessSec = math.max(0, now - (charDB.sessionStartTime or now))
    local dingOffset = charDB.levelDingSessionSec or 0
    local sessAfterDing = math.max(0, sessSec - dingOffset)

    -- Synchronize baseline with server: levelBasePlayed + sessAfterDing == timePlayedThisLevel
    charDB.levelBasePlayed = math.max(0, timePlayedThisLevel - sessAfterDing)

    self:UpdateClockDisplay(true)
end

function XPBar:PLAYER_LEVEL_UP(event, newLevel)
    local charDB = self:GetCharDB()
    local now = time()
    local sessSec = math.max(0, now - (charDB.sessionStartTime or now))

    -- Reset level played tracker for the new level
    charDB.levelBasePlayed = 0
    charDB.levelDingSessionSec = sessSec

    local currXP = UnitXP("player") or 0
    local maxXP = UnitXPMax("player") or 0

    if self.lastXP and self.lastMaxXP and self.lastMaxXP > 0 and currXP < self.lastXP then
        -- Ding rollover if PLAYER_LEVEL_UP fired before PLAYER_XP_UPDATE
        local delta = (self.lastMaxXP - self.lastXP) + currXP
        if delta > 0 then
            charDB.sessionGainedXP = (charDB.sessionGainedXP or 0) + delta
            if charDB.isAutoPaused and charDB.lastXPTime then
                local totalIdle = math.max(0, now - charDB.lastXPTime)
                local neglectedThisIdle = 360 + math.max(0, totalIdle - 600)
                charDB.neglectedSec = (charDB.neglectedSec or 0) + neglectedThisIdle
                charDB.isAutoPaused = false
            end
            local activeSec = GetActiveSessionSec(charDB, now)
            AddXPToRingBuffer(activeSec, delta)

            charDB.lastXPTime = now
            charDB.lastHeartbeat = now
            SaveRingSnapshot(charDB)
        end
    end

    self.lastXP = currXP
    self.lastMaxXP = maxXP
    self:RequestQuestUpdate()
    self:UpdateBarDisplay()
    self:UpdateClockDisplay(true)
end

function XPBar:UPDATE_EXHAUSTION()
    if not barFrame then return end
    self:UpdateBarDisplay()
end

function XPBar:QUEST_LOG_UPDATE()
    self:RequestQuestUpdate()
end

function XPBar:QUEST_WATCH_UPDATE()
    self:RequestQuestUpdate()
end

function XPBar:QUEST_TURNED_IN()
    self:RequestQuestUpdate()
end

function XPBar:QUEST_ACCEPTED()
    self:RequestQuestUpdate()
end

function XPBar:PLAYER_LOGOUT()
    local charDB = self:GetCharDB()
    charDB.lastHeartbeat = time()
    SaveRingSnapshot(charDB)
end
