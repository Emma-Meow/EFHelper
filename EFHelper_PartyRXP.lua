-- ----------------------------------------------------------------------------
-- EFHelper_PartyRXP.lua
-- Live Party RestedXP Step & Objective Tracker, Group Remaining Calculator,
-- 1-Click EFHRXP Mob Tagging & Town-Cycle Quest Alignment / Auto-Share
-- ----------------------------------------------------------------------------
local addonName, addonTable = ...
local EFHelper = _G.EFHelper or addonTable
if EFHelper.PartyRXP then return end
local PartyRXP = EFHelper:NewModule("PartyRXP", "AceEvent-3.0")
EFHelper.PartyRXP = PartyRXP
addonTable.PartyRXP = PartyRXP

local Utils = EFHelper.Utils
local UI = EFHelper.UI

local COMM_PREFIX = "EFH_RXP"
local BROADCAST_DEBOUNCE = 0.75
local MAX_HUD_ROWS = 28
local CUSTOM_QUEST_FADE_SEC = 180
local TOWN_EXIT_SETTLE_SEC = 8.0

local function GetRXPAddon()
    if LibStub then
        local ace = LibStub("AceAddon-3.0", true)
        if ace then
            local addon = ace:GetAddon("RXPGuides", true)
            if addon and type(addon.SetStep) == "function" then
                return addon
            end
            if addon then return addon end
        end
    end
    return nil
end
PartyRXP.GetRXPAddon = GetRXPAddon

PartyRXP.isTestMode = false
PartyRXP.partyState = {}
PartyRXP.localState = {
    guide = "",
    step = nil,
    category = "TRAVEL",
    progress = "",
    isTownCandidate = false,
    isTownCycle = false,
    isCombatStep = false,
    objectives = {},
}

-- Town-Cycle Quest Alignment state (Quest Log Diff architecture)
PartyRXP.inTownCycle = false
PartyRXP.localInTown = false
PartyRXP.townExitStep = nil
PartyRXP.preTownQuestSnapshot = {} -- [questID] = true (quest IDs present in log BEFORE town cycle began)
PartyRXP.localTownQuests = {}      -- [questID] = { id, title, pushable } (computed via currentLog \ preTownQuestSnapshot)
PartyRXP.partyTownQuests = {}      -- [senderKey] = { [questID] = { id, title, pushable, sender } }
PartyRXP.missedTownQuests = {}     -- [questID] = { id, title, sender, pushable }

-- Dynamic Unlisted / Custom Quest Tracker (Guide-Diff + Zone Match + All-Party-Have-It + 3m Fade)
PartyRXP.questProgressSnapshot = {} -- [questID] = totalFulfilledCount
PartyRXP.activeCustomQuests = {}    -- [questID] = { id, title, expiresAt, localObjectives = {}, partyObjectives = {} }
PartyRXP._cachedGuideKey = nil
PartyRXP._cachedGuideQuestIDs = {}

local lastSentPayload = nil
local broadcastPending = false

-- ----------------------------------------------------------------------------
-- Database Access
-- ----------------------------------------------------------------------------
function PartyRXP:GetDB()
    if EFHelper.db and EFHelper.db.profile then
        if not EFHelper.db.profile.PartyRXP then
            EFHelper.db.profile.PartyRXP = {
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
            }
        else
            local db = EFHelper.db.profile.PartyRXP
            if db.enabled == nil then db.enabled = true end
            if db.showHUD == nil then db.showHUD = true end
            if db.showSelf == nil then db.showSelf = true end
            if db.showGroupRemaining == nil then db.showGroupRemaining = true end
            if db.clickToTag == nil then db.clickToTag = true end
            if db.townCycleSync == nil then db.townCycleSync = true end
            if db.autoShareTownQuests == nil then db.autoShareTownQuests = true end
            if db.scale == nil then db.scale = 100 end
        end
        return EFHelper.db.profile.PartyRXP
    end
    return {
        enabled = true,
        showHUD = true,
        showSelf = true,
        showGroupRemaining = true,
        clickToTag = true,
        townCycleSync = true,
        autoShareTownQuests = true,
        scale = 100,
        locked = false,
    }
end

-- ----------------------------------------------------------------------------
-- Helpers & Sanitization
-- ----------------------------------------------------------------------------
local function NormalizeShortName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local short = name:match("^([^%-]+)") or name
    short = Utils.Trim(short)
    return (short ~= "") and short or nil
end

local function CleanField(str, maxLen)
    if type(str) ~= "string" then return "" end
    local s = str:gsub("[|^~]", " "):gsub("[\r\n]+", " "):gsub("%s+", " ")
    s = Utils.Trim(s)
    if maxLen and #s > maxLen then
        s = s:sub(1, maxLen)
    end
    return s
end

local function FindPartyUnitByShortName(shortLower)
    if not shortLower then return nil end
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local uShort = NormalizeShortName(Utils.GetUnitName(unit))
            if uShort and uShort:lower() == shortLower then
                return unit
            end
        end
    end
    return nil
end

local function GetLocalXPPercent()
    local cur = UnitXP and UnitXP("player") or 0
    local max = UnitXPMax and UnitXPMax("player") or 0
    if max and max > 0 then
        return math.floor((cur / max) * 100 + 0.5)
    end
    return 0
end

local function IsInDungeonOrInstance()
    if not IsInInstance then return false end
    local inInstance, instanceType = IsInInstance()
    return (inInstance and (instanceType == "party" or instanceType == "raid" or instanceType == "pvp" or instanceType == "arena")) and true or false
end

-- ----------------------------------------------------------------------------
-- Quest Log Inspection & Class/Profession Header Filtering
-- ----------------------------------------------------------------------------
local IGNORED_QUEST_HEADERS = {
    ["warrior"] = true, ["paladin"] = true, ["hunter"] = true, ["rogue"] = true,
    ["priest"] = true, ["shaman"] = true, ["mage"] = true, ["warlock"] = true,
    ["druid"] = true, ["death knight"] = true, ["monk"] = true, ["demon hunter"] = true,
    ["evoker"] = true, ["class"] = true, ["professions"] = true, ["cooking"] = true,
    ["first aid"] = true, ["fishing"] = true, ["alchemy"] = true, ["blacksmithing"] = true,
    ["enchanting"] = true, ["engineering"] = true, ["herbalism"] = true, ["inscription"] = true,
    ["jewelcrafting"] = true, ["leatherworking"] = true, ["mining"] = true, ["skinning"] = true,
    ["tailoring"] = true, ["archaeology"] = true, ["battle pets"] = true, ["seasonal"] = true,
}

if _G.LOCALIZED_CLASS_NAMES_MALE then
    for _, locName in pairs(_G.LOCALIZED_CLASS_NAMES_MALE) do
        if type(locName) == "string" then IGNORED_QUEST_HEADERS[locName:lower()] = true end
    end
end
if _G.LOCALIZED_CLASS_NAMES_FEMALE then
    for _, locName in pairs(_G.LOCALIZED_CLASS_NAMES_FEMALE) do
        if type(locName) == "string" then IGNORED_QUEST_HEADERS[locName:lower()] = true end
    end
end

local function IsIgnoredClassOrProfHeader(header)
    if type(header) ~= "string" or header == "" then return false end
    return IGNORED_QUEST_HEADERS[header:lower()] == true
end

local function IsLogEntryPushable(questID, logIndex)
    if C_QuestLog and C_QuestLog.IsPushableQuest then
        return C_QuestLog.IsPushableQuest(questID) and true or false
    elseif GetQuestLogPushable then
        if SelectQuestLogEntry and logIndex then pcall(SelectQuestLogEntry, logIndex) end
        local ok, p = pcall(GetQuestLogPushable, logIndex)
        if not ok or p == nil then
            ok, p = pcall(GetQuestLogPushable)
        end
        return (ok and p) and true or false
    end
    return false
end

local function ForEachQuestInLog(callback)
    local currentHeader = ""
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local numEntries = C_QuestLog.GetNumQuestLogEntries() or 0
        for i = 1, numEntries do
            local info = C_QuestLog.GetInfo(i)
            if info then
                if info.isHeader then
                    currentHeader = info.title or ""
                else
                    local qID = tonumber(info.questID)
                    if qID and qID > 0 then
                        if callback(qID, info.title or ("Quest #" .. tostring(qID)), currentHeader, i) == true then
                            return
                        end
                    end
                end
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local numEntries = GetNumQuestLogEntries() or 0
        for i = 1, numEntries do
            local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
            if isHeader then
                currentHeader = title or ""
            else
                local qID = tonumber(questID)
                if qID and qID > 0 then
                    if callback(qID, title or ("Quest #" .. tostring(qID)), currentHeader, i) == true then
                        return
                    end
                end
            end
        end
    end
end

local function GetQuestMetadataFromLog(targetQuestID)
    targetQuestID = tonumber(targetQuestID)
    if not targetQuestID or targetQuestID <= 0 then return nil end

    local found = nil
    ForEachQuestInLog(function(qID, title, header, logIndex)
        if qID == targetQuestID then
            found = {
                id = qID,
                title = title,
                header = header,
                pushable = IsLogEntryPushable(qID, logIndex),
                logIndex = logIndex,
            }
            return true
        end
    end)
    return found
end

local function ScanEligibleQuestLog()
    local eligible = {}
    ForEachQuestInLog(function(qID, title, header, logIndex)
        if not IsIgnoredClassOrProfHeader(header) then
            eligible[qID] = {
                id = qID,
                title = title,
                header = header,
                pushable = IsLogEntryPushable(qID, logIndex),
                logIndex = logIndex,
            }
        end
    end)
    return eligible
end

