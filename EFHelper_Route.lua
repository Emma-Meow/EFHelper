-- ----------------------------------------------------------------------------
-- EFHelper_Route.lua
-- Leveling Route Profiles & Interactive Mob Checklist HUD (12.0 Midnight)
-- ----------------------------------------------------------------------------
local addonName, addonTable = ...
local EFHelper = _G.EFHelper or addonTable
local Route = EFHelper:NewModule("Route", "AceEvent-3.0")
EFHelper.Route = Route

local Utils = EFHelper.Utils
local UI = EFHelper.UI

-- ----------------------------------------------------------------------------
-- Leveling Route Profiles (Per Zone)
-- ----------------------------------------------------------------------------
Route.ProfileNames = {
    "Tirisfal Glades",
    "Durotar",
    "Mulgore",
    "Fortnelf",
}

Route.Profiles = {
    ["Tirisfal Glades"] = {
        { "Mindless Zombie", "Wretched Zombie" },
        { "Young Scavenger", "Duskbat" },
        { "Rattlecage Skeleton" },
        { "Young Night Web Spider", "Night Web Spider" },
        { "Samuel Fipps" },
        { "Scarlet Convert", "Scarlet Initiate" },
        { "Meven Korgal" },
    },
    ["Durotar"] = {},
    ["Mulgore"] = {},
    ["Fortnelf"] = {},
}

-- Backward compatibility aliases
EFHelper.RouteProfileNames = Route.ProfileNames
EFHelper.RouteProfiles = Route.Profiles
addonTable.RouteProfileNames = Route.ProfileNames
addonTable.RouteProfiles = Route.Profiles

-- ----------------------------------------------------------------------------
-- Helper Functions
-- ----------------------------------------------------------------------------
function Route:ParseRouteEntry(entry)
    local mob1, mob2
    if type(entry) == "table" then
        mob1 = entry[1] and Utils.Trim(entry[1]) or nil
        mob2 = entry[2] and Utils.Trim(entry[2]) or nil
    elseif entry then
        mob1 = Utils.Trim(tostring(entry))
    end
    return mob1, mob2
end

local function IsInsideInstance()
    if not IsInInstance then return false end
    local inInstance, instanceType = IsInInstance()
    return inInstance and (instanceType ~= "none")
end
Route.IsInsideInstance = IsInsideInstance

function Route:UpdateInstanceVisibility()
    local shouldShow = (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.hudShown) or (EFHelperCharDB and EFHelperCharDB.hudShown)
    if IsInsideInstance() then
        if Route.hud then Route.hud:Hide() end
    else
        if shouldShow then
            local hud = Route:BuildHUD()
            hud:Show()
            Route:RefreshHUD()
        end
    end
end

function Route:GetCurrentProfile()
    if EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.currentProfile then
        return EFHelper.db.profile.currentProfile
    end
    if EFHelperCharDB and EFHelperCharDB.currentProfile then
        return EFHelperCharDB.currentProfile
    end
    return "Tirisfal Glades"
end

function Route:GetRouteMobs()
    local prof = Route:GetCurrentProfile()
    return Route.Profiles[prof] or Route.Profiles["Tirisfal Glades"] or {}
end

function Route:SetRouteProfile(profileName, silent)
    if not Route.Profiles[profileName] then return end
    local prof = EFHelper.db and EFHelper.db.profile
    if prof then prof.currentProfile = profileName end
    if EFHelperCharDB then EFHelperCharDB.currentProfile = profileName end

    EFHelper.currentProfile = profileName
    EFHelper.RouteMobs = Route.Profiles[profileName]

    if not silent then
        EFHelper.activeRouteMob = nil
        EFHelper.activeRouteIndex = nil
        if prof then prof.activeRouteIndex = nil end
        if EFHelperCharDB then EFHelperCharDB.activeRouteIndex = nil end
        if Route.hud and Route.hud.scrollFrame then
            Route.hud.scrollFrame:SetVerticalScroll(0)
        end
        Route:RefreshHUD()
    end

    if Route.hud and Route.hud.profileDropdown then
        Route.hud.profileDropdown:SetText(profileName)
    end
end

-- Backward compatibility bridge
function EFHelper:SetRouteProfile(profileName, silent)
    return Route:SetRouteProfile(profileName, silent)
end

