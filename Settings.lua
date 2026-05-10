-- Broker_MidnightEvents - Settings
-- WoW Settings panel registration and saved-variables defaults.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

local defaults = {
    -- Settings will be added in subsequent versions.
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

local sf = CreateFrame("Frame")
sf:RegisterEvent("ADDON_LOADED")
sf:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    Broker_MidnightEventsDB = Broker_MidnightEventsDB or {}
    local db = Broker_MidnightEventsDB
    db.minimapIcon = db.minimapIcon or { hide = false }  -- sub-table; managed by LibDBIcon
    db.chars       = db.chars or {}
    for k, v in pairs(defaults) do
        if db[k] == nil then db[k] = v end
    end
    ns.db = db

    -- Per-character bootstrap. Key is "Realm/Name" so connected realms with
    -- duplicate names stay distinct.
    local charKey  = (GetRealmName() or "?") .. "/" .. (UnitName("player") or "?")
    db.chars[charKey] = db.chars[charKey] or {}
    local char = db.chars[charKey]
    char.lastLogin       = time()
    char.weeklyReset     = char.weeklyReset     or 0
    char.worldBossesDone = char.worldBossesDone or {}
    ns.char = char

    -- Weekly reset detection: if the most recent reset is newer than the one
    -- this character's data covers, wipe the weekly state.
    local currentReset = CurrentWeeklyResetEpoch()
    if currentReset and char.weeklyReset < currentReset then
        char.worldBossesDone = {}
        char.weeklyReset     = currentReset
    end

    -- Register minimap button (LibDBIcon manages show/hide via its own right-click menu).
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if LibDBIcon and ns.broker then
        LibDBIcon:Register("Broker_MidnightEvents", ns.broker, db.minimapIcon)
    end

    -- Kick the world-boss lockout cache; UPDATE_INSTANCE_INFO will fire when
    -- the server replies and Core.lua picks it up from there.
    if RequestRaidInfo then RequestRaidInfo() end
end)
