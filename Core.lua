-- Broker_MidnightEvents - Core
-- LDB data broker plugin: world event timers and weekly activity tracking for Midnight.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

local LDB = LibStub("LibDataBroker-1.1")
local broker = LDB:NewDataObject("Broker_MidnightEvents", {
    type  = "data source",
    label = "MidnightEvents",
    icon  = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    text  = "...",
})
ns.broker = broker  -- exposed for LibDBIcon registration in Settings.lua
