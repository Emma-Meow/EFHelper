-- ----------------------------------------------------------------------------
-- EFHelper_Campfire.lua
-- Campfire Buffs Tooltip Parsing & Minimalist HUD for WoW Forever (Camelot)
-- ----------------------------------------------------------------------------
--test
local addonName, addonTable = ...
local EFHelper = _G.EFHelper or addonTable
local Campfire = EFHelper:NewModule("Campfire", "AceEvent-3.0", "AceTimer-3.0")
EFHelper.Campfire = Campfire
addonTable.Campfire = Campfire

local Utils = EFHelper.Utils
local UI = EFHelper.UI

function Campfire:GetDB()
    if EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.Campfire then
        return EFHelper.db.profile.Campfire
    end
    EFHelperDB = EFHelperDB or {}
    EFHelperDB.Campfire = EFHelperDB.Campfire or {}
    local db = EFHelperDB.Campfire
    if db.enabled == nil then db.enabled = true end
    if db.sound == nil then db.sound = true end
    if db.soundFile == nil then db.soundFile = "Interface\\AddOns\\EllesmereUI\\media\\sounds\\heroism.ogg" end
    return db
end

-- Spell ID and Buff Name for Camp Benefits in WoW Forever
Campfire.SPELL_ID = 1229741
Campfire.BUFF_NAME = "Camp Benefits"

-- Campfire Nearby (buff) & Boosted Rest (debuff from resting at tent)
Campfire.CAMPFIRE_NEARBY_SPELL_ID = 1283391
Campfire.CAMPFIRE_NEARBY_NAME = "Campfire Nearby"

Campfire.BOOSTED_REST_SPELL_ID = 1229451
Campfire.BOOSTED_REST_NAME = "Boosted Rest"

-- ----------------------------------------------------------------------------
-- All Available Campfire Buffs & Equivalent WoW Buff Names
-- ----------------------------------------------------------------------------
Campfire.AvailableBuffs = {
    "Mana Well",
    "Sharpening Wheel",
    "Enchanted Lute",
    "Tent",
    "Faction Banner",
    "Incense Candle",
    "Lodestone",
    "Camp Chair",
    "Fish Bowl",
    "First Aid Kit",
}

-- Mapping to equivalent WoW buffs
Campfire.BuffAliases = {
    ["Mana Well"] = "Wisdom",
    ["Sharpening Wheel"] = "Strength Totem",
    ["Enchanted Lute"] = "Motw",
    ["Tent"] = "XP Tent",
    ["Faction Banner"] = "Spirit",
    ["Incense Candle"] = "Int",
    ["Lodestone"] = "Might",
    ["Camp Chair"] = "Lotp",
    ["Fish Bowl"] = "Kings",
    ["First Aid Kit"] = "Stamina",
}

-- Quick lookup table for matching buff names
Campfire.BuffLookup = {}
for _, name in ipairs(Campfire.AvailableBuffs) do
    Campfire.BuffLookup[name:lower()] = name
end
Campfire.BuffLookup["fishing bowl"] = "Fish Bowl"

-- Active state
Campfire.activeBuffs = {}
EFHelper.currentCampfireBuffs = Campfire.activeBuffs
Campfire.isTestMode = false

-- Last scanned lines cache for debugging
Campfire.lastScannedLines = {}
Campfire.lastFullText = ""

-- Tracking for aura refresh detection
local lastCampfireInstanceID = nil
local lastCampfireExpiration = nil

-- ----------------------------------------------------------------------------
-- Combat State Tracking (100% Taint-Safe)
-- ----------------------------------------------------------------------------
local inCombat = false

local function IsInCombat()
    if inCombat then return true end
    if InCombatLockdown and InCombatLockdown() then return true end
    if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
    return false
end
Campfire.IsInCombat = IsInCombat

local function IsInsideInstance()
    if not IsInInstance then return false end
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType ~= "none")
end
Campfire.IsInsideInstance = IsInsideInstance

-- ----------------------------------------------------------------------------
-- String & Stat Formatting Helpers
-- ----------------------------------------------------------------------------
local function StripFormatting(text)
    if not text then return "" end
    if Utils and Utils.IsSecret and Utils.IsSecret(text) then return "" end
    if Utils and Utils.StripFormatting then
        local res = Utils.StripFormatting(text)
        if res and not (Utils.IsSecret and Utils.IsSecret(res)) then
            return res
        end
        return ""
    end
    local ok, res = pcall(function()
        local clean = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
        return clean:match("^%s*(.-)%s*$") or clean
    end)
    if ok and res and not (Utils and Utils.IsSecret and Utils.IsSecret(res)) then
        return res
    end
    return ""
end

function Campfire:GetBuffAlias(name)
    if not name or (Utils and Utils.IsSecret and Utils.IsSecret(name)) then return "" end
    local ok, alias = pcall(function()
        if Campfire.BuffAliases[name] then
            return Campfire.BuffAliases[name]
        end
        local lower = name:lower()
        for origName, a in pairs(Campfire.BuffAliases) do
            if origName:lower() == lower then
                return a
            end
        end
        return name
    end)
    if ok and alias then return alias end
    return ""
end