local function IsQuestInPlayerLog(questID)
    questID = tonumber(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsOnQuest then
        return C_QuestLog.IsOnQuest(questID) and true or false
    end
    return GetQuestMetadataFromLog(questID) ~= nil
end

local function IsQuestAlreadyCompleted(questID)
    questID = tonumber(questID)
    if not questID then return false end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        return C_QuestLog.IsQuestFlaggedCompleted(questID) and true or false
    end
    if IsQuestFlaggedCompleted then
        return IsQuestFlaggedCompleted(questID) and true or false
    end
    return false
end

local function IsPartyMemberOnQuest(unit, questID)
    if not unit or not questID then return false end
    if C_QuestLog and C_QuestLog.IsUnitOnQuest then
        local ok, res = pcall(C_QuestLog.IsUnitOnQuest, unit, questID)
        if ok then return res and true or false end
    end
    return false
end

local function ShareQuestByID(questID)
    local meta = GetQuestMetadataFromLog(questID)
    if not meta or not meta.pushable then return false end

    if C_QuestLog and C_QuestLog.SetSelectedQuest then
        pcall(C_QuestLog.SetSelectedQuest, questID)
    end
    if SelectQuestLogEntry and meta.logIndex then
        pcall(SelectQuestLogEntry, meta.logIndex)
    end
    if QuestLogPushQuest then
        local ok = pcall(function()
            if SelectQuestLogEntry and meta.logIndex and not (C_QuestLog and C_QuestLog.SetSelectedQuest) then
                QuestLogPushQuest(meta.logIndex)
            else
                QuestLogPushQuest()
            end
        end)
        return ok and true or false
    end
    return false
end

local function GetQuestObjectivesFromLog(questID, logIndex)
    questID = tonumber(questID)
    if not questID or questID <= 0 then return {}, 0, false end

    local out = {}
    local totalCur = 0
    local allDone = true

    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        local ok, rawObjs = pcall(C_QuestLog.GetQuestObjectives, questID)
        if ok and type(rawObjs) == "table" and #rawObjs > 0 then
            for _, o in ipairs(rawObjs) do
                local text = Utils.Trim(o.text or "")
                if text ~= "" then
                    local cur = tonumber(o.numFulfilled)
                    local max = tonumber(o.numRequired)
                    if not cur or not max then
                        local cStr, mStr = text:match("(%d+)%s*/%s*(%d+)")
                        cur, max = tonumber(cStr), tonumber(mStr)
                    end
                    local done = (o.finished and true or false) or (cur ~= nil and max ~= nil and max > 0 and cur >= max)
                    local kind = "other"
                    if o.type == "monster" or text:lower():find("slain") then
                        kind = "kill"
                    elseif o.type == "item" or o.type == "object" or (cur and max) then
                        kind = "loot"
                    end
                    local mob = nil
                    if kind == "kill" then
                        mob = text:match("^(.+)%s+slain:%s*%d+/%d+") or text:match("^%d+/%d+%s+(.+)%s+slain$")
                    end
                    totalCur = totalCur + (cur or 0)
                    if not done then allDone = false end
                    table.insert(out, {
                        text = text,
                        kind = kind,
                        cur = cur,
                        max = max,
                        completed = done,
                        mob = mob,
                    })
                end
            end
            return out, totalCur, (#out > 0 and allDone)
        end
    end

    if not logIndex then
        local meta = GetQuestMetadataFromLog(questID)
        logIndex = meta and meta.logIndex or nil
    end

    if logIndex and GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        local numBoards = GetNumQuestLeaderBoards(logIndex) or 0
        for j = 1, numBoards do
            local text, objType, finished = GetQuestLogLeaderBoard(j, logIndex)
            text = Utils.Trim(text or "")
            if text ~= "" then
                local cStr, mStr = text:match("(%d+)%s*/%s*(%d+)")
                local cur, max = tonumber(cStr), tonumber(mStr)
                local done = (finished and true or false) or (cur ~= nil and max ~= nil and max > 0 and cur >= max)
                local kind = "other"
                if objType == "monster" or text:lower():find("slain") then
                    kind = "kill"
                elseif objType == "item" or objType == "object" or (cur and max) then
                    kind = "loot"
                end
                local mob = nil
                if kind == "kill" then
                    mob = text:match("^(.+)%s+slain:%s*%d+/%d+") or text:match("^%d+/%d+%s+(.+)%s+slain$")
                end
                totalCur = totalCur + (cur or 0)
                if not done then allDone = false end
                table.insert(out, {
                    text = text,
                    kind = kind,
                    cur = cur,
                    max = max,
                    completed = done,
                    mob = mob,
                })
            end
        end
    end

    return out, totalCur, (#out > 0 and allDone)
end

-- ----------------------------------------------------------------------------
-- Objective Encoding & Decoding Over Addon Channel
-- ----------------------------------------------------------------------------
local function EncodeObjectives(objectives)
    if type(objectives) ~= "table" or #objectives == 0 then return "" end
    local parts = {}
    local maxItems = math.min(#objectives, 4)
    for i = 1, maxItems do
        local o = objectives[i]
        if o and o.text then
            local kCode = (o.kind == "kill" and "K") or (o.kind == "loot" and "L") or "O"
            local dCode = o.completed and "1" or "0"
            local curStr = o.cur and tostring(o.cur) or ""
            local maxStr = o.max and tostring(o.max) or ""
            local mobStr = CleanField(o.mob or "", 22)
            local txtStr = CleanField(o.text or "", 34)
            table.insert(parts, string.format("%s~%s~%s~%s~%s~%s", kCode, dCode, curStr, maxStr, mobStr, txtStr))
        end
    end
    return table.concat(parts, "^")
end

local function DecodeObjectives(encoded)
    local out = {}
    if type(encoded) ~= "string" or encoded == "" then return out end
    for item in encoded:gmatch("([^%^]+)") do
        local kCode, dCode, curStr, maxStr, mobStr, txtStr = strsplit("~", item)
        if txtStr and txtStr ~= "" then
            local kind = (kCode == "K" and "kill") or (kCode == "L" and "loot") or "other"
            local completed = (dCode == "1")
            local cur = tonumber(curStr)
            local max = tonumber(maxStr)
            local mob = (mobStr and mobStr ~= "") and mobStr or nil
            table.insert(out, {
                text = txtStr,
                kind = kind,
                cur = cur,
                max = max,
                completed = completed,
                mob = mob,
            })
        end
    end
    return out
end

-- ----------------------------------------------------------------------------
-- Dynamic Unlisted / Custom Quest Tracker (Guide-Diff + Zone + Party Consensus)
-- ----------------------------------------------------------------------------
local function ExtractObjectiveBaseLabel(text)
    if type(text) ~= "string" then return "Objective" end
    local s = text
    -- Remove X/Y counts
    s = s:gsub("%s*:?%s*%d+%s*/%s*%d+%s*", " ")
    -- Remove trailing "slain"
    s = s:gsub("%s+[sS]lain%s*$", "")
    s = s:gsub("^%s*[kK]ill%s+", "")
    s = s:gsub("%s+", " ")
    s = Utils.Trim(s)
    return (s ~= "") and s or text
end

local function HasSharedObjectiveWith(localObjectives, partyObjectives)
    if not localObjectives or not partyObjectives then return false end
    local localIncomplete = {}
    for _, obj in ipairs(localObjectives) do
        if not obj.completed and obj.text then
            localIncomplete[ExtractObjectiveBaseLabel(obj.text):lower()] = true
        end
    end
    for _, pObj in ipairs(partyObjectives) do
        if not pObj.completed and pObj.text then
            local key = ExtractObjectiveBaseLabel(pObj.text):lower()
            if localIncomplete[key] then
                return true
            end
        end
    end
    return false
end
PartyRXP.HasSharedObjectiveWith = HasSharedObjectiveWith

function PartyRXP:IsQuestInLoadedRXPGuide(questID)
    questID = tonumber(questID)
    if not questID then return false end

    local rxp = GetRXPAddon()
    local cg = rxp and rxp.currentGuide or nil
    if not cg or type(cg.steps) ~= "table" then
        return false
    end

    local guideKey = cg.key or cg.name or tostring(cg)
    if self._cachedGuideKey ~= guideKey then
        self._cachedGuideKey = guideKey
        wipe(self._cachedGuideQuestIDs)
        for _, st in ipairs(cg.steps) do
            if st and type(st.elements) == "table" then
                for _, el in ipairs(st.elements) do
                    if tonumber(el.questId) then
                        self._cachedGuideQuestIDs[tonumber(el.questId)] = true
                    end
                    if type(el.questIds) == "table" then
                        for _, q in pairs(el.questIds) do
                            if tonumber(q) then self._cachedGuideQuestIDs[tonumber(q)] = true end
                        end
                    end
                    if type(el.ids) == "table" then
                        for _, q in pairs(el.ids) do
                            if tonumber(q) then self._cachedGuideQuestIDs[tonumber(q)] = true end
                        end
                    end
                end
            end
        end
    end

    return self._cachedGuideQuestIDs[questID] == true
end

local function DoesHeaderMatchCurrentZone(header)
    if type(header) ~= "string" or header == "" then return false end
    local hLow = header:lower()
    local realZone = (GetRealZoneText and GetRealZoneText() or ""):lower()
    local zone = (GetZoneText and GetZoneText() or ""):lower()
    if realZone ~= "" and (hLow == realZone or realZone:find(hLow, 1, true) or hLow:find(realZone, 1, true)) then
        return true
    end
    if zone ~= "" and (hLow == zone or zone:find(hLow, 1, true) or hLow:find(zone, 1, true)) then
        return true
    end
    return false
end

local function DoAllPartyMembersHaveQuest(questID)
    local hasAnyParty = false
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            hasAnyParty = true
            if UnitIsConnected(unit) ~= false then
                if not IsPartyMemberOnQuest(unit, questID) then
                    return false
                end
            end
        end
    end
    return hasAnyParty
end

function PartyRXP:PruneExpiredCustomQuests()
    local now = GetTime and GetTime() or 0
    for qID, entry in pairs(self.activeCustomQuests) do
        if (entry.expiresAt and now >= entry.expiresAt) or not IsQuestInPlayerLog(qID) then
            self.activeCustomQuests[qID] = nil
        else
            -- Check if all party members (self + connected party members) have completed all objectives
            local selfDone = false
            if type(entry.localObjectives) == "table" and #entry.localObjectives > 0 then
                selfDone = true
                for _, o in ipairs(entry.localObjectives) do
                    if not o.completed then selfDone = false; break end
                end
            end
            if selfDone then
                local allPartyDone = true
                for i = 1, 4 do
                    local unit = "party" .. i
                    if UnitExists(unit) and UnitIsConnected(unit) ~= false then
                        local short = NormalizeShortName(Utils.GetUnitName(unit))
                        local key = short and short:lower() or nil
                        local pObjs = key and entry.partyObjectives and entry.partyObjectives[key] or nil
                        if not pObjs or #pObjs == 0 then
                            allPartyDone = false
                            break
                        end
                        for _, po in ipairs(pObjs) do
                            if not po.completed then
                                allPartyDone = false
                                break
                            end
                        end
                        if not allPartyDone then break end
                    end
                end
                if allPartyDone then
                    entry.expiresAt = math.min(entry.expiresAt or (now + 5), now + 5)
                end
            end
        end
    end
end

function PartyRXP:GetMergedObjectives(baseObjectives, isSelf, partyKey)
    self:PruneExpiredCustomQuests()
    local base = baseObjectives or {}
    if next(self.activeCustomQuests) == nil then
        return base
    end

    local out = {}
    local seen = {}
    for _, o in ipairs(base) do
        table.insert(out, o)
        if o.text then
            seen[ExtractObjectiveBaseLabel(o.text):lower()] = true
        end
    end

    for _, entry in pairs(self.activeCustomQuests) do
        local extraList = isSelf and entry.localObjectives or (partyKey and entry.partyObjectives and entry.partyObjectives[partyKey]) or nil
        if type(extraList) == "table" then
            for _, eo in ipairs(extraList) do
                if eo.text then
                    local k = ExtractObjectiveBaseLabel(eo.text):lower()
                    if not seen[k] then
                        seen[k] = true
                        table.insert(out, eo)
                    end
                end
            end
        end
    end

    return out
end

function PartyRXP:ScanQuestLogForCustomProgress()
    if self:GetDB().enabled == false then return end
    local inParty = (IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()))
    local now = GetTime and GetTime() or 0
    local changedHUD = false

    local function ProcessQuestEntry(qID, title, header, logIndex)
        if not qID or qID <= 0 then return end
        local objs, totalCur = GetQuestObjectivesFromLog(qID, logIndex)
        local prevCur = self.questProgressSnapshot[qID]
        self.questProgressSnapshot[qID] = totalCur

        local activeEntry = self.activeCustomQuests[qID]
        if activeEntry then
            activeEntry.localObjectives = objs
        end

        if prevCur ~= nil and totalCur > prevCur and inParty then
            local shouldActivate = (activeEntry ~= nil)
            if not shouldActivate then
                if not IsIgnoredClassOrProfHeader(header)
                    and not self:IsQuestInLoadedRXPGuide(qID)
                    and DoesHeaderMatchCurrentZone(header)
                    and DoAllPartyMembersHaveQuest(qID)
                then
                    shouldActivate = true
                end
            end

            if shouldActivate then
                if not activeEntry then
                    activeEntry = {
                        id = qID,
                        title = title or ("Quest #" .. tostring(qID)),
                        partyObjectives = {},
                    }
                    self.activeCustomQuests[qID] = activeEntry
                end
                activeEntry.localObjectives = objs
                activeEntry.expiresAt = now + CUSTOM_QUEST_FADE_SEC
                changedHUD = true

                local enc = EncodeObjectives(objs)
                self:SendRaw(string.format("CQP|%d|%s", qID, enc))

                if C_Timer and C_Timer.After then
                    C_Timer.After(CUSTOM_QUEST_FADE_SEC + 1, function()
                        PartyRXP:PruneExpiredCustomQuests()
                        PartyRXP:UpdateHUD()
                    end)
                end
            end
        end
    end

    ForEachQuestInLog(ProcessQuestEntry)

    if changedHUD or next(self.activeCustomQuests) ~= nil then
        self:UpdateHUD()
    end
end

-- ----------------------------------------------------------------------------
-- Smart "Group Remaining" Calculation (Loot = sum, Kill = max)
-- ----------------------------------------------------------------------------
function PartyRXP:CollectGroupRemainingParts()
    local db = self:GetDB()
    if db.showGroupRemaining == false then return nil, false end

    -- Collect active player objective lists to aggregate (You + Synced Party Members)
    local objLists = {}
    local myStep = tonumber(self.localState and self.localState.step)
    local myGuide = (self.localState and self.localState.guide) or ""

    local myMerged = self:GetMergedObjectives(self.localState and self.localState.objectives, true, nil)
    if #myMerged > 0 then
        table.insert(objLists, myMerged)
    end

    if self.isTestMode and next(self.partyState) == nil then
        local fakeStates = self:GetPreviewPartyStates()
        for _, fst in ipairs(fakeStates) do
            table.insert(objLists, fst.objectives or {})
        end
    else
        for key, st in pairs(self.partyState) do
            local sameGuide = (myGuide == "") or (st.guide == "") or (myGuide:lower() == st.guide:lower())
            -- Aggregate party members on the same or behind steps (within 3 steps)
            if sameGuide and (not myStep or not st.step or math.abs(st.step - myStep) <= 3) then
                table.insert(objLists, self:GetMergedObjectives(st.objectives, false, key))
            end
        end
    end

    if #objLists == 0 then return nil, false end

    local buckets = {}
    local bucketOrder = {}
    local hadAnyNumericObj = false

    for _, list in ipairs(objLists) do
        for _, obj in ipairs(list) do
            if (obj.kind == "kill" or obj.kind == "loot") and obj.cur and obj.max and obj.max > 0 then
                hadAnyNumericObj = true
                local rem = math.max(0, obj.max - obj.cur)
                local label = ExtractObjectiveBaseLabel(obj.text)
                local key = label:lower()
                local b = buckets[key]
                if not b then
                    b = {
                        label = label,
                        kind = obj.kind,
                        remaining = 0,
                        mob = obj.mob,
                    }
                    buckets[key] = b
                    table.insert(bucketOrder, b)
                end
                if not b.mob and obj.mob then
                    b.mob = obj.mob
                end
                if obj.kind == "kill" then
                    -- Shared kill credit: group needs the furthest-behind member's remaining count (max)
                    if rem > b.remaining then
                        b.remaining = rem
                    end
                else
                    -- Individual item drop/loot: group needs the sum of all members' remaining counts (sum)
                    b.remaining = b.remaining + rem
                end
            end
        end
    end

    if not hadAnyNumericObj then
        return nil, false
    end

    local activeParts = {}
    for _, b in ipairs(bucketOrder) do
        if b.remaining > 0 then
            local countColor = (b.kind == "loot") and "|cffffd100" or "|cffff8800"
            table.insert(activeParts, string.format("%s%dx|r |cffffffff%s|r", countColor, b.remaining, b.label))
        end
    end

    return activeParts, true
end

function PartyRXP:BuildGroupRemainingSummary()
    local activeParts, hadAny = self:CollectGroupRemainingParts()
    if not hadAny then return nil end
    if #activeParts == 0 then
        return "|cff00ff00Group Remaining: Complete ✓|r"
    end
    return "|cffffd100Group Remaining:|r " .. table.concat(activeParts, "  |cff666666•|r  ")
end

function PartyRXP:BuildGroupRemainingRows()
    local activeParts, hadAny = self:CollectGroupRemainingParts()
    if not hadAny then return nil end
    if #activeParts == 0 then
        return { "|cff00ff00Group Remaining: Complete ✓|r" }
    end

    local rows = { "|cffffd100Group Remaining:|r" }
    for i = 1, #activeParts, 2 do
        if activeParts[i + 1] then
            table.insert(rows, string.format("   %s  |cff666666•|r  %s", activeParts[i], activeParts[i + 1]))
        else
            table.insert(rows, "   " .. activeParts[i])
        end
    end
    return rows
end

-- ----------------------------------------------------------------------------
-- Town-Cycle State Machine & Quest Log Diff Reconciliation
-- ----------------------------------------------------------------------------
function PartyRXP:CapturePreTownSnapshotFromLog()
    local eligible = ScanEligibleQuestLog()
    local snap = {}
    for qID in pairs(eligible) do
        snap[qID] = true
    end
    self.preTownQuestSnapshot = snap
    local db = self:GetDB()
    if type(db) == "table" then
        db.preTownQuestSnapshot = snap
    end
end

function PartyRXP:EnsurePreTownBaselineInitialized()
    if next(self.preTownQuestSnapshot) ~= nil then return end
    local db = self:GetDB()
    if type(db) == "table" and type(db.preTownQuestSnapshot) == "table" and next(db.preTownQuestSnapshot) ~= nil then
        for k, v in pairs(db.preTownQuestSnapshot) do
            local qID = tonumber(k)
            if qID and v then
                self.preTownQuestSnapshot[qID] = true
            end
        end
        return
    end
    self:CapturePreTownSnapshotFromLog()
end

function PartyRXP:BroadcastTownQuestDiff()
    if self:GetDB().enabled == false or self:GetDB().townCycleSync == false then return end
    if not (IsInGroup and IsInGroup()) then return end

    local sortedIDs = {}
    for qID in pairs(self.localTownQuests) do
        table.insert(sortedIDs, qID)
    end
    table.sort(sortedIDs)

    if #sortedIDs == 0 then
        self:SendRaw("QLOG|1|")
        return
    end

    local chunks = {}
    local currentParts = {}
    local currentLen = 0

    for _, qID in ipairs(sortedIDs) do
        local qData = self.localTownQuests[qID]
        local cleanTitle = CleanField(qData.title or ("Quest #" .. tostring(qID)), 28):gsub(":", " ")
        local token = string.format("%d:%s:%s", qID, qData.pushable and "1" or "0", cleanTitle)
        if currentLen + #token + 1 > 195 and #currentParts > 0 then
            table.insert(chunks, table.concat(currentParts, "^"))
            currentParts = { token }
            currentLen = #token
        else
            table.insert(currentParts, token)
            currentLen = currentLen + #token + 1
        end
    end
    if #currentParts > 0 then
        table.insert(chunks, table.concat(currentParts, "^"))
    end

    for idx, chunkStr in ipairs(chunks) do
        local resetFlag = (idx == 1) and "1" or "0"
        self:SendRaw(string.format("QLOG|%s|%s", resetFlag, chunkStr))
    end
end

function PartyRXP:RefreshTownQuestDiff(forceBroadcast)
    if self:GetDB().townCycleSync == false then return end

    local currentEligible = ScanEligibleQuestLog()

    -- Clear any missed-quest warning if the quest is now in our Quest Log
    local clearedMissed = false
    for qID in pairs(currentEligible) do
        if self.missedTownQuests[qID] then
            self.missedTownQuests[qID] = nil
            clearedMissed = true
        end
    end
    if clearedMissed then
        self:UpdateHUD()
    end

    -- When outside a town cycle and not in town:
    -- Always prune quests that were turned in or abandoned, but ONLY add newly accepted quests
    -- to the baseline when on an active field combat/loot step (or initial login) so quests
    -- accepted at town entrance before touching the .goto coordinate are NOT absorbed into preTownQuestSnapshot!
    local st = self.localState or {}
    if not self.inTownCycle and not self.localInTown then
        if not st.isTownCandidate then
            local snap = self.preTownQuestSnapshot or {}
            local pruned = {}
            for qID in pairs(snap) do
                if currentEligible[qID] then
                    pruned[qID] = true
                end
            end
            if next(pruned) == nil or st.isCombatStep then
                for qID in pairs(currentEligible) do
                    pruned[qID] = true
                end
            end
            self.preTownQuestSnapshot = pruned
            local db = self:GetDB()
            if type(db) == "table" then
                db.preTownQuestSnapshot = pruned
            end
        end
        return
    end

    self:EnsurePreTownBaselineInitialized()

    local newDiff = {}
    for qID, meta in pairs(currentEligible) do
        if not self.preTownQuestSnapshot[qID] then
            newDiff[qID] = {
                id = qID,
                title = meta.title,
                pushable = meta.pushable,
            }
        end
    end

    local changed = (forceBroadcast == "force")
    if not changed then
        for qID, d in pairs(newDiff) do
            local old = self.localTownQuests[qID]
            if not old or old.pushable ~= d.pushable or old.title ~= d.title then
                changed = true
                break
            end
        end
        if not changed then
            for qID in pairs(self.localTownQuests) do
                if not newDiff[qID] then
                    changed = true
                    break
                end
            end
        end
    end

    self.localTownQuests = newDiff
    if changed then
        self:BroadcastTownQuestDiff()
    end
end

function PartyRXP:RunPostTownCycleReconciliation()
    local db = self:GetDB()
    if db.enabled == false or db.townCycleSync == false then return end
    if not (IsInGroup and IsInGroup()) then return end

    -- 1. Auto-Share any pushable quest added during the town cycle that a party member is missing
    if db.autoShareTownQuests ~= false then
        local questsToShare = {}
        for qID, qData in pairs(self.localTownQuests) do
            if IsQuestInPlayerLog(qID) then
                local meta = GetQuestMetadataFromLog(qID)
                local isPushable = (meta and meta.pushable) or qData.pushable
                if isPushable then
                    local someoneMissing = false
                    for i = 1, 4 do
                        local unit = "party" .. i
                        if UnitExists(unit) then
                            local short = NormalizeShortName(Utils.GetUnitName(unit))
                            local key = short and short:lower() or nil
                            local pQuests = key and self.partyTownQuests[key] or nil
                            local hasInTownList = pQuests and pQuests[qID] ~= nil
                            local hasInNativeLog = IsPartyMemberOnQuest(unit, qID)
                            if not hasInTownList and not hasInNativeLog then
                                someoneMissing = true
                                break
                            end
                        end
                    end
                    if someoneMissing then
                        table.insert(questsToShare, {
                            id = qID,
                            title = (meta and meta.title) or qData.title or ("Quest #" .. tostring(qID)),
                        })
                    end
                end
            end
        end

        for idx, qItem in ipairs(questsToShare) do
            local function DoShare()
                if ShareQuestByID(qItem.id) then
                    print(string.format(
                        "|cff0cd29f[EFHelper PartyRXP]|r Town Cycle complete — Auto-sharing '|cffffd100%s|r' with party.",
                        qItem.title
                    ))
                end
            end
            if idx == 1 or not (C_Timer and C_Timer.After) then
                DoShare()
            else
                C_Timer.After((idx - 1) * 1.5, DoShare)
            end
        end
    end

    -- 2. Check if any party member added a town-cycle quest that we don't have (after a 4.5s grace window for auto-shares)
    local snapshotPartyQuests = {}
    for senderKey, qMap in pairs(self.partyTownQuests) do
        snapshotPartyQuests[senderKey] = {}
        for qID, qInfo in pairs(qMap) do
            snapshotPartyQuests[senderKey][qID] = qInfo
        end
    end

    local function CheckMissingPartyTownQuests()
        local addedAny = false
        for _, qMap in pairs(snapshotPartyQuests) do
            for qID, qInfo in pairs(qMap) do
                if not IsQuestInPlayerLog(qID) and not IsQuestAlreadyCompleted(qID) then
                    if not PartyRXP.missedTownQuests[qID] then
                        PartyRXP.missedTownQuests[qID] = {
                            id = qID,
                            title = qInfo.title or ("Quest #" .. tostring(qID)),
                            sender = qInfo.sender or "Party",
                            pushable = qInfo.pushable,
                        }
                        addedAny = true
                        print(string.format(
                            "|cffffaa00[EFHelper PartyRXP]|r Notice: |cffffffff%s|r picked up '|cffffd100%s|r' during the town cycle, which is not in your Quest Log.",
                            qInfo.sender or "A party member",
                            qInfo.title or ("Quest #" .. tostring(qID))
                        ))
                    end
                end
            end
        end
        if addedAny then
            PartyRXP:UpdateHUD()
        end
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(4.5, CheckMissingPartyTownQuests)
    else
        CheckMissingPartyTownQuests()
    end
end

function PartyRXP:EvaluateTownCycleState()
    if self:GetDB().townCycleSync == false then
        self.localInTown = false
        self.inTownCycle = false
        return
    end

    local st = self.localState or {}
    local prevLocalInTown = self.localInTown

    -- Pure step-based town determination:
    -- 1. Enter localInTown when st.isTownCycle is true (current step has incomplete town candidate + forward lookahead confirms town cluster)
    -- 2. Stay in localInTown through the final town step(s) as long as st.isTownCandidate remains true (at least 1 incomplete town element on curIdx)
    local localIsTown = false
    if st.isTownCycle then
        localIsTown = true
    elseif prevLocalInTown and st.isTownCandidate then
        localIsTown = true
    end

    self.localInTown = localIsTown
    if prevLocalInTown and not localIsTown then
        self.townExitStep = tonumber(st.step) or self.townExitStep
        self:ScheduleBroadcast(false)
    elseif prevLocalInTown ~= localIsTown then
        self:ScheduleBroadcast(false)
    end

    local myGuide = (st.guide or ""):lower()
    local anyPartyStillInTown = false
    for _, pSt in pairs(self.partyState) do
        if pSt.isTownCycle then
            anyPartyStillInTown = true
            break
        elseif self.townExitStep and pSt.step then
            local sameGuide = (myGuide == "") or (pSt.guide == "") or (myGuide == (pSt.guide or ""):lower())
            if sameGuide and pSt.step < self.townExitStep and (self.townExitStep - pSt.step) <= 6 then
                -- Check if teammate is already functionally on the field step (shares field goal or is outside town within 2 steps)
                local isSharingFieldGoal = HasSharedObjectiveWith(st.objectives, pSt.objectives)
                local isSmallOffset = (self.townExitStep - pSt.step) <= 2
                if not (isSharingFieldGoal or (not pSt.isTownCycle and isSmallOffset)) then
                    anyPartyStillInTown = true
                    break
                end
            end
        end
    end

    if localIsTown or anyPartyStillInTown then
        if not self.inTownCycle then
            self:EnsurePreTownBaselineInitialized()
            self.inTownCycle = true
            self:RefreshTownQuestDiff("force")
        else
            self:RefreshTownQuestDiff(false)
        end
        return
    end

    -- When both we and all synced party members have finished our town steps (localInTown == false, all st.isTownCycle == false,
    -- and all party members on the same guide have reached the post-town step), compute our post-town Quest Log diff and finalize
    -- after a generous settle delay (8.0s) so unlisted quests accepted right after step advance are captured.
    if self.inTownCycle then
        self:RefreshTownQuestDiff(false)
        if not self._reconcilePending then
            self._reconcilePending = true
            local function FinalizeTownCycle()
                PartyRXP._reconcilePending = false
                if not PartyRXP.inTownCycle or PartyRXP.localInTown then return end
                local curSt = PartyRXP.localState or {}
                local curGuide = (curSt.guide or ""):lower()
                for _, pSt in pairs(PartyRXP.partyState) do
                    if pSt.isTownCycle then return end
                    if PartyRXP.townExitStep and pSt.step then
                        local sameGuide = (curGuide == "") or (pSt.guide == "") or (curGuide == (pSt.guide or ""):lower())
                        if sameGuide and pSt.step < PartyRXP.townExitStep and (PartyRXP.townExitStep - pSt.step) <= 6 then
                            local isSharingFieldGoal = HasSharedObjectiveWith(curSt.objectives, pSt.objectives)
                            local isSmallOffset = (PartyRXP.townExitStep - pSt.step) <= 2
                            if not (isSharingFieldGoal or (not pSt.isTownCycle and isSmallOffset)) then
                                return
                            end
                        end
                    end
                end
                PartyRXP:RefreshTownQuestDiff("force")
                PartyRXP.inTownCycle = false
                PartyRXP.townExitStep = nil
                PartyRXP:RunPostTownCycleReconciliation()
                wipe(PartyRXP.localTownQuests)
                wipe(PartyRXP.partyTownQuests)
                PartyRXP:CapturePreTownSnapshotFromLog()
                PartyRXP:UpdateHUD()
            end
            if C_Timer and C_Timer.After then
                C_Timer.After(TOWN_EXIT_SETTLE_SEC, FinalizeTownCycle)
            else
                FinalizeTownCycle()
            end
        end
    end
end

function PartyRXP:OnQuestAccepted(event, arg1, arg2)
    local questID = tonumber(arg2) or tonumber(arg1)
    if not questID or questID <= 0 then return end

    if self.missedTownQuests[questID] then
        self.missedTownQuests[questID] = nil
        self:UpdateHUD()
    end

    -- If a quest is accepted during an active town cycle or while town exit settle is pending, refresh diff immediately
    if self.inTownCycle then
        self:RefreshTownQuestDiff(false)
    end
end

function PartyRXP:OnQuestTurnedIn()
    self:EvaluateTownCycleState()
end

-- ----------------------------------------------------------------------------
-- Addon Communication (C_ChatInfo "EFH_RXP")
-- ----------------------------------------------------------------------------
function PartyRXP:BuildPayload()
    local st = self.localState or {}
    local guide = CleanField(st.guide or "", 28)
    local step = tostring(tonumber(st.step) or 0)
    local cat = CleanField(st.category or "TRAVEL", 14)
    local townFlag = self.localInTown and "1" or "0"
    local xpStr = tostring(GetLocalXPPercent())
    local prog = CleanField(st.progress or "", 42)
    local encObj = EncodeObjectives(st.objectives or {})

    local payload = string.format("STEP|%s|%s|%s|%s|%s|%s|%s", guide, step, cat, townFlag, xpStr, prog, encObj)
    if #payload > 250 then
        payload = payload:sub(1, 250)
    end
    return payload
end

function PartyRXP:SendRaw(message)
    if self:GetDB().enabled == false then return end
    if not (IsInGroup and IsInGroup()) then return end
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return end

    local channel = (IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT")
        or (IsInRaid and IsInRaid() and "RAID")
        or "PARTY"

    pcall(C_ChatInfo.SendAddonMessage, COMM_PREFIX, message, channel)
end

function PartyRXP:FlushBroadcast(force)
    broadcastPending = false
    if self:GetDB().enabled == false then return end
    if not (IsInGroup and IsInGroup()) then return end

    if not self.localState or not self.localState.step or self.localState.step <= 0 then
        self:SyncLocalRXPStep()
    end

    local st = self.localState
    if not st or not st.step or st.step <= 0 then
        -- Broadcast XP percentage immediately so teammate's XP bar is never blank
        local xpPayload = string.format("XP|%d", GetLocalXPPercent())
        if not force and xpPayload == lastSentPayload then
            return
        end
        lastSentPayload = xpPayload
        self:SendRaw(xpPayload)
        return
    end

    local payload = self:BuildPayload()
    if not force and payload == lastSentPayload then
        return
    end
    lastSentPayload = payload
    self:SendRaw(payload)
end

function PartyRXP:ScheduleBroadcast(force)
    if self:GetDB().enabled == false then return end
    if not (IsInGroup and IsInGroup()) then return end

    if force then
        lastSentPayload = nil
    end
    if broadcastPending then return end
    broadcastPending = true

    if C_Timer and C_Timer.After then
        C_Timer.After(BROADCAST_DEBOUNCE, function()
            PartyRXP:FlushBroadcast(false)
        end)
    else
        self:FlushBroadcast(false)
    end
end

-- ----------------------------------------------------------------------------
-- Self-Contained RXP Step & Town-Cycle Extraction
-- ----------------------------------------------------------------------------
local function SanitizeRXPText(rxp, raw)
    if type(raw) ~= "string" or raw == "" then return nil end
    if rxp and rxp.ReplaceNpcIds then
        local ok, replaced = pcall(rxp.ReplaceNpcIds, raw)
        if ok and type(replaced) == "string" then
            raw = replaced
        end
    end
    raw = raw:gsub("RXP_[A-Z_]+", "")
    raw = raw:gsub("|T.-|t", "")
    raw = raw:gsub("|c%x%x%x%x%x%x%x%x", "")
    raw = raw:gsub("|r", "")
    raw = raw:gsub("[\r\n]+", " ")
    raw = raw:gsub("^%s*%-+%s*", "")
    raw = raw:gsub("%s+", " ")
    raw = Utils.Trim(raw)
    if raw == "" or raw == "-" then return nil end
    return raw
end

local function ResolveUnitListNames(rxp, list, out, seen)
    if type(list) ~= "table" then return end
    for _, rawUnit in ipairs(list) do
        local name = rawUnit
        local numId = tonumber(rawUnit)
        if numId and rxp then
            if rxp.GetNpcName then
                local ok, resolved = pcall(rxp.GetNpcName, numId)
                if ok and resolved and resolved ~= "" then name = resolved end
            elseif rxp.GetCreatureName then
                local ok, resolved = pcall(rxp.GetCreatureName, numId)
                if ok and resolved and resolved ~= "" then name = resolved end
            end
        elseif type(rawUnit) == "string" then
            local parsedName = rawUnit:match("^[%+%*]?%s*(.+)::%d+$") or rawUnit:match("^[%+%*]?%s*(.+)$")
            if parsedName and not tonumber(parsedName) then
                name = parsedName
            end
        end
        name = SanitizeRXPText(rxp, tostring(name or ""))
        if name and not tonumber(name) and not seen[name:lower()] then
            seen[name:lower()] = true
            table.insert(out, name)
        end
    end
end

local function InspectStepForTown(st)
    if not st or type(st.elements) ~= "table" then return false, 0, 0 end
    local qCount, hCount = 0, 0
    local isStepDone = (st.completed and true or false)
    for _, el in ipairs(st.elements) do
        if not el.skip and not el.hidden then
            local t = el.tag
            local isCombatTag = (t == "complete" or t == "collect" or t == "collectmultiple" or t == "questitemcount" or t == "xp")
            local isQuestTag = (t == "accept" or t == "turnin" or t == "daily" or t == "dailyturnin" or t == "acceptmultiple" or t == "turninmultiple")
            local isHubTag = (t == "vendor" or t == "buy" or t == "train" or t == "trainer" or t == "home" or t == "hs" or t == "bindlocation" or t == "fp" or t == "fly" or t == "bankdeposit")

            if isCombatTag and not el.completed then
                return true, 0, 0 -- Incomplete field combat/loot/grind objective; stop forward lookahead
            elseif isQuestTag and not el.completed then
                qCount = qCount + 1
            elseif isHubTag and (not el.completed or (el.textOnly and not isStepDone)) then
                hCount = hCount + 1
            end
        end
    end
    return false, qCount, hCount
end

function PartyRXP:SyncLocalRXPStep()
    if self._isSyncing then return end
    self._isSyncing = true

    local rxp = GetRXPAddon()
    if not rxp then
        self._isSyncing = false
        return
    end

    local curIdx = (type(rxp.GetGuideProgress) == "function" and rxp.GetGuideProgress())
        or (_G.RXPCData and _G.RXPCData.currentStep)
        or nil

    local guide = rxp.currentGuide
    if not guide and type(rxp.GetGuideTable) == "function" and _G.RXPCData and _G.RXPCData.currentGuideName then
        guide = rxp.GetGuideTable(_G.RXPCData.currentGuideGroup, _G.RXPCData.currentGuideName)
    end

    local guideSteps = guide and guide.steps or nil
    local step = (curIdx and type(guideSteps) == "table" and guideSteps[curIdx])
        or (rxp.arrowFrame and rxp.arrowFrame.element and rxp.arrowFrame.element.step)
        or nil
    if not step then
        self._isSyncing = false
        return
    end
    curIdx = step.index or curIdx

    local stepMobs, seenStepMobs = {}, {}
    local noteLines = {}
    local combatIcon = rxp.icons and rxp.icons.combat
    local collectIcon = rxp.icons and rxp.icons.collect

    if type(step.elements) == "table" then
        for _, el in ipairs(step.elements) do
            local parentDone = (type(el.parent) == "table") and (el.parent.completed or el.parent.skip)
            if not el.skip and not el.hidden and not parentDone then
                if el.tag == "mob" then
                    ResolveUnitListNames(rxp, el.mobs or el.unitlist, stepMobs, seenStepMobs)
                elseif el.text and el.text ~= "" and (el.textOnly or not el.completed) then
                    local cleanNote = SanitizeRXPText(rxp, el.text)
                    if cleanNote and #noteLines == 0 then
                        table.insert(noteLines, cleanNote)
                    end
                end
            end
        end
    end

    if rxp.targeting and rxp.targeting.GetCurrentTargets then
        local ok, _, rxpMobList = pcall(rxp.targeting.GetCurrentTargets)
        if ok and type(rxpMobList) == "table" then
            ResolveUnitListNames(rxp, rxpMobList, stepMobs, seenStepMobs)
        end
    end

    local function MatchMobForObjectiveText(objText)
        if not objText then return nil end
        local low = objText:lower()
        for _, m in ipairs(stepMobs) do
            if low:find(m:lower(), 1, true) then
                return m
            end
        end
        local slainMob = objText:match("^(.+)%s+slain:%s*%d+/%d+") or objText:match("^%d+/%d+%s+(.+)%s+slain$")
        if slainMob then return slainMob end
        for _, m in ipairs(stepMobs) do
            for word in m:gmatch("%a%a%a%a+") do
                if low:find(word:lower(), 1, true) then
                    return m
                end
            end
        end
        return stepMobs[1]
    end

    local structuredObjectives, seenStructObj = {}, {}
    local activeObjLines = {}
    local function AddStructuredObjective(cleanText, kind, isDone)
        if not cleanText or cleanText == "" then return end
        local key = cleanText:lower()
        if seenStructObj[key] then return end
        seenStructObj[key] = true

        local curStr, maxStr = cleanText:match("(%d+)%s*/%s*(%d+)")
        local cur, max = tonumber(curStr), tonumber(maxStr)
        local completed = (isDone and true or false) or (cur ~= nil and max ~= nil and max > 0 and cur >= max)
        local assocMob = (kind == "kill" or kind == "loot") and MatchMobForObjectiveText(cleanText) or nil

        if not completed then
            table.insert(activeObjLines, cleanText)
        end
        table.insert(structuredObjectives, {
            text = cleanText,
            kind = kind or "other",
            cur = cur,
            max = max,
            completed = completed,
            mob = assocMob,
        })
    end

    if type(step.elements) == "table" then
        for _, el in ipairs(step.elements) do
            local parentDone = (type(el.parent) == "table") and (el.parent.completed or el.parent.skip)
            if not el.skip and not el.hidden and not parentDone then
                local tag = el.tag
                if tag == "complete" or tag == "collect" or tag == "collectmultiple" or tag == "questitemcount" or tag == "blastedLands" then
                    local clean = SanitizeRXPText(rxp, el.text or el.rawtext or el.itemName)
                    if clean then
                        local kind = "loot"
                        if tag == "complete" then
                            if combatIcon and el.icon == combatIcon then
                                kind = "kill"
                            elseif collectIcon and el.icon == collectIcon then
                                kind = "loot"
                            else
                                local low = clean:lower()
                                if low:find("slain") or low:find("^kill ") then
                                    kind = "kill"
                                end
                            end
                        end
                        AddStructuredObjective(clean, kind, el.completed)
                    end
                elseif not el.completed and (
                    tag == "turnin" or tag == "dailyturnin" or tag == "turninmultiple" or
                    tag == "accept" or tag == "daily" or tag == "acceptmultiple" or
                    tag == "train" or tag == "trainer" or tag == "vendor" or
                    tag == "fly" or tag == "fp" or tag == "hs" or tag == "home" or
                    tag == "xp" or tag == "reputation"
                ) then
                    local fallbackText = el.text
                        or (el.title and ((tag:find("turnin") and "Turn in " or "Accept ") .. el.title))
                        or el.tooltipText
                    local clean = SanitizeRXPText(rxp, fallbackText)
                    if clean then
                        AddStructuredObjective(clean, "other", false)
                    end
                end
            end
        end
    end

    if #structuredObjectives == 0 and noteLines[1] then
        AddStructuredObjective(noteLines[1], "other", false)
    end

    -- Pure Step-Based Town-Cycle Detection (current step incomplete town candidate + forward lookahead only)
    local isTownCandidate = false
    local isTownCycle = false
    local isCombatStep = false
    if curIdx and type(guideSteps) == "table" then
        local curCombat, cq, ch = InspectStepForTown(guideSteps[curIdx])
        isCombatStep = curCombat
        if not curCombat then
            local futureQ = 0
            local futureH = 0
            local futureTownSteps = 0

            for sIdx = curIdx + 1, math.min(#guideSteps, curIdx + 5) do
                local isCombat, q, h = InspectStepForTown(guideSteps[sIdx])
                if isCombat then break end
                futureQ = futureQ + q
                futureH = futureH + h
                if (q + h) > 0 then
                    futureTownSteps = futureTownSteps + 1
                end
            end

            local totalQ = cq + futureQ
            local totalH = ch + futureH
            local totalTownSteps = ((cq + ch) > 0 and 1 or 0) + futureTownSteps

            -- Entry Trigger (isTownCycle): current step itself has pending town action(s) AND lookahead meets cluster threshold
            if (cq + ch) > 0 and (totalQ >= 3 or (totalQ >= 1 and totalH >= 1) or (totalTownSteps >= 2 and (totalQ + totalH) >= 2)) then
                isTownCycle = true
            end

            -- Continuation Flag (isTownCandidate): stays true while there are incomplete town actions on curIdx OR in upcoming contiguous steps before combat
            if (cq + ch + futureQ + futureH) > 0 then
                isTownCandidate = true
            end
        end
    end

    local progressSummary = (#activeObjLines > 0 and table.concat(activeObjLines, " • "))
        or noteLines[1]
        or "Objective"

    local guideName = (guide and (guide.name or guide.key))
        or (rxp.currentGuide and (rxp.currentGuide.name or rxp.currentGuide.key))
        or (_G.RXPCData and _G.RXPCData.currentGuideName)
        or ""

    self.localState = {
        guide = guideName,
        step = curIdx,
        category = "TRAVEL",
        progress = progressSummary,
        isTownCandidate = isTownCandidate,
        isTownCycle = isTownCycle,
        isCombatStep = isCombatStep,
        objectives = structuredObjectives,
    }

    self:EvaluateTownCycleState()
    self:UpdateHUD()
    self:ScheduleBroadcast(false)
    self._isSyncing = false
end

function PartyRXP:HookRXP()
    local rxp = GetRXPAddon()
    if not rxp then return end

    if type(rxp.SetStep) == "function" and not self._isSetStepHooked then
        self._isSetStepHooked = true
        hooksecurefunc(rxp, "SetStep", function()
            PartyRXP:SyncLocalRXPStep()
        end)
    end

    if type(rxp.LoadGuide) == "function" and not self._isLoadGuideHooked then
        self._isLoadGuideHooked = true
        hooksecurefunc(rxp, "LoadGuide", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, function()
                    PartyRXP:HookRXP()
                    PartyRXP:SyncLocalRXPStep()
                    PartyRXP:ScheduleBroadcast(true)
                end)
            else
                PartyRXP:HookRXP()
                PartyRXP:SyncLocalRXPStep()
                PartyRXP:ScheduleBroadcast(true)
            end
        end)
    end

    if type(rxp.ReloadGuide) == "function" and not self._isReloadGuideHooked then
        self._isReloadGuideHooked = true
        hooksecurefunc(rxp, "ReloadGuide", function()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.05, function()
                    PartyRXP:HookRXP()
                    PartyRXP:SyncLocalRXPStep()
                    PartyRXP:ScheduleBroadcast(true)
                end)
            else
                PartyRXP:HookRXP()
                PartyRXP:SyncLocalRXPStep()
                PartyRXP:ScheduleBroadcast(true)
            end
        end)
    end

    if type(rxp.UpdateMap) == "function" and not self._isUpdateMapHooked then
        self._isUpdateMapHooked = true
        hooksecurefunc(rxp, "UpdateMap", function()
            PartyRXP:SyncLocalRXPStep()
        end)
    end

    if type(rxp.UpdateGotoSteps) == "function" and not self._isUpdateGotoHooked then
        self._isUpdateGotoHooked = true
        hooksecurefunc(rxp, "UpdateGotoSteps", function()
            PartyRXP:SyncLocalRXPStep()
        end)
    end

    if rxp.RXPFrame and rxp.RXPFrame.CurrentStepFrame and type(rxp.RXPFrame.CurrentStepFrame.UpdateText) == "function" and not self._isCurrentStepFrameHooked then
        self._isCurrentStepFrameHooked = true
        hooksecurefunc(rxp.RXPFrame.CurrentStepFrame, "UpdateText", function()
            PartyRXP:SyncLocalRXPStep()
        end)
    end

    if type(rxp.RegisterMessage) == "function" and not self._isRXPMessageHooked then
        self._isRXPMessageHooked = true
        pcall(rxp.RegisterMessage, rxp, "RXP_GUIDE_LOADED", function()
            PartyRXP:HookRXP()
            PartyRXP:SyncLocalRXPStep()
            PartyRXP:ScheduleBroadcast(true)
        end)
        pcall(rxp.RegisterMessage, rxp, "RXP_STEP_ACTIVATED", function()
            PartyRXP:SyncLocalRXPStep()
        end)
        pcall(rxp.RegisterMessage, rxp, "RXP_STEP_COMPLETE", function()
            PartyRXP:SyncLocalRXPStep()
        end)
        pcall(rxp.RegisterMessage, rxp, "RXP_OBJECTIVE_COMPLETE", function()
            PartyRXP:SyncLocalRXPStep()
        end)
    end

    self:SyncLocalRXPStep()
end

function PartyRXP:RequestPartySync()
    if self:GetDB().enabled == false then return end
    if not (IsInGroup and IsInGroup()) then return end
    self:HookRXP()
    self:SyncLocalRXPStep()
    self:SendRaw("REQ")
    self:ScheduleBroadcast(true)
end

function PartyRXP:PruneStalePartyMembers()
    if not (IsInGroup and IsInGroup()) then
        wipe(self.partyState)
        wipe(self.partyTownQuests)
        lastSentPayload = nil
        return
    end

    local validKeys = {}
    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local short = NormalizeShortName(Utils.GetUnitName(unit))
            if short then
                validKeys[short:lower()] = true
            end
        end
    end

    for k in pairs(self.partyState) do
        if not validKeys[k] then
            self.partyState[k] = nil
        end
    end
    for k in pairs(self.partyTownQuests) do
        if not validKeys[k] then
            self.partyTownQuests[k] = nil
        end
    end
end

function PartyRXP:OnChatMsgAddon(event, prefix, msg, channel, sender)
    if prefix ~= COMM_PREFIX then return end
    if self:GetDB().enabled == false then return end
    if type(msg) ~= "string" then return end

    local senderShort = NormalizeShortName(sender)
    local myShort = NormalizeShortName(Utils.GetUnitName("player"))
    if not senderShort or (myShort and senderShort:lower() == myShort:lower()) then
        return
    end

    local key = senderShort:lower()

    if msg == "REQ" then
        self:HookRXP()
        self:SyncLocalRXPStep()
        self:ScheduleBroadcast(true)
        if self.inTownCycle or next(self.localTownQuests) ~= nil then
            self:BroadcastTownQuestDiff()
        end
        for qID, entry in pairs(self.activeCustomQuests) do
            if type(entry.localObjectives) == "table" and #entry.localObjectives > 0 then
                self:SendRaw(string.format("CQS|%d|%s", qID, EncodeObjectives(entry.localObjectives)))
            end
        end
        return
    end

    local cmd, a1, a2, a3, a4, a5, a6, a7 = strsplit("|", msg)
    if cmd == "QLOG" then
        local resetFlag = a1
        local entriesStr = a2
        if resetFlag == "1" or not self.partyTownQuests[key] then
            self.partyTownQuests[key] = {}
        end
        if type(entriesStr) == "string" and entriesStr ~= "" then
            for token in entriesStr:gmatch("[^%^]+") do
                local qIDStr, pushFlag, title = token:match("^(%d+):([01]):(.*)$")
                local qID = tonumber(qIDStr)
                if qID and qID > 0 then
                    self.partyTownQuests[key][qID] = {
                        id = qID,
                        title = (title and title ~= "") and title or ("Quest #" .. tostring(qID)),
                        pushable = (pushFlag == "1"),
                        sender = senderShort,
                    }
                end
            end
        end
        return
    end

    if cmd == "CQP" or cmd == "CQS" then
        local qID = tonumber(a1)
        local encObjs = a2
        if qID and qID > 0 and IsQuestInPlayerLog(qID) then
            local now = GetTime and GetTime() or 0
            local entry = self.activeCustomQuests[qID]
            local wasNew = (entry == nil)
            if not entry then
                local meta = GetQuestMetadataFromLog(qID)
                entry = {
                    id = qID,
                    title = (meta and meta.title) or ("Quest #" .. tostring(qID)),
                    localObjectives = GetQuestObjectivesFromLog(qID, meta and meta.logIndex),
                    partyObjectives = {},
                    expiresAt = now + CUSTOM_QUEST_FADE_SEC,
                }
                self.activeCustomQuests[qID] = entry
                if C_Timer and C_Timer.After then
                    C_Timer.After(CUSTOM_QUEST_FADE_SEC + 1, function()
                        PartyRXP:PruneExpiredCustomQuests()
                        PartyRXP:UpdateHUD()
                    end)
                end
            elseif cmd == "CQP" then
                entry.expiresAt = now + CUSTOM_QUEST_FADE_SEC
            end

            entry.partyObjectives[key] = DecodeObjectives(encObjs)

            -- When a party member triggers CQP (or activates a new shared custom quest), reply with our own current state
            if cmd == "CQP" or wasNew then
                local myObjs = GetQuestObjectivesFromLog(qID)
                entry.localObjectives = myObjs
                if #myObjs > 0 then
                    self:SendRaw(string.format("CQS|%d|%s", qID, EncodeObjectives(myObjs)))
                end
            end

            self:PruneExpiredCustomQuests()
            self:UpdateHUD()
        end
        return
    end

    if cmd == "XP" then
        local xpVal = tonumber(a1)
        if xpVal then
            local prevSt = self.partyState[key]
            if not prevSt then
                self.partyState[key] = {
                    name = senderShort,
                    class = classToken,
                    guide = "",
                    step = 0,
                    category = "TRAVEL",
                    isTownCycle = false,
                    xpPct = xpVal,
                    progress = "",
                    objectives = {},
                    updatedAt = GetTime and GetTime() or 0,
                }
            else
                prevSt.xpPct = xpVal
                prevSt.updatedAt = GetTime and GetTime() or 0
            end
            self:UpdateHUD()
        end
        return
    end

    if cmd ~= "STEP" then return end

    local guide, stepStr, cat, townFlag, xpStr, prog, encObj
    if a7 ~= nil then
        guide, stepStr, cat, townFlag, xpStr, prog, encObj = a1, a2, a3, a4, a5, a6, a7
    else
        guide, stepStr, cat, townFlag, prog, encObj = a1, a2, a3, a4, a5, a6
    end

    local unit = FindPartyUnitByShortName(key)
    local _, classToken = nil, nil
    if unit and UnitClass then
        _, classToken = UnitClass(unit)
    end

    local decodedObjs = DecodeObjectives(encObj)
    if #decodedObjs == 0 and prog and prog ~= "" then
        table.insert(decodedObjs, {
            text = prog,
            kind = "other",
            completed = false,
        })
    end

    local prevSt = self.partyState[key]
    local incomingStep = tonumber(stepStr) or 0
    if incomingStep <= 0 and prevSt and prevSt.step and prevSt.step > 0 then
        incomingStep = prevSt.step
    end

    self.partyState[key] = {
        name = senderShort,
        class = classToken,
        guide = guide or "",
        step = incomingStep,
        category = (cat and cat ~= "") and cat or "TRAVEL",
        isTownCycle = (townFlag == "1"),
        xpPct = tonumber(xpStr) or (prevSt and prevSt.xpPct) or nil,
        progress = (prog and prog ~= "") and prog or "Synced",
        objectives = decodedObjs,
        updatedAt = GetTime and GetTime() or 0,
    }

    self:EvaluateTownCycleState()
    self:UpdateHUD()

    if EFHelper.Config and EFHelper.Config.RefreshActivePanel then
        EFHelper.Config:RefreshActivePanel()
    end
end

-- ----------------------------------------------------------------------------
-- Preview / Test Mode Data & Config Status Summary
-- ----------------------------------------------------------------------------
function PartyRXP:GetPreviewPartyStates()
    local myStep = tonumber(self.localState and self.localState.step) or 14
    local myGuide = (self.localState and self.localState.guide) or "Tirisfal 1-11"
    return {
        {
            name = "Kaelen",
            class = "PALADIN",
            guide = myGuide,
            step = myStep,
            xpPct = 42,
            category = "KILL_LOOT",
            isTownCycle = false,
            progress = "Mindless Zombie slain: 8/8 • Wretched Zombie slain: 5/8 • Rattlecage Skull: 3/6",
            objectives = {
                { text = "Mindless Zombie slain: 8/8", kind = "kill", cur = 8, max = 8, completed = true, mob = "Mindless Zombie" },
                { text = "Wretched Zombie slain: 5/8", kind = "kill", cur = 5, max = 8, completed = false, mob = "Wretched Zombie" },
                { text = "Rattlecage Skull: 3/6", kind = "loot", cur = 3, max = 6, completed = false, mob = "Rattlecage Skeleton" },
            },
        },
        {
            name = "Sylvara",
            class = "SHAMAN",
            guide = myGuide,
            step = math.max(1, myStep - 1),
            xpPct = 18,
            category = "KILL_LOOT",
            isTownCycle = false,
            progress = "Mindless Zombie slain: 8/8 • Wretched Zombie slain: 8/8 • Rattlecage Skull: 4/6",
            objectives = {
                { text = "Mindless Zombie slain: 8/8", kind = "kill", cur = 8, max = 8, completed = true, mob = "Mindless Zombie" },
                { text = "Wretched Zombie slain: 8/8", kind = "kill", cur = 8, max = 8, completed = true, mob = "Wretched Zombie" },
                { text = "Rattlecage Skull: 4/6", kind = "loot", cur = 4, max = 6, completed = false, mob = "Rattlecage Skeleton" },
            },
        },
    }
end

function PartyRXP:GetFormattedPartyLines()
    local lines = {}
    local myStep = tonumber(self.localState and self.localState.step)
    local myGuide = (self.localState and self.localState.guide) or ""

    if self.isTestMode and next(self.partyState) == nil then
        for _, fst in ipairs(self:GetPreviewPartyStates()) do
            local delta = (myStep and fst.step) and (fst.step - myStep) or 0
            local badge = (delta == 0) and string.format("|cff00ff00[%d]|r", fst.step)
                or string.format("|cffff8800[%d]|r", fst.step)
            local coloredName = Utils.FormatClassColored(fst.name, fst.class)
            local xpSuffix = fst.xpPct and string.format(" (%d%%)", fst.xpPct) or ""
            table.insert(lines, string.format("%s %s%s", badge, coloredName, xpSuffix))
        end
        return lines
    end

    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists(unit) then
            local short = NormalizeShortName(Utils.GetUnitName(unit))
            local key = short and short:lower() or nil
            local st = key and self.partyState[key] or nil
            if st then
                local _, classToken = UnitClass(unit)
                local coloredName = Utils.FormatClassColored(st.name, classToken or st.class)
                local badge
                if myGuide ~= "" and st.guide ~= "" and myGuide:lower() ~= st.guide:lower() then
                    badge = string.format("|cffffaa00[%s #%d]|r", st.guide:sub(1, 12), st.step or 0)
                elseif myStep and st.step and st.step > 0 then
                    local delta = st.step - myStep
                    if delta == 0 then
                        badge = string.format("|cff00ff00[%d]|r", st.step)
                    elseif delta < 0 then
                        badge = string.format("|cffff8800[%d]|r", st.step)
                    else
                        badge = string.format("|cff00ccff[%d]|r", st.step)
                    end
                else
                    badge = string.format("|cffaaaaaa[%s]|r", tostring(st.step or "?"))
                end
                local xpSuffix = (st.xpPct ~= nil) and string.format(" (%d%%)", st.xpPct) or ""
                table.insert(lines, string.format("%s %s%s", badge, coloredName, xpSuffix))
            else
                local rawName = Utils.GetUnitName(unit) or unit
                local _, classToken = UnitClass(unit)
                table.insert(lines, string.format("|cff666666[No Sync]|r %s", Utils.FormatClassColored(rawName, classToken)))
            end
        end
    end

    return lines
end

function PartyRXP:ClearMissedQuests()
    wipe(self.missedTownQuests)
    self:UpdateHUD()
end

-- ----------------------------------------------------------------------------
-- Unified Group Quest-Tracker HUD (Movable / Lockable + 1-Click EFHRXP Tagging)
-- ----------------------------------------------------------------------------
function PartyRXP:SavePosition(frame)
    if not frame then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    if point and relPoint then
        self:GetDB().pos = { point, "UIParent", relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
    end
end

function PartyRXP:RestorePosition(frame)
    if not frame then return end
    local p = self:GetDB().pos
    frame:ClearAllPoints()
    if type(p) == "table" and p[1] and p[3] and p[4] and p[5] then
        frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 24, -180)
    end
end

function PartyRXP:CreateHUD()
    if self.hud then return self.hud end

    local f = UI.CreateBackdropFrame("Frame", "EFHelperPartyRXPFrame", UIParent, 240, 80)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)

    self:RestorePosition(f)

    -- Pool of interactive row buttons (supports both header rows and clickable objective rows)
    f.rows = {}
    for i = 1, MAX_HUD_ROWS do
        local rowBtn = CreateFrame("Button", nil, f)
        rowBtn:SetHeight(17)
        rowBtn:SetPoint("LEFT", f, "LEFT", 8, 0)
        rowBtn:SetPoint("RIGHT", f, "RIGHT", -8, 0)
        rowBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        rowBtn:RegisterForDrag("LeftButton")

        local hl = rowBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(0.05, 0.82, 0.62, 0.16)
        rowBtn.hl = hl

        local text = rowBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        UI.SetupFontString(text, 13, "OUTLINE")
        text:SetPoint("LEFT", rowBtn, "LEFT", 0, 0)
        text:SetPoint("RIGHT", rowBtn, "RIGHT", 0, 0)
        text:SetJustifyH("LEFT")
        text:SetWordWrap(false)
        rowBtn.text = text

        rowBtn:SetScript("OnDragStart", function()
            local s = f:GetScript("OnDragStart")
            if s then s(f) end
        end)

        rowBtn:SetScript("OnDragStop", function()
            local s = f:GetScript("OnDragStop")
            if s then s(f) end
        end)

        rowBtn:SetScript("OnClick", function(btn, mouseBtn)
            if mouseBtn == "RightButton" and IsShiftKeyDown and IsShiftKeyDown() then
                local onRight = f:GetScript("OnMouseUp")
                if onRight then onRight(f, "RightButton") end
                return
            end
            if btn._dismissQuestID then
                PartyRXP.missedTownQuests[btn._dismissQuestID] = nil
                PartyRXP:UpdateHUD()
                return
            end
            if btn._tagMob and PartyRXP:GetDB().clickToTag ~= false then
                if InCombatLockdown and InCombatLockdown() then
                    print("|cffff4444[EFHelper PartyRXP]|r Cannot update 'EFHRXP' while in combat.")
                    return
                end
                if EFHelper.Tagging and EFHelper.Tagging.CreateOrUpdateTaggingMacro then
                    local spell = (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.lastSpell) or EFHelper.selectedSpell
                    local silent = not (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.silentTagClicks == false)
                    EFHelper.Tagging:CreateOrUpdateTaggingMacro(EFHelper.Tagging.rxpMacroName or "EFHRXP", btn._tagMob, spell, true, silent)
                end
            end
        end)

        rowBtn:SetScript("OnEnter", function(btn)
            if btn._tagMob and PartyRXP:GetDB().clickToTag ~= false and GameTooltip then
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Click to set EFHRXP Target", 0.05, 0.82, 0.62)
                GameTooltip:AddLine("Mob: " .. tostring(btn._tagMob), 1, 0.82, 0)
                GameTooltip:Show()
            elseif btn._dismissQuestID and GameTooltip then
                GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Click to dismiss missed quest notice", 1, 0.75, 0.2)
                GameTooltip:Show()
            end
        end)

        rowBtn:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)

        rowBtn:Hide()
        f.rows[i] = rowBtn
    end

    UI.MakeMovable(f, function() return PartyRXP:GetDB() end, {
        moduleTag = "[EFHelper PartyRXP]",
        isTestModeFn = function() return PartyRXP.isTestMode end,
        onSavePos = function(frame)
            PartyRXP:SavePosition(frame)
        end,
        onLockChanged = function()
            PartyRXP:UpdateHUD()
        end,
    })

    self.hud = f
    return f
end

function PartyRXP:UpdateHUD()
    local db = self:GetDB()
    if db.enabled == false or db.showHUD == false then
        if self.hud then self.hud:Hide() end
        return
    end

    -- Auto-hide the entire Party RXP HUD while inside a dungeon / raid / PvP instance
    if IsInDungeonOrInstance() and not self.isTestMode then
        if self.hud then self.hud:Hide() end
        return
    end

    local inParty = (IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()))
    if not inParty and not self.isTestMode then
        if self.hud then self.hud:Hide() end
        return
    end

    local f = self:CreateHUD()
    local isLocked = (db.locked == true)

    -- Apply HUD scale slider
    local scalePct = tonumber(db.scale) or 100
    f:SetScale(math.max(0.5, math.min(2.0, scalePct / 100)))

    -- Fully transparent when Locked (floating outlined text like the Quest Tracker);
    -- subtle drag box only while Unlocked or in Preview Mode.
    if isLocked and not self.isTestMode then
        f:SetBackdropColor(0, 0, 0, 0)
        f:SetBackdropBorderColor(0, 0, 0, 0)
    else
        f:SetBackdropColor(0.04, 0.05, 0.07, 0.55)
        f:SetBackdropBorderColor(0.2, 0.75, 0.6, 0.55)
    end

    local myLocalMergedObjs = self:GetMergedObjectives(self.localState and self.localState.objectives, true, nil)

    -- Build lookup of which objectives the local player has completed or still has active/incomplete
    local myCompletedSet = {}
    local myIncompleteSet = {}
    local myStep = tonumber(self.localState and self.localState.step)
    local myGuide = (self.localState and self.localState.guide) or ""
    for _, obj in ipairs(myLocalMergedObjs) do
        if obj.text then
            local base = ExtractObjectiveBaseLabel(obj.text):lower()
            if obj.completed then
                myCompletedSet[base] = true
            else
                myIncompleteSet[base] = true
            end
        end
    end

    local function HasSharedObjective(partyObjs)
        if not partyObjs then return false end
        for _, pObj in ipairs(partyObjs) do
            if not pObj.completed and pObj.text then
                local key = ExtractObjectiveBaseLabel(pObj.text):lower()
                if myIncompleteSet[key] then
                    return true
                end
            end
        end
        return false
    end

    local rowSpecs = {}
    local function PushRow(text, tagMob, dismissQuestID, extraTopGap)
        if #rowSpecs < MAX_HUD_ROWS then
            table.insert(rowSpecs, {
                text = text,
                tagMob = tagMob,
                dismissQuestID = dismissQuestID,
                extraTopGap = extraTopGap or 0,
            })
        end
    end

    -- 0. Top Party XP % Row (Current XP percentage of all party members)
    local xpParts = {}
    local myName = NormalizeShortName(Utils.GetUnitName("player")) or "Player"
    local _, myClass = UnitClass("player")
    local coloredSelf = Utils.FormatClassColored(myName, myClass)
    local myXpPct = GetLocalXPPercent()
    table.insert(xpParts, string.format("%s: |cffffffff%d%%|r", coloredSelf, myXpPct))

    if self.isTestMode and next(self.partyState) == nil then
        for _, fst in ipairs(self:GetPreviewPartyStates()) do
            local cName = Utils.FormatClassColored(fst.name, fst.class)
            table.insert(xpParts, string.format("%s: |cffffffff%d%%|r", cName, fst.xpPct or 0))
        end
    else
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                local short = NormalizeShortName(Utils.GetUnitName(unit))
                local key = short and short:lower() or nil
                local st = key and self.partyState[key] or nil
                local _, classToken = UnitClass(unit)
                local cName = Utils.FormatClassColored((st and st.name) or short or unit, classToken or (st and st.class))
                if st and st.xpPct ~= nil then
                    table.insert(xpParts, string.format("%s: |cffffffff%d%%|r", cName, st.xpPct))
                else
                    table.insert(xpParts, string.format("%s: |cff888888–%%|r", cName))
                end
            end
        end
    end

    if #xpParts > 0 then
        PushRow(table.concat(xpParts, "  |cff666666•|r  "), nil, nil, 0)
    end

    local function EmitPlayerSection(headerBadge, coloredName, state, mergedObjs, isSelf, isFirstSection)
        local isTown = isSelf and self.localInTown or (state and state.isTownCycle)
        local catSuffix = isTown and " |cff00ff99(Town)|r" or ""
        PushRow(string.format("%s %s%s", headerBadge, coloredName, catSuffix), nil, nil, isFirstSection and 4 or 5)

        local objs = mergedObjs or (state and state.objectives) or {}
        if #objs == 0 then
            local fallbackProg = "Waiting for step..."
            if state and state.step and state.step > 0 and state.progress and state.progress ~= "" then
                fallbackProg = state.progress
            end
            PushRow("  |cffaaaaaa• " .. fallbackProg .. "|r", nil, nil, 0)
            return
        end

        for _, obj in ipairs(objs) do
            if obj.completed then
                -- Keep completed objectives visible in dim green with a checkmark until step advances
                PushRow(string.format("  |cff44aa66✓ %s|r", obj.text), nil, nil, 0)
            else
                local baseKey = ExtractObjectiveBaseLabel(obj.text):lower()
                local isFarBehind = (not isSelf) and myStep and state.step and (state.step < (myStep - 3))
                local iFinishedAlready = (not isSelf) and (
                    (myCompletedSet[baseKey] and not myIncompleteSet[baseKey])
                    or isFarBehind
                )
                local lineColor = iFinishedAlready and "|cffffd100" or "|cffffffff"
                local tagHint = (obj.mob and db.clickToTag ~= false) and " |cff55bbee[Tag]|r" or ""
                PushRow(string.format("  %s• %s|r%s", lineColor, obj.text, tagHint), obj.mob, nil, 0)
            end
        end
    end

    -- 1. Local Player Section
    local sectionCount = 0
    if db.showSelf ~= false then
        sectionCount = sectionCount + 1
        local selfState = self.localState
        local selfObjs = myLocalMergedObjs
        if self.isTestMode and (not selfState or not selfState.objectives or #selfState.objectives == 0) then
            selfState = {
                step = 14,
                isTownCycle = false,
                objectives = {
                    { text = "Mindless Zombie slain: 8/8", kind = "kill", cur = 8, max = 8, completed = true, mob = "Mindless Zombie" },
                    { text = "Wretched Zombie slain: 8/8", kind = "kill", cur = 8, max = 8, completed = true, mob = "Wretched Zombie" },
                    { text = "Rattlecage Skull: 4/6", kind = "loot", cur = 4, max = 6, completed = false, mob = "Rattlecage Skeleton" },
                },
            }
            selfObjs = selfState.objectives
            myCompletedSet["mindless zombie"] = true
            myCompletedSet["wretched zombie"] = true
        end

        local effectiveSelfStep = (selfState and selfState.step) or myStep
        local selfBadge = (effectiveSelfStep and effectiveSelfStep > 0)
            and string.format("|cff0cd29f[%d]|r", effectiveSelfStep)
            or "|cff0cd29f[–]|r"
        EmitPlayerSection(selfBadge, coloredSelf, selfState, selfObjs, true, sectionCount == 1)
    end

    -- 2. Party Member Sections
    if self.isTestMode and next(self.partyState) == nil then
        for _, fst in ipairs(self:GetPreviewPartyStates()) do
            sectionCount = sectionCount + 1
            local delta = (myStep or 14) and (fst.step - (myStep or 14)) or 0
            local isFunctionallySynced = (delta == 0) or (math.abs(delta) <= 3 and HasSharedObjective(fst.objectives))
            local badge = isFunctionallySynced
                and string.format("|cff00ff00[%d]|r", fst.step)
                or (delta < 0 and string.format("|cffff8800[%d]|r", fst.step) or string.format("|cff00ccff[%d]|r", fst.step))
            local coloredName = Utils.FormatClassColored(fst.name, fst.class)
            EmitPlayerSection(badge, coloredName, fst, fst.objectives, false, sectionCount == 1)
        end
    else
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists(unit) then
                sectionCount = sectionCount + 1
                local short = NormalizeShortName(Utils.GetUnitName(unit))
                local key = short and short:lower() or nil
                local st = key and self.partyState[key] or nil
                local _, classToken = UnitClass(unit)
                if st then
                    local coloredName = Utils.FormatClassColored(st.name, classToken or st.class)
                    local memberMergedObjs = self:GetMergedObjectives(st.objectives, false, key)
                    local badge
                    if myGuide ~= "" and st.guide ~= "" and myGuide:lower() ~= st.guide:lower() then
                        local stepDisp = (st.step and st.step > 0) and tostring(st.step) or "–"
                        badge = string.format("|cffffaa00[%s #%s]|r", st.guide:sub(1, 12), stepDisp)
                    elseif myStep and myStep > 0 and st.step and st.step > 0 then
                        local delta = st.step - myStep
                        local isFunctionallySynced = (delta == 0) or (math.abs(delta) <= 3 and HasSharedObjective(memberMergedObjs))
                        if isFunctionallySynced then
                            badge = string.format("|cff00ff00[%d]|r", st.step)
                        elseif delta < 0 then
                            badge = string.format("|cffff8800[%d]|r", st.step)
                        else
                            badge = string.format("|cff00ccff[%d]|r", st.step)
                        end
                    elseif st.step and st.step > 0 then
                        badge = string.format("|cff00ff00[%d]|r", st.step)
                    else
                        badge = "|cffaaaaaa[–]|r"
                    end
                    EmitPlayerSection(badge, coloredName, st, memberMergedObjs, false, sectionCount == 1)
                else
                    local rawName = Utils.GetUnitName(unit) or unit
                    PushRow(
                        string.format("|cff666666[–]|r %s — |cff666666Waiting...|r", Utils.FormatClassColored(rawName, classToken)),
                        nil, nil, sectionCount == 1 and 4 or 5
                    )
                end
            end
        end
    end

    -- 3. Smart "Group Remaining" Footer (Wrapped 2 items per horizontal line under label)
    local groupRemRows = self:BuildGroupRemainingRows()
    if groupRemRows then
        for idx, line in ipairs(groupRemRows) do
            PushRow(line, nil, nil, idx == 1 and 6 or 0)
        end
    end

    -- 4. Missed Town-Cycle Quest Notices (if any)
    for qID, mInfo in pairs(self.missedTownQuests) do
        if IsQuestInPlayerLog(qID) or IsQuestAlreadyCompleted(qID) then
            self.missedTownQuests[qID] = nil
        else
            PushRow(
                string.format("|cffffaa00! Missed:|r |cffffffff%s|r |cffaaaaaa(%s)|r |cff00ffff[Dismiss]|r", mInfo.title, mInfo.sender),
                nil, qID, 4
            )
        end
    end

    -- Render rows & compute compact vertical frame size
    local yOffset = -6
    local maxTextWidth = 140

    for i = 1, MAX_HUD_ROWS do
        local rowBtn = f.rows[i]
        local spec = rowSpecs[i]
        if spec then
            yOffset = yOffset - (spec.extraTopGap or 0)
            rowBtn:ClearAllPoints()
            rowBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 8, yOffset)
            rowBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, yOffset)
            rowBtn.text:SetText(spec.text)
            rowBtn._tagMob = (db.clickToTag ~= false) and spec.tagMob or nil
            rowBtn._dismissQuestID = spec.dismissQuestID

            local isInteractive = (rowBtn._tagMob ~= nil) or (rowBtn._dismissQuestID ~= nil)
            rowBtn:EnableMouse(isInteractive)
            rowBtn.hl:SetShown(isInteractive)

            rowBtn:Show()
            local w = rowBtn.text:GetStringWidth() or 0
            if w > maxTextWidth then
                maxTextWidth = w
            end
            yOffset = yOffset - 18
        else
            rowBtn:Hide()
        end
    end

    local totalHeight = math.max(24, math.abs(yOffset) + 6)
    local totalWidth = math.min(350, math.max(155, maxTextWidth + 16))
    f:SetSize(totalWidth, totalHeight)
    f:Show()
