-- ----------------------------------------------------------------------------
-- EFHelper_Swapper.lua
-- Out-of-Combat Raid Subgroup Swapper for WoW Forever (Midnight 12.0 API)
-- ----------------------------------------------------------------------------
local addonName, addonTable = ...
local EFHelper = _G.EFHelper or addonTable
local Swapper = EFHelper:NewModule("Swapper", "AceEvent-3.0")
EFHelper.Swapper = Swapper

local Utils = EFHelper.Utils
local UI = EFHelper.UI

-- Session runtime state
Swapper.state = {
    slot1 = nil,
    slot2 = nil,
}

local lastSwapTime = 0
local lastSwapKey = ""

-- ----------------------------------------------------------------------------
-- Database Access
-- ----------------------------------------------------------------------------
function Swapper:GetDB()
    if EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.Swapper then
        return EFHelper.db.profile.Swapper
    end
    EFHelperDB = EFHelperDB or {}
    EFHelperDB.Swapper = EFHelperDB.Swapper or {}
    local db = EFHelperDB.Swapper
    if db.enabled == nil then db.enabled = true end
    if db.showHUD == nil then db.showHUD = false end
    if db.dummyName == nil then db.dummyName = "" end
    return db
end

-- ----------------------------------------------------------------------------
-- Roster & Name Helpers (First + Last Name Format)
-- ----------------------------------------------------------------------------
function Swapper:FindRosterMember(targetName)
    if not targetName or not IsInRaid() then return nil, nil, nil, nil end
    local target = Utils.Trim(targetName):lower()
    local num = GetNumGroupMembers()
    for i = 1, num do
        local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
        if name and Utils.Trim(name):lower() == target then
            local short = strsplit("-", name)
            return i, Utils.Trim(short), subgroup, class
        end
    end
    return nil, nil, nil, nil
end

function Swapper:IsSenderInRaid(sender)
    if not sender or not IsInRaid() then return false end
    local senderShort = strsplit("-", sender)
    senderShort = Utils.Trim(senderShort):lower()
    local num = GetNumGroupMembers()
    for i = 1, num do
        local name = GetRaidRosterInfo(i)
        if name then
            local short = strsplit("-", name)
            if Utils.Trim(short):lower() == senderShort then
                return true
            end
        end
    end
    return false
end

function Swapper:GetClassColoredName(targetName)
    if not targetName then return "|cff888888(None)|r" end
    local idx, short, subgroup, class = Swapper:FindRosterMember(targetName)
    if class then
        return Utils.FormatClassColored(short or targetName, class)
    end
    return targetName
end

-- ----------------------------------------------------------------------------
-- Dummy Character Engine: Comma-Separated Whisper Parsing
-- ----------------------------------------------------------------------------
function Swapper:HandleSwapCommand(text, sender)
    if not text or not sender then return false end
    local db = Swapper:GetDB()
    if not db.enabled then return false end

    -- Parse strictly: !swap First Last, Other Name
    local p1, p2 = text:match("^![sS][wW][aA][pP]%s+([^,]+)%s*,%s*(.+)$")
    if not p1 or not p2 then
        return false
    end

    p1 = Utils.Trim(p1)
    p2 = Utils.Trim(p2)

    local senderShort = strsplit("-", sender)
    senderShort = Utils.Trim(senderShort)

    -- Group check: dummy must be in a raid
    if not IsInRaid() then
        return false
    end

    -- Authorization check: sender MUST be inside the dummy's raid
    if not Swapper:IsSenderInRaid(sender) then
        return false
    end

    -- Combat check: dummy must be out of combat to circumvent #nocombat
    local inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
    if inCombat then
        Utils.SendWhisper("[EFHelper] Swap failed: Dummy is in combat!", sender)
        print("|cffff4444[EFHelper Swapper]|r Swap requested by " .. senderShort .. " failed: Dummy is in combat.")
        return false
    end

    -- Raid permission check: dummy character must have Assistant or Leader rank
    local isLeader = UnitIsGroupLeader and UnitIsGroupLeader("player")
    local isAssist = UnitIsGroupAssistant and UnitIsGroupAssistant("player")
    if not (isLeader or isAssist) then
        Utils.SendWhisper("[EFHelper] Swap failed: Dummy is not Raid Leader or Assistant!", sender)
        print("|cffff4444[EFHelper Swapper]|r Swap requested by " .. senderShort .. " failed: I am not Raid Leader or Assistant.")
        return false
    end

    -- Locate both raid members
    local idx1, name1, sub1 = Swapper:FindRosterMember(p1)
    local idx2, name2, sub2 = Swapper:FindRosterMember(p2)

    if not idx1 or not idx2 then
        local missing = {}
        if not idx1 then table.insert(missing, p1) end
        if not idx2 then table.insert(missing, p2) end
        Utils.SendWhisper("[EFHelper] Swap failed: Player(s) not in raid: " .. table.concat(missing, ", "), sender)
        return false
    end

    if sub1 == sub2 then
        Utils.SendWhisper(string.format("[EFHelper] %s and %s are already in Group %d.", name1, name2, sub1), sender)
        return false
    end

    -- Debounce duplicate executions (prevents instant double swaps)
    local now = GetTime()
    local swapKey = (idx1 < idx2) and (idx1 .. ":" .. idx2) or (idx2 .. ":" .. idx1)
    if (now - lastSwapTime) < 0.8 and lastSwapKey == swapKey then
        return false
    end
    lastSwapTime = now
    lastSwapKey = swapKey

    -- Execute subgroup swap
    SwapRaidSubgroup(idx1, idx2)
    local result = string.format("[EFHelper] Swapped %s (G%d) <-> %s (G%d)", name1, sub1, name2, sub2)
    Utils.SendWhisper(result, sender)
    print("|cff00ff00[EFHelper Swapper]|r " .. result)
    return true