local statPatterns = {
    { "Strength%s+increased%s+by%s+(%d+)", "+%s Str" },
    { "Stamina%s+increased%s+by%s+(%d+)", "+%s Stam" },
    { "Melee%s+Attack%s+Power%s+increased%s+by%s+(%d+)", "+%s AP" },
    { "Attack%s+Power%s+increased%s+by%s+(%d+)", "+%s AP" },
    { "Intellect%s+increased%s+by%s+(%d+)", "+%s Int" },
    { "Spirit%s+increased%s+by%s+(%d+)", "+%s Spi" },
    { "[Aa]ll%s+[Ss]tats%s+increased%s+by%s+(%d+)", "+%s All Stats" },
    { "[Aa]ll%s+[Aa]ttributes%s+increased%s+by%s+(%d+)", "+%s All Stats" },
    { "(%d+)%s+mana%s+every", "+%s MP5" },
    { "Mana%s+regeneration%s+increased%s+by%s+(%d+)", "+%s MP5" },
    { "Crit.-increased%s+by%s+(%d+%%?)", "+%s Crit" },
    { "increased%s+by%s+(%d+%%)", "+%s" },
    { "increased%s+by%s+(%d+)", "+%s" },
}

local function FormatStatShort(statText)
    if not statText or (Utils and Utils.IsSecret and Utils.IsSecret(statText)) then return "" end
    local ok, res = pcall(function()
        if statText == "" then return "" end
        local clean = statText:match("^%s*(.-)%s*$") or statText
        clean = clean:gsub("%.$", "")
        for _, p in ipairs(statPatterns) do
            local val = clean:match(p[1])
            if val then return string.format(p[2], val) end
        end
        if clean:lower():find("rested") or clean:lower():find("experience") or clean:lower():find("xp") then
            return "Rested XP"
        end
        return (#clean <= 16) and clean or ""
    end)
    if ok and res then return res end
    return ""
end

-- Retrieves text lines from tooltip and TooltipData
local function ExtractAllTooltipText(tooltip, data)
    if IsInCombat() then return {}, "" end

    local splitLines = {}
    local seen = {}

    local function AddClean(str)
        if not str then return end
        if Utils and Utils.IsSecret and Utils.IsSecret(str) then return end
        local okProbe = pcall(function() local _ = (str == "") end)
        if not okProbe or str == "" then return end

        local clean = StripFormatting(str)
        if not clean or (Utils and Utils.IsSecret and Utils.IsSecret(clean)) or clean == "" then return end

        pcall(function()
            for line in clean:gmatch("[^\r\n]+") do
                local trimmed = Utils.Trim(line)
                if trimmed ~= "" and not seen[trimmed] then
                    seen[trimmed] = true
                    table.insert(splitLines, trimmed)
                end
            end
        end)
    end

    -- 1. Modern TooltipData (Midnight 12.0 / Dragonflight)
    if data and data.lines then
        for _, lineData in ipairs(data.lines) do
            if lineData then
                AddClean(lineData.leftText)
                AddClean(lineData.rightText)
            end
        end
    end

    -- 2. Tooltip fontstrings fallback
    local tt = tooltip or GameTooltip
    if #splitLines == 0 and tt and tt.GetName then
        local okName, name = pcall(tt.GetName, tt)
        if okName and name and not (Utils and Utils.IsSecret and Utils.IsSecret(name)) then
            local numLines = 30
            pcall(function()
                if tt.NumLines then numLines = tt:NumLines() end
            end)
            for i = 1, numLines do
                local left = _G[name .. "TextLeft" .. i]
                if left and left.GetText then
                    local okL, txtL = pcall(left.GetText, left)
                    if okL and txtL then AddClean(txtL) end
                end
                local right = _G[name .. "TextRight" .. i]
                if right and right.GetText then
                    local okR, txtR = pcall(right.GetText, right)
                    if okR and txtR then AddClean(txtR) end
                end
            end
        end
    end

    local fullText = table.concat(splitLines, "\n")
    Campfire.lastScannedLines = splitLines
    Campfire.lastFullText = fullText
    return splitLines, fullText
end

-- Checks if the given tooltip / data corresponds to the Campfire buff
local function IsCampfireTooltip(tooltip, data, fullText)
    if not tooltip and not data and (not fullText or (Utils and Utils.IsSecret and Utils.IsSecret(fullText))) then
        if not tooltip and not data then return false end
    end

    -- 1. Direct TooltipData ID match (Dragonflight / Midnight API)
    if data then
        local match = false
        pcall(function()
            if data.id and not (Utils and Utils.IsSecret and Utils.IsSecret(data.id)) then
                if data.id == Campfire.SPELL_ID then
                    match = true
                end
            end
            if not match and data.spellId and not (Utils and Utils.IsSecret and Utils.IsSecret(data.spellId)) then
                if data.spellId == Campfire.SPELL_ID then
                    match = true
                end
            end
        end)
        if match then return true end

        -- In modern AuraContainers (such as EllesmereUI Player Aura Bars),
        -- data.id for UnitAura is the dynamic auraInstanceID, not the spell ID.
        if data.id and not (Utils and Utils.IsSecret and Utils.IsSecret(data.id)) and C_UnitAuras and C_UnitAuras.GetAuraByAuraInstanceID then
            local ok, aura = pcall(C_UnitAuras.GetAuraByAuraInstanceID, "player", data.id)
            if ok and aura and IsAuraMatch(aura, Campfire.SPELL_ID, Campfire.BUFF_NAME) then
                return true
            end
        end
    end

    -- 2. Check TooltipData lines title (Dragonflight / Midnight API)
    if data and data.lines and data.lines[1] and data.lines[1].leftText then
        local title = data.lines[1].leftText
        if title and not (Utils and Utils.IsSecret and Utils.IsSecret(title)) then
            local ok, match = pcall(function()
                return title:find(Campfire.BUFF_NAME) or title:lower():find("camp benefits")
            end)
            if ok and match then return true end
        end
    end

    -- 3. Check tooltip:GetSpell()
    local tt = tooltip or GameTooltip
    if tt and tt.GetSpell then
        local ok, name, _, id = pcall(tt.GetSpell, tt)
        if ok then
            if id and not (Utils and Utils.IsSecret and Utils.IsSecret(id)) and id == Campfire.SPELL_ID then
                return true
            end
            if name and not (Utils and Utils.IsSecret and Utils.IsSecret(name)) and name == Campfire.BUFF_NAME then
                return true
            end
        end
    end

    -- 4. Check visual tooltip title fontstring
    if tt and tt.GetName then
        local okName, name = pcall(tt.GetName, tt)
        if okName and name and not (Utils and Utils.IsSecret and Utils.IsSecret(name)) then
            local titleLine = _G[name .. "TextLeft1"]
            if titleLine and titleLine.GetText then
                local okTxt, txt = pcall(titleLine.GetText, titleLine)
                if okTxt and txt and not (Utils and Utils.IsSecret and Utils.IsSecret(txt)) then
                    local okMatch, match = pcall(function()
                        return txt:find(Campfire.BUFF_NAME) or txt:lower():find("camp benefits")
                    end)
                    if okMatch and match then return true end
                end
            end
        end
    end

    -- 5. Full text fallback
    if fullText and not (Utils and Utils.IsSecret and Utils.IsSecret(fullText)) and fullText ~= "" then
        local okMatch, match = pcall(function()
            return fullText:find("1229741") or fullText:find(Campfire.BUFF_NAME) or fullText:lower():find("camp benefits")
        end)
        if okMatch and match then return true end
    end

    return false
end

-- Parses all active campfire buffs from splitLines and fullText
local function ParseCampfireBuffs(splitLines, fullText)
    local foundBuffs = {}
    local foundLookup = {}

    local function AddBuff(canonicalName, stat, fullLine)
        if not foundLookup[canonicalName] then
            foundLookup[canonicalName] = true
            table.insert(foundBuffs, {
                name = canonicalName,
                stat = Utils.Trim(stat),
                fullText = fullLine or (canonicalName .. ": " .. (stat or "")),
            })
        end
    end

    -- Pass 1: Match individual split lines
    if splitLines then
        pcall(function()
            for _, line in ipairs(splitLines) do
                for _, buffName in ipairs(Campfire.AvailableBuffs) do
                    local escaped = buffName:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                    local stat = line:match("^" .. escaped .. "%s*:%s*(.*)$")
                    if not stat and buffName == "Fish Bowl" then
                        stat = line:match("^Fishing Bowl%s*:%s*(.*)$")
                    end
                    if not stat and line:find("^" .. escaped) then
                        stat = line:sub(#buffName + 1):gsub("^%s*[:%-]%s*", "")
                    end
                    if stat then
                        AddBuff(buffName, stat, line)
                    end
                end
            end
        end)
    end

    -- Pass 2: Match fullText fallback
    if fullText and not (Utils and Utils.IsSecret and Utils.IsSecret(fullText)) and fullText ~= "" then
        pcall(function()
            for _, buffName in ipairs(Campfire.AvailableBuffs) do
                if not foundLookup[buffName] then
                    local escaped = buffName:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                    local stat = fullText:match(escaped .. "%s*:%s*([^\r\n]+)")
                    if not stat and buffName == "Fish Bowl" then
                        stat = fullText:match("Fishing Bowl%s*:%s*([^\r\n]+)")
                    end
                    if stat then
                        AddBuff(buffName, stat)
                    elseif fullText:find(escaped) or (buffName == "Fish Bowl" and fullText:find("Fishing Bowl")) then
                        AddBuff(buffName, "")
                    end
                end
            end
        end)
    end

    return foundBuffs
end

-- Helper to safely compare aura spellId and name against target values without crashing on secret values
local function IsAuraMatch(aura, targetSpellID, targetName)
    if not aura then return false end
    if targetSpellID then
        local match = false
        pcall(function()
            if aura.spellId and aura.spellId == targetSpellID then
                match = true
            end
        end)
        if match then return true end
    end
    if targetName then
        local match = false
        pcall(function()
            if aura.name and aura.name == targetName then
                match = true
            end
        end)
        if match then return true end
    end
    return false
end

-- ----------------------------------------------------------------------------
-- Player Aura Detection & Scanning
-- ----------------------------------------------------------------------------
function Campfire:FindPlayerCampfireAura()
    if IsInCombat() then
        return nil
    end

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, Campfire.SPELL_ID)
        if ok and aura then return aura end
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not aura then break end
            if IsAuraMatch(aura, Campfire.SPELL_ID, Campfire.BUFF_NAME) then
                return aura
            end
        end
    end

    return nil
end

-- Checks if player currently has a specific aura (buff or debuff) by SpellID
function Campfire:PlayerHasAura(spellID, nameFallback)
    if IsInCombat() then return false end

    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID and spellID then
        local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
        if ok and aura then return true end
    end

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok or not aura then break end
            if IsAuraMatch(aura, spellID, nameFallback) then
                return true
            end
        end
        for i = 1, 40 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HARMFUL")
            if not ok or not aura then break end
            if IsAuraMatch(aura, spellID, nameFallback) then
                return true
            end
        end
    end

    return false
end

local hasPrintedBuffsThisHover = false

function Campfire:ScanFromPlayerAura(printChat)
    if IsInCombat() then return false end
    local aura = Campfire:FindPlayerCampfireAura()
    if not aura then return false end

    -- 1. Try C_TooltipInfo by auraInstanceID
    if C_TooltipInfo and C_TooltipInfo.GetUnitAuraByAuraInstanceID and aura.auraInstanceID then
        local ok, data = pcall(C_TooltipInfo.GetUnitAuraByAuraInstanceID, "player", aura.auraInstanceID)
        if ok and data then
            local splitLines, fullText = ExtractAllTooltipText(GameTooltip, data)
            local found = ParseCampfireBuffs(splitLines, fullText)
            if #found > 0 then
                Campfire.activeBuffs = found
                EFHelper.currentCampfireBuffs = found
                Campfire:UpdateDisplay()
                if printChat and not hasPrintedBuffsThisHover and Campfire.PrintBuffs then
                    hasPrintedBuffsThisHover = true
                    Campfire:PrintBuffs(found)
                end
                return true
            end
        end
    end

    -- 2. Try C_TooltipInfo by slot
    if C_TooltipInfo and C_TooltipInfo.GetUnitBuff and aura.slot then
        local ok, data = pcall(C_TooltipInfo.GetUnitBuff, "player", aura.slot)
        if ok and data then
            local splitLines, fullText = ExtractAllTooltipText(GameTooltip, data)
            local found = ParseCampfireBuffs(splitLines, fullText)
            if #found > 0 then
                Campfire.activeBuffs = found
                EFHelper.currentCampfireBuffs = found
                Campfire:UpdateDisplay()
                if printChat and not hasPrintedBuffsThisHover and Campfire.PrintBuffs then
                    hasPrintedBuffsThisHover = true
                    Campfire:PrintBuffs(found)
                end
                return true
            end
        end
    end

    return false
end

-- ----------------------------------------------------------------------------
-- Modern Minimalist HUD (Draggable, Below Minimap)
-- ----------------------------------------------------------------------------
-- ----------------------------------------------------------------------------
-- SharedMedia Font Management (Delegated to EFHelper_Config.lua)
-- ----------------------------------------------------------------------------
local function SetupFontString(fs, size, outline, fontName)
    if UI and UI.SetupFontString then
        UI.SetupFontString(fs, size, outline, fontName or "Expressway")
    elseif EFHelper and EFHelper.SetupFontString then
        EFHelper:SetupFontString(fs, size, outline, fontName or "Expressway")
    else
        local fallback = (GameFontNormal and GameFontNormal.GetFont and GameFontNormal:GetFont()) or "Fonts\\ARIALN.TTF"
        pcall(fs.SetFont, fs, fallback, size or 12, outline or "OUTLINE")
    end
end
Campfire.SetupFontString = SetupFontString

function Campfire:SaveDisplayPosition(frame)
    if not frame then return end
    local point, _, relPoint, x, y = frame:GetPoint()
    if point and relPoint then
        local p = { point, "UIParent", relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
        local db = Campfire:GetDB()
        db.pos = p
        if EFHelperCharDB then
            EFHelperCharDB.campfirePoint = p
        end
    end
end

function Campfire:RestoreDisplayPosition(frame)
    if not frame then return end
    local db = Campfire:GetDB()
    local p = db.pos or (EFHelperCharDB and EFHelperCharDB.campfirePoint)
    if p then
        frame:ClearAllPoints()
        frame:SetPoint(p[1], UIParent, p[3], p[4], p[5])
    else
        frame:ClearAllPoints()
        if Minimap then
            frame:SetPoint("TOP", Minimap, "BOTTOM", 0, -8)
        else
            frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -20, -220)
        end
    end
end

function Campfire:GetOrCreateDisplayFrame()
    if displayFrame then return displayFrame end

    -- Create or retrieve minimal floating frame
    local f = _G["EFHelperCampfireHUD"] or CreateFrame("Frame", "EFHelperCampfireHUD", UIParent, "BackdropTemplate")
    f:SetSize(160, 48)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")

    -- Sleek modern minimalist styling (translucent dark glass with subtle border on hover)
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.04, 0.05, 0.07, 0.35)
    f:SetBackdropBorderColor(0.15, 0.15, 0.2, 0.3)

    f:SetScript("OnMouseDown", function(self, button)
        local curDb = Campfire:GetDB()
        local isLocked = (curDb.locked == true) and not Campfire.isTestMode
        if isLocked and not (button == "RightButton" and IsShiftKeyDown()) then
            if self.SetPropagateMouseClicks then
                self:SetPropagateMouseClicks(true)
            end
        else
            if self.SetPropagateMouseClicks then
                self:SetPropagateMouseClicks(false)
            end
        end
    end)

    -- Drag & Reposition Handlers
    f:SetScript("OnDragStart", function(self)
        local curDb = Campfire:GetDB()
        if curDb.locked and not Campfire.isTestMode then return end
        self:StartMoving()
    end)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Campfire:SaveDisplayPosition(self)
    end)
    f:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" and IsShiftKeyDown() then
            local curDb = Campfire:GetDB()
            curDb.locked = not curDb.locked
            print(string.format("|cff0cd29f[EFHelper Campfire]|r HUD is now %s.", curDb.locked and "|cffff5555Locked (click-through)|r" or "|cff55ff55Unlocked|r"))
            Campfire:ApplyLockState()
        end
        if self.SetPropagateMouseClicks then
            self:SetPropagateMouseClicks(false)
        end
    end)

    -- Hover visuals and tooltip
    f:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.04, 0.05, 0.07, 0.8)
        self:SetBackdropBorderColor(0.05, 0.82, 0.62, 0.8)

        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:ClearLines()
            GameTooltip:AddLine("Campfire Buffs", 0.05, 0.82, 0.62)
            if Campfire.activeBuffs and #Campfire.activeBuffs > 0 then
                for _, b in ipairs(Campfire.activeBuffs) do
                    local alias = Campfire:GetBuffAlias(b.name)
                    GameTooltip:AddDoubleLine(b.name .. " (" .. alias .. ")", b.stat or "", 1, 0.82, 0, 1, 1, 1)
                end
            else
                GameTooltip:AddLine("Resting at campfire. Mouseover buff icon to scan.", 0.7, 0.7, 0.7)
            end
            GameTooltip:AddLine("Left-click and drag to reposition.", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end
    end)

    f:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.04, 0.05, 0.07, 0.35)
        self:SetBackdropBorderColor(0.15, 0.15, 0.2, 0.3)
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)

    -- Header FontString ("Campfire")
    local header = f.header or f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetJustifyH("CENTER")
    header:ClearAllPoints()
    header:SetPoint("TOP", f, "TOP", 0, -5)
    header:SetPoint("LEFT", f, "LEFT", 4, 0)
    header:SetPoint("RIGHT", f, "RIGHT", -4, 0)
    header:SetHeight(16)
    header:SetTextColor(1, 0.82, 0, 1)
    header:SetText("Campfire")
    SetupFontString(header, 14, "OUTLINE", "Expressway")
    header:Show()
    f.header = header

    -- Up to 3 lines of minimalist text
    f.lines = f.lines or {}
    for i = 1, 3 do
        local line = f.lines[i] or f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        line:SetJustifyH("CENTER")
        line:SetHeight(14)
        line:ClearAllPoints()
        line:SetPoint("LEFT", f, "LEFT", 4, 0)
        line:SetPoint("RIGHT", f, "RIGHT", -4, 0)
        if i == 1 then
            line:SetPoint("TOP", header, "BOTTOM", 0, -3)
        else
            line:SetPoint("TOP", f.lines[i - 1], "BOTTOM", 0, -2)
        end
        SetupFontString(line, 12, "OUTLINE", "Expressway")
        f.lines[i] = line
    end

    Campfire:RestoreDisplayPosition(f)
    displayFrame = f
    Campfire.displayFrame = f
    return f
