-- Broker_MidnightEvents - Data
-- Midnight-specific definitions: zones, events, schedules, aliases. Edit this
-- file (and only this file) to add or update content for new patches.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

-- ── Midnight zone uiMapIDs ────────────────────────────────────────────────────
-- Verified via C_Map.GetMapChildrenInfo on the Midnight continent. The
-- player's current map is always also scanned at runtime, so events visible
-- from adjacent maps (e.g. Silvermoon City Prey POIs) still show up.
ns.zones = {
    2395,  -- Eversong Woods
    2405,  -- Voidstorm
    2413,  -- Harandar
    2437,  -- Zul'Aman
}

-- ── Fixed-cadence schedule fallback ───────────────────────────────────────────
-- Events that fire on a wall-clock cadence without pushing a per-POI timer
-- through the API. Keyed by the short event name (everything before ": ").
-- If empirical observation shows a non-:00/:30 phase, anchor adjustment
-- (additive offset before the modulo) goes here.
ns.fixedCadence = {
    ["Stormarion Assault"] = 1800,  -- every 30 min, Voidstorm
}

function ns.ScheduleFallbackSecs(name)
    local short   = name and (name:match("^(.-): ") or name)
    local cadence = short and ns.fixedCadence[short]
    if not cadence then return nil end
    return cadence - (time() % cadence)
end

-- After a predicted firing has passed, the entry stays in 'now!' state for
-- this many seconds before rolling forward to the next cadence mark. Long
-- enough to cover most realistic event durations; short enough that a
-- mispredicted firing self-corrects within reason.
ns.scheduleGracePeriod = 600  -- 10 min

-- ── Event toggle aliases ──────────────────────────────────────────────────────
-- Maps an observed event name (full or short) to a stable toggle key, so
-- multiple POI variants collapse onto one setting (every flavor of Void
-- Assault → "voidAssault").
local EVENT_KEY = {
    ["Abundance"]                = "abundance",
    ["Stormarion Assault"]       = "stormarionAssault",
    ["Slayer's Rise"]            = "slayersRise",
    ["Void Assaults"]            = "voidAssault",
    ["Void Incursion"]           = "voidAssault",
    ["Impending Void Incursion"] = "voidAssault",
    ["Void Rift"]                = "voidAssault",
    ["Bountiful Delve"]          = "bountifulDelve",
}

function ns.GetEventToggleKey(name)
    if not name then return nil end
    local short = name:match("^(.-): ") or name
    return EVENT_KEY[short]
end

-- ── Settings UI: ordered list of toggle definitions ───────────────────────────
ns.eventToggles = {
    { key = "abundance",          label = "Abundance"          },
    { key = "stormarionAssault",  label = "Stormarion Assault" },
    { key = "slayersRise",        label = "Slayer's Rise"      },
    { key = "voidAssault",        label = "Void Assaults"      },
    { key = "bountifulDelve",     label = "Bountiful Delve"    },
}
