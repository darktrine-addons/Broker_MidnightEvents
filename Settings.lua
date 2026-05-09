-- Broker_MidnightEvents - Settings
-- WoW Settings panel registration and saved-variables defaults.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

local defaults = {
    -- Settings will be added in subsequent versions.
}

local sf = CreateFrame("Frame")
sf:RegisterEvent("ADDON_LOADED")
sf:SetScript("OnEvent", function(self, event, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    Broker_MidnightEventsDB = Broker_MidnightEventsDB or {}
    local db = Broker_MidnightEventsDB
    db.minimapIcon = db.minimapIcon or { hide = false }  -- sub-table; managed by LibDBIcon
    for k, v in pairs(defaults) do
        if db[k] == nil then db[k] = v end
    end
    ns.db = db

    -- Register minimap button (LibDBIcon manages show/hide via its own right-click menu).
    local LibDBIcon = LibStub("LibDBIcon-1.0", true)
    if LibDBIcon and ns.broker then
        LibDBIcon:Register("Broker_MidnightEvents", ns.broker, db.minimapIcon)
    end
end)