end

function Campfire:ApplyLockState()
    if not displayFrame then return end
    displayFrame:EnableMouse(true)
end

-- Updates the HUD content based on active campfire state
function Campfire:UpdateDisplay()
    local db = Campfire:GetDB()
    if not db or not db.enabled then
        if Campfire.displayFrame then Campfire.displayFrame:Hide() end
        return
    end

    local frame = Campfire:GetOrCreateDisplayFrame()
    Campfire:ApplyLockState()
    local hasAura = Campfire:FindPlayerCampfireAura() ~= nil

    -- If not in test mode and no campfire buff is on the player, hide HUD
    if not Campfire.isTestMode and not hasAura then
        frame:Hide()
        return
    end

    frame:Show()
    if frame.header then
        frame.header:SetText("Campfire")
        frame.header:Show()
    end

    local buffs = Campfire.activeBuffs or {}

    -- State 1: Campfire detected, but not yet mouseovered / scanned (or after an aura refresh)
    if #buffs == 0 then
        frame.lines[1]:SetText("|cffaaaaaaPlease mouseover buff|r")
        frame.lines[1]:Show()
        frame.lines[2]:SetText("")
        frame.lines[2]:Hide()
        frame.lines[3]:SetText("")
        frame.lines[3]:Hide()
        frame:SetSize(170, 42)
        return
    end

    -- State 2: Display up to 3 lines using equivalent WoW buffs
    local count = math.min(#buffs, 3)
    for i = 1, 3 do
        if i <= count then
            local b = buffs[i]
            local alias = Campfire:GetBuffAlias(b.name)
            local statShort = FormatStatShort(b.stat)

            local text = "|cffffffff" .. alias .. "|r"
            if statShort and statShort ~= "" then
                text = text .. " |cff0cd29f(" .. statShort .. ")|r"
            end

            frame.lines[i]:SetText(text)
            frame.lines[i]:Show()
        else
            frame.lines[i]:SetText("")
            frame.lines[i]:Hide()
        end
    end

    frame:SetSize(170, 24 + (count * 16))
end

-- ----------------------------------------------------------------------------
-- Tent Alert Display (Floating text central on screen)
-- ----------------------------------------------------------------------------
local tentAlertFrame = nil

function Campfire:GetOrCreateTentAlertFrame()
    if tentAlertFrame then return tentAlertFrame end

    local f = _G["EFHelperTentAlertFrame"] or CreateFrame("Frame", "EFHelperTentAlertFrame", UIParent)
    f:SetSize(500, 36)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    f:SetFrameStrata("HIGH")

    local text = f.text or f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
    text:SetJustifyH("CENTER")
    text:ClearAllPoints()
    text:SetPoint("CENTER", f, "CENTER", 0, 0)

    text:SetTextColor(1, 0.82, 0, 1)
    text:SetText("Campfire nearby, check Tent")
    SetupFontString(text, 20, "OUTLINE", "Expressway")
    f.text = text
    f:Hide()

    tentAlertFrame = f
    Campfire.tentAlertFrame = f
    return f
end

function Campfire:UpdateTentAlert()
    if IsInCombat() then return end

    local db = Campfire:GetDB()
    if not db or not db.enabled then
        if Campfire.tentAlertFrame then Campfire.tentAlertFrame:Hide() end
        return
    end

    local frame = Campfire:GetOrCreateTentAlertFrame()

    if Campfire.isTestMode then
        frame:Show()
        return
    end

    local hasNearby = Campfire:PlayerHasAura(Campfire.CAMPFIRE_NEARBY_SPELL_ID, Campfire.CAMPFIRE_NEARBY_NAME)
    local hasBoostedRest = Campfire:PlayerHasAura(Campfire.BOOSTED_REST_SPELL_ID, Campfire.BOOSTED_REST_NAME)

    if hasNearby and not hasBoostedRest then
        frame:Show()
    else
        frame:Hide()
    end
end

-- ----------------------------------------------------------------------------
-- Chat Output & Debouncing
-- ----------------------------------------------------------------------------
local pendingGraceTimer = nil

function Campfire:PrintBuffs(buffs)
    buffs = buffs or Campfire.activeBuffs or {}
    if #buffs == 0 then
        print("|cff0cd29f[EFHelper]|r |cffffd100Camp Benefits:|r Resting at campfire, but no specific benefits detected.")
        return
    end

    print(string.format("|cff0cd29f[EFHelper]|r |cffffd100Active Campfire Buffs (%d):|r", #buffs))
    for _, buff in ipairs(buffs) do
        local alias = Campfire:GetBuffAlias(buff.name)
        local aliasText = (alias and alias ~= buff.name) and (" (" .. alias .. ")") or ""
        if buff.stat and buff.stat ~= "" then
            print(string.format("  |cffffd100*|r |cffffffff%s%s|r: %s", buff.name, aliasText, buff.stat))
        else
            print(string.format("  |cffffd100*|r |cffffffff%s%s|r", buff.name, aliasText))
        end
    end
end

-- Main tooltip processing function
local function ProcessCampfireTooltip(tooltip, data)
    local db = Campfire:GetDB()
    if not db or not db.enabled then return end
    if IsInCombat() or IsInsideInstance() then return end

    -- Guard 1: Fast-path check BEFORE extracting text to avoid processing every buff on screen
    if not IsCampfireTooltip(tooltip, data, nil) then
        return
    end

    local splitLines, fullText = ExtractAllTooltipText(tooltip, data)

    -- Guard 2: If initial check was inconclusive (no ID/title match), verify with full text
    if #splitLines == 0 and not IsCampfireTooltip(tooltip, data, fullText) then
        return
    end

    local foundBuffs = ParseCampfireBuffs(splitLines, fullText)

    if #foundBuffs > 0 then
        if pendingGraceTimer and pendingGraceTimer.Cancel then
            pendingGraceTimer:Cancel()
            pendingGraceTimer = nil
        end

        Campfire.activeBuffs = foundBuffs
        EFHelper.currentCampfireBuffs = foundBuffs
        Campfire:UpdateDisplay()

        if not hasPrintedBuffsThisHover then
            hasPrintedBuffsThisHover = true
            Campfire:PrintBuffs(foundBuffs)
        end
    else
        if not hasPrintedBuffsThisHover and not pendingGraceTimer then
            if C_Timer and C_Timer.NewTimer then
                pendingGraceTimer = C_Timer.NewTimer(0.3, function()
                    pendingGraceTimer = nil
                    if IsInCombat() then return end
                    if not hasPrintedBuffsThisHover then
                        if not IsCampfireTooltip(tooltip, data, nil) then return end
                        local sl, ft = ExtractAllTooltipText(tooltip, data)
                        if not IsCampfireTooltip(tooltip, data, ft) then return end
                        local fb = ParseCampfireBuffs(sl, ft)
                        if #fb > 0 then
                            Campfire.activeBuffs = fb
                            EFHelper.currentCampfireBuffs = fb
                            Campfire:UpdateDisplay()
                            hasPrintedBuffsThisHover = true
                            Campfire:PrintBuffs(fb)
                        else
                            Campfire.activeBuffs = {}
                            EFHelper.currentCampfireBuffs = {}
                            Campfire:UpdateDisplay()
                            hasPrintedBuffsThisHover = true
                            Campfire:PrintBuffs({})
                        end
                    end
                end)
            end
        end
    end
end

-- Public API
function EFHelper:GetCampfireBuffs()
    return Campfire.activeBuffs or {}
end

function EFHelper:HasCampfireBuff(buffName)
    if not buffName or (Utils and Utils.IsSecret and Utils.IsSecret(buffName)) or not Campfire.activeBuffs then return false end
    local ok, hasBuff, stat = pcall(function()
        local lower = buffName:lower()
        for _, buff in ipairs(Campfire.activeBuffs) do
            if buff.name and buff.name:lower() == lower then
                return true, buff.stat
            end
        end
        return false
    end)
    if ok and hasBuff then return true, stat end
    return false
end

-- ----------------------------------------------------------------------------
-- Tooltip Hooks Setup
-- ----------------------------------------------------------------------------
local function InitCampfireTooltipHooks()
    if Campfire._hooksInitialized then return end

    -- 1. Modern WoW TooltipDataProcessor (10.0+ / 11.0+ / Midnight 12.0+)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall then
        if Enum and Enum.TooltipDataType and Enum.TooltipDataType.UnitAura then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.UnitAura, function(tooltip, data)
                if IsInCombat() then return end
                pcall(ProcessCampfireTooltip, tooltip, data)
            end)
        end
        if Enum and Enum.TooltipDataType and Enum.TooltipDataType.Spell then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
                if IsInCombat() then return end
                pcall(ProcessCampfireTooltip, tooltip, data)
            end)
        end

        -- Use hooksecurefunc for Hide: runs securely without modifying GameTooltip script handlers or causing frame taint
        if hooksecurefunc and GameTooltip then
            pcall(hooksecurefunc, GameTooltip, "Hide", function()
                hasPrintedBuffsThisHover = false
                if pendingGraceTimer and pendingGraceTimer.Cancel then
                    pendingGraceTimer:Cancel()
                    pendingGraceTimer = nil
                end
            end)
        end
    elseif GameTooltip and GameTooltip.HookScript then
        -- 2. Classic fallback (only if TooltipDataProcessor does not exist)
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetSpell", function(self)
            if IsInCombat() then return end
            pcall(ProcessCampfireTooltip, self)
        end)

        pcall(GameTooltip.HookScript, GameTooltip, "OnHide", function()
            hasPrintedBuffsThisHover = false
            if pendingGraceTimer and pendingGraceTimer.Cancel then
                pendingGraceTimer:Cancel()
                pendingGraceTimer = nil
            end
        end)
    end

    Campfire._hooksInitialized = true
