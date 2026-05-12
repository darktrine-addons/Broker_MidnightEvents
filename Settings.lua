-- Broker_MidnightEvents - Settings
-- WoW Settings panel registration and saved-variables defaults.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

local defaults = {
    showWorldBosses = true,    -- show World Bosses row in This Week section
    showAltSummary  = true,    -- show Alts roll-up section
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

    -- Phase 2 migration: per-event toggles and "hide distant" are gone now
    -- that the Events surface is C_EventScheduler-driven (Blizzard's own
    -- panel handles filtering). Drop the orphaned SV keys on first load.
    db.events      = nil
    db.hideDistant = nil

    if db.showWorldBosses == nil then db.showWorldBosses = defaults.showWorldBosses end
    if db.showAltSummary  == nil then db.showAltSummary  = defaults.showAltSummary  end
    ns.db = db

    -- Per-character bootstrap. Key is "Realm/Name" so connected realms with
    -- duplicate character names stay distinct.
    local charKey  = (GetRealmName() or "?") .. "/" .. (UnitName("player") or "?")
    db.chars[charKey] = db.chars[charKey] or {}
    local char = db.chars[charKey]
    char.lastLogin       = time()
    char.weeklyReset     = char.weeklyReset or 0
    char.worldBoss       = char.worldBoss   or { done = false }
    char.weeklies        = char.weeklies    or {}
    char.worldBossesDone = nil  -- legacy, replaced by worldBoss table
    ns.char = char

    -- Weekly reset detection: if the most recent reset is newer than the one
    -- this character's data covers, wipe weekly state.
    local currentReset = CurrentWeeklyResetEpoch()
    if currentReset and char.weeklyReset < currentReset then
        char.worldBoss   = { done = false }
        char.weeklies    = {}
        char.weeklyReset = currentReset
    end

    -- Register minimap button (LibDBIcon manages show/hide via right-click menu).
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if LibDBIcon and ns.broker then
        LibDBIcon:Register("Broker_MidnightEvents", ns.broker, db.minimapIcon)
    end

    -- ── Settings panel ────────────────────────────────────────────────────────

    local category = Settings.RegisterVerticalLayoutCategory("Broker: MidnightEvents")

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

    -- Section: Alts
    Settings.RegisterInitializer(category,
        CreateSettingsListSectionHeaderInitializer("Alts", nil))

    local altSetting = Settings.RegisterAddOnSetting(
        category, addonName .. "_showAltSummary", "showAltSummary", db,
        Settings.VarType.Boolean, "Show Alts roll-up",
        defaults.showAltSummary)
    altSetting:SetValueChangedCallback(RefreshUI)
    Settings.CreateCheckbox(category, altSetting,
        "Aggregate weekly progress across every character you've logged into "
        .. "with this addon enabled. Hidden when only the active character is tracked.")

    Settings.RegisterAddOnCategory(category)
    ns.settingsCategoryID = category:GetID()
end)
