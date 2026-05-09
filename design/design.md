# Broker_MidnightEvents — Design Document

This document captures the design and implementation plan for `Broker_MidnightEvents`. Authoritative for v1; revise in place when scope changes.

## Goal

A single LDB broker button. The **broker text** shows the most urgent upcoming timed event ("Stormarion in 23m" / "Abundance now!"). The **tooltip** has three collapsible sections: live event countdowns, a weekly/daily checklist for the current character, and an alt summary row. No standalone window — the addon lives entirely in the broker bar.

## Non-Goals

- Standalone tracker window (Midnight Routine occupies that niche with ~1.6M downloads; competing there is a losing proposition)
- Replacing WeakAuras for arbitrary in-combat state tracking
- Holiday/seasonal event tracking (well-served by existing addons)
- Cooperative read of Midnight Routine SavedVariables (research showed this is fragile, with no versioned contract; own tracking is the foundation and MR cooperation does not buy enough to justify the maintenance cost)

## Event Catalogue → Implementation Tiers

Events split cleanly into three implementation tiers by data source and cadence.

### Tier 1 — Live POI Timers (clock-driven, `C_AreaPoiInfo`)

These events have a visible world-map marker with a server-managed countdown. No hardcoded schedule table needed — POIs are discovered at runtime.

| Event | Zone | Cadence | Completion |
|---|---|---|---|
| **Abundance** | Rotating (4 zones) | Every 8 h, fixed | Per-char (8 Shards/week cap) |
| **Stormarion Assault** | Voidstorm | Every 30 min, fixed | Per-char (weekly quest ×2) |
| **Slayer's Rise PvP Events** | Voidstorm | Every 30 min, rotating pool | Stateless |
| **Bountiful Delve (daily marker)** | All zones | Daily reset | Per-char |

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

### Tier 2 — Weekly Checklist (quest-completion-driven)

Binary done/not-done checks with no live countdown. Refresh on login and on `QUEST_TURNED_IN`.

| Activity | API | Quest source |
|---|---|---|
| **Prey Hunts** (4 high-value/week) | `C_QuestLog.IsQuestFlaggedCompleted(questID)` × 4 | Quest IDs from Wowhead at implementation |
| **World Bosses** (warband loot) | `GetSavedWorldBossInfo(index)` — check `locked` per boss | Native API |
| **Saltheril's Soiree** ("Fortify the Runestones") | `IsQuestFlaggedCompleted` | Wowhead |
| **Stormarion Assault weekly** ("Stand Your Ground") | `IsQuestFlaggedCompleted` | Wowhead |
| **Great Vault progress** | `C_WeeklyRewards.GetActivities()` → `progress / threshold` | Native API |
| **Legends of the Haranir** (warband) | `IsQuestFlaggedCompleted` | Wowhead |
| **Patron Orders / Profession KP** | `IsQuestFlaggedCompleted` × profession | Wowhead; one ID per crafting prof |

**Event-driven pattern:**

```lua
f:RegisterEvent("PLAYER_ENTERING_WORLD")   -- bulk init via GetAllCompletedQuestIDs()
f:RegisterEvent("QUEST_TURNED_IN")         -- immediate single-quest update
f:RegisterEvent("QUEST_LOG_UPDATE")        -- server-push catch-all (debounced 0.5 s)
```

`C_QuestLog.GetAllCompletedQuestIDs()` at login seeds the local completion table cheaply. `QUEST_TURNED_IN` keeps it hot without a full re-scan.

**Weekly reset detection** — compare `GetQuestResetTime()` (daily) against a stored `lastResetEpoch`. When the stored epoch is older than the most recent Tuesday 08:00 UTC, wipe the weekly completion cache.

### Tier 3 — Weekly Currency Caps (display-only)

Optional section; shows weekly-capped currency progress.

```lua
C_CurrencyInfo.GetCurrencyInfo(currencyID)
-- fields: quantityEarnedThisWeek, maxQuantityPerWeek, quantity
```

Currency IDs to be resolved at implementation: Valorstone (3008 confirmed), knowledge points, crests. Low cost, high tooltip value.

## Data Model (SavedVariables)