end

-- ----------------------------------------------------------------------------
-- Caller / Trigger Engine: Streamlined UnitId Resolution
-- ----------------------------------------------------------------------------
function Swapper:GetHoveredOrTargetRaidMember()
    local unit = (UnitExists("mouseover") and "mouseover") or (UnitExists("target") and "target")
    if not unit then return nil end

    local name = Utils.GetUnitName(unit)
    if not name or name == "" then return nil end

    if IsInRaid() then
        local idx, rosterName = Swapper:FindRosterMember(name)
        return rosterName or (UnitInRaid(unit) and name)
    end
    return name
end

function Swapper:SelectSlot(slotNum)
    local name = Swapper:GetHoveredOrTargetRaidMember()
    if not name then
        print("|cffff4444[EFHelper Swapper]|r No valid raid member under mouse or target.")
        return
    end

    if slotNum == 1 then
        Swapper.state.slot1 = name
        print("|cff00ff00[EFHelper Swapper]|r Slot 1: " .. Swapper:GetClassColoredName(name))
    elseif slotNum == 2 then
        Swapper.state.slot2 = name
        print("|cff00ff00[EFHelper Swapper]|r Slot 2: " .. Swapper:GetClassColoredName(name))
    end
    Swapper:UpdateHUD()
end

function Swapper:ExecuteSwap(manualP1, manualP2)
    local p1 = manualP1 or Swapper.state.slot1
    local p2 = manualP2 or Swapper.state.slot2

    if not p1 or not p2 then
        print("|cffff4444[EFHelper Swapper]|r Error: You must select both players first (/efswap 1 and /efswap 2).")
        return
    end

    local db = Swapper:GetDB()
    local dummy = db.dummyName and Utils.Trim(db.dummyName)
    if not dummy or dummy == "" then
        print("|cffff4444[EFHelper Swapper]|r Error: Dummy character name is not set! Set it via /efswap dummy <name> or in /efh settings.")
        return
    end

    -- Clean comma-separated command: !swap Player One, Player Two
    local cmd = string.format("!swap %s, %s", p1, p2)

    Utils.SendWhisper(cmd, dummy)
    print(string.format("|cff00ffff[EFHelper Swapper]|r Sent swap to |cffffd100%s|r: %s <-> %s", dummy, p1, p2))
end

function Swapper:ClearSlots()
    Swapper.state.slot1 = nil
    Swapper.state.slot2 = nil
    Swapper:UpdateHUD()
    print("|cff888888[EFHelper Swapper]|r Slot selections cleared.")
end

-- ----------------------------------------------------------------------------
-- Line-Efficient Minimalist Selection HUD
-- ----------------------------------------------------------------------------
local hudFrame = nil

