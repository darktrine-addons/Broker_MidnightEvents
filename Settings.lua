-- Broker_MidnightEvents - Settings
-- WoW Settings panel registration and saved-variables defaults.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

-- Default visibility flags. enabledSections mirrors the tooltip's top-level
-- section list one-for-one. showWorldBosses gates the World Boss row inside
-- the "weekly" section (kept as a separate flag so disabling it doesn't hide
-- the whole section).
local defaults = {
    enabledSections = {
        now      = true,
        upcoming = true,
        weekly   = true,
        alts     = true,
    },
    showWorldBosses = true,
    broker = {
        showProgress = true,   -- "Weeklies N/M" / "All done" left-side chunk
        showEvent    = true,   -- "Stormarion 12m next" / "Abundance now!" tag
    },
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

    -- Phase 6 migration: consolidate section visibility under enabledSections.
    -- The legacy showAltSummary flag becomes enabledSections.alts; new flags
    -- (now, upcoming, weekly) default to true on first load.
    db.enabledSections = db.enabledSections or {}
    if db.showAltSummary ~= nil then
        if db.enabledSections.alts == nil then
            db.enabledSections.alts = db.showAltSummary
        end
        db.showAltSummary = nil
    end
    for k, v in pairs(defaults.enabledSections) do
        if db.enabledSections[k] == nil then db.enabledSections[k] = v end
    end

    if db.showWorldBosses == nil then db.showWorldBosses = defaults.showWorldBosses end

    db.broker = db.broker or {}
    for k, v in pairs(defaults.broker) do
        if db.broker[k] == nil then db.broker[k] = v end
    end

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

    -- Section: Tooltip Sections (mirror of the tooltip's top-level hierarchy)
    Settings.RegisterInitializer(category,
        CreateSettingsListSectionHeaderInitializer("Tooltip Sections", nil))

    local sectionOptions = {
        { key = "now",      label = "Now",                       desc = "Show currently-firing events (Stormarion, Legends, ongoing Abundance, etc.)." },
        { key = "upcoming", label = "Upcoming (next 24h)",       desc = "Show scheduled events firing within the next 24 hours." },
        { key = "weekly",   label = "This Week",                 desc = "Show the per-character weekly checklist (World Bosses + tracked weekly quests)." },
        { key = "alts",     label = "Alts roll-up",              desc = "Aggregate weekly progress across every character you've logged into with this addon enabled. Hidden when only the active character is tracked." },
    }
    for _, opt in ipairs(sectionOptions) do
        local setting = Settings.RegisterAddOnSetting(
            category, addonName .. "_section_" .. opt.key,
            opt.key, db.enabledSections,
            Settings.VarType.Boolean, opt.label,
            defaults.enabledSections[opt.key])
        setting:SetValueChangedCallback(RefreshUI)
        Settings.CreateCheckbox(category, setting, opt.desc)
    end

    -- Section: This Week rows
    Settings.RegisterInitializer(category,
        CreateSettingsListSectionHeaderInitializer("This Week rows", nil))

    local wbSetting = Settings.RegisterAddOnSetting(
        category, addonName .. "_showWorldBosses", "showWorldBosses", db,
        Settings.VarType.Boolean, "World Bosses",
        defaults.showWorldBosses)
    wbSetting:SetValueChangedCallback(RefreshUI)
    Settings.CreateCheckbox(category, wbSetting,
        "Display the World Bosses row inside the This Week section.")

    -- Section: Broker bar
    Settings.RegisterInitializer(category,
        CreateSettingsListSectionHeaderInitializer("Broker bar", nil))

    local brokerProgressSetting = Settings.RegisterAddOnSetting(
        category, addonName .. "_broker_showProgress", "showProgress", db.broker,
        Settings.VarType.Boolean, "Show weekly progress (N/M)",
        defaults.broker.showProgress)
    brokerProgressSetting:SetValueChangedCallback(RefreshUI)
    Settings.CreateCheckbox(category, brokerProgressSetting,
        "Show the weekly-progress count (e.g. \"Weeklies 3/7\") on the broker bar.")

    local brokerEventSetting = Settings.RegisterAddOnSetting(
        category, addonName .. "_broker_showEvent", "showEvent", db.broker,
        Settings.VarType.Boolean, "Show next-event tag",
        defaults.broker.showEvent)
    brokerEventSetting:SetValueChangedCallback(RefreshUI)
    Settings.CreateCheckbox(category, brokerEventSetting,
        "Append the next-firing event (e.g. \"Abundance in 23m\") to the broker bar text.")

    Settings.RegisterAddOnCategory(category)
    ns.settingsCategoryID = category:GetID()
end)
