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
-- Harvest curation 2026-05-12 (Elune/Artherio + Elune/Sundowner via DevHarvest,
-- cross-referenced on Wowhead). Two architectural findings worth noting:
--
--   1. The "Midnight: <X>" family (93769/93889/93892/93909/93911/94457/95842)
--      is NOT one-time intro quests, as a prior note here speculated. They
--      are Lady Liadrin's weekly *choice pool*: she offers ~4 of the pool
--      per char per week, all freq=3, all rewarding Spark of Radiance +
--      Apex Cache. Completing one on a char locks the others on that char.
--      The slot is in-scope per design (open question #4) but needs multi-
--      questID "any completed = done" semantics; parked in candidates below
--      until Core supports it.
--
--   2. The PvP/Call-to-Battle slot off Archmage Aethas Sunreaver appears
--      to be a multi-content rotation. This week (Artherio) it gave 93613
--      "A Savage Path Through Time" which Wowhead classifies as the
--      Timewalking weekly (5 TW dungeons). The actual "A Call to Battle"
--      questID is still unharvested. Slot parked in candidates pending more
--      data — and 93613 itself is out-of-scope (TW is not event-tied).
ns.weeklies = {
    { key = "abundance",     questID = 89507, label = "Abundant Offerings" },
    { key = "stormarion",    questID = 94581, label = "Stand Your Ground"  },  -- Stormarion Assault weekly (Voidstorm WQ)
    { key = "preyNightmare", questID = 94446, label = "A Nightmarish Task" },  -- Prey NM tier weekly (3 Nightmare Hunts)
    { key = "haranir",       questID = 89268, label = "Lost Legends"       },
}

-- Candidate weeklies — harvested IDs that map to design rows but can't be
-- promoted as-is. Two reasons a row stays here:
--   (a) needs multi-questID slot semantics Core doesn't yet implement
--       (rotation pool, choose-N umbrella) — promote once Core iterates a
--       `questIDs = {a, b, …}` field with "any flagged completed = done";
--   (b) classification still uncertain after this harvest pass — needs
--       another reset or another char to disambiguate.
-- Entries are commented-out Lua so the structure stays self-documenting
-- and trivial to uncomment when the gate clears.
ns.candidateWeeklies = {
    -- (a) Lady Liadrin's weekly choice pool. Up to ~4 offered per char per
    --     week from this pool of 7 known IDs. The current `voidAssaults` row
    --     the design specced as Liadrin's umbrella is really this whole pool.
    -- { key = "liadrin", label = "Lady Liadrin's Weekly", questIDs = {
    --       93769,  -- Midnight: Housing               (5 Community Coupons)
    --       93889,  -- Midnight: Saltheril's Soiree    (faction favor)
    --       93892,  -- Midnight: Stormarion Assault    (3 Singularity Anchor Wave events)
    --       93909,  -- Midnight: Delves                (any seasonal Delve)
    --       93911,  -- Midnight: Dungeons              (any seasonal Dungeon)
    --       94457,  -- Midnight: Battlegrounds         (any BG in Midnight)
    --       95842,  -- Midnight: Void Assaults         (Void Strikes + Incursions)
    --   } },

    -- (a) Void Assault zone-rotation weekly. The active zone changes weekly
    --     (per 12.0.5 design note); each zone has its own questID. Two
    --     confirmed; Harandar / Voidstorm variants likely exist and surface
    --     when the rotation lands on those zones.
    -- { key = "voidAssaultZone", label = "Void Assault (active zone)", questIDs = {
    --       94385,  -- Void Assaults: Eversong Woods   (giver: Ranger Captain Lilatha)
    --       94386,  -- Void Assaults: Zul'Aman
    --   } },

    -- (a) A Call to Battle / Aethas Sunreaver rotation slot. Holding the
    --     slot open until the actual Call to Battle (Win 4 BGs) ID is
    --     harvested next reset. 93613 (TW) is NOT a member — it's OOS.
    -- { key = "callToBattle", label = "A Call to Battle", questIDs = {
    --       -- TBD: actual A Call to Battle questID
    --   } },

    -- (b) 91700 "Darkness Unmade" — freq=2: eliminate 2 rares in Stormarion
    --     Citadel (drops Stormarion Core; suggested 3 players). Distinct
    --     from Stand Your Ground (94581); may be a bonus Stormarion weekly
    --     deserving its own row, or a sub-objective of a hidden umbrella.
    --     Sample size 1 (Artherio pew-scan). Needs another char to confirm.
    -- { key = "stormarionRares", questID = 91700, label = "Darkness Unmade" },

    -- (b) 95468 "Hope in the Darkest Corners" — freq=2: complete WQs,
    --     Dungeons, and Delves in Midnight zones, rewards Quel'Thalas
    --     Adventurer's Cache. Generic adventurer umbrella; most likely
    --     belongs under out-of-scope (MR territory). Kept here as the
    --     user's hold pending a final scope call.
    -- { key = "advCache", questID = 95468, label = "Hope in the Darkest Corners" },
}

-- ── Out-of-scope reference (ceded to Midnight Routine) ────────────────────────
-- Quest IDs harvested in passing that map to design out-of-scope content.
-- Block-commented as the user requested — nothing consumes this, it's a
-- changelog so future harvest passes don't waste curation time re-checking
-- the same IDs. Uncomment + move to ns.candidateWeeklies if scope changes.
--
-- ns.outOfScopeWeeklies = {
--     -- { questID, title, reason, source }
--     { 93613, "A Savage Path Through Time",            "Timewalking weekly (5 TW dungeons) — not event-tied",                 "Artherio 2026-05-12 accept (Aethas Sunreaver)"  },
--     { 93697, "Shimmering Melodies",                   "Profession/enchanting (20 Eversinging Dust → Dolothos, Silvermoon)",  "Artherio 2026-05-12 accept (Dolothos)"          },
--     { 93755, "Den of Nalorakk",                       "Dungeon weekly (Zul'Aman boss credit) — Silvermoon dungeon family",   "Artherio 2026-05-12 accept (Halduron Brightwing)" },
--     { 94790, "Research Console: Exploring the Void",  "Generic Voidstorm WQ weekly (3 WQs for Void Researcher Anomander)",   "Artherio 2026-05-12 pew-scan"                   },
--     { 95413, "Community Engagement",                  "Housing weekly (Vaeli endeavor trader — Vaeli Housing scope)",        "Artherio 2026-05-12 accept (Vaeli)"             },
-- }

-- ── World boss credit quests ──────────────────────────────────────────────────
-- Midnight world bosses register completion via per-boss kill-credit quests,
-- not raid lockouts (which is why GetSavedWorldBossInfo never populated).
-- Iterate this table; the first questID flagged completed identifies the
-- boss this character has killed.
--
-- The 93913 'Midnight: World Boss' umbrella we tried earlier turned out to
-- be a one-time intro quest in the same family as the binary-weekly intros
-- we removed — it flagged on Shatanaris even though Shatanaris had killed
-- nothing this week. Don't reintroduce it.
--
-- Whether the per-boss credits below reset on the weekly clock is still
-- unverified; will be confirmed at the next reset. If they turn out to be
-- achievement-style (never reset) we'll need a different approach entirely.
ns.worldBosses = {
    { name = "Lu'ashal",    questID = 92560 },
    { name = "Cragpine",    questID = 92123 },
    { name = "Thorm'belan", questID = 92034 },
    { name = "Predaxas",    questID = 92636 },
}
