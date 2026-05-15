-- Broker_MidnightEvents - Data
-- Midnight-specific definitions: zones, events, schedules, quest IDs. Edit
-- this file (and only this file) to add or update content for new patches.
-- Provenance and harvest history live in design/harvest-notes.md.
-- Copyright (C) 2026 artherion77
-- Licensed under the GNU General Public License v2.0 - see LICENSE.

local addonName, ns = ...

-- ── Wave-cadence overrides ────────────────────────────────────────────────────
-- Events that are continuously visible as a POI (so the scheduler tags them
-- "ongoing", isTimed=false) but internally cycle waves on a wall-clock
-- schedule. We synthesize a "next wave in Xm" countdown for these from server
-- time, since the tooltipWidgetSet is empty between waves and provides no
-- reliable countdown source.
--
-- Format: { period = seconds-between-waves, offset = seconds-from-the-hour }.
-- For Stormarion Assault, waves fire at :01 and :31 of each server hour →
-- period 30 min, offset 60 s.
ns.waveCadence = {
    ["Stormarion Assault"] = { period = 1800, offset = 60 },
}

function ns.GetWaveCountdown(eventName)
    local c = eventName and ns.waveCadence and ns.waveCadence[eventName]
    if not c then return nil end
    local now = (GetServerTime and GetServerTime()) or time()
    local elapsed = (now - (c.offset or 0)) % c.period
    return c.period - elapsed
end

-- ── Tier 2: weekly checklist quest IDs ────────────────────────────────────────
-- Each entry = one row in the tooltip's "This Week" section, in render order.
-- Two row shapes supported by Core's IsWeeklySlotDone:
--   { questID  = N }       — single quest; row done iff N flagged complete
--   { questIDs = {a, b…} } — pool/rotation slot; row done iff any member flagged
-- Refreshed on PLAYER_ENTERING_WORLD, QUEST_TURNED_IN, QUEST_REMOVED.
ns.weeklies = {
    { key = "abundance",       questID = 89507, label = "Abundant Offerings", short = "AbunO" },
    { key = "stormarion",      questID = 94581, label = "Stand Your Ground",  short = "SYG" },
    { key = "preyNightmare",   questID = 94446, label = "A Nightmarish Task", short = "NightT" },

    -- Lady Liadrin's choice pool. She offers ~4 of 7 per char per week;
    -- completing one locks the others on that char. All freq=3, all reward
    -- Spark of Radiance + Apex Cache.
    { key = "liadrin", label = "Lady Liadrin's Weekly", short = "LiadW", questIDs = {
          93769,  -- Midnight: Housing
          93889,  -- Midnight: Saltheril's Soiree
          93892,  -- Midnight: Stormarion Assault
          93909,  -- Midnight: Delves
          93911,  -- Midnight: Dungeons
          94457,  -- Midnight: Battlegrounds
          95842,  -- Midnight: Void Assaults
      } },

    -- Void Assault zone-rotation weekly. The active zone changes weekly
    -- (12.0.5 design note); each zone has its own questID. Harandar /
    -- Voidstorm variants likely exist; add when harvest reveals them.
    { key = "voidAssaultZone", label = "Void Assault (active zone)", short = "VoidA", questIDs = {
          94385,  -- Void Assaults: Eversong Woods
          94386,  -- Void Assaults: Zul'Aman
      } },

    { key = "haranir",         questID = 89268, label = "Lost Legends",       short = "LL" },
}

-- Last-resort POI name lookup. C_AreaPoiInfo.GetAreaPOIInfo returns nil
-- for several scheduler-only POI IDs (Abundance variants) regardless of
-- which mapID we pass and regardless of where the player is standing —
-- they don't appear in any zone's GetEventsForMap, so WarmZonePois can't
-- populate the cache for them either. Blizzard's own events panel knows
-- the names; we don't have access to whatever internal path it uses.
--
-- This hardcoded table is the fallback after live API and account-wide
-- name cache both fail. Brittle to patch updates — re-verify on new
-- content patches if the events panel starts showing different names.
ns.knownEventNames = {
    [8419] = "Stormarion Assault",
    [8423] = "Legends of the Haranir",
    [8525] = "Abundance: Skinning Den",       -- Zul'Aman
    [8527] = "Abundance: Herbalism Grotto",   -- Harandar
    [8528] = "Abundance: Enchanting Crypt",   -- Eversong Woods
    [8697] = "Void Assaults",
}

