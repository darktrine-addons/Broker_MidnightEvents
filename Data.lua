-- Broker_MidnightEvents - Data
-- Midnight-specific definitions: zones, events, schedules, quest IDs. Edit
-- this file (and only this file) to add or update content for new patches.
-- Provenance and harvest history live in design/harvest-notes.md.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

-- ── Tier 2: weekly checklist quest IDs ────────────────────────────────────────
-- Each entry = one row in the tooltip's "This Week" section, in render order.
-- Core iterates and calls IsQuestFlaggedCompleted(questID) on
-- PLAYER_ENTERING_WORLD, QUEST_TURNED_IN, and QUEST_REMOVED.
ns.weeklies = {
    { key = "abundance",     questID = 89507, label = "Abundant Offerings" },  -- Abundance event weekly
    { key = "stormarion",    questID = 94581, label = "Stand Your Ground"  },  -- Stormarion Assault weekly (Voidstorm WQ)
    { key = "preyNightmare", questID = 94446, label = "A Nightmarish Task" },  -- Prey NM tier weekly (3 Nightmare Hunts)
    { key = "haranir",       questID = 89268, label = "Lost Legends"       },  -- Haranir warband scenario
}

-- Candidate weeklies — harvested IDs that can't be promoted as-is. Two gates:
--   (a) needs multi-questID slot semantics Core doesn't yet implement. Promote
--       once Core iterates a `questIDs = {a, b, …}` field with "any flagged
--       completed = slot done".
--   (b) classification still uncertain — needs more harvest data.
-- Entries are commented-out Lua so the structure is self-documenting and
-- trivial to uncomment when the gate clears.
ns.candidateWeeklies = {
    -- (a) Lady Liadrin's choice pool. She offers ~4 of 7 per char per week;
    --     completing one locks the others on that char. All freq=3.
    -- { key = "liadrin", label = "Lady Liadrin's Weekly", questIDs = {
    --       93769,  -- Midnight: Housing
    --       93889,  -- Midnight: Saltheril's Soiree
    --       93892,  -- Midnight: Stormarion Assault
    --       93909,  -- Midnight: Delves
    --       93911,  -- Midnight: Dungeons
    --       94457,  -- Midnight: Battlegrounds
    --       95842,  -- Midnight: Void Assaults
    --   } },

    -- (a) Void Assault zone-rotation weekly. Each active zone has its own
    --     questID; "any completed = done". Harandar/Voidstorm variants TBD.
    -- { key = "voidAssaultZone", label = "Void Assault (active zone)", questIDs = {
    --       94385,  -- Void Assaults: Eversong Woods
    --       94386,  -- Void Assaults: Zul'Aman
    --   } },

    -- (b) 91700 "Darkness Unmade" — freq=2: kill 2 rares in Stormarion Citadel,
    --     drops Stormarion Core. Distinct from Stand Your Ground; may merit
    --     its own row or fold into a Stormarion umbrella.
    -- { key = "stormarionRares", questID = 91700, label = "Darkness Unmade" },

    -- (b) 95468 "Hope in the Darkest Corners" — freq=2: complete WQs/Dungeons/
    --     Delves in Midnight zones; rewards Quel'Thalas Adventurer's Cache.
    --     Likely OOS umbrella (MR territory), pending final scope call.
    -- { key = "advCache", questID = 95468, label = "Hope in the Darkest Corners" },
}

-- ── Out-of-scope reference (ceded to Midnight Routine) ────────────────────────
-- Harvested IDs that map to design out-of-scope content. Block-commented;
-- nothing consumes this. Uncomment + move to candidates if scope changes.
--
-- ns.outOfScopeWeeklies = {
--     -- { questID, title, reason }
--     { 93613, "A Savage Path Through Time",           "Timewalking weekly (Aethas slot)" },
--     { 93697, "Shimmering Melodies",                  "Profession/enchanting"            },
--     { 93755, "Den of Nalorakk",                      "Dungeon weekly"                   },
--     { 94790, "Research Console: Exploring the Void", "Generic Voidstorm WQ weekly"      },
--     { 95413, "Community Engagement",                 "Housing weekly (Vaeli)"           },
-- }

-- ── World boss credit quests ──────────────────────────────────────────────────
-- Midnight world bosses register completion via per-boss kill-credit quests,
-- not raid lockouts (GetSavedWorldBossInfo doesn't populate). Iterate this
-- table; the first questID flagged completed identifies the boss this char
-- has killed. Weekly-reset behaviour of these IDs is TBD — verify at the
-- next reset.
ns.worldBosses = {
    { name = "Lu'ashal",    questID = 92560 },
    { name = "Cragpine",    questID = 92123 },
    { name = "Thorm'belan", questID = 92034 },
    { name = "Predaxas",    questID = 92636 },
}
