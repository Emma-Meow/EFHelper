-- ----------------------------------------------------------------------------
-- EFHelper_WaypointBridge.lua
-- Translation Layer: RestedXP (RXPGuides) Active Objective -> WaypointUI 3D Pin
-- Zero-modification bridge between RXPGuides and WaypointUI
-- ----------------------------------------------------------------------------
local addonName, addonTable = ...
local EFHelper = _G.EFHelper or addonTable
if EFHelper.WaypointBridge then return end
local WaypointBridge = EFHelper:NewModule("WaypointBridge", "AceEvent-3.0")
EFHelper.WaypointBridge = WaypointBridge
addonTable.WaypointBridge = WaypointBridge

local Utils = EFHelper.Utils

local BRIDGE_FLAG = "EFHelper_RXP_Waypoint"
local WUI_ICON_PATH = "Interface\\AddOns\\WaypointUI\\Art\\Icons\\"

-- Visual profiles per detected RXP step objective category
local CATEGORY_PROFILES = {
    KILL = {
        label = "Kill / Combat",
        icon  = "Interface\\GossipFrame\\BattleMasterGossipIcon",
        r = 1.00, g = 0.45, b = 0.40,
    },
    KILL_LOOT = {
        label = "Kill & Loot",
        icon  = "Interface\\GossipFrame\\BattleMasterGossipIcon",
        r = 1.00, g = 0.62, b = 0.35,
    },
    LOOT = {
        label = "Loot / Collect",
        icon  = "Interface\\GossipFrame\\VendorGossipIcon",
        r = 1.00, g = 0.76, b = 0.35,
    },
    TURNIN = {
        label = "Quest Turn-In",
        icon  = WUI_ICON_PATH .. "CompleteQuest",
        r = 0.45, g = 1.00, b = 0.58,
    },
    TURNIN_ACCEPT = {
        label = "Turn-In & Accept",
        icon  = WUI_ICON_PATH .. "CompleteQuest",
        r = 1.00, g = 0.92, b = 0.42,
    },
    ACCEPT = {
        label = "Quest Accept",
        icon  = WUI_ICON_PATH .. "AvailableQuest",
        r = 1.00, g = 0.85, b = 0.30,
    },
    TRAIN = {
        label = "Trainer",
        icon  = "Interface\\GossipFrame\\TrainerGossipIcon",
        r = 0.55, g = 0.88, b = 1.00,
    },
    VENDOR = {
        label = "Vendor / Restock",
        icon  = "Interface\\GossipFrame\\BankerGossipIcon",
        r = 0.95, g = 0.80, b = 0.45,
    },
    FLY = {
        label = "Flight Path",
        icon  = "Interface\\GossipFrame\\TaxiGossipIcon",
        r = 0.50, g = 0.92, b = 0.95,
    },
    HOME = {
        label = "Hearthstone / Home",
        icon  = "Interface\\MINIMAP\\TRACKING\\Innkeeper",
        r = 0.82, g = 0.62, b = 1.00,
    },
    TALK = {
        label = "Talk / Interact",
        icon  = "Interface\\GossipFrame\\GossipGossipIcon",
        r = 0.82, g = 0.95, b = 1.00,
    },
    TRAVEL = {
        label = "Travel / Goto",
        icon  = WUI_ICON_PATH .. "Navigation",
        r = 1.00, g = 0.94, b = 0.71,
    },
}

-- Cached state to avoid redundant WaypointUI calls during RXP ticker updates
local lastElement = nil
local lastMapID = nil
local lastRoundedX = nil
local lastRoundedY = nil
local lastTitle = nil
local lastCategory = nil
local lastIconTexture = nil
local lastR = nil
local lastG = nil
local lastB = nil
local lastUseColor = true

-- Loop chain lock state (prevents spawn-loop arrow cycling from moving the 3D pin)
local lockedLoopStep = nil
local lockedLoopKey = nil
local lockedLoopElement = nil

-- Re-entrancy guards for hooks
local isEnforcingSuperTrack = false
local isApplyingWUIVisuals = false

-- ----------------------------------------------------------------------------
-- External Addon Accessors
-- ----------------------------------------------------------------------------
local function GetRXP()
    if LibStub then
        local ace = LibStub("AceAddon-3.0", true)
        if ace then
            return ace:GetAddon("RXPGuides", true)
        end
    end
    return nil
end

local function GetWUI()
    return _G.WaypointUIAPI and _G.WaypointUIAPI.Navigation or nil
end

local function GetHBD()
    return LibStub and LibStub("HereBeDragons-2.0", true) or nil
end