-- ----------------------------------------------------------------------------
-- HUD Construction & Refresh
-- ----------------------------------------------------------------------------
function Route:RefreshHUD()
    if IsInsideInstance() then return end
    if not Route.hud or not Route.hud.content then return end
    local content = Route.hud.content
    content.rows = content.rows or {}

    local mobs = Route:GetRouteMobs()
    local rowHeight = 22

    local prof = EFHelper.db and EFHelper.db.profile
    local activeIdx = prof and prof.activeRouteIndex or EFHelper.activeRouteIndex
    local activeMob = prof and prof.lastMobName or EFHelper.activeRouteMob

    for i, entry in ipairs(mobs) do
        local mob1, mob2 = Route:ParseRouteEntry(entry)
        local displayText = mob1 or ""
        if mob2 and mob2 ~= "" then
            displayText = mob1 .. " / " .. mob2
        end

        local row = content.rows[i]
        if not row then
            row = CreateFrame("Button", nil, content)
            row:SetHeight(rowHeight - 2)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(i - 1) * rowHeight)
            row:SetPoint("TOPRIGHT", content, "TOPRIGHT", -2, -(i - 1) * rowHeight)

            local selBg = row:CreateTexture(nil, "BACKGROUND")
            selBg:SetAllPoints()
            selBg:SetColorTexture(0.05, 0.82, 0.62, 0.25)
            row.selBg = selBg

            local hl = row:CreateTexture(nil, "HIGHLIGHT")
            hl:SetAllPoints()
            hl:SetColorTexture(1, 1, 1, 0.12)

            local text = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            text:SetPoint("LEFT", row, "LEFT", 4, 0)
            text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
            text:SetJustifyH("LEFT")
            UI.SetupFontString(text, 11, "OUTLINE")
            row.text = text

            content.rows[i] = row
        end

        local isActive = (activeIdx == i) or (activeMob == mob1)
        if isActive then
            row.selBg:Show()
            row.text:SetText(string.format("|cff0cd29f%d.|r |cffffffff%s|r", i, displayText))
        else
            row.selBg:Hide()
            row.text:SetText(string.format("|cff888888%d.|r |cffcccccc%s|r", i, displayText))
        end

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(string.format("Route Step %d", i), 1, 0.82, 0)
            if mob2 and mob2 ~= "" then
                GameTooltip:AddLine("EFTag:  |cffffffff" .. mob1 .. "|r")
                GameTooltip:AddLine("EFTag2: |cffffffff" .. mob2 .. "|r")
            else
                GameTooltip:AddLine("EFTag:  |cffffffff" .. (mob1 or "None") .. "|r")
            end
            GameTooltip:AddLine("Click to set macro(s)", 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        row:SetScript("OnClick", function()
            if InCombatLockdown and InCombatLockdown() then
                print("|cffff4444[EFHelper]|r Cannot create or edit macros while in combat!")
                return
            end

            if not mob1 or mob1 == "" then return end

            local currentSpell = (prof and prof.lastSpell) or EFHelper.selectedSpell
            local Tagging = EFHelper.Tagging

            local success1 = Tagging and Tagging:CreateOrUpdateTaggingMacro(Tagging.defaultMacroName, mob1, currentSpell, true)
            local success2 = true
            if mob2 and mob2 ~= "" then
                success2 = Tagging and Tagging:CreateOrUpdateTaggingMacro(Tagging.secondMacroName, mob2, currentSpell, true)
            end

            if success1 or success2 then
                EFHelper.activeRouteMob = mob1
                EFHelper.activeRouteIndex = i
                if prof then
                    prof.lastMobName = mob1
                    prof.activeRouteIndex = i
                end
                if EFHelperCharDB then
                    EFHelperCharDB.lastMobName = mob1
                    EFHelperCharDB.activeRouteIndex = i
                end
                if EFHelper.Config and EFHelper.Config.frame and EFHelper.Config.frame.mobInput then
                    EFHelper.Config.frame.mobInput:SetText(mob1)
                end
                Route:RefreshHUD()
            end
        end)

        row:Show()
    end

    for i = #mobs + 1, #content.rows do
        content.rows[i]:Hide()
    end

    content:SetHeight(math.max(1, #mobs * rowHeight))
end

function Route:BuildHUD()
    if Route.hud then return Route.hud end

    local hud = UI.CreateBackdropFrame("Frame", "EFHelperHUD", UIParent, 220, 185)
    hud:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -180)
    hud:SetMovable(true)
    hud:EnableMouse(true)
    hud:RegisterForDrag("LeftButton")
    hud:SetClampedToScreen(true)

    hud:SetScript("OnDragStart", hud.StartMoving)
    hud:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
        if EFHelper.db and EFHelper.db.profile then
            EFHelper.db.profile.hudPosition = { point, nil, relativePoint, xOfs, yOfs }
        end
        if EFHelperCharDB then
            EFHelperCharDB.hudPoint = { point, nil, relativePoint, xOfs, yOfs }
        end
    end)
    hud:Hide()

    -- Title
    local title = hud:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", hud, "TOPLEFT", 8, -6)
    title:SetText("Route Mobs")
    UI.SetupFontString(title, 11, "OUTLINE")

    -- Close Button
    local closeBtn = CreateFrame("Button", nil, hud, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        hud:Hide()
        if EFHelper.db and EFHelper.db.profile then
            EFHelper.db.profile.hudShown = false
        end
        if EFHelperCharDB then
            EFHelperCharDB.hudShown = false
        end
    end)

    -- Profile Dropdown
    local profileDropdown
    local ok, btn = pcall(CreateFrame, "DropdownButton", "EFHelperHUDProfileDropdown", hud, "WowStyle1DropdownTemplate")
    if ok and btn then
        profileDropdown = btn
    else
        profileDropdown = CreateFrame("Button", "EFHelperHUDProfileDropdown", hud, "UIPanelButtonTemplate")
    end
    profileDropdown:SetSize(204, 20)
    profileDropdown:SetPoint("TOPLEFT", hud, "TOPLEFT", 8, -22)
    profileDropdown:SetText(Route:GetCurrentProfile())

    local function SetupProfileMenu(owner, rootDescription)
        rootDescription:SetTag("EFHELPER_HUD_PROFILE_DROPDOWN")
        local profiles = Route.ProfileNames or {}
        for _, profileName in ipairs(profiles) do
            rootDescription:CreateRadio(
                profileName,
                function() return Route:GetCurrentProfile() == profileName end,
                function()
                    Route:SetRouteProfile(profileName)
                end
            )
        end
    end

    if profileDropdown.SetupMenu then
        profileDropdown:SetupMenu(SetupProfileMenu)
    elseif MenuUtil and MenuUtil.CreateContextMenu then
        profileDropdown:SetScript("OnClick", function(self)
            MenuUtil.CreateContextMenu(self, SetupProfileMenu)
        end)
    end
    hud.profileDropdown = profileDropdown

    -- ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", "EFHelperHUDScrollFrame", hud, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", hud, "TOPLEFT", 6, -46)
    scrollFrame:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", -24, 6)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(190, 1)
    scrollFrame:SetScrollChild(content)

    hud.content = content
    hud.scrollFrame = scrollFrame

    Route.hud = hud
    EFHelper.hud = hud

    -- Restore saved position
    local savedPos = (EFHelper.db and EFHelper.db.profile and EFHelper.db.profile.hudPosition) or (EFHelperCharDB and EFHelperCharDB.hudPoint)
    if savedPos then
        hud:ClearAllPoints()
        hud:SetPoint(savedPos[1], UIParent, savedPos[3], savedPos[4], savedPos[5])
    end

    Route:RefreshHUD()
    return hud