-- Per-POI override for the widget set carrying a StatusBar progress meter.
-- Used when the POI's own tooltipWidgetSet / iconWidgetSet fields don't
-- reference the progress widget — either because the POI is in a state
-- where iws is nil (Void Incursion mid-firing), or because the progress
-- bar lives in a separately-published widget set the POI doesn't link to.
--
-- Discover candidates via /mewidget <N> on the widget set displayed in the
-- on-map icon overlay (the "X%" you can see floating over the POI). The
-- right set is the one whose enumeration returns a type-2 (StatusBar)
-- widget with barMax > 0.
ns.eventProgressWidgetSet = {
    [8718] = 2042,  -- Void Incursion: build progress for next firing
}

-- Per-POI heuristic for detecting "main event firing RIGHT NOW." The
-- C_UIWidgetManager / C_AreaPoiInfo / C_EventScheduler APIs don't expose
-- a direct firing flag for these events, so where we have a reliable
-- *empirical* bar-behaviour pattern, we encode it here.
--
-- Why this lives here (vs. inline in Core): rules are content-tuned and
-- expected to drift on balance patches. Keeping them in Data.lua matches
-- the "edit this on new patches" convention already established for
-- knownEventNames and waveCadence. Auditable, easy to extend with new
-- POIs, easy to retune thresholds.
--
-- Schema:
--   [areaPoiID] = {
--       type      = "lowProgress",   -- see types below
--       threshold = number,           -- meaning depends on type
--       comment   = "string",         -- empirical basis + caveats
--   }
--
-- Types:
--   "lowProgress" — firing iff progPct exists and progPct < threshold.
--                   Used for events whose build bar resets at fire-trigger
--                   and where firing concludes by the time the bar passes
--                   the threshold on its rebuild. Will false-positive in
--                   the brief post-weekly-reset window before the bar
--                   first crosses the threshold; tolerated as low-impact.
--
-- Brittle by design. Re-verify on content patches by probing /mewidget
-- against the relevant widget set while observing the in-zone event state.
ns.eventFiringHeuristic = {
    [8718] = {  -- Void Incursion
        type = "lowProgress", threshold = 10,
        comment = "Bar resets at major-attack trigger; firing observed to "
               .. "conclude by ~10% rebuild. 2-sample empirical "
               .. "(2026-05-14): bar at 8.35% and ~10% both during "
               .. "confirmed-firing states. Brief false positives after "
               .. "weekly reset until bar crosses 10%.",
    },
}

-- Resolve a firing heuristic for an event entry. Returns true iff the
-- POI has a heuristic and its condition is satisfied right now.
function ns.IsEventFiring(areaPoiID, progPct)
    local rule = areaPoiID and ns.eventFiringHeuristic
                 and ns.eventFiringHeuristic[areaPoiID]
    if not rule then return false end
    if rule.type == "lowProgress" then
        return progPct ~= nil and progPct < rule.threshold
    end
    return false
end

-- Lady Liadrin pool member → human-friendly short label. Used by the
-- tooltip to annotate the Liadrin row with which choice the current char
-- picked this week (e.g. "Lady Liadrin's Weekly (Delves picked)").
ns.liadrinLabels = {
    [93769] = "Housing",
    [93889] = "Soiree",
    [93892] = "Stormarion",
    [93909] = "Delves",
    [93911] = "Dungeons",
    [94457] = "Battlegrounds",
    [95842] = "Void Assaults",
}

-- Candidate weeklies — harvested IDs not yet promoted to ns.weeklies. Stay
-- here when classification is still uncertain (sample size 1, scope
-- ambiguous, etc.). Entries are commented-out Lua so the structure is
-- self-documenting and trivial to uncomment if scope changes.
ns.candidateWeeklies = {
    -- 91700 "Darkness Unmade" — freq=2: kill 2 rares in Stormarion Citadel,
    -- drops Stormarion Core. Distinct from Stand Your Ground; may merit
    -- its own row or fold into a Stormarion umbrella.
    -- { key = "stormarionRares", questID = 91700, label = "Darkness Unmade" },

    -- 95468 "Hope in the Darkest Corners" — freq=2: complete WQs/Dungeons/
    -- Delves in Midnight zones; rewards Quel'Thalas Adventurer's Cache.
    -- Likely OOS umbrella (MR territory), pending final scope call.
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