function WaypointBridge:GetDB()
    if EFHelper.db and EFHelper.db.profile then
        if not EFHelper.db.profile.WaypointBridge then
            EFHelper.db.profile.WaypointBridge = {
                enabled = true,
                showStepSummary = true,
                colorByType = true,
            }
        else
            local wb = EFHelper.db.profile.WaypointBridge
            if wb.showStepSummary == nil then wb.showStepSummary = true end
            if wb.colorByType == nil then wb.colorByType = true end
        end
        return EFHelper.db.profile.WaypointBridge
    end
    return { enabled = true, showStepSummary = true, colorByType = true }
end

function WaypointBridge:GetStatusInfo()
    local rxp = GetRXP()
    local wui = GetWUI()
    local profile = lastCategory and CATEGORY_PROFILES[lastCategory] or nil
    return {
        rxpLoaded = rxp ~= nil,
        wuiLoaded = wui ~= nil,
        lastTitle = lastTitle,
        lastCategory = profile and profile.label or nil,
        lastMapID = lastMapID,
        lastX = lastRoundedX and (lastRoundedX / 10) or nil,
        lastY = lastRoundedY and (lastRoundedY / 10) or nil,
        isLoopLocked = (lockedLoopKey ~= nil),
    }
end

-- ----------------------------------------------------------------------------
-- Runtime WUI Frame Visual Enforcement & SuperTrack Protection
-- ----------------------------------------------------------------------------
local function EnsureWUIFooterWidth()
    local wf = _G.WUIWaypointFrame
    if wf and wf.Footer and not wf.Footer._efWidened then
        wf.Footer._efWidened = true
        pcall(function()
            if wf.Footer.width then wf.Footer:width(260) end
            if wf.Footer.SetWidth then wf.Footer:SetWidth(260) end
            if wf.Footer.InfoText then
                if wf.Footer.InfoText.width then wf.Footer.InfoText:width(260) end
                if wf.Footer.InfoText.SetWidth then wf.Footer.InfoText:SetWidth(260) end
            end
            if wf.Footer.DistanceText then
                if wf.Footer.DistanceText.width then wf.Footer.DistanceText:width(260) end
                if wf.Footer.DistanceText.SetWidth then wf.Footer.DistanceText:SetWidth(260) end
            end
            if wf.Footer.ArrivalTimeText then
                if wf.Footer.ArrivalTimeText.width then wf.Footer.ArrivalTimeText:width(260) end
                if wf.Footer.ArrivalTimeText.SetWidth then wf.Footer.ArrivalTimeText:SetWidth(260) end
            end
            if wf.Footer._Render then wf.Footer:_Render() end
        end)
    end
end

--- Prevents RXP's C_SuperTrack.SetSuperTrackedQuestID calls (on .complete steps)
-- from hijacking highest-priority super-tracking away from our UserWaypoint,
-- which otherwise causes WaypointUI to treat the pin as an IncompleteQuest ('?' grey).
local function EnforceUserWaypointSuperTrack()
    if isEnforcingSuperTrack then return end
    if not lastMapID then return end
    if not (C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint()) then return end

    isEnforcingSuperTrack = true
    pcall(function()
        if C_SuperTrack then
            if C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.SetSuperTrackedQuestID then
                local trackedQuest = C_SuperTrack.GetSuperTrackedQuestID()
                if trackedQuest and trackedQuest ~= 0 then
                    C_SuperTrack.SetSuperTrackedQuestID(0)
                end
            end
            if C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end
    end)
    isEnforcingSuperTrack = false
end

