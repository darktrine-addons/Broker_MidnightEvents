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
    { key = "abundance",     questID = 89507, label = "Abundant Offerings",  short = "AbunO" },
    { key = "stormarion",    questID = 94581, label = "Stand Your Ground",   short = "SYG",
      hint = "Stormarion Assault" },
    { key = "preyNightmare", questID = 94446, label = "A Nightmarish Task",  short = "NightT",
      hint = "Prey Hunts", objectiveRequired = 3, levelMin = 90 },

    -- Lady Liadrin's choice pool. She offers ~4 of 8 per char per week;
    -- completing one locks the others on that char. All freq=3, all reward
    -- Spark of Radiance + Apex Cache. The `picks` map enables Core's
    -- generic DetectWeeklyPicks scan + the "(<choice> picked, N/M)"
    -- annotation in This Week.
    { key = "liadrin", label = "Lady Liadrin's Weekly", short = "LiadW",
      levelMin = 90,
      questIDs = {
          93769,  -- Midnight: Housing
          93889,  -- Midnight: Saltheril's Soiree
          93890,  -- Midnight: Abundance
          93892,  -- Midnight: Stormarion Assault
          93909,  -- Midnight: Delves
          93910,  -- Midnight: Prey
          93911,  -- Midnight: Dungeons
          94457,  -- Midnight: Battlegrounds
          95842,  -- Midnight: Void Assaults
      },
      picks = {
          [93769] = "Housing",
          [93889] = "Soiree",
          [93890] = "Abundance",
          [93892] = "Stormarion",
          [93909] = "Delves",
          [93910] = "Prey",
          [93911] = "Dungeons",
          [94457] = "Battlegrounds",
          [95842] = "Void Assaults",
      },
    },

    -- Bonus Event Weekly — separate system from Liadrin's pool. One bonus
    -- event is active per week on a 7-event rotation; reward varies by
    -- event type (Cache of Quel'Thalas Treasures for some, Mark of
    -- Honor/Conquest for PvP, etc.). Giver: Archmage Aethas Sunreaver in
    -- Silvermoon. The "A Call to X" naming covers only 2 of the 7 events
    -- (Delves, Battle); the others use different names (The Arena Calls,
    -- The World Awaits, The Very Best, Emissary of War, Timewalking).
    -- Expand questIDs/picks as those quest IDs surface via harvest.
    { key = "bonusEvent", label = "Bonus Event Weekly", short = "BonusW",
      levelMin = 90,
      questIDs = {
          93595,  -- A Call to Delves (5 Midnight Delves)
          93593,  -- A Call to Battle (4 BG wins)
          93598,  -- Emissary of War (4 Mythic Dungeons) — Aethas, freq=2
      },
      picks = {
          [93595] = "Delves",
          [93593] = "Battle",
          [93598] = "Dungeons",
      },
    },

    -- Featured Dungeon weekly. Halduron Brightwing (NPC 256210, Silvermoon
    -- tent) offers one quest per week from a pool of eight, each named
    -- after a Midnight dungeon and asking the player to clear that dungeon
    -- at any difficulty (Follower included). Reward: gold + a player-
    -- choice 1,000 reputation token (Hara'ti / Singularity / Silvermoon
    -- Court / Amani). Independent of the M+ Awakened/affix rotation.
    -- Quest IDs verified via Wowhead 2026-05-26; pool is contiguous
    -- 93751–93758. `picksFormat = "zoneOnly"` renders the row as
    -- "Featured Dungeon (Voidscar Arena)" — same shape as Void Assault.
    { key = "featuredDungeon", label = "Featured Dungeon", short = "FeatD",
      levelMin = 90,
      questIDs = {
          93751,  -- Windrunner Spire
          93752,  -- Murder Row
          93753,  -- Magisters' Terrace
          93754,  -- Maisara Caverns
          93755,  -- Den of Nalorakk
          93756,  -- The Blinding Vale
          93757,  -- Voidscar Arena
          93758,  -- Nexus-Point Xenas
      },
      picks = {
          [93751] = "Windrunner Spire",
          [93752] = "Murder Row",
          [93753] = "Magisters' Terrace",
          [93754] = "Maisara Caverns",
          [93755] = "Den of Nalorakk",
          [93756] = "The Blinding Vale",
          [93757] = "Voidscar Arena",
          [93758] = "Nexus-Point Xenas",
      },
      picksFormat = "zoneOnly",
    },

    -- Hope in the Darkest Corners — Halduron Brightwing's sub-90 weekly
    -- (offered in place of Featured Dungeon while levelling). Asks for
    -- 10 Midnight activities (world quests / dungeons / delves), any mix.
    -- Confirmed 2026-05-26 on Alaelyne (level 80). levelMax=89 hides the
    -- row once the character hits max and Halduron switches to the
    -- Featured Dungeon variant.
    { key = "hopeDarkest", questID = 95468, label = "Hope in the Darkest Corners", short = "Hope",
      hint = "10 Midnight activities", levelMax = 89 },

    -- Void Assault zone-rotation weekly. The active zone changes weekly
    -- (12.0.5 design note); each zone has its own questID. Harandar /
    -- Voidstorm variants likely exist; add when harvest reveals them.
    -- `picks` + `picksFormat = "zoneOnly"` makes the render append the
    -- active zone name directly — "Void Assault (Zul'Aman)" — instead
    -- of the generic "(active zone)" placeholder we used before.
    { key = "voidAssaultZone", label = "Void Assault", short = "VoidA",
      questIDs = {
          94385,  -- Void Assaults: Eversong Woods
          94386,  -- Void Assaults: Zul'Aman
      },
      picks = {
          [94385] = "Eversong Woods",
          [94386] = "Zul'Aman",
      },
      picksFormat = "zoneOnly",
    },

    { key = "haranir",       questID = 89268, label = "Lost Legends",        short = "LL",
      hint = "Legends of the Haranir" },

    -- Prey Hunts — comprehensive weekly row backed by ns.preyQuests
    -- (questID -> tier). Per-tier weekly cap is 4; total weekly cap
    -- scales with unlocked tier (Normal=4, Hard=8, Nightmare=12).
    -- customDone: row marked ✓ once flagged completions reach the
    -- unlock-tier max (matches the in-room board's bar going to 0).
    -- customLabel: appends "(Normal X/4 · Hard Y/4 · Nightmare Z/4)"
    -- gated by unlocked tier — only renders tiers the char can do.
    { key = "preyHunts", label = "Prey Hunts", short = "PreyH",
      customDone = function()
          if not (ns.preyQuests and C_QuestLog
                  and C_QuestLog.IsQuestFlaggedCompleted) then return false end
          local pH = ns.char and ns.char.preyHunts
          local unlockMax = (pH and pH.max) or 12
          local total = 0
          for qid in pairs(ns.preyQuests) do
              if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                  total = total + 1
              end
          end
          if total > unlockMax then total = unlockMax end
          return total >= unlockMax
      end,
      customLabel = function(rowLabel)
          if not (ns.preyQuests and C_QuestLog
                  and C_QuestLog.IsQuestFlaggedCompleted) then return rowLabel end
          local pH = ns.char and ns.char.preyHunts
          local unlockMax = (pH and pH.max) or 12
          local counts = { normal = 0, hard = 0, nightmare = 0 }
          for qid, tier in pairs(ns.preyQuests) do
              if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                  counts[tier] = (counts[tier] or 0) + 1
              end
          end
          for t in pairs(counts) do
              if counts[t] > 4 then counts[t] = 4 end
          end
          local DIM, PROG, CLOSE = "|cff909090", "|cffd9c97f", "|r"
          local function part(label, n)
              return DIM .. label .. " " .. CLOSE .. PROG .. n .. "/4" .. CLOSE
          end
          local parts = { part("Normal", counts.normal) }
          if unlockMax >= 8  then parts[#parts + 1] = part("Hard",      counts.hard)      end
          if unlockMax >= 12 then parts[#parts + 1] = part("Nightmare", counts.nightmare) end
          return rowLabel .. " "
                 .. DIM .. "(" .. CLOSE
                 .. table.concat(parts, DIM .. " · " .. CLOSE)
                 .. DIM .. ")" .. CLOSE
      end,
    },

    -- A Gnawing Void of Curiosity — Naleidea Rivergleam's auto-credited
    -- weekly that fires on the first delve completion of the week. Reward
    -- is Voidlight Marl currency, so a T4+ tier gate is likely (Marl
    -- doesn't drop from low tiers). Frequency=2 in Blizzard's quest data
    -- confirms weekly cadence even though Wowhead misclassifies it as
    -- one-time. Re-verify reset behaviour on first weekly cycle; rip if
    -- 93784 doesn't actually clear.
    -- Confirmed warband-shared 2026-05-26: Artherio's completion auto-
    -- credited Shatanaris (93784=true on Sha before she ran any delve
    -- this week). The reward (Voidlight Marl) still implies a T4+ gate
    -- at the credit boundary, but the credit propagates to alts.
    { key = "gnawingVoid",   questID = 93784, label = "Gnawing Curiosity", short = "GnawC",
      hint = "warband first delve T4+" },

    -- Delver's Bounty weekly. The Beacon of Hope → Nullaeus → Delver's
    -- Bounty → Hidden Trove chain. Single trackable flag 91190 is an
    -- internal Blizzard system quest (Wowhead: "doesn't exist") that
    -- flips on Hidden Trove turn-in and clears on weekly reset.
    -- Confirmed 2026-05-26 reset cycle. See memory:
    --   brokermidnightevents-beacon-of-hope-untrackable
    { key = "delversBounty", questID = 91190, label = "Delver's Bounty", short = "DBnty",
      hint = "Beacon of Hope" },

    -- Arcantina — Khadgar's patron-tavern hub (unlocked via Arator's
    -- Journey campaign chapter + Personal Key toy). Weekly visit slot
    -- (quest 93767) confirmed resetting; the nine patron quests
    -- (92319–92327) are a LIFETIME collection (Old Soldiers achievement
    -- structure) and their flags persist. Annotated with running
    -- collection progress via `progressIDs`. See memory:
    --   brokermidnightevents-arcantina
    -- Tooltip output suppressed pending investigation: 93767 flips true
    -- from non-Arcantina activity (e.g. on Artherio 2026-05-26 it went
    -- true after world boss / Liadrin's weekly, before any Arcantina
    -- interaction). Per-char (Shatanaris stayed false post-reset), so
    -- not account-wide, but the credit condition is broader than the
    -- quest's name suggests. Data path stays warm — `hideInTooltip`
    -- only skips the rendering step in This Week, RefreshWeeklies
    -- continues to populate ns.char.weeklies.arcantina so future
    -- probes can correlate triggers.
    { key = "arcantina", questID = 93767, label = "Arcantina", short = "Arc",
      hideInTooltip = true,
      progressIDs = {
          92319,  -- A Favor to Axe
          92320,  -- Still Behind Enemy Portals
          92321,  -- A Frostbitten Tally
          92322,  -- Timear Foresees a Proof of Demise!
          92323,  -- Where the Fire Once Burned
          92324,  -- Uncrowned's Cold Case
          92325,  -- Hellscream's Heritage
          92326,  -- The Fragrance of the Dunes
          92327,  -- A Generational Moment
      },
      progressLabel = "patrons",
    },
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

-- Per-character progression tracked via Decimus's Voidforge widgets in
-- Voidstorm. Each entry maps to a Blizzard widget set carrying a single
-- StatusBar (value/max). We poll these via the same ticker as event
-- progress (Core.lua's RefreshProgressCache) and cache the result in
-- ns.char.voidforge[key] per character. Cache only updates when the
-- player is near enough Decimus for the widgets to be live; otherwise
-- the last-known value persists.
--
-- Scope semantics:
--   "weekly"   — the bar value resets each weekly reset (Voidcores).
--                Settings.lua weekly-reset hook sets cached value to 0
--                so the tooltip reflects the post-reset state immediately.
--   "lifetime" — the bar ticks up over multiple weeks (Nilhammer: +1/wk
--                up to 4/4). Once `completedAt` is reached, the row
--                renders dim with a ✓ permanently.
-- Quest that signals the Voidforge build chain is complete. 95268 "New
-- Tools, New Heights" is the post-build bridge that opens the Nilhammer
-- empowerment line — completion guarantees Decimus is interactable. The
-- underlying Voidforge build is warband-wide, so on alts that inherit
-- the unlock without personally completing this quest, Core falls back
-- to "have we ever observed widget data for this char" as a secondary
-- unlock signal.
ns.voidforgeUnlockQuest = 95268

-- Prey Hunts board widget set. Same pattern as Voidforge — bars only
-- update when the player is near the in-room display (Eversong Prey
-- chamber); cache stays warm in ns.char.preyHunts until the next
-- observation. Tier semantics (Normal / Hard / Nightmare) inferred
-- from the user's report of three difficulty bands and Blizzard's
-- ordering — sorted by widgetID ascending. Render uses raw counts
-- so any mismatch between this guess and the actual semantics
-- surfaces immediately during the week.
ns.preyHuntsWidgetSet = 1843

-- Prey hunt quest pool — questID → tier. Used by Core to count flagged-
-- completed prey hunts per tier each week ("Normal 3/4 · Hard 2/4 ·
-- Nightmare 0/4"). Cap per tier per week is 4.
--
-- Normal block is fully enumerable: contiguous 91095–91124, one per
-- target in storyline order (30 named targets). Verified 2026-05-26
-- via Wowhead crawl.
--
-- Hard / Nightmare IDs are scattered across ~91210–91267 with gaps
-- and irregular pairing. The confirmed entries below are the ones we
-- could pin from in-game harvest plus targeted Wowhead lookups.
-- Coverage grows automatically at addon load by parsing every
-- "Prey: <Name> (Tier)" entry in the harvest quest catalogue
-- (Broker_MidnightEventsQuestCatalogue), so the table self-heals as
-- the warband encounters more variants over time.
ns.preyQuests = {}
for id = 91095, 91124 do ns.preyQuests[id] = "normal" end
-- Confirmed Hard / Nightmare (partial coverage; catalogue scan fills in
-- the rest at runtime).
ns.preyQuests[91210] = "hard"       -- Magister Sunbreaker
ns.preyQuests[91211] = "nightmare"  -- Magister Sunbreaker
ns.preyQuests[91212] = "hard"       -- Magistrix Emberlash
ns.preyQuests[91213] = "nightmare"  -- Magistrix Emberlash
ns.preyQuests[91220] = "hard"       -- Deliah Gloomsong
ns.preyQuests[91221] = "nightmare"  -- Deliah Gloomsong
ns.preyQuests[91263] = "hard"       -- Lost Theldrin (approximate; pair unverified)
ns.preyQuests[91264] = "nightmare"  -- Lost Theldrin
ns.preyQuests[91265] = "hard"       -- Thornspeaker Edgath
ns.preyQuests[91266] = "nightmare"  -- Thornspeaker Edgath
ns.preyQuests[91267] = "nightmare"  -- Thorn-Witch Liset

ns.charProgress = {
    {
        key         = "voidcores",
        widgetSetID = 1960,
        label       = "Voidcores transmuted",
        hint        = "weekly bonus rolls",
        scope       = "weekly",
    },
    {
        key         = "nilhammer",
        widgetSetID = 1958,
        label       = "Nilhammer empowered",
        hint        = "Voidforge upgrade",
        scope       = "lifetime",
        completedAt = 4,
    },
}

-- Delve-name → "Stories" sub-achievement ID. Each entry is a per-delve
-- 3-criteria achievement (one criterion per story variant). The Loremaster
-- meta is 61741 (rolls up all 10 sub-achievements; not used here — we want
-- per-story completion granularity).
--
-- Lookup chain at render time:
--   1. Read each bountiful delve POI's tooltipWidgetSet for a TextWithState
--      widget whose text matches "Story Variant: <name>"
--   2. Look up the delve by name in this table → achievement ID
--   3. Iterate the achievement's criteria; the criterion whose name matches
--      the story-variant text is this delve's active story
--   4. The criterion's `completed` boolean is per-character status
--
-- Adding a new Midnight delve to the rotation: append { name = id } here.
-- Patch updates to story names won't break anything because we match by
-- live widget text, not hardcoded story strings.
ns.delveStoryAchievement = {
    ["Atal'Aman"]           = 61729,
    ["Collegiate Calamity"] = 61726,
    ["Parhelion Plaza"]     = 61725,
    ["Shadowguard Point"]   = 61733,
    ["Sunkiller Sanctum"]   = 61732,
    ["The Darkway"]         = 61728,
    ["The Grudge Pit"]      = 61724,
    ["The Gulf of Memory"]  = 61731,
    ["The Shadow Enclave"]  = 61727,
    ["Twilight Crypts"]     = 61730,
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
    [8718] = 2042,  -- Void Incursion (Eversong variant)
}

-- Same idea, keyed by event name. Catches every zone variant of the same
-- event (each zone gets its own POI ID — 8717 Zul'Aman, 8718 Eversong,
-- future zones — but the underlying widget set is the same) without
-- requiring a per-POI entry above. Looked up as a fallback after the
-- per-POI table misses.
ns.eventProgressWidgetSetByName = {
    ["Void Incursion"] = 2042,
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
    [8718] = {  -- Void Incursion (Eversong variant)
        type = "lowProgress", threshold = 10,
        comment = "Bar resets at major-attack trigger; firing observed to "
               .. "conclude by ~10% rebuild. 2-sample empirical "
               .. "(2026-05-14): bar at 8.35% and ~10% both during "
               .. "confirmed-firing states. Brief false positives after "
               .. "weekly reset until bar crosses 10%. Does NOT catch "
               .. "server-triggered firings that occur mid-build without "
               .. "the 100%→reset cycle (observed at 17.2% in Zul'Aman "
               .. "2026-05-23) — the bar value alone is ambiguous in that "
               .. "case; would need a separate signal to detect reliably.",
    },
}

-- Same idea, keyed by event name. Catches every zone variant without
-- requiring a per-POI entry. Looked up as a fallback after the per-POI
-- table misses, so Eversong's 8718 keeps its existing entry above and
-- Zul'Aman's 8717 (and future zone variants) get the same rule via name.
ns.eventFiringHeuristicByName = {
    ["Void Incursion"] = {
        type = "lowProgress", threshold = 10,
        comment = "See ns.eventFiringHeuristic[8718] for empirical basis.",
    },
}

-- Resolve a firing heuristic for an event. Returns true iff the event has
-- a heuristic (matched by POI ID first, then by name) and its condition
-- is satisfied right now.
function ns.IsEventFiring(ev, progPct)
    -- Backward compat: callers that pass a raw POI ID still work.
    local areaPoiID, name
    if type(ev) == "table" then
        areaPoiID, name = ev.areaPoiID, ev.name
    else
        areaPoiID = ev
    end
    local rule
    if areaPoiID and ns.eventFiringHeuristic then
        rule = ns.eventFiringHeuristic[areaPoiID]
    end
    if not rule and name and ns.eventFiringHeuristicByName then
        rule = ns.eventFiringHeuristicByName[name]
    end
    if not rule then return false end
    if rule.type == "lowProgress" then
        return progPct ~= nil and progPct < rule.threshold
    end
    return false
end

-- (Previously: ns.liadrinLabels — moved inline into the Liadrin entry
-- in ns.weeklies above. Each pool entry now carries its own `picks` map
-- so the same render path serves both Liadrin and the Bonus Event row.)

-- Candidate weeklies awaiting promotion (and out-of-scope IDs ceded to
-- Midnight Routine) used to live here as commented-out tables. Both lists
-- moved to design/harvest-notes.md to keep the runtime-loaded file lean.
-- Promote a candidate to ns.weeklies above when classification firms up.

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
