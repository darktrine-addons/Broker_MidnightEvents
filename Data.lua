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

    -- Lady Liadrin's "Unity against the Void" choice pool. She offers 4
    -- of the pool per char per week; completing one flags ALL members
    -- (lockout) and the weekly reset clears them all (verified 2026-06-03
    -- — NOT lifetime accumulation; see memory wow-isquestflaggedcompleted-
    -- lifetime). All freq=3, reward Spark of Radiance + Apex Cache. The
    -- `picks` map drives Core's DetectWeeklyPicks active-log scan + the
    -- "(<choice> picked)" annotation.
    --
    -- Pool enumerated to 12 via Wowhead + Warcraft Wiki (meta quest 93744
    -- "Unity Against the Void") 2026-06-03. 93766/93891/93913 were missing
    -- from the original 9. 93891 "Legends of the Haranir" is flagged
    -- obsolete on Wowhead — included (additive-safe; pool resets weekly so
    -- a stale flag can't false-positive permanently) but unverified live.
    -- No Raid/M+/Professions member surfaced; harvest if a future week
    -- offers a choice not in this map.
    { key = "liadrin", label = "Lady Liadrin's Weekly", short = "LiadW",
      levelMin = 90,
      questIDs = {
          93766,  -- Midnight: World Quests
          93769,  -- Midnight: Housing
          93889,  -- Midnight: Saltheril's Soiree
          93890,  -- Midnight: Abundance
          93891,  -- Midnight: Legends of the Haranir  (Wowhead: obsolete — verify)
          93892,  -- Midnight: Stormarion Assault
          93909,  -- Midnight: Delves
          93910,  -- Midnight: Prey
          93911,  -- Midnight: Dungeons
          93913,  -- Midnight: World Boss
          94457,  -- Midnight: Battlegrounds
          95842,  -- Midnight: Void Assaults
      },
      picks = {
          [93766] = "World Quests",
          [93769] = "Housing",
          [93889] = "Soiree",
          [93890] = "Abundance",
          [93891] = "Haranir Legends",
          [93892] = "Stormarion",
          [93909] = "Delves",
          [93910] = "Prey",
          [93911] = "Dungeons",
          [93913] = "World Boss",
          [94457] = "Battlegrounds",
          [95842] = "Void Assaults",
      },
    },

    -- Bonus Event Weekly — separate system from Liadrin's pool. One bonus
    -- event is active per week on a 7-event rotation; reward varies by
    -- event type (Cache of Quel'Thalas Treasures for PvE, Mark of Honor /
    -- Conquest for PvP). Giver: Archmage Aethas Sunreaver (NPC 256212) in
    -- Silvermoon. Each event is its own weekly quest with a distinct title.
    --
    -- Enumerated via Wowhead 2026-06-03 — 6 of 7 mapped. The 7th, Arena
    -- Skirmishes ("The Arena Calls"), appears to REUSE the cross-expansion
    -- TWW quest 83358 rather than mint a Midnight 935xx ID. NOT added: a
    -- TWW quest may be lifetime-flagged from old Arena play and would
    -- false-positive this row as done. Harvest the real Midnight ID via
    -- GetQuestID() on Aethas's dialog during an Arena bonus week.
    { key = "bonusEvent", label = "Bonus Event Weekly", short = "BonusW",
      levelMin = 90,
      questIDs = {
          93593,  -- A Call to Battle (4 BG wins)
          93595,  -- A Call to Delves (5 Midnight Delves)
          93598,  -- Emissary of War (4 Mythic Dungeons) — Aethas, freq=2
          93599,  -- The Very Best (Pet Battle)
          93605,  -- The World Awaits (World Quests)
          93614,  -- A Fel Path Through Time (5 Timewalking dungeons)
          -- 83358 Arena ("The Arena Calls") held — cross-expansion TWW ID,
          -- false-positive risk; harvest the Midnight ID in an Arena week.
      },
      picks = {
          [93593] = "Battle",
          [93595] = "Delves",
          [93598] = "Dungeons",
          [93599] = "Pet Battles",
          [93605] = "World Quests",
          [93614] = "Timewalking",
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

    -- Saltheril's Soiree — weekly pick from Lord Saltheril. The pinnacle
    -- 'Favor of the Court' (89289) gives 4 subfaction choices that gate
    -- one 'Fortify the Runestones' (90573–90576) variant for the week.
    -- Pool semantics:
    --   89289 is the pick quest; flags complete on subfaction choice
    --   90573/4/5/6 — the gated pinnacle weeklies, one per subfaction
    -- 'Any pool member flagged' = done covers both '89289 chosen but
    -- Fortify not finished' and 'Fortify completed' states.
    -- Reward for the pinnacle: Surplus Bag of Party Favors (150 Brimming
    -- Arcana + 300 subfaction rep + 2,000 Silvermoon Court rep).
    --
    -- Picks map keyed on the Fortify questIDs (not 89289) — DetectWeeklyPicks
    -- writes the picked subfaction label once the Fortify quest enters the
    -- log. Before the Fortify accept the row shows un-annotated.
    --
    -- The pool extends with ~30 Favor-unlocked weeklies surfaced via vendor
    -- token spend (Apprentice Diell / Armorer Goldcrest / Ranger Allorn /
    -- Neriv). 3 known (91984 Sungrub Silk, 91979 Chop It Down, 91978
    -- Taxing the Tideborne). BeaconHarvest's discovery logger fills the
    -- rest as the player engages — pool not in the row schema yet because
    -- we don't have enough IDs to render a stable X/N count.
    { key = "soiree", label = "Saltheril's Soiree", short = "Soir",
      levelMin = 90,
      questIDs = {
          89289,  -- Favor of the Court (weekly pick)
          90573,  -- Fortify the Runestones: Magisters
          90574,  -- Fortify the Runestones: Blood Knights
          90575,  -- Fortify the Runestones: Farstriders
          90576,  -- Fortify the Runestones: Shades of the Row
      },
      picks = {
          [90573] = "Magisters",
          [90574] = "Blood Knights",
          [90575] = "Farstriders",
          [90576] = "Shades of the Row",
      },
    },

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
      -- In progress = at least one hunt done but not yet at the unlock cap.
      customInProgress = function()
          if not (ns.preyQuests and C_QuestLog
                  and C_QuestLog.IsQuestFlaggedCompleted) then return false end
          local pH = ns.char and ns.char.preyHunts
          local unlockMax = (pH and pH.max) or 12
          local total = 0
          for qid in pairs(ns.preyQuests) do
              if C_QuestLog.IsQuestFlaggedCompleted(qid) then total = total + 1 end
          end
          if total > unlockMax then total = unlockMax end
          return total > 0 and total < unlockMax
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

    -- Beacon of Hope weekly. SOLVED 2026-06-03: the per-character weekly is
    -- "loot the Nullaeus Cache" (the nemesis cache you get after using a
    -- Beacon of Hope to summon Nullaeus in a delve). There is NO quest flag
    -- or scenario criterion for it (verified across quest/scenario/loot
    -- harvests) — the only signal is looting the cache container, identified
    -- by its GameObject ID 618495. A LOOT_OPENED hook in Core sets
    -- char.delveBounty.cacheLooted (cleared at the weekly reset); customDone
    -- reads it. (91190 was a red herring — per-delve reward-chest plumbing.
    -- The Trovehunter's Bounty → Hidden Trove chain has no weekly lockout, so
    -- it is intentionally NOT tracked.) See memory:
    -- brokermidnightevents-beacon-of-hope-untrackable.
    { key = "delversBounty", label = "Beacon of Hope", short = "Beacon",
      hint = "Nullaeus Cache",
      customDone = function()
          return (ns.char and ns.char.delveBounty and ns.char.delveBounty.cacheLooted)
                 and true or false
      end },

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

-- Myth-crest delve weekly. There is NO quest flag or currency weekly-cap
-- field for "loot 20 Myth Dawncrests from bountiful delves per week"
-- (confirmed 2026-05-31: a 5-crest delve loot ticked no quest objective,
-- and the currency API reports maxWeekly=0 / earnedThisWeek=0 for the
-- Dawncrest tiers). So we count it ourselves: sum CURRENCY_DISPLAY_UPDATE
-- gains for the Myth Dawncrest currency while inside a delve (scenario),
-- capped at the weekly max. Raid / dungeon crests are excluded by the
-- scenario gate.
--
-- Both values are patch-fragile (the currency ID rotates per season; the
-- cap can change on patch). Re-harvest via /mecrest if the row stops
-- updating or the cap looks wrong. Currency ID verified from a live
-- delve loot 2026-05-31 (Myth Dawncrest, +5 per coffer).
ns.mythCrestCurrencyID = 3347
ns.mythCrestWeeklyCap  = 20

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
--   "weekly"    — the bar value resets each weekly reset. Settings.lua's
--                 reset hook sets cached value to 0 so the tooltip reflects
--                 the post-reset state immediately. (No current users —
--                 Voidcores turned out to be seasonCap.)
--   "seasonCap" — the VALUE is season-cumulative and persists across weekly
--                 resets; only the CAP rises (+2/week for Voidcores in S1,
--                 may change on patch). We can't know the new cap until a
--                 Decimus visit re-syncs the widget, so the reset hook keeps
--                 the value and marks `maxStale`; the render shows `NN/??`
--                 plus a faint "visit Decimus" prompt until the next sync
--                 clears it. Verified 2026-06-03: Decimus read 12/14 the
--                 reset after 12/12, value carried over.
--   "lifetime"  — the bar ticks up over multiple weeks (Nilhammer: +1/wk
--                 up to 4/4). Once `completedAt` is reached, the row
--                 renders dim with a ✓ permanently.
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
        hint        = "bonus rolls, +2 cap/wk",
        scope       = "seasonCap",
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