end

function PartyRXP:ToggleTestMode()
    self.isTestMode = not self.isTestMode
    if self.isTestMode then
        self:GetDB().showHUD = true
    end
    self:UpdateHUD()
    return self.isTestMode
end

function PartyRXP:ResetPosition()
    self:GetDB().pos = nil
    if self.hud then
        self:RestorePosition(self.hud)
    end
end

-- ----------------------------------------------------------------------------
-- Lifecycle
-- ----------------------------------------------------------------------------
function PartyRXP:OnInitialize()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
        pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM_PREFIX)
    end

    self:RegisterEvent("CHAT_MSG_ADDON", "OnChatMsgAddon")
    self:RegisterEvent("QUEST_ACCEPTED", "OnQuestAccepted")
    self:RegisterEvent("QUEST_TURNED_IN", "OnQuestTurnedIn")
    self:RegisterEvent("PLAYER_XP_UPDATE", function()
        PartyRXP:UpdateHUD()
        PartyRXP:ScheduleBroadcast(false)
    end)
    self:RegisterEvent("PLAYER_LEVEL_UP", function()
        PartyRXP:UpdateHUD()
        PartyRXP:ScheduleBroadcast(true)
    end)
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
        PartyRXP:UpdateHUD()
    end)
    self:RegisterEvent("ADDON_LOADED", function(_, loadedName)
        if loadedName == "RXPGuides" then
            PartyRXP:HookRXP()
        end
    end)
    self:RegisterEvent("QUEST_LOG_UPDATE", function()
        if PartyRXP._qlogScanPending then return end
        PartyRXP._qlogScanPending = true
        if C_Timer and C_Timer.After then
            C_Timer.After(0.35, function()
                PartyRXP._qlogScanPending = false
                PartyRXP:SyncLocalRXPStep()
                PartyRXP:RefreshTownQuestDiff(false)
                PartyRXP:ScanQuestLogForCustomProgress()
            end)
        else
            PartyRXP._qlogScanPending = false
            PartyRXP:SyncLocalRXPStep()
            PartyRXP:RefreshTownQuestDiff(false)
            PartyRXP:ScanQuestLogForCustomProgress()
        end
    end)
    self:RegisterEvent("GROUP_ROSTER_UPDATE", function()
        PartyRXP:PruneStalePartyMembers()
        PartyRXP:UpdateHUD()
        if IsInGroup and IsInGroup() then
            PartyRXP:RequestPartySync()
        end
    end)
    self:RegisterEvent("PLAYER_ENTERING_WORLD", function()
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            pcall(C_ChatInfo.RegisterAddonMessagePrefix, COMM_PREFIX)
        end
        PartyRXP:CreateHUD()
        PartyRXP:HookRXP()
        PartyRXP:PruneStalePartyMembers()
        PartyRXP:EnsurePreTownBaselineInitialized()
        PartyRXP:RefreshTownQuestDiff(false)
        PartyRXP:ScanQuestLogForCustomProgress()
        PartyRXP:UpdateHUD()

        -- Launch retry ticker: RXP frequently initializes its guide asynchronously via ScheduleTask after PEW
        if C_Timer and C_Timer.After then
            local retryDelays = { 0.3, 0.8, 1.5, 3.0 }
            for _, delay in ipairs(retryDelays) do
                C_Timer.After(delay, function()
                    PartyRXP:HookRXP()
                    if not PartyRXP.localState or not PartyRXP.localState.step or PartyRXP.localState.step <= 0 then
                        PartyRXP:SyncLocalRXPStep()
                    end
                    if IsInGroup and IsInGroup() then
                        PartyRXP:RequestPartySync()
                    end
                end)
            end
        end
    end)
end