end

InitCampfireTooltipHooks()

-- ----------------------------------------------------------------------------
-- UNIT_AURA Refresh & State Tracking
-- ----------------------------------------------------------------------------
local function CheckCampfireAuraRefresh()
    local db = Campfire:GetDB()
    if not db or not db.enabled then return end
    if IsInCombat() or IsInsideInstance() then
        return
    end

    -- Real-time update for floating tent alert ("Campfire nearby, check Tent")
    Campfire:UpdateTentAlert()

    if Campfire.isTestMode then
        Campfire:UpdateDisplay()
        return
    end

    local aura = Campfire:FindPlayerCampfireAura()
    if not aura then
        -- Buff has faded/expired
        lastCampfireInstanceID = nil
        lastCampfireExpiration = nil
        Campfire.activeBuffs = {}
        EFHelper.currentCampfireBuffs = {}
        if Campfire.displayFrame then
            Campfire.displayFrame:Hide()
        end
        return
    end

    -- Player has an active campfire aura. Check if it's new or was refreshed.
    local isNew = (lastCampfireInstanceID == nil)
    if not isNew then
        pcall(function()
            if aura.auraInstanceID and lastCampfireInstanceID ~= aura.auraInstanceID then
                isNew = true
            end
        end)
    end

    local isRefreshed = false
    if aura.expirationTime and lastCampfireExpiration then
        pcall(function()
            -- If expiration time jumped forward by more than 2 seconds, the buff was refreshed at a campfire!
            if aura.expirationTime > (lastCampfireExpiration + 2) then
                isRefreshed = true
            end
        end)
    end

    if isNew or isRefreshed then
        -- Buff was gained or refreshed! Since campfire benefits can change upon refresh,
        -- clear cached buffs, reset hover debounce, and attempt instant scan.
        lastCampfireInstanceID = aura.auraInstanceID
        lastCampfireExpiration = aura.expirationTime

        Campfire.activeBuffs = {}
        EFHelper.currentCampfireBuffs = {}
        hasPrintedBuffsThisHover = false

        -- Attempt instant programmatic scan from player aura (bypasses manual hover!)
        local scanned = Campfire:ScanFromPlayerAura(true)
        if not scanned then
            Campfire:UpdateDisplay()
        end
    else
        -- Regular countdown tick
        if aura.expirationTime then
            lastCampfireExpiration = aura.expirationTime
        end
        -- If buffs haven't been resolved yet (e.g. on login or delayed aura data), attempt scan
        if (not Campfire.activeBuffs or #Campfire.activeBuffs == 0) and not hasPrintedBuffsThisHover then
            Campfire:ScanFromPlayerAura(true)
        end
        Campfire:UpdateDisplay()
    end
end

-- ----------------------------------------------------------------------------
-- Module Lifecycle (AceEvent-3.0 & Dedicated Player Aura Watcher)
-- ----------------------------------------------------------------------------
local auraWatcher = CreateFrame("Frame")
auraWatcher:SetScript("OnEvent", function(self, event, unit)
    local db = Campfire:GetDB()
    if not db or not db.enabled then return end
    if IsInCombat() or IsInsideInstance() then return end
    CheckCampfireAuraRefresh()
end)

local function UpdateAuraWatcherState()
    local db = Campfire:GetDB()
    if not db or not db.enabled or IsInsideInstance() then
        auraWatcher:UnregisterAllEvents()
        if Campfire.displayFrame then Campfire.displayFrame:Hide() end
        if Campfire.tentAlertFrame then Campfire.tentAlertFrame:Hide() end
    else
        auraWatcher:RegisterUnitEvent("UNIT_AURA", "player")
        CheckCampfireAuraRefresh()
    end
end
Campfire.UpdateAuraWatcherState = UpdateAuraWatcherState

function Campfire:OnInitialize()
    local db = self:GetDB()
    if not db.enabled then
        self:SetEnabledState(false)
    end
end

function Campfire:OnEnable()
    local db = self:GetDB()
    db.enabled = true

    inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
    InitCampfireTooltipHooks()

    local frame = Campfire:GetOrCreateDisplayFrame()
    Campfire:RestoreDisplayPosition(frame)
    Campfire:GetOrCreateTentAlertFrame()

    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD")

    UpdateAuraWatcherState()
end

function Campfire:OnDisable()
    local db = self:GetDB()
    db.enabled = false

    if pendingGraceTimer and pendingGraceTimer.Cancel then
        pendingGraceTimer:Cancel()
        pendingGraceTimer = nil
    end

    if auraWatcher then
        auraWatcher:UnregisterAllEvents()
    end

    self:UnregisterAllEvents()

    if Campfire.isTestMode then
        Campfire.isTestMode = false
    end

    if Campfire.displayFrame then
        Campfire.displayFrame:Hide()
    end
    if Campfire.tentAlertFrame then
        Campfire.tentAlertFrame:Hide()
    end

    lastCampfireInstanceID = nil
    lastCampfireExpiration = nil
    Campfire.activeBuffs = {}
    EFHelper.currentCampfireBuffs = {}
    hasPrintedBuffsThisHover = false
end

function Campfire:PLAYER_ENTERING_WORLD()
    local db = self:GetDB()
    if not db.enabled then return end
    inCombat = (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) or false
    UpdateAuraWatcherState()
end

function Campfire:PLAYER_REGEN_DISABLED()
    inCombat = true
end

function Campfire:PLAYER_REGEN_ENABLED()
    inCombat = false
    hasPrintedBuffsThisHover = false
    local db = self:GetDB()
    if db.enabled and not IsInsideInstance() then
        CheckCampfireAuraRefresh()
    end
end

-- ----------------------------------------------------------------------------
-- Public Campfire Control Methods (Used by /efcamp and EFHelper_Config)
-- ----------------------------------------------------------------------------
function Campfire:ToggleTestMode()
    local db = Campfire:GetDB()
    if not db.enabled then
        print("|cff0cd29f[EFHelper]|r Campfire & Rest module is currently disabled. Enable it first to test.")
        return false
    end
    Campfire.isTestMode = not Campfire.isTestMode
    if Campfire.isTestMode then
        Campfire.activeBuffs = {
            { name = "Sharpening Wheel", stat = "Strength increased by 6." },
            { name = "First Aid Kit", stat = "Stamina increased by 8." },
            { name = "Fish Bowl", stat = "All stats increased by 4." },
        }
    else
        Campfire.activeBuffs = {}
    end
    Campfire:UpdateDisplay()
    Campfire:UpdateTentAlert()
    return Campfire.isTestMode
end

function Campfire:ResetPosition()
    if EFHelperCharDB then
        EFHelperCharDB.campfirePoint = nil
    end
    local f = Campfire:GetOrCreateDisplayFrame()
    Campfire:RestoreDisplayPosition(f)
end

function Campfire:DumpDebug()
    local splitLines, fullText = ExtractAllTooltipText(GameTooltip)
    print(string.format("|cff0cd29f[EFHelper Debug]|r Scanned %d split lines:", #splitLines))
    for i, line in ipairs(splitLines) do
        print(string.format("  [%d] %s", i, line))
    end
    local found = ParseCampfireBuffs(splitLines, fullText)
    print(string.format("|cff0cd29f[EFHelper Debug]|r Parsed buffs: %d", #found))
    for _, b in ipairs(found) do
        local alias = Campfire:GetBuffAlias(b.name)
        print("  * " .. b.name .. " (" .. alias .. ") => " .. (b.stat or ""))
    end
end