```lua
Broker_MidnightEventsDB = {
    -- settings
    enabledSections  = { timers = true, weekly = true, alts = true },
    enabledEvents    = { Abundance = true, Stormarion = true, ... },
    sectionState     = { timers = "expanded", weekly = "expanded", alts = "collapsed" },
    -- per-character progress snapshot (keyed by "realm/charname")
    chars = {
        ["Realm/CharName"] = {
            weeklyReset     = 0,          -- epoch of the reset this data covers
            questsDone      = {},         -- set of questIDs completed this week
            worldBossesDone = {},         -- set of worldBossIDs with active lockout
            vaultProgress   = {},         -- from C_WeeklyRewards, snapshot on login
            currencies      = {},         -- weekly caps snapshot
        },
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

## Tooltip Layout

```
┌─ Timed Events ──────────────────────────────────┐
│  [icon] Abundance          now! / 7h 44m        │
│  [icon] Stormarion Assault  23m                 │
│  [icon] Slayer's Rise       23m                 │
│  [icon] Bountiful Delve     resets in 4h 11m    │
├─ This Week (CharName) ──────────────────────────┤
│  ✓  Prey Hunts              4/4                 │
│  ✗  World Boss: Lu'ashal                        │
│  ✓  Saltheril's Soiree                          │
│  ✗  Stand Your Ground       0/2                 │
│  ✓  Legends of the Haranir  (warband)           │
│     Great Vault             5/8                 │
├─ Alts ──────────────────────────────────────────┤
│  Thrandis    ✓ Prey  ✗ Boss  ✓ Soiree           │
│  Miravel     ✗ Prey  ✗ Boss  ✗ Soiree           │
└─────────────────────────────────────────────────┘
```

Section state (collapsed/expanded) saved in `db.sectionState`. Shift-click a section header to toggle it.

## Settings Panel

Three categories, native WoW Settings API (matches Broker_PlayerCoords pattern):

- **Timed Events** — enable/disable each event type; show/hide "inactive" events (those not currently firing)
- **Weekly Checklist** — enable/disable each activity row; toggle Patron Orders per-profession
- **Display** — broker text style (countdown only vs. event name + countdown); alt panel max rows; tooltip refresh rate

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
| Bulk completion history | `C_QuestLog.GetAllCompletedQuestIDs()` | Returns sorted array; use for login bulk init |
| Daily reset time | `GetQuestResetTime()` | Daily only; weekly via SavedInstance reset field |
| Great Vault progress | `C_WeeklyRewards.GetActivities([type])` | Returns `progress`, `threshold`, `rewards[]` per slot |
| World boss lockout | `GetSavedWorldBossInfo(index)` | Iterate 1..GetNumSavedWorldBosses |
| Raid lockout | `GetSavedInstanceInfo(index)` | `reset` field is seconds until expiry |
| Weekly currencies | `C_CurrencyInfo.GetCurrencyInfo(currencyID)` | `quantityEarnedThisWeek` is 0 for non-capped currencies |

## Recommended Build Sequence

1. **Scaffold + Tier 1 POI timers** — broker text + live countdown tooltip section. Validates the `C_AreaPoiInfo` event loop and gives something usable immediately.
2. **Tier 2 weekly checklist** — requires harvesting quest IDs from Wowhead for each activity; one-time data work.
3. **Tier 3 currency caps** — additive; cheap to add.
4. **Alt tracking** — own SavedVariables snapshot, populated passively over time.
5. **Settings panel** — same pattern as Broker_PlayerCoords.
6. **Minimap button + LibDBIcon registration** — already in scaffold; no extra work.

## Risks and Open Questions

- **Quest IDs are patch-fragile.** Each minor patch can change quest IDs. Maintain a single table at the top of `Core.lua` for easy per-patch updates.
- **POI ID stability across zones.** `GetEventsForMap` is the right approach precisely because POI IDs may shift; we filter by `isCurrentEvent` and read names/icons live.
- **Stormarion Assault weekly quest count uncertain.** Sources disagree on whether the weekly completion requires 1 or 2 runs. Resolve via in-game inspection at implementation.
- **World boss rotation model uncertain.** Whether all four bosses are simultaneously available per week or rotate. `GetSavedWorldBossInfo` will report the truth at runtime regardless; no preflight assumption needed.
- **Bountiful Delve markers.** The daily-rotating "Bountiful" marker is a POI but we need to confirm it appears in `GetEventsForMap` (vs. `GetDelvesForMap`).