end

function Route:ToggleRouteHUD()
    local hud = Route:BuildHUD()
    if hud:IsShown() then
        hud:Hide()
        if EFHelper.db and EFHelper.db.profile then
            EFHelper.db.profile.hudShown = false
        end
        if EFHelperCharDB then
            EFHelperCharDB.hudShown = false
        end
    else
        hud:Show()
        Route:RefreshHUD()
        if EFHelper.db and EFHelper.db.profile then
            EFHelper.db.profile.hudShown = true
        end
        if EFHelperCharDB then
            EFHelperCharDB.hudShown = true
        end
    end
end

function Route:ResetRouteHUDPosition()
    if EFHelper.db and EFHelper.db.profile then
        EFHelper.db.profile.hudPosition = nil
    end
    if EFHelperCharDB then
        EFHelperCharDB.hudPoint = nil
    end
    local hud = Route.hud or Route:BuildHUD()
    if hud then
        hud:ClearAllPoints()
        hud:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 60, -180)
    end
end

-- Backward compatibility aliases
function EFHelper:RefreshHUD() return Route:RefreshHUD() end
function EFHelper:ToggleRouteHUD() return Route:ToggleRouteHUD() end
function EFHelper:ResetRouteHUDPosition() return Route:ResetRouteHUDPosition() end

-- ----------------------------------------------------------------------------
-- Slash Commands (/efhud, /efhhud)
-- ----------------------------------------------------------------------------
SLASH_EFHELPERHUD1 = "/efhhud"
SLASH_EFHELPERHUD2 = "/efhud"
SlashCmdList["EFHELPERHUD"] = function()
    Route:ToggleRouteHUD()
end

-- ----------------------------------------------------------------------------
-- Module Lifecycle (AceEvent-3.0)
-- ----------------------------------------------------------------------------
function Route:OnInitialize()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "UpdateInstanceVisibility")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "UpdateInstanceVisibility")
    Route:UpdateInstanceVisibility()
end