function Swapper:GetOrCreateHUD()
    if hudFrame then return hudFrame end

    local db = Swapper:GetDB()
    local f = UI.CreateBackdropFrame("Frame", "EFHelperSwapperHUD", UIParent, 140, 36)
    f:SetPoint("CENTER", UIParent, "CENTER", db.hudX or 0, db.hudY or -180)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetClampedToScreen(true)

    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local _, _, _, x, y = self:GetPoint()
        db.hudX = math.floor(x or 0)
        db.hudY = math.floor(y or 0)
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            Swapper:ClearSlots()
        end
    end)

    local line1 = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    line1:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -4)
    line1:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -4)
    line1:SetJustifyH("LEFT")
    f.line1 = line1

    local line2 = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    line2:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 6, 4)
    line2:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)
    line2:SetJustifyH("LEFT")
    f.line2 = line2

    hudFrame = f
    Swapper.hud = f
    return f
end

function Swapper:UpdateHUD()
    local db = Swapper:GetDB()
    if not db.showHUD then
        if hudFrame then hudFrame:Hide() end
        return
    end

    local hud = Swapper:GetOrCreateHUD()
    hud:Show()

    local s1 = Swapper.state.slot1
    local s2 = Swapper.state.slot2

    hud.line1:SetText("1: " .. Swapper:GetClassColoredName(s1))
    hud.line2:SetText("2: " .. Swapper:GetClassColoredName(s2))

    if s1 and s2 then
        hud:SetBackdropBorderColor(0.05, 0.82, 0.62, 0.95)
    else
        hud:SetBackdropBorderColor(0.2, 0.2, 0.25, 0.8)
    end
end

function Swapper:ToggleHUD()
    local db = Swapper:GetDB()
    db.showHUD = not db.showHUD
    Swapper:UpdateHUD()
    print(string.format("|cff0cd29f[EFHelper Swapper]|r Selection HUD: %s", db.showHUD and "|cff00ff00Enabled|r" or "|cffff4444Disabled|r"))
end

-- ----------------------------------------------------------------------------
-- Slash Commands (/efswap)
-- ----------------------------------------------------------------------------
SLASH_EFSWAP1 = "/efswap"
SlashCmdList["EFSWAP"] = function(msg)
    local raw = Utils.Trim(msg)
    local cmd = raw:lower()

    if cmd == "1" or cmd == "slot1" then
        Swapper:SelectSlot(1)
    elseif cmd == "2" or cmd == "slot2" then
        Swapper:SelectSlot(2)
    elseif cmd == "exec" or cmd == "go" or cmd == "swap" then
        Swapper:ExecuteSwap()
    elseif cmd == "clear" or cmd == "reset" then
        Swapper:ClearSlots()
    elseif cmd == "hud" then
        Swapper:ToggleHUD()
    elseif cmd:find("^dummy") then
        local dummyArg = raw:match("^%S+%s+(.+)$")
        if dummyArg and dummyArg ~= "" then
            local db = Swapper:GetDB()
            db.dummyName = Utils.Trim(dummyArg)
            print("|cff00ff00[EFHelper Swapper]|r Dummy character name set to: |cffffd100" .. db.dummyName .. "|r")
        else
            local db = Swapper:GetDB()
            print("|cff00ffff[EFHelper Swapper]|r Current dummy character name: " .. (db.dummyName ~= "" and db.dummyName or "|cffff4444None|r"))
        end
    elseif raw:find(",") then
        -- Direct comma-separated swap: /efswap Player One, Player Two
        local p1, p2 = raw:match("^([^,]+)%s*,%s*(.+)$")
        if p1 and p2 then
            Swapper:ExecuteSwap(Utils.Trim(p1), Utils.Trim(p2))
        end
    else
        print("|cff00ffff[EFHelper Swapper]|r Commands:")
        print("  |cffffd100/efswap 1|r - Select Slot 1 (hovered frame/target)")
        print("  |cffffd100/efswap 2|r - Select Slot 2 (hovered frame/target)")
        print("  |cffffd100/efswap exec|r - Execute swap via dummy character (persistent)")
        print("  |cffffd100/efswap clear|r - Clear selections")
        print("  |cffffd100/efswap hud|r - Toggle selection HUD")
        print("  |cffffd100/efswap dummy <Name>|r - Set dummy character name")
        print("  |cffffd100/efswap <P1>, <P2>|r - Direct swap between two players")
    end
end

-- ----------------------------------------------------------------------------
-- Module Lifecycle (AceEvent-3.0)
-- ----------------------------------------------------------------------------
function Swapper:OnInitialize()
    self:RegisterEvent("CHAT_MSG_WHISPER", function(event, text, sender)
        Swapper:HandleSwapCommand(text, sender)
    end)
    local db = Swapper:GetDB()
    if db.showHUD then
        Swapper:UpdateHUD()
    end
end
