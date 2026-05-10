-- Broker_MidnightEvents - Settings
-- WoW Settings panel registration and saved-variables defaults.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

local defaults = {
    -- Per-event visibility (keys come from ns.eventToggles in Data.lua).
    events = {
        abundance         = true,
        stormarionAssault = true,
        slayersRise       = true,
        voidAssault       = true,
        bountifulDelve    = true,
    },
    hideDistant     = true,    -- hide events firing more than 24h away
    showWorldBosses = true,    -- show World Bosses row in This Week section
}

-- Returns the epoch (seconds) of the most recent weekly reset, or nil if the
-- API isn't available yet (early addon-load, or rare timing windows).
local function CurrentWeeklyResetEpoch()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local s = C_DateAndTime.GetSecondsUntilWeeklyReset()
        if s and s > 0 then
            return time() + s - 7 * 86400
        end
    end
    return nil
end

local function RefreshUI()
    if ns.UpdateBrokerText     then ns.UpdateBrokerText()     end
    if ns.RebuildTooltipIfOpen then ns.RebuildTooltipIfOpen() end
end

local sf = CreateFrame("Frame")
sf:RegisterEvent("ADDON_LOADED")
sf:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    Broker_MidnightEventsDB = Broker_MidnightEventsDB or {}
    local db = Broker_MidnightEventsDB
    db.minimapIcon = db.minimapIcon or { hide = false }  -- managed by LibDBIcon
    db.chars       = db.chars       or {}
    db.events      = db.events      or {}
    for k, v in pairs(defaults.events) do
        if db.events[k] == nil then db.events[k] = v end
    end
    if db.hideDistant     == nil then db.hideDistant     = defaults.hideDistant     end
    if db.showWorldBosses == nil then db.showWorldBosses = defaults.showWorldBosses end
    ns.db = db

    -- Per-character bootstrap. Key is "Realm/Name" so connected realms with
    -- duplicate character names stay distinct.
    local charKey  = (GetRealmName() or "?") .. "/" .. (UnitName("player") or "?")
    db.chars[charKey] = db.chars[charKey] or {}
    local char = db.chars[charKey]
    char.lastLogin       = time()
    char.weeklyReset     = char.weeklyReset     or 0
    char.worldBossesDone = char.worldBossesDone or {}
    ns.char = char

    -- Weekly reset detection: if the most recent reset is newer than the one
    -- this character's data covers, wipe weekly state.
    local currentReset = CurrentWeeklyResetEpoch()
    if currentReset and char.weeklyReset < currentReset then
        char.worldBossesDone = {}
        char.weeklyReset     = currentReset
    end

    -- Register minimap button (LibDBIcon manages show/hide via right-click menu).
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if LibDBIcon and ns.broker then
        LibDBIcon:Register("Broker_MidnightEvents", ns.broker, db.minimapIcon)
    end

    -- Kick the world-boss lockout cache; UPDATE_INSTANCE_INFO will fire when
    -- the server replies and Core.lua picks it up from there.
    if RequestRaidInfo then RequestRaidInfo() end

    -- ── Settings panel ────────────────────────────────────────────────────────

    local category = Settings.RegisterVerticalLayoutCategory("Broker: MidnightEvents")

    -- Section: Timed Events
    Settings.RegisterInitializer(category,
        CreateSettingsListSectionHeaderInitializer("Timed Events", nil))

    for _, toggle in ipairs(ns.eventToggles or {}) do
        local setting = Settings.RegisterAddOnSetting(
            category, addonName .. "_event_" .. toggle.key,
            toggle.key, db.events,
            Settings.VarType.Boolean, toggle.label,
            defaults.events[toggle.key] ~= false)
        setting:SetValueChangedCallback(RefreshUI)
        Settings.CreateCheckbox(category, setting,
            "Show " .. toggle.label .. " in the Timed Events list.")
    end

    local hideDistantSetting = Settings.RegisterAddOnSetting(
        category, addonName .. "_hideDistant", "hideDistant", db,
        Settings.VarType.Boolean, "Hide events firing more than 24h away",
        defaults.hideDistant)
    hideDistantSetting:SetValueChangedCallback(RefreshUI)
    Settings.CreateCheckbox(category, hideDistantSetting,
        "Reduces clutter by hiding long-running events whose next firing is "
        .. "more than 24 hours out.")

    -- Section: This Week
    Settings.RegisterInitializer(category,
        CreateSettingsListSectionHeaderInitializer("This Week", nil))

    local wbSetting = Settings.RegisterAddOnSetting(
        category, addonName .. "_showWorldBosses", "showWorldBosses", db,
        Settings.VarType.Boolean, "Show World Bosses row",
        defaults.showWorldBosses)
    wbSetting:SetValueChangedCallback(RefreshUI)
    Settings.CreateCheckbox(category, wbSetting,
        "Display the world boss kill list in the This Week section.")

    Settings.RegisterAddOnCategory(category)
    ns.settingsCategoryID = category:GetID()
end)