--- Directly applies our active step summary, category icon, diamond/card tint,
-- and beacon beam color to WaypointUI's Waypoint, Pinpoint, and Navigator frames.
-- Hooked onto WaypointUI's frame update methods so asynchronous context refreshes
-- (such as Waypoint_Director's 0.075s distanceAwait) never revert our visuals.
local function ApplyActiveWUIVisuals()
    if isApplyingWUIVisuals then return end
    if not lastMapID or not lastTitle then return end
    if WaypointBridge:GetDB().enabled == false then return end

    isApplyingWUIVisuals = true
    EnsureWUIFooterWidth()

    local iconData = nil
    local tintColor = nil
    if lastUseColor and lastIconTexture and lastR and lastG and lastB then
        iconData = {
            type = "TEXTURE",
            path = lastIconTexture,
            requestRecolor = true,
        }
        tintColor = {
            r = lastR,
            g = lastG,
            b = lastB,
            a = 1,
        }
    end

    -- 1. 3D Waypoint Beacon (WUIWaypointFrame)
    local wf = _G.WUIWaypointFrame
    if wf then
        pcall(function()
            if iconData and tintColor then
                if wf.SetIcon then wf:SetIcon(iconData) end
                if wf.SetTint then wf:SetTint(tintColor) end
                if wf.SetBeamTint then wf:SetBeamTint(tintColor) end
                if wf.SetIconRecolor then wf:SetIconRecolor(true) end
            end
            if wf.Footer and wf.Footer.InfoText then
                wf.Footer.InfoText:SetShown(true)
                if wf.Footer.InfoText:GetText() ~= lastTitle then
                    wf.Footer.InfoText:SetText(lastTitle)
                end
                if tintColor and wf.Footer.InfoText.SetTextColor then
                    wf.Footer.InfoText:SetTextColor(tintColor.r, tintColor.g, tintColor.b, 1)
                end
                if wf.Footer.InfoText.FitContent then
                    wf.Footer.InfoText:FitContent()
                end
                if wf.Footer._Render then
                    wf.Footer:_Render()
                end
            end
        end)
    end

    -- 2. Close-Range Pinpoint Card (WUIPinpointFrame)
    local pf = _G.WUIPinpointFrame
    if pf then
        pcall(function()
            if iconData and tintColor then
                if pf.SetIcon then pf:SetIcon(iconData) end
                if pf.SetTint then pf:SetTint(tintColor) end
                if pf.SetIconRecolor then pf:SetIconRecolor(true) end
            end
            if pf.Foreground and pf.Foreground.Content then
                local hasText = (#lastTitle > 1)
                if pf.Foreground.Background then
                    pf.Foreground.Background:SetShown(hasText)
                end
                if pf.Foreground.Content:GetText() ~= lastTitle then
                    pf.Foreground.Content:SetText(lastTitle)
                end
                if tintColor and pf.Foreground.Content.SetTextColor then
                    pf.Foreground.Content:SetTextColor(tintColor.r, tintColor.g, tintColor.b, 1)
                end
                if pf.SetIconOpacity then
                    pf:SetIconOpacity(hasText and 0.5 or 1)
                end
            end
        end)
    end

    -- 3. Off-Screen Edge Navigator Arrow (WUINavigatorFrame)
    local nf = _G.WUINavigatorFrame
    if nf and iconData and tintColor then
        pcall(function()
            if nf.SetIcon then nf:SetIcon(iconData) end
            if nf.SetTint then nf:SetTint(tintColor) end
            if nf.SetIconRecolor then nf:SetIconRecolor(true) end
        end)
    end

    isApplyingWUIVisuals = false
end

-- ----------------------------------------------------------------------------
-- RXP Active Objective Inspection & Loop Detection
-- ----------------------------------------------------------------------------
local function RoundCoord(val)
    return math.floor((val or 0) * 10 + 0.5)
end

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

--- Verifies whether RXP's arrowFrame.element is genuinely active right now,
-- independent of whether the player hid RXP's 2D arrow in RXP settings.
local function IsElementCurrentlyActive(rxp, af, element)
    if not element or not af then return false end
    if af.wrongContinent or (rxp.IsInInstance and rxp.IsInInstance()) then
        return false
    end
    if element.hidden or element.skip then
        return false
    end

    -- Ghost corpse / Spirit Healer waypoint (wpHash == 0, generated == 1)
    if element.wpHash == 0 and element.generated == 1 then
        return UnitIsGhost and UnitIsGhost("player") and true or false
    end

    local step = element.step
    if not step or not step.active then
        return false
    end

    local src = element.source or element
    local parent = (type(src.parent) == "table") and src.parent
        or ((type(element.parent) == "table") and element.parent)
        or nil
    if parent and (parent.completed or parent.skip) then
        return false
    end

    if not rxp.activeWaypoints or #rxp.activeWaypoints == 0 then
        return false
    end

    return true
end

--- Identifies if an element belongs to an RXP loop chain (#loop step or .loop segments).
-- Returns a non-nil key representing the loop chain (scoped per objective so a 2nd
-- distinct objective in the same step still gets its own waypoint).
local function GetLoopChainKey(element)
    if not element then return nil end
    local step = element.step

    -- 1. Polygon / segment loop (.loop command generates linePoints with element.anchor)
    if element.anchor and (element.anchor.tag == "loop" or element.anchor.segments) then
        return element.anchor
    end
    if element.tag == "loop" or element.segments then
        return element
    end

    -- 2. Step-level #loop directive (step.loop is truthy)
    if step and step.loop then
        local src = element.source or element
        local parent = (type(src.parent) == "table") and src.parent
            or ((type(element.parent) == "table") and element.parent)
            or nil
        return parent or step
    end

    return nil
end

--- Resolves valid (mapID, x, y) on a 0..100 scale for WaypointUI.
local function ResolveElementCoordinates(element)
    if not element then return nil end

    local canSet = C_Map and C_Map.CanSetUserWaypointOnMap
    local mapID = tonumber(element.zone)
    local x = tonumber(element.x)
    local y = tonumber(element.y)

    if mapID and x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
        if not canSet or canSet(mapID) then
            return mapID, x, y
        end
    end

    -- Fallback: resolve from world coordinates (wx, wy) via HereBeDragons-2.0
    local HBD = GetHBD()
    if HBD and element.wx and element.wy then
        local candidates = {}
        if mapID then table.insert(candidates, mapID) end
        if C_Map and C_Map.GetBestMapForUnit then
            local playerMap = C_Map.GetBestMapForUnit("player")
            if playerMap and playerMap ~= mapID then
                table.insert(candidates, playerMap)
            end
        end

        for _, candidate in ipairs(candidates) do
            local cur = candidate
            local depth = 0
            while cur and cur ~= 0 and depth < 5 do
                depth = depth + 1
                if not canSet or canSet(cur) then
                    local zx, zy = HBD:GetZoneCoordinatesFromWorld(element.wx, element.wy, cur)
                    if zx and zy and zx >= 0 and zx <= 1 and zy >= 0 and zy <= 1 then
                        return cur, zx * 100, zy * 100
                    end
                end
                local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(cur)
                cur = info and info.parentMapID or nil
            end
        end
    end

    return nil
end

-- ----------------------------------------------------------------------------
-- Rich Step Context & Objective Classification
-- ----------------------------------------------------------------------------
local GOTO_TAGS = {
    ["goto"] = true,
    ["groundgoto"] = true,
    ["flygoto"] = true,
    ["waypoint"] = true,
    ["loop"] = true,
}

--- Partitions step.elements into waypoint clusters so multi-NPC steps only show
-- the objectives & targets associated with the currently active waypoint cluster,
-- while single-cluster / loop steps include all active objectives in the step.
local function GetRelevantStepElements(step, activeElement)
    if not step or type(step.elements) ~= "table" then
        return {}
    end

    local elements = step.elements
    local targetGoto = (activeElement and (activeElement.source or activeElement.anchor)) or activeElement

    local clusters = {}
    local pendingNonGoto = {}
    local currentCluster = nil

    for _, el in ipairs(elements) do
        local isGoto = (el.tag and GOTO_TAGS[el.tag]) or (el.x and el.y and el.zone)
        if isGoto then
            if not currentCluster then
                currentCluster = {
                    gotos = {},
                    items = {},
                }
                for _, item in ipairs(pendingNonGoto) do
                    table.insert(currentCluster.items, item)
                end
                pendingNonGoto = {}
                table.insert(clusters, currentCluster)
            end
            table.insert(currentCluster.gotos, el)
            if el.text and el.text ~= "" then
                table.insert(currentCluster.items, el)
            end
        else
            currentCluster = nil
            table.insert(pendingNonGoto, el)
        end
    end

    -- Attach any trailing non-goto elements (e.g. Pattern A where .gotos are at the
    -- top of the step and .complete / .mob lines are below them) to the last cluster.
    if #pendingNonGoto > 0 then
        if #clusters > 0 then
            local lastC = clusters[#clusters]
            for _, item in ipairs(pendingNonGoto) do
                table.insert(lastC.items, item)
            end
        else
            return pendingNonGoto
        end
    end

    if #clusters <= 1 then
        return clusters[1] and clusters[1].items or elements
    end

    -- Find which cluster owns targetGoto (or shares its parent objective)
    local targetParent = targetGoto and type(targetGoto.parent) == "table" and targetGoto.parent or nil
    for _, c in ipairs(clusters) do
        for _, g in ipairs(c.gotos) do
            if g == targetGoto or g == activeElement then
                if #c.items > 0 then
                    return c.items
                end
            end
        end
        if targetParent then
            for _, item in ipairs(c.items) do
                if item == targetParent then
                    return c.items
                end
            end
        end
    end

    return elements
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
            local parsedName = rawUnit:match("^%+?(.+)::%d+$") or rawUnit:match("^%+?(.+)$")
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

--- Extracts a structured summary and objective category from the active RXP step/element.
-- Returns: summaryText, categoryKey, iconTexture, r, g, b
local function ExtractStepContext(rxp, element, useRichSummary)
    if not element then
        local prof = CATEGORY_PROFILES.TRAVEL
        return "Objective", "TRAVEL", prof.icon, prof.r, prof.g, prof.b
    end

    -- Ghost corpse run special case
    if element.wpHash == 0 and element.generated == 1 then
        local prof = CATEGORY_PROFILES.TRAVEL
        return "Run to your Corpse", "TRAVEL", prof.icon, 0.9, 0.95, 1.0
    end

    local step = element.step
    local clusterItems = GetRelevantStepElements(step, element)

    local targets, seenTargets = {}, {}
    local mobs, seenMobs = {}, {}
    local objectiveLines, seenLines = {}, {}
    local noteLines = {}

    local flags = {
        kill = false,
        loot = false,
        turnin = false,
        accept = false,
        train = false,
        vendor = false,
        fly = false,
        home = false,
        talk = false,
        grind = false,
    }

    local combatIcon = rxp and rxp.icons and rxp.icons.combat
    local collectIcon = rxp and rxp.icons and rxp.icons.collect

    local function AddLine(list, str)
        local clean = SanitizeRXPText(rxp, str)
        if clean and not seenLines[clean:lower()] then
            seenLines[clean:lower()] = true
            table.insert(list, clean)
        end
    end

    for _, el in ipairs(clusterItems) do
        local parentDone = (type(el.parent) == "table") and (el.parent.completed or el.parent.skip)
        if not el.skip and not el.hidden and not parentDone then
            local tag = el.tag

            if tag == "target" then
                ResolveUnitListNames(rxp, el.targets or el.unitlist, targets, seenTargets)
            elseif tag == "mob" or tag == "unitscan" then
                ResolveUnitListNames(rxp, el.mobs or el.unitscan or el.unitlist, mobs, seenMobs)
            elseif not el.completed then
                if tag == "complete" then
                    if combatIcon and el.icon == combatIcon then
                        flags.kill = true
                    elseif collectIcon and el.icon == collectIcon then
                        flags.loot = true
                    else
                        local lower = (el.text or ""):lower()
                        if lower:find("slain") or lower:find("^kill ") then
                            flags.kill = true
                        else
                            flags.loot = true
                        end
                    end
                    AddLine(objectiveLines, el.text or el.rawtext)

                elseif tag == "collect" or tag == "collectmultiple" or tag == "questitemcount" or tag == "blastedLands" then
                    flags.loot = true
                    AddLine(objectiveLines, el.text or el.itemName)

                elseif tag == "turnin" or tag == "dailyturnin" or tag == "turninmultiple" then
                    flags.turnin = true
                    local t = el.text or (el.title and ("Turn in " .. el.title))
                    AddLine(objectiveLines, t)

                elseif tag == "accept" or tag == "daily" or tag == "acceptmultiple" then
                    flags.accept = true
                    local t = el.text or (el.title and ("Accept " .. el.title))
                    AddLine(objectiveLines, t)

                elseif tag == "train" or tag == "trainer" or tag == "tradeskill" or tag == "dualspec" then
                    flags.train = true
                    AddLine(objectiveLines, el.text or "Train spells")

                elseif tag == "vendor" or tag == "buy" or tag == "buyAll" or tag == "buyUntilBroke" or tag == "bankdeposit" or tag == "bankwithdraw" then
                    flags.vendor = true
                    AddLine(objectiveLines, el.text or "Vendor / Restock")

                elseif tag == "fly" or tag == "fp" then
                    flags.fly = true
                    AddLine(objectiveLines, el.text or el.tooltipText or (el.location and ("Fly to " .. el.location)))

                elseif tag == "hs" or tag == "home" or tag == "bindlocation" then
                    flags.home = true
                    AddLine(objectiveLines, el.text or el.tooltipText or (el.location and ("Hearthstone: " .. el.location)))

                elseif tag == "xp" or tag == "reputation" then
                    flags.grind = true
                    AddLine(objectiveLines, el.text or el.rawtext)

                elseif tag == "gossip" or tag == "gossipoption" or tag == "skipgossip" then
                    flags.talk = true
                    AddLine(objectiveLines, el.text)

                elseif tag == "cast" or tag == "use" or tag == "usespell" or tag == "emote" or tag == "vehicle" then
                    AddLine(objectiveLines, el.text)

                elseif GOTO_TAGS[tag or ""] then
                    if el.text and el.text ~= "" then
                        AddLine(noteLines, el.text)
                    end
                elseif el.text and el.text ~= "" then
                    AddLine(noteLines, el.text)
                end
            elseif el.textOnly and el.text and el.text ~= "" then
                -- Guide instruction lines (e.g. >>Talk to Sarvis, >>Kill Zombies) have textOnly=true
                -- and RXP marks element.completed=true on render; keep them in noteLines!
                AddLine(noteLines, el.text)
            end
        end
    end

    -- Determine primary category
    local category = "TRAVEL"
    if flags.kill and flags.loot then
        category = "KILL_LOOT"
    elseif flags.kill or (flags.grind and #mobs > 0) then
        category = "KILL"
    elseif flags.loot and #mobs > 0 then
        category = "KILL_LOOT"
    elseif flags.loot then
        category = "LOOT"
    elseif flags.turnin and flags.accept then
        category = "TURNIN_ACCEPT"
    elseif flags.turnin then
        category = "TURNIN"
    elseif flags.accept then
        category = "ACCEPT"
    elseif flags.train then
        category = "TRAIN"
    elseif flags.vendor then
        category = "VENDOR"
    elseif flags.fly then
        category = "FLY"
    elseif flags.home then
        category = "HOME"
    elseif flags.talk or #targets > 0 then
        category = "TALK"
    elseif #mobs > 0 then
        category = "KILL"
    end

    local prof = CATEGORY_PROFILES[category] or CATEGORY_PROFILES.TRAVEL

    -- If rich summary is disabled in settings, return a single-line title
    if not useRichSummary then
        local single = objectiveLines[1] or noteLines[1]
        if not single then
            if #targets > 0 then
                single = "Talk to " .. table.concat(targets, ", ")
            elseif #mobs > 0 then
                single = "Kill " .. table.concat(mobs, ", ")
            elseif step and step.index then
                single = "Step " .. tostring(step.index)
            else
                single = "Objective"
            end
        end
        return single, category, prof.icon, prof.r, prof.g, prof.b
    end

    -- Build rich multi-line context summary (capped at 4 concise lines)
    local finalLines = {}
    local maxLines = 4

    local joinedObjectivesLower = table.concat(objectiveLines, " "):lower()

    -- 1. Friendly NPC Target header (if not already stated in objective lines)
    if #targets > 0 then
        local missingTargets = {}
        for _, npc in ipairs(targets) do
            if not joinedObjectivesLower:find(npc:lower(), 1, true) then
                table.insert(missingTargets, npc)
            end
        end
        if #missingTargets > 0 then
            local targetListStr = table.concat(missingTargets, ", ")
            table.insert(finalLines, "Talk to " .. targetListStr)
        end
    end

    -- 2. Enemy Mob Target header (when mobs aren't already named in the objective lines,
    --    e.g. "0/3 Rattlecage Skull" where the mob is "Rattlecage Skeleton")
    if #mobs > 0 then
        local missingMobs = {}
        for _, mob in ipairs(mobs) do
            if not joinedObjectivesLower:find(mob:lower(), 1, true) then
                table.insert(missingMobs, mob)
            end
        end
        if #missingMobs > 0 then
            local mobPrefix = (category == "KILL_LOOT") and "Kill & Loot: " or "Kill: "
            table.insert(finalLines, mobPrefix .. table.concat(missingMobs, ", "))
        end
    end

    -- 3. Active Objective Progress Lines (.complete, .collect, .turnin, .accept, .train, etc.)
    for _, line in ipairs(objectiveLines) do
        if #finalLines < maxLines then
            table.insert(finalLines, line)
        else
            break
        end
    end

    -- 4. Fallback to instruction note lines (>> ...) if no structured objectives were added
    if #finalLines == 0 then
        for _, line in ipairs(noteLines) do
            if #finalLines < 2 then
                table.insert(finalLines, line)
            else
                break
            end
        end
    end

    -- 5. Ultimate fallback to element title / step index
    if #finalLines == 0 then
        local rawFallback = SanitizeRXPText(rxp, element.title or (step and (step.arrowtext or step.title or step.text)))
        if rawFallback then
            table.insert(finalLines, rawFallback)
        elseif step and step.index then
            table.insert(finalLines, "Step " .. tostring(step.index))
        else
            table.insert(finalLines, "Objective")
        end
    end

    local summaryText = table.concat(finalLines, "\n")
    return summaryText, category, prof.icon, prof.r, prof.g, prof.b
end

--- Updates an already-placed WaypointUI user navigation in-place when only the
-- objective progress text (e.g. 6/8 -> 7/8) or category changed at the same coordinates,
-- avoiding re-triggering WaypointUI's hide/intro animation.
local function UpdateActiveWUIContextInPlace(title, iconTexture, r, g, b, useColor)
    lastTitle = title
    lastIconTexture = iconTexture
    lastR = r
    lastG = g
    lastB = b
    lastUseColor = useColor

    EnforceUserWaypointSuperTrack()

    local updatedInSession = false
    if _G.WaypointDB_Local and _G.WaypointDB_Local.mapPinSessionData then
        local nav = _G.WaypointDB_Local.mapPinSessionData.userNavigation
        if nav and nav.flags == BRIDGE_FLAG then
            nav.name = title
            nav.stripCoordinates = true
            if useColor then
                nav.iconTexture = iconTexture
                nav.r = r
                nav.g = g
                nav.b = b
                nav.requestRecolor = true
            else
                nav.iconTexture = nil
                nav.r = nil
                nav.g = nil
                nav.b = nil
            end
            updatedInSession = true
        end
    end

    ApplyActiveWUIVisuals()
    return updatedInSession
end

-- ----------------------------------------------------------------------------
-- Waypoint Synchronization
-- ----------------------------------------------------------------------------
function WaypointBridge:ClearSyncedWaypoint()
    lastElement = nil
    lastMapID = nil
    lastRoundedX = nil
    lastRoundedY = nil
    lastTitle = nil
    lastCategory = nil
    lastIconTexture = nil
    lastR = nil
    lastG = nil
    lastB = nil
    lockedLoopStep = nil
    lockedLoopKey = nil
    lockedLoopElement = nil

    local wui = GetWUI()
    if wui and wui.IsUserNavigationFlagged and wui.ClearUserNavigation then
        local ok, isOurs = pcall(wui.IsUserNavigationFlagged, BRIDGE_FLAG)
        if ok and isOurs then
            pcall(wui.ClearUserNavigation)
        end
    end
end

function WaypointBridge:SyncObjective(force)
    local db = self:GetDB()
    if db.enabled == false then
        self:ClearSyncedWaypoint()
        return
    end

    local rxp = GetRXP()
    local wui = GetWUI()
    if not rxp or not wui or not wui.NewUserNavigation then
        return
    end

    local af = rxp.arrowFrame or _G.RXPG_ARROW
    local element = af and af.element or nil

    if not IsElementCurrentlyActive(rxp, af, element) then
        self:ClearSyncedWaypoint()
        return
    end

    EnsureWUIFooterWidth()

    local step = element.step
    local loopKey = GetLoopChainKey(element)
    local useRichSummary = (db.showStepSummary ~= false)
    local useColor = (db.colorByType ~= false)

    -- If this element is part of a loop chain (#loop or .loop) and we have already
    -- placed the initial waypoint for this (step, loopKey), keep the 1st coordinate
    -- locked, but still allow live text updates (e.g. 6/8 -> 7/8 slain)!
    if not force and loopKey ~= nil and step == lockedLoopStep and loopKey == lockedLoopKey and lastMapID ~= nil then
        local contextEl = lockedLoopElement or element
        local title, category, iconTexture, r, g, b = ExtractStepContext(rxp, contextEl, useRichSummary)
        if title ~= lastTitle or category ~= lastCategory or useColor ~= lastUseColor then
            lastCategory = category
            UpdateActiveWUIContextInPlace(title, iconTexture, r, g, b, useColor)
        else
            EnforceUserWaypointSuperTrack()
            ApplyActiveWUIVisuals()
        end
        return
    end

    local mapID, x, y = ResolveElementCoordinates(element)
    if not mapID or not x or not y then
        self:ClearSyncedWaypoint()
        return
    end

    local rx = RoundCoord(x)
    local ry = RoundCoord(y)
    local title, category, iconTexture, r, g, b = ExtractStepContext(rxp, element, useRichSummary)

    lastElement = element
    lockedLoopStep = (loopKey ~= nil) and step or nil
    lockedLoopKey = loopKey
    lockedLoopElement = (loopKey ~= nil) and element or nil

    -- If coordinates are unchanged, update text/context in-place without re-playing intro animation
    if not force and mapID == lastMapID and rx == lastRoundedX and ry == lastRoundedY then
        if title ~= lastTitle or category ~= lastCategory or useColor ~= lastUseColor then
            lastCategory = category
            if UpdateActiveWUIContextInPlace(title, iconTexture, r, g, b, useColor) then
                return
            end
        else
            EnforceUserWaypointSuperTrack()
            ApplyActiveWUIVisuals()
            return
        end
    end

    lastMapID = mapID
    lastRoundedX = rx
    lastRoundedY = ry
    lastTitle = title
    lastCategory = category
    lastIconTexture = iconTexture
    lastR = r
    lastG = g
    lastB = b
    lastUseColor = useColor

    local navOpts = {
        name = title,
        mapID = mapID,
        x = x,
        y = y,
        flags = BRIDGE_FLAG,
        suppressAudio = true,
        stripCoordinates = true,
    }

    if useColor then
        navOpts.iconTexture = iconTexture
        navOpts.r = r
        navOpts.g = g
        navOpts.b = b
        navOpts.requestRecolor = true
    end

    pcall(wui.NewUserNavigation, navOpts)
    EnforceUserWaypointSuperTrack()
    ApplyActiveWUIVisuals()
end

-- ----------------------------------------------------------------------------
-- Non-Invasive RXP, SuperTrack & WaypointUI Frame Hooks
-- ----------------------------------------------------------------------------
function WaypointBridge:HookWUIFrames()
    if self.isWUIHooked then return end
    local wf = _G.WUIWaypointFrame
    local pf = _G.WUIPinpointFrame
    local nf = _G.WUINavigatorFrame
    if not wf or not pf then return end

    self.isWUIHooked = true

    if type(wf.UpdateText) == "function" then
        hooksecurefunc(wf, "UpdateText", ApplyActiveWUIVisuals)
    end
    if type(wf.UpdateFooter) == "function" then
        hooksecurefunc(wf, "UpdateFooter", ApplyActiveWUIVisuals)
    end
    if type(wf.SetIconRecolor) == "function" then
        hooksecurefunc(wf, "SetIconRecolor", ApplyActiveWUIVisuals)
    end

    if type(pf.UpdateText) == "function" then
        hooksecurefunc(pf, "UpdateText", ApplyActiveWUIVisuals)
    end
    if type(pf.SetIconRecolor) == "function" then
        hooksecurefunc(pf, "SetIconRecolor", ApplyActiveWUIVisuals)
    end

    if nf and type(nf.SetIconRecolor) == "function" then
        hooksecurefunc(nf, "SetIconRecolor", ApplyActiveWUIVisuals)
    end
end

function WaypointBridge:HookRXP()
    -- 1. Guard C_SuperTrack so RXP's quest tracker calls don't hijack our UserWaypoint
    if not self.isSuperTrackHooked and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID then
        self.isSuperTrackHooked = true
        hooksecurefunc(C_SuperTrack, "SetSuperTrackedQuestID", function()
            if WaypointBridge:GetDB().enabled ~= false then
                EnforceUserWaypointSuperTrack()
                ApplyActiveWUIVisuals()
            end
        end)
    end

    -- 2. Hook WaypointUI frames so async distanceAwait (0.075s) updates preserve our style & text
    self:HookWUIFrames()

    local rxp = GetRXP()
    if not rxp then return end

    if not self.isRXPHooked then
        self.isRXPHooked = true

        if type(rxp.UpdateMap) == "function" then
            hooksecurefunc(rxp, "UpdateMap", function()
                WaypointBridge:SyncObjective(false)
            end)
        end

        if type(rxp.UpdateGotoSteps) == "function" then
            hooksecurefunc(rxp, "UpdateGotoSteps", function()
                WaypointBridge:SyncObjective(false)
            end)
        end

        if rxp.RXPFrame and rxp.RXPFrame.CurrentStepFrame and type(rxp.RXPFrame.CurrentStepFrame.UpdateText) == "function" then
            hooksecurefunc(rxp.RXPFrame.CurrentStepFrame, "UpdateText", function()
                WaypointBridge:SyncObjective(false)
            end)
        end
    end

    local af = rxp.arrowFrame or _G.RXPG_ARROW
    if af and not self.isArrowHooked then
        self.isArrowHooked = true
        hooksecurefunc(af, "Hide", function()
            WaypointBridge:SyncObjective(false)
        end)
        hooksecurefunc(af, "SetShown", function()
            WaypointBridge:SyncObjective(false)
        end)
    end

    self:SyncObjective(false)
end

function WaypointBridge:OnInitialize()
    self.isRXPHooked = false
    self.isArrowHooked = false
    self.isSuperTrackHooked = false
    self.isWUIHooked = false
end

function WaypointBridge:OnEnable()
    self:RegisterEvent("ADDON_LOADED", "OnAddonLoaded")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("SUPER_TRACKING_CHANGED", "OnSuperTrackingChanged")
    self:RegisterEvent("QUEST_LOG_UPDATE", "OnQuestLogUpdate")
    self:HookRXP()
end

function WaypointBridge:OnDisable()
    self:ClearSyncedWaypoint()
    self:UnregisterAllEvents()
end

function WaypointBridge:OnAddonLoaded(_, loadedName)
    if loadedName == "RXPGuides" or loadedName == "WaypointUI" then
        self:HookRXP()
    end
end

function WaypointBridge:OnPlayerEnteringWorld()
    self:HookRXP()
end

function WaypointBridge:OnSuperTrackingChanged()
    if self:GetDB().enabled ~= false then
        EnforceUserWaypointSuperTrack()
        ApplyActiveWUIVisuals()
    end
end

function WaypointBridge:OnQuestLogUpdate()
    if self:GetDB().enabled ~= false and lastMapID ~= nil then
        self:SyncObjective(false)
    end
end
