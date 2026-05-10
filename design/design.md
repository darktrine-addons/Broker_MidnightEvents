# Broker_MidnightEvents — Design Document

This document captures the design and implementation plan for `Broker_MidnightEvents`. Authoritative for v1; revise in place when scope changes.

## Goal

A single LDB broker button focused on **live world event timers and the weeklies tied to them**. The **broker text** shows the most urgent upcoming timed event ("Stormarion in 23m" / "Abundance now!"). The **tooltip** has three collapsible top-level sections: live event countdowns, this week's event-tied checklist, and an alt roll-up. For altoholics, **Shift-Right-Click** detaches a scrollable, sortable detail panel showing all tracked alts in a tabular grid. No always-on standalone window — the addon lives in the broker bar.

## Scope and Differentiation

**Midnight Routine** (~1.6M downloads, very actively maintained) is the dominant comprehensive weekly tracker. We do not compete with it. Our differentiation is form factor (LDB tooltip in a broker bar) and scope (events first, with only the weeklies that are directly tied to events we already track via Tier 1 timers). Everything else — Voidforge, Patron Orders, M+ best, T11 Delves, Housing, Ritual Sites, full Vault breakdown — is intentionally out of scope and explicitly handed to Midnight Routine via the README.

**In scope:**
- Tier 1 — live POI event timers (Abundance, Stormarion Assault, Slayer's Rise, Bountiful Delve daily, Void Assault active zone)
- Tier 2 — weekly quests **directly tied to those events**:
  - Prey Hunts (event-flavoured, 12 contracts across 3 tiers)
  - World Bosses (per-week loot lockout)
  - Saltheril's Soiree ("Fortify the Runestones")
  - Stormarion Assault weekly ("Stand Your Ground")
  - Legends of the Haranir (weekly scenario)
  - Midnight: Void Assaults (Lady Liadrin umbrella)
  - Bountiful Delve weekly (paired with the daily timer)
  - A Call to Battle (PvP weekly — small footprint, BG win counter)
- Tier 3 — only the currencies that come from Tier 1 events (Shards of Dundun, Field Accolades, Latent Arcana)

**Out of scope (cede to Midnight Routine):**
- Voidforge questline
- Silvermoon Weekly Dungeon
- T11 Delve weekly
- Mythic+ weekly best
- Great Vault detail rows (M+/Raid/World breakdown)
- Patron Orders / Profession Knowledge
- Vaeli Housing Weekly
- Ritual Sites
- Decor Duels

## Non-Goals

- Standalone tracker window — Midnight Routine occupies that niche.
- Replacing WeakAuras for arbitrary in-combat state tracking.
- Holiday/seasonal events (well-served elsewhere).
- Cooperative read of Midnight Routine SavedVariables — fragile, no versioned contract; own tracking is the foundation.
- Comprehensive activity coverage. We deliberately stop at events and event-tied weeklies.

## Event Catalogue → Implementation Tiers

### Tier 1 — Live POI Timers (clock-driven, `C_AreaPoiInfo`)

These events have a visible world-map marker with a server-managed countdown. No hardcoded schedule table needed — POIs are discovered at runtime.

| Event | Zone | Cadence | Completion |
|---|---|---|---|
| **Abundance** | Rotating (4 zones) | Every 8 h, fixed | Per-char (8 Shards/week cap) |
| **Stormarion Assault** | Voidstorm | Every 30 min, fixed | Per-char (weekly quest, count TBD) |
| **Slayer's Rise PvP Events** | Voidstorm | Every 30 min, rotating pool | Stateless |
| **Bountiful Delve (daily marker)** | All zones | Daily reset | Per-char |
| **Void Assault — active zone** (12.0.5) | Eversong or Zul'Aman | Weekly rotation (no countdown — week-long indicator) | Stateless zone marker |

**API approach — fully event-driven:**

```lua
-- Register for POI changes and login refreshes
f:RegisterEvent("AREA_POIS_UPDATED")          -- fires when server pushes POI state
f:RegisterEvent("PLAYER_ENTERING_WORLD")      -- force refresh on login/zone

local ALL_ZONE_IDS = { 2601, 2602, 2603, 2604 }  -- Eversong, Zul'Aman, Harandar, Voidstorm
--    (uiMapIDs resolved once from C_Map.GetMapInfo at startup; values placeholder)

local function RefreshPOITimers()
    wipe(activeEvents)
    for _, mapID in ipairs(ALL_ZONE_IDS) do
        local pois = C_AreaPoiInfo.GetEventsForMap(mapID) or {}
        for _, poiID in ipairs(pois) do
            local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
            if info and info.isCurrentEvent then
                local isTimed = C_AreaPoiInfo.IsAreaPOITimed(poiID)
                local secs    = isTimed and C_AreaPoiInfo.GetAreaPOISecondsLeft(poiID) or nil
                -- store: name = info.name, icon = info.atlasName, secs, mapID, poiID
            end
        end
    end
    UpdateBrokerText()
end
```

**No hardcoded POI IDs.** Names come from `info.name` (localized). Icons from `info.atlasName` or `info.textureIndex`. This survives patches cleanly.

**Schedule fallback** — for fixed-cadence events like Stormarion Assault and Slayer's Rise, when `secs` returns nil (event not currently active), derive the next firing time from the 30-minute clock: `math.ceil(time() / 1800) * 1800 - time()`. Flag these as "schedule-predictable" events.

### Tier 2 — Event-Tied Weekly Checklist (quest-completion-driven)

Binary done/not-done checks with no live countdown. Refresh on login and on `QUEST_TURNED_IN`. Every row here is justified by a direct connection to a Tier 1 event we already display.

#### Group: World

| Activity | Display | API | Notes |
|---|---|---|---|
| **Prey Hunts** | `N 4/4 · H 4/4 · NM 3/3` (12 contracts total: 4 zones × 3 tiers) | `IsQuestFlaggedCompleted` × 12 | NM tier locks until Preyseeker Rank 4. When locked, render NM tier as `NM —` greyed. Weekly *quest* asks for 3 Nightmare hunts (per icy-veins May 2026); raw contract cap is 4 per tier. |
| **World Bosses** | `Lu'ashal ✓ · Cragpine ✗ · Thorm'belan ✗ · Predaxas ✓` | `GetSavedWorldBossInfo(index)` iterate, check `locked` | Native API; truth at runtime regardless of rotation model. |
| **Saltheril's Soiree** ("Fortify the Runestones") | binary `✓ / ✗` | `IsQuestFlaggedCompleted` | Eversong runestone weekly. Quest ID: TBD. |
| **Stormarion Assault weekly** ("Stand Your Ground") | `0/2` or `0/1` (TBD) | `IsQuestFlaggedCompleted` | Voidstorm. Required-runs-per-week TBD. |
| **Legends of the Haranir** (warband) | binary | `IsQuestFlaggedCompleted` | Solo scenario. |
| **Midnight: Void Assaults** (Lady Liadrin weekly) | binary or objective progress | `IsQuestFlaggedCompleted` *or* `C_QuestLog.GetQuestObjectives` | Quest giver: Lady Liadrin. Single weekly umbrella; Strikes/Incursions presumably contribute to its objectives — confirm objective format at implementation. Quest ID: TBD. |
| **Bountiful Delve weekly** (1st of the week) | binary | `IsQuestFlaggedCompleted` | Paired with the Tier 1 daily Bountiful marker. |

#### Group: PvP

| Activity | Display | API | Notes |
|---|---|---|---|
| **A Call to Battle** | `0/4` BG wins | `C_QuestLog.GetQuestObjectives` (or `IsQuestFlaggedCompleted` for binary) | Quest giver: Archmage Aethas Sunreaver. Objective: Win 4 Battleground matches. Rewards: 5 Mark of Honor + 175 Conquest. Quest ID: TBD. |

**Out of scope (cede to Midnight Routine):** Voidforge questline, Silvermoon Weekly Dungeon, T11 Delve weekly, M+ weekly best, Vaeli Housing Weekly, Ritual Sites, Patron Orders / Profession Knowledge, Decor Duels, full Great Vault breakdown.

**Event-driven pattern (applies to all rows above):**

```lua
f:RegisterEvent("PLAYER_ENTERING_WORLD")   -- bulk init via GetAllCompletedQuestIDs()
f:RegisterEvent("QUEST_TURNED_IN")         -- immediate single-quest update
f:RegisterEvent("QUEST_LOG_UPDATE")        -- server-push catch-all (debounced 0.5 s)
```

`C_QuestLog.GetAllCompletedQuestIDs()` at login seeds the local completion table cheaply. `QUEST_TURNED_IN` keeps it hot without a full re-scan.

**Weekly reset detection** — compare `GetQuestResetTime()` (daily) against a stored `lastResetEpoch`. When the stored epoch is older than the most recent Tuesday 08:00 UTC, wipe the weekly completion cache.

### Tier 3 — Event-Tied Currencies (display-only)

Only currencies that come from Tier 1 events:

| Currency | Source event | Notes |
|---|---|---|
| **Shards of Dundun** | Abundance | Cap 8/week |
| **Field Accolades** | Void Assaults (Strikes + Incursions) | Cap TBD; tooltip cross-check for the Liadrin weekly |
| **Latent Arcana** | Saltheril's Soiree daily/runestone activities | Daily trickle that funds the weekly Soiree |

```lua
C_CurrencyInfo.GetCurrencyInfo(currencyID)
-- fields: quantityEarnedThisWeek, maxQuantityPerWeek, quantity
```

Currency IDs to be resolved at implementation. Knowledge points, crests, and Valorstone are **not** tracked (cede to Midnight Routine).

## Data Model (SavedVariables)

```lua
Broker_MidnightEventsDB = {
    -- top-level section toggles
    enabledSections  = { timers = true, weekly = true, alts = true },
    -- weekly sub-group toggles
    enabledGroups    = { world = true, pvp = true, currencies = true },
    -- per-row toggles (keys match activity slugs)
    enabledRows      = { prey = true, bosses = true, soiree = true,
                         stormarion = true, haranir = true,
                         voidAssaults = true,         -- Lady Liadrin weekly
                         bountifulDelve = true,
                         callToBattle = true },
    -- per-event toggles (Tier 1 timers)
    enabledEvents    = { abundance = true, stormarionAssault = true,
                         slayersRise = true, bountifulDelveDaily = true,
                         voidAssaultZone = true },
    -- collapse state per section + sub-group
    sectionState     = { timers = "expanded", weekly = "expanded",
                         alts = "collapsed",
                         ["weekly.world"] = "expanded",
                         ["weekly.pvp"] = "collapsed",
                         ["weekly.currencies"] = "collapsed" },
    -- per-character progress snapshot (keyed by "realm/charname")
    chars = {
        ["Realm/CharName"] = {
            weeklyReset     = 0,          -- epoch of the reset this data covers
            lastLogin       = 0,          -- for stale/archive detection
            questsDone      = {},         -- set of questIDs completed this week
            preyProgress    = { N = 0, H = 0, NM = 0 },  -- Prey hunt counts per tier
            worldBossesDone = {},         -- set of worldBossIDs with active lockout
            currencies      = {},         -- weekly caps snapshot (event-tied only)
        },
    },
    -- characters the user has explicitly hidden from alt panel
    hiddenChars = {},                     -- set of "Realm/CharName" keys
    -- alts detail panel geometry/preferences
    altsPanel = {
        width = 600, height = 400, x = 0, y = 0,
        sort = "lastLogin", filter = "all", showArchived = false,
        staleThresholdDays = 30,
    },
    -- broker bar / display preferences
    display = {
        brokerStyle    = "name+countdown",  -- "countdown" | "name+countdown" | "urgent"
        tooltipRefresh = 5,                  -- seconds while tooltip open
    },
    -- minimap icon position
    minimapIcon = { hide = false },
}
```

Own tracking is the foundation. Alt data accumulates naturally as each character logs in.

## Broker Text Logic

```
Priority 1: any Tier 1 event active now           → "Abundance  now!"
Priority 2: soonest Tier 1 event firing in <1h    → "Stormarion  23m"
Priority 3: soonest event today                   → "Abundance  3h 12m"
Priority 4: all weekly checklist done             → "All done this week"
Priority 5: nothing trackable                     → "Midnight Events"
```

Broker text refresh:
- On `AREA_POIS_UPDATED`
- 60-second `OnUpdate` ticker for countdown decrement while tooltip is closed
- 5-second refresh while the tooltip is open

## Tooltip Section Hierarchy

The tooltip has three top-level sections. The middle section (**This Week**) splits into named sub-groups so it stays readable. Every section and every sub-group is independently collapsible (state persisted in `db.sectionState`); shift-click a header to toggle. The Settings panel mirrors this hierarchy exactly.

```
1. Timed Events                          (Tier 1)
2. This Week  (CharName)                 (Tier 2 + Tier 3)
   ├─ World
   ├─ PvP
   └─ Currencies                         (Tier 3 — event-tied currency caps)
3. Alts                                  (roll-up summary; detail view detached)
```

## Tooltip Layout

```
┌─ Timed Events ──────────────────────────────────┐
│  [icon] Abundance              now! / 7h 44m    │
│  [icon] Stormarion Assault     23m              │
│  [icon] Slayer's Rise          23m              │
│  [icon] Bountiful Delve        resets in 4h 11m │
│  [icon] Void Assault           Eversong (week)  │
├─ This Week (CharName) ──────────────────────────┤
│  ▼ World                                        │
│      Prey Hunts        N 4/4 · H 4/4 · NM 3/3   │
│      World Bosses      Lu'a ✓ · Crag ✗ · …      │
│      Saltheril's Soiree                    ✓    │
│      Stand Your Ground                     0/2  │
│      Legends of the Haranir          (warband)  │
│      Midnight: Void Assaults  (Liadrin) 5/8     │
│      Bountiful Delve weekly                ✓    │
│  ▶ PvP                A Call to Battle  3/4 BG  │
│  ▶ Currencies         Shards 5/8 · Accol 6/?    │
├─ Alts (12 tracked, 8 active this reset) ────────┤
│  Prey hunts:    5/12 done                       │
│  World Boss:    7/12 done                       │
│  Soiree:        9/12 done                       │
│  Void Assaults: 4/12 done                       │
│  ▸ Shift-Right-click for detail panel           │
└─────────────────────────────────────────────────┘
```

Sub-group headers show `▼` when expanded, `▶` when collapsed. Collapsed groups can show a one-line summary on the header line (e.g. "PvP ▶ A Call to Battle 3/4") so the user keeps the most important data visible without expanding.

## Alts — Two-Mode Display

Per-alt detail does not scale to altoholic users (15-30 chars). Two modes:

### Mode 1: Roll-up summary (in tooltip, default)

```
Alts (12 tracked, 8 active this reset)
   Prey hunts:    5/12 done
   World Boss:    7/12 done
   Soiree:        9/12 done
   Void Assaults: 4/12 done
```

Aggregates **enabled activity rows** across all tracked characters. Constant size regardless of alt count. "Active this reset" = logged in since the most recent weekly reset; characters with stale data are excluded from the denominator (so "5/12" reflects only fresh data).

### Mode 2: Detail panel (detached frame, on demand)

Triggered by **Shift-Right-Click** on the broker button (or a dedicated keybind). Opens a custom frame using the same template style as Broker_PlayerCoords' copy dialog (`BasicFrameTemplateWithInset`), but full-fledged: title bar, close button, scrollable rows.

```
┌─ Broker_MidnightEvents · Alts ────────────────────────[X]┐
│ Filter: [All ▼]  Sort: [Last login ▼]   12 chars         │
├──────────────────────────────────────────────────────────┤
│ Char       Prey   Boss  Soir  Stmrn  Haran  VoidA   BGs  │
│ Thrandis   12/12   ✓     ✓     2/2    ✓      8/8    4/4  │
│ Miravel     8/12   ✗     ✗     0/2    ✓      5/8    1/4  │
│ Tessadra    —      —     —     —      —      —      —    │
│ Hawken     12/12   ✓     ✓     1/2    ✗      7/8    4/4  │
│ … (scrollable)                                           │
└──────────────────────────────────────────────────────────┘
```

UX rules:
- **Class colour** on the character name column.
- **Truncate** char names to ~10 chars with ellipsis if needed.
- **Auto-stale**: chars not logged in since the current weekly reset → all cells render as `—` and the row is dimmed.
- **Auto-archive**: chars not logged in for 30+ days are hidden by default. Filter "Show archived" reveals them.
- **User-hide**: right-click a row → context menu "Don't track this character." Persisted in `db.hiddenChars`.
- **Filter dropdown**: All / Tracked only / Active this reset / By realm / By class.
- **Sort dropdown**: Last login (default) / Name / Most progress / Least progress.
- **Column visibility** mirrors the enabled activity toggles. Disabling "Soiree" in Settings removes both the tooltip row *and* the alts column.
- **Resizable**: user can drag the bottom-right corner. Geometry persisted.
- **No hard row cap** — the scrollable list handles 30+ alts gracefully.

The narrower tier-2 scope means fewer columns (~8 instead of ~15), so the panel default width can shrink and most users will never need to scroll horizontally.

### Frame implementation notes

Use `ScrollFrame` + `FauxScrollFrame` pattern (Blizzard standard) to render only visible rows.

## Settings Panel

Hierarchical, native WoW Settings API (matches Broker_PlayerCoords pattern). Three top-level categories.

- **Timed Events**
   - per-event toggle: Abundance, Stormarion Assault, Slayer's Rise, Bountiful Delve, Void Assault zone indicator
   - "Show inactive events" master toggle (greys out events not currently firing)

- **Weekly Checklist**
   - **World** sub-group toggle + per-row toggles (Prey, Bosses, Soiree, Stormarion, Haranir, Midnight: Void Assaults, Bountiful Delve)
      - Prey: optional toggles per tier (Normal/Hard/Nightmare)
   - **PvP** sub-group toggle + per-row toggles (A Call to Battle)
   - **Currencies** sub-group toggle + per-currency toggles (Shards of Dundun, Field Accolades, Latent Arcana)

- **Display**
   - Broker text style: countdown only / event name + countdown / urgent-only
   - Tooltip refresh rate while open (5 s default)
   - Alt summary mode: roll-up only / roll-up + detail-panel keybind
   - Detail panel: max default rows, default sort, "show archived" default
   - Stale threshold (days since login before character archives) — default 30

## API Reference (confirmed for Interface 120005)

| Need | API | Notes |
|---|---|---|
| List active world events | `C_AreaPoiInfo.GetEventsForMap(uiMapID)` | Filter to events; preferred over GetAreaPOIForMap |
| Event timer countdown | `C_AreaPoiInfo.GetAreaPOISecondsLeft(areaPoiID)` | MayReturnNothing — always nil-guard |
| Event metadata | `C_AreaPoiInfo.GetAreaPOIInfo([uiMapID], areaPoiID)` | Returns `name`, `atlasName`, `textureIndex`, `isCurrentEvent`, `tooltipWidgetSet` |
| Cheap timer pre-check | `C_AreaPoiInfo.IsAreaPOITimed(areaPoiID)` | Static lookup; gate before GetAreaPOISecondsLeft |
| Refresh trigger | `AREA_POIS_UPDATED` | No payload; fires on POI state change |
| Widget timer enumeration | `C_UIWidgetManager.GetAllWidgetsBySetID(setID)` | Use `info.tooltipWidgetSet` from POI for setID |
| Single widget update | `UPDATE_UI_WIDGET` | Payload: `{widgetSetID, widgetID, widgetType}` |
| Weekly quest completion | `C_QuestLog.IsQuestFlaggedCompleted(questID)` | Stale briefly post-instance; re-check on PEW |
| Quest objective progress | `C_QuestLog.GetQuestObjectives(questID)` | For multi-objective weeklies (BG wins, Stormarion runs) |
| Bulk completion history | `C_QuestLog.GetAllCompletedQuestIDs()` | Returns sorted array; use for login bulk init |
| Daily reset time | `GetQuestResetTime()` | Daily only; weekly via SavedInstance reset field |
| World boss lockout | `GetSavedWorldBossInfo(index)` | Iterate 1..GetNumSavedWorldBosses |
| Weekly currencies | `C_CurrencyInfo.GetCurrencyInfo(currencyID)` | `quantityEarnedThisWeek` is 0 for non-capped currencies |

## Recommended Build Sequence

1. **Tier 1 POI timers** — broker text + live countdown tooltip section. Validates the `C_AreaPoiInfo` event loop and gives something usable immediately.
2. **Tier 2 weekly checklist** — single Group: World, plus the small PvP row. Quest IDs harvested from Wowhead in one pass.
3. **Tier 3 currency caps** — three currencies, additive once Tier 2 is wired.
4. **Alt tracking — Mode 1 (roll-up summary)** in tooltip.
5. **Alt tracking — Mode 2 (detail panel frame)** with scroll, sort, filter, hide.
6. **Settings panel** — same pattern as Broker_PlayerCoords; mirrors the tooltip hierarchy exactly.
7. **Minimap button + LibDBIcon registration** — already in scaffold.

## Open Questions for Resolution

| # | Item | Status |
|---|---|---|
| 1 | ~~Silvermoon Weekly Dungeon Quest~~ | **Out of scope (Option Y, May 2026):** ceded to Midnight Routine. |
| 2 | ~~A Call to Battle quest giver/objective~~ | **Resolved (in-game inspection):** Archmage Aethas Sunreaver, Win 4 BG matches, 5 Mark of Honor + 175 Conquest. Quest ID still TBD. |
| 3 | **Stormarion Assault weekly quest count** | Confirm whether the weekly completion requires 1 or 2 runs. Resolve via in-game inspection. |
| 4 | ~~Lady Liadrin Weekly~~ | **Resolved (user, May 2026):** This *is* "Midnight: Void Assaults" — single umbrella row. Quest ID still TBD. |
| 5 | ~~Voidforge questline weekly gate~~ | **Out of scope (Option Y):** ceded to Midnight Routine. |
| 6 | ~~Vaeli Housing Weekly~~ | **Out of scope (Option Y):** ceded to Midnight Routine. |
| 7 | ~~Ritual Sites~~ | **Out of scope (Option Y):** ceded to Midnight Routine. |
| 8 | **Midnight: Void Assaults objective format** | Whether the weekly is binary completion or has an objective bar. Use `C_QuestLog.GetQuestObjectives(questID)` once quest ID is known. |
| 9 | ~~Patron Order quest IDs per profession~~ | **Out of scope (Option Y):** ceded to Midnight Routine. |
| 10 | **Prey Hunt quest IDs** | 12 IDs total (4 zones × 3 tiers); plus the Nightmare-3-hunts weekly quest ID. |
| 11 | **Field Accolades currency ID** | For Tier 3 cap display. |
| 12 | **Latent Arcana currency ID** | For Tier 3 cap display. |
| 13 | **Shards of Dundun currency ID** | For Tier 3 cap display. |
| 14 | **Soiree, Stormarion, Liadrin, Bountiful Delve weekly quest IDs** | 4 quest IDs for `IsQuestFlaggedCompleted`. |

## General Risks

- **Quest IDs are patch-fragile.** Each minor patch can change quest IDs. Maintain a single table at the top of `Core.lua` for easy per-patch updates. Consider warning the user in chat once when the build's interface version is below the running game's.
- **POI ID stability across zones.** `GetEventsForMap` is the right approach precisely because POI IDs may shift; we filter by `isCurrentEvent` and read names/icons live.
- **World boss rotation model uncertain.** Whether all four bosses are simultaneously available per week or rotate. `GetSavedWorldBossInfo` reports the truth at runtime regardless.
- **Bountiful Delve markers.** The daily-rotating "Bountiful" marker is a POI but we need to confirm it appears in `GetEventsForMap` (vs. `GetDelvesForMap`).
- **Void Assault active-zone detection.** No public timer expected (week-long indicator), so likely inferred from which zone has active Void Strike POIs in `GetEventsForMap`. Validate at implementation.
