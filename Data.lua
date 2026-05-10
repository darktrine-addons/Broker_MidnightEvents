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

-- ── Tier 2: weekly checklist quest IDs ────────────────────────────────────────
-- Each entry maps to one row in the tooltip's "This Week" section. The order
-- here is the rendering order. `questID` is checked via IsQuestFlaggedCompleted
-- on PEW + QUEST_TURNED_IN + QUEST_REMOVED.
--
-- NOTE: the `Midnight: <X>` umbrella quests we initially used (93889 Saltheril,
-- 93892 Stormarion, 93909 Delves, 94457 Battlegrounds, 95842 Void Assaults)
-- turned out to be one-time intro/unlock quests, not weekly trackers. They
-- flag permanently after first engagement with each event, so every character
-- who ever touched the content reads as "done forever." Removed pending a
-- harvest cycle of the actual weekly IDs (accept the quest on a char, /reload,
-- DevHarvest captures the live ID).
ns.weeklies = {
    { key = "haranir", questID = 89268, label = "Lost Legends" },
}

-- ── World boss credit quests ──────────────────────────────────────────────────
-- Midnight world bosses register completion via quest credit, not raid lockouts
-- (which is why GetSavedWorldBossInfo never populated). The umbrella questID
-- below flips when ANY world boss has been killed this week; the per-boss
-- entries identify which one.
ns.worldBossWeekly = 93913   -- "Midnight: World Boss" umbrella

ns.worldBosses = {
    { name = "Lu'ashal",    questID = 92560 },
    { name = "Cragpine",    questID = 92123 },
    { name = "Thorm'belan", questID = 92034 },
    { name = "Predaxas",    questID = 92636 },
}
