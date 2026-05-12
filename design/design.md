# Broker_MidnightEvents — Design Document

This document captures the design and implementation plan for `Broker_MidnightEvents`. Authoritative for v1; revise in place when scope changes.

## Goal

A single LDB broker button that surfaces **Midnight event-tied weekly progress** for the current character, with a compact tooltip mirroring Blizzard's built-in Events panel and an **alt roll-up** that Blizzard's UI doesn't provide. The **broker text** is the headline: how many event-tied weeklies the current char has done out of how many are tracked, augmented by the next imminent event firing. The **tooltip** has four collapsible sections: ongoing events now, scheduled events in the next ~72 h, this week's weekly checklist, and an alt roll-up. **Left-click** opens Blizzard's native Events panel so the user can dig into details there — we don't try to duplicate it.

## Positioning vs. the field

| Tool | What it does | What it doesn't |
|---|---|---|
| **Blizzard built-in Events panel** (12.x) | Ongoing + scheduled events, currency progress inline, reminders, filters | Per-char weekly *quest* completion roll-up; alt comparison |
| **Midnight Routine** (1.6M downloads) | Comprehensive weekly tracker for everything in Midnight | LDB form factor; narrow event-tied focus |
| **Broker_MidnightEvents** (us) | LDB-bar surface for event-tied weeklies + alt roll-up; condensed mirror of Blizzard's events list with click-through; complements both | Comprehensive activity tracking; standalone window |

Our differentiation is **form factor (LDB-bar) + scope (event-tied weeklies) + alt roll-up**. We do not attempt to be a Midnight Routine alternative or a Blizzard Events panel replacement.

## Scope

**In scope:**
- **Events surface** — read via `C_EventScheduler`. Ongoing + scheduled (~72 h window) events with names, atlas icons, exact start/end epochs.
- **Weekly checklist** — event-tied weekly quests only:
  - Prey Hunts (12 contracts across 3 tiers + the Nightmare-3 weekly umbrella)
  - World Bosses (per-week kill-credit lockouts)
  - Saltheril's Soiree ("Fortify the Runestones")
  - Stormarion Assault weekly ("Stand Your Ground", 94581)
  - Legends of the Haranir (89268, warband scenario)
  - Lady Liadrin's Weekly Choice (pool of 7 known "Midnight: …" quests; one chosen per char per week)
  - Bountiful Delve weekly (paired with the Bountiful Delve daily POI)
- **Bountiful Delves** *(Tier 2.5)* — daily-rotating bountiful Delve POIs surfaced via `C_AreaPoiInfo.GetDelvesForMap` (per-zone) and filtered by `atlasName = "delves-bountiful"`. Use `isPrimaryMapForPOI` to dedupe across zones (Atal'Aman appears on both Eversong and Zul'Aman, etc.). Per-Delve completion roll-up across alts is the value-add. Quest IDs for completion tracking still need a harvest pass.
- **Alts roll-up** — passive snapshot of each character's weekly state on login; tooltip shows aggregate progress, Shift-Right-Click opens a scrollable detail panel.

**Dropped from earlier scope (May 2026 probe findings):**
- **Shards of Dundun row** — currency 3376 has `rechargingCycleDurationMS=0`, no timed reload. Pure weekly-reset budget; Blizzard's inline "6/8" on the Abundance event tooltip is sufficient.
- **Slayer's Rise as a separate event** — not surfaced by `C_EventScheduler` or `GetEventsForMap`. Likely a sub-state/wave inside the continuous Stormarion Assault event, surfacing via widgets when active (widget set 1795 was empty between waves at probe time).
- **Field Accolades / Latent Arcana / generic currency display** — Blizzard's panel covers them inline; we don't duplicate.

**Out of scope (cede to Midnight Routine):**
- Voidforge questline · Silvermoon Weekly Dungeon · T11 Delve weekly · Mythic+ weekly best · Great Vault detail rows · Patron Orders / Profession Knowledge · Vaeli Housing Weekly · Ritual Sites · Decor Duels · A Call to Battle / Aethas Sunreaver weekly slot (rotates with Timewalking; not event-tied)

## Non-Goals

- Standalone tracker window — Midnight Routine occupies that niche.
- Replicating Blizzard's Events panel — we mirror a condensed view and click-through to Blizzard's full UI rather than reimplement filters, reminders UI, widget rendering, etc.
- Holiday/seasonal events (well-served elsewhere).
- Cooperative read of Midnight Routine SavedVariables — fragile, no versioned contract; own tracking is the foundation.
- Comprehensive activity coverage. We deliberately stop at event-tied content.

## Architecture

### Events surface — `C_EventScheduler`

The 11.1.0/12.0 native `C_EventScheduler` namespace gives us everything Blizzard's panel uses, with no zone-loop scanning or fixed-cadence guessing.

```lua
local f = CreateFrame("Frame")
f:RegisterEvent("EVENT_SCHEDULER_UPDATE")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_ENTERING_WORLD" then
        C_EventScheduler.RequestEvents()       -- throttled by Blizzard
    end
    RefreshEventsSurface()
end)

local function RefreshEventsSurface()
    if not C_EventScheduler.HasData() then return end
    local ongoing   = C_EventScheduler.GetOngoingEvents()   -- now
    local scheduled = C_EventScheduler.GetScheduledEvents() -- ~72h ahead
    -- Each entry: { areaPoiID, rewardsClaimed, displayInfo, [scheduled extras: eventKey, eventID, startTime, endTime, duration, hasReminder] }
    -- Resolve names/icons via:
    --   C_AreaPoiInfo.GetAreaPOIInfo(C_EventScheduler.GetEventUiMapID(areaPoiID), areaPoiID)
end
```

**Confirmed via in-game probe (Shatanaris, 2026-05-12)**:

| Event | Source | Notes |
|---|---|---|
| Stormarion Assault | ongoing | `isTimed=false` — **continuously ongoing** during season, not a 30-min cycle. 30-min wave pacing happens inside the POI's widget set (1795). |
| Legends of the Haranir | ongoing | `isTimed=false` — continuously ongoing. |
| Abundance (Skinning Den / Enchanting Crypt / Herbalism Grotto) | scheduled (10 entries) | 8 h cadence, rotating across Zul'Aman / Eversong / Harandar. Each entry has exact `startTime`/`endTime`. |
| Void Assaults | scheduled (1 entry) | `duration=604800` (7 days) — the entry **is** the week-long active-zone indicator. Active zone resolves from the entry's POI info (`_poi.zoneName`). |
| Prey | **map-only** | Surfaces on Silvermoon's map via `C_AreaPoiInfo.GetEventsForMap` (areaPoiID 8742, atlas `UI-EventPoi-PreyCrystal`, widget set 2072). NOT in `C_EventScheduler`. To show "Prey ongoing" we merge the scheduler results with a per-zone `GetEventsForMap` scan. |
| Slayer's Rise | **likely a Stormarion sub-wave** | Neither ongoing nor scheduled, no separate POI. Widget set 1795 (Stormarion) was empty at probe time, consistent with a wave-only surface. Treat as part of Stormarion Assault; revisit if a future probe during an active wave reveals a separate POI. |
| Bountiful Delves | **map-only, separate POI category** | `C_AreaPoiInfo.GetDelvesForMap(mapID)` returns delves; filter by `atlasName = "delves-bountiful"`. Handled by the Bountiful Delves module. |
| Impending Void Incursion | **map-only, currently locked** | Surfaces on multiple zone maps with `isLocked=true`, atlas `ui-eventpoi-majorattacks`. Out of scope until it unlocks; flagged here for future awareness. |

**Per-event details available** — `_poi` blob carries `name`, `atlasName`, `zoneName`, `description`, `tooltipWidgetSet`, `isTimed`, `secondsLeft` (when timed). The `tooltipWidgetSet` ID exposes Blizzard's rich tooltip data (currency progress lines, wave counters) via `C_UIWidgetManager.GetAllWidgetsBySetID(setID)` if needed — useful for surfacing "Shards 6/8" in our tooltip.

**No `ns.fixedCadence`, no zone-list scan for scheduled events** — both deleted. `EVENT_SCHEDULER_UPDATE` is the primary refresh hook. For continuous map-only POIs (Prey), supplement with a lightweight `GetEventsForMap` pass over the discovered Midnight zones on `AREA_POIS_UPDATED`.

**Dynamic zone discovery**: walk up via `C_Map.GetMapInfo(...).parentMapID` from the player's current map to the Continent ancestor, then down via `C_Map.GetMapChildrenInfo`. Static zone lists are fragile — the first probe pass missed Isle of Quel'Danas (which carries the Parhelion Plaza bountiful delve). Use a fallback set only if the walk fails.

### Weekly checklist

Binary done/not-done per quest, refreshed on login + `QUEST_TURNED_IN` + `QUEST_REMOVED`. Iterated by Core, currently consumes `{ key, questID, label }` rows from `ns.weeklies`.

| Activity | Display | Quest ID(s) | Notes |
|---|---|---|---|
| **Prey Hunts** | `N 4/4 · H 4/4 · NM 3/3` (12 contracts) + binary NM weekly | NM weekly: **94446** ("A Nightmarish Task"). 12 per-tier contract IDs TBD. | NM tier locks until Preyseeker Rank 4 — render as `NM —` greyed when locked. |
| **World Bosses** | `Lu'a ✓ · Crag ✗ · …` | Per-boss kill-credit IDs: 92560 Lu'ashal, 92123 Cragpine, 92034 Thorm'belan, 92636 Predaxas | `GetSavedWorldBossInfo` doesn't populate in Midnight — kill-credit quest IDs are the working approach. Weekly-reset behaviour of these IDs TBD. |
| **Saltheril's Soiree** | binary ✓/✗ | TBD | 93889 ("Midnight: Saltheril's Soiree") is the Liadrin-pool variant, NOT the direct weekly. |
| **Stand Your Ground** | binary ✓/✗ | **94581** | Voidstorm WQ tied to the Stormarion Assault event. |
| **Legends of the Haranir** | binary ✓/✗ | **89268** | Solo warband scenario. |
| **Lady Liadrin's Weekly Choice** | binary ✓/✗ (any pool member completed) + `(Chosen)` annotation | Pool: 93769 Housing, 93889 Soiree, 93892 Stormarion Assault, 93909 Delves, 93911 Dungeons, 94457 Battlegrounds, 95842 Void Assaults | Multi-questID slot: `any(IsQuestFlaggedCompleted(qid) for qid in pool)`. Choice locks the others on the char. Pool offers ~4 of 7 per week; week-2 cross-check pending. |
| **Bountiful Delve weekly** | binary ✓/✗ | TBD | Paired with the Bountiful Delve daily POI. |

**Multi-questID slot semantics** — Core currently iterates `{ questID }`. The Liadrin pool and the Void Assault zone-rotation pair (94385 Eversong + 94386 Zul'Aman + TBD Harandar/Voidstorm) need `{ questIDs = {a, b, …} }` array support with "any flagged completed = done". This is a small Core change blocking promotion of those slots.

**Wiring**:
```lua
f:RegisterEvent("PLAYER_ENTERING_WORLD")   -- bulk init via GetAllCompletedQuestIDs()
f:RegisterEvent("QUEST_TURNED_IN")         -- single-quest update
f:RegisterEvent("QUEST_REMOVED")           -- handles drops + Liadrin choice locks
```

**Weekly reset detection** — compare `C_DateAndTime.GetSecondsUntilWeeklyReset()` against a stored `lastResetEpoch`. When reset has occurred, wipe the weekly completion cache.

### Bountiful Delves *(Tier 2.5 — ships after events surface + weeklies)*

Bountiful Delves are a separate POI category not surfaced by `C_EventScheduler`. They appear on the world map as a daily-rotating set of Delve markers. The feature:

- **Active list** in the tooltip: which Delves are bountiful right now (name + zone + icon), pulled from `C_AreaPoiInfo.GetDelvesForMap` filtered by `atlasName = "delves-bountiful"`.
- **Per-char completion**: has *this* character cleared the active bountiful set today?
- **Alt roll-up**: which alts haven't cleared yet, for cross-char prioritisation.

**API resolved (2026-05-12 probe)**:

```lua
-- For each Midnight zone uiMapID (discover dynamically — see "Dynamic zone discovery" above):
local ids = C_AreaPoiInfo.GetDelvesForMap(mapID) or {}
for _, poiID in ipairs(ids) do
    local info = C_AreaPoiInfo.GetAreaPOIInfo(mapID, poiID)
    if info and info.atlasName == "delves-bountiful" and info.isPrimaryMapForPOI then
        -- info.name, info.areaPoiID, info.tooltipWidgetSet, info.iconWidgetSet
    end
end
```

`isPrimaryMapForPOI` dedupes Delves that show on multiple zone maps (Atal'Aman appears on both Eversong and Zul'Aman). Probe found 3 distinct bountifuls across 4 of 5 probed zones (Quel'Danas pending in the next probe pass).

**Per-Delve completion tracking still needs a harvest pass**: clear a bountiful Delve on a probed char, observe the `QUEST_TURNED_IN` event for the kill-credit quest ID. Without these IDs we can show the active list but not completion state.

**Daily reset**: `GetQuestResetTime()` returns daily. Bountiful rotation appears to happen at daily reset (verify in next harvest cycle).

**Alt aggregation**: per-char `bountifulDone[delveID]` map (storing the daily-reset epoch when cleared), compared against today's active POI list at render time.

Sequenced after Tier 2 (weeklies) because the per-Delve quest IDs are not yet harvested. Discovery API is solved.

### Alts roll-up

Per-alt detail does not scale for altoholics (15–30 chars). Two modes:

**Mode 1: roll-up summary** (in tooltip, default)
```
Alts (12 tracked, 8 active this reset)
   Prey hunts:    5/12 done
   World Boss:    7/12 done
   Soiree:        9/12 done
   Liadrin:       4/12 done
   Bountiful:     6/12 cleared today    (if Bountiful Delves feature shipped)
```
Aggregates **enabled activity rows**. "Active this reset" = logged in since the most recent weekly reset; stale chars are excluded from the denominator.

**Mode 2: detail panel** (detached frame, on demand via Shift-Right-Click)
Custom frame with `BasicFrameTemplateWithInset`: title bar, close button, scrollable rows.

```
┌─ Broker_MidnightEvents · Alts ────────────────────────[X]┐
│ Filter: [All ▼]  Sort: [Last login ▼]   12 chars         │
├──────────────────────────────────────────────────────────┤
│ Char       Prey   Boss  Soir  Stmrn  Haran  Liadrin     │
│ Thrandis   12/12   ✓     ✓     ✓      ✓      Soiree  ✓  │
│ Miravel     8/12   ✗     ✗     ✗      ✓      Delves  ✗  │
│ Tessadra    —      —     —     —      —      —          │
│ Hawken     12/12   ✓     ✓     ✓      ✗      Dung.   ✓  │
│ … (scrollable)                                           │
└──────────────────────────────────────────────────────────┘
```

UX rules:
- **Class colour** on the character name column; truncate names to ~10 chars with ellipsis.
- **Auto-stale**: chars not logged in since the current weekly reset → all cells `—`, row dimmed.
- **Auto-archive**: chars not logged in for 30+ days are hidden by default. Filter "Show archived" reveals them.
- **User-hide**: right-click a row → "Don't track this character." Persisted in `db.hiddenChars`.
- **Filter**: All / Tracked only / Active this reset / By realm / By class.
- **Sort**: Last login (default) / Name / Most progress / Least progress.
- **Column visibility** mirrors Settings toggles. Disabling "Soiree" removes both the tooltip row *and* the alts column.
- **Resizable**: drag bottom-right; geometry persisted.

Use `ScrollFrame` + `FauxScrollFrame` to render only visible rows.

## Broker Text

The broker text is current-char-focused with a secondary event tag:

| State | Text | Color |
|---|---|---|
| Mid-week, partial weeklies | `Weeklies 3/6 · Stormarion ongoing` | white |
| All weeklies done | `All done · Abundance 23m` | green |
| All done, no event soon | `All done this week` | green dim |
| Event ongoing, partial weeklies | `Weeklies 3/6 · Abundance now!` | amber on event |
| Events API not ready | `Weeklies 3/6` | white |
| Nothing trackable | `Midnight Events` | white dim |

The `N/M` count is the only persistent metric and reflects **enabled rows** (a user who disables, say, Prey gets a denominator of 5 instead of 6). The event tag rotates with the next imminent firing within the 72 h window — or "ongoing" for continuous events like Stormarion / Legends.

Refresh cadence:
- On `EVENT_SCHEDULER_UPDATE` (server-push when scheduled data refreshes)
- On `QUEST_TURNED_IN` / `QUEST_REMOVED` (weekly count change)
- 60-second `OnUpdate` ticker for countdown decrement while tooltip is closed
- 5-second refresh while the tooltip is open

## Tooltip Layout

```
┌─ Now ───────────────────────────────────────────┐
│  [icon] Stormarion Assault    ongoing           │
│  [icon] Legends of the Haranir       ongoing    │
├─ Upcoming (next 24 h) ──────────────────────────┤
│  [icon] Abundance: Skinning Den    11 PM · ZA   │
│  [icon] Void Assaults             active · ES   │
│  [icon] Abundance: Enchanting Crypt 1 AM · ES   │
├─ Bountiful Delves (today)               2/3    │  (stretch feature)
│  [icon] Crusted Cavern               ✓          │
│  [icon] Lost Reliquary               ✓          │
│  [icon] Mossy Hollow                 ✗          │
├─ This Week (CharName) ──────────────────────────┤
│  Prey Hunts        N 4/4 · H 4/4 · NM 3/3       │
│  World Bosses      Lu'a ✓ · Crag ✗ · …          │
│  Saltheril's Soiree                       ✓     │
│  Stand Your Ground                        ✓     │
│  Legends of the Haranir         (warband)       │
│  Liadrin Weekly    (Delves picked)        ✓     │
│  Bountiful Delve weekly                   ✓     │
├─ Alts (12 tracked, 8 active this reset) ────────┤
│  Prey hunts:    5/12 done                       │
│  World Boss:    7/12 done                       │
│  Liadrin:       4/12 done                       │
│  ▸ Shift-Right-Click for detail panel           │
└─────────────────────────────────────────────────┘
                  ↑ Left-click anywhere → opens Blizzard's Events panel
```

Each section header is independently collapsible (state persisted in `db.sectionState`); shift-click a header to toggle. Collapsed sections can show a one-line summary on the header (e.g. "This Week ▶ 3/6 done") so the most important data stays visible.

The Liadrin row shows the *chosen* pool member in parentheses when one has been accepted on the current character (e.g. "Liadrin Weekly (Delves picked) ✗"). If no choice has been made yet the parenthetical is omitted.

## Click Hooks

- **Left-click** → `OpenMapToEventPoi(firstOngoingPOI)` if any ongoing event exists, else `OpenWorldMap(currentContinentMapID)`. Drops the user into Blizzard's events panel.
- **Right-click** → open the addon's Settings panel.
- **Shift-Right-click** → open the Alts detail panel (Mode 2).

`OpenMapToEventPoi` is a global Blizzard function (defined in `Blizzard_WorldMap.lua`); we call it as-is.

## Data Model (SavedVariables)

```lua
Broker_MidnightEventsDB = {
    -- top-level section toggles
    enabledSections  = { now = true, upcoming = true, delves = true, weekly = true, alts = true },
    -- per-row toggles (keys match activity slugs)
    enabledRows      = { prey = true, bosses = true, soiree = true,
                         stormarion = true, haranir = true,
                         liadrin = true,
                         bountifulDelve = true },
    -- collapse state per section
    sectionState     = { now = "expanded", upcoming = "expanded",
                         delves = "collapsed", weekly = "expanded",
                         alts = "collapsed" },
    -- per-character progress snapshot (keyed by "realm/charname")
    chars = {
        ["Realm/CharName"] = {
            weeklyReset     = 0,          -- epoch of the reset this data covers
            lastLogin       = 0,          -- for stale/archive detection
            questsDone      = {},         -- set of weekly questIDs completed
            preyProgress    = { N = 0, H = 0, NM = 0 },
            worldBossesDone = {},
            liadrinChoice   = nil,        -- which pool questID was accepted (or nil)
            bountifulDone   = {},         -- delveID → daily-reset epoch when cleared
        },
    },
    hiddenChars = {},
    altsPanel = {
        width = 600, height = 400, x = 0, y = 0,
        sort = "lastLogin", filter = "all", showArchived = false,
        staleThresholdDays = 30,
    },
    display = {
        upcomingWindow  = 24 * 3600,        -- seconds of "Upcoming" tooltip window (max 72h per API)
        tooltipRefresh  = 5,                -- seconds while tooltip open
        brokerEventTag  = "next",           -- "next" | "ongoing-only" | "off"
    },
    minimapIcon = { hide = false },
}
```

Per-event toggles are removed — Blizzard's panel handles event filtering. Per-currency toggles for Field Accolades / Latent Arcana removed (out of scope). `shards` row is opt-in, off by default.

Alt data accumulates naturally as each character logs in.

## Settings Panel

Hierarchical, native WoW Settings API (matches Broker_PlayerCoords pattern). Three top-level categories.

- **Tooltip Sections**
   - Per-section toggle: Now / Upcoming / Bountiful Delves / This Week / Alts
   - Upcoming window: 6 h / 12 h / 24 h / 72 h (max from API)

- **Weekly Checklist**
   - Per-row toggle: Prey, Bosses, Soiree, Stormarion, Haranir, Liadrin, Bountiful Delve
   - Prey: sub-toggles per tier (Normal / Hard / Nightmare)

- **Alts**
   - Roll-up summary in tooltip: on / off
   - Detail panel default sort + filter
   - Stale threshold (days since login before archiving) — default 30

- **Display**
   - Broker event tag style: next event / ongoing only / off
   - Tooltip refresh rate while open (5 s default)

## API Reference (confirmed for Interface 120005)

### Events surface
| Need | API | Notes |
|---|---|---|
| Current ongoing events | `C_EventScheduler.GetOngoingEvents()` | `[{areaPoiID, rewardsClaimed, displayInfo}]` |
| Future scheduled events (~72 h window) | `C_EventScheduler.GetScheduledEvents()` | `[{eventKey, eventID, areaPoiID, startTime, endTime, duration, hasReminder, rewardsClaimed, displayInfo}]` |
| Resolve event POI metadata | `C_AreaPoiInfo.GetAreaPOIInfo(uiMapID, areaPoiID)` | Combine with `GetEventUiMapID(areaPoiID)` for the map. Returns `name`, `atlasName`, `description`, `tooltipWidgetSet`. |
| Map for an event | `C_EventScheduler.GetEventUiMapID(areaPoiID)` | Returns uiMapID or nil |
| Zone name for an event | `C_EventScheduler.GetEventZoneName(areaPoiID)` | Localized zone string |
| Trigger server fetch | `C_EventScheduler.RequestEvents()` | Throttled by Blizzard; safe to call on PEW |
| Data availability gate | `C_EventScheduler.HasData()` / `CanShowEvents()` | Bool — gate reads |
| Refresh trigger | `EVENT_SCHEDULER_UPDATE` | No payload; fires on data refresh |
| Open Blizzard panel at event | global `OpenMapToEventPoi(areaPoiID)` | Defined in `Blizzard_WorldMap.lua` |
| Set/clear reminder | `C_EventScheduler.SetReminder(eventKey)` / `ClearReminder(eventKey)` | Hooks into native reminder UI |
| Widget content (for tooltipWidgetSet) | `C_UIWidgetManager.GetAllWidgetsBySetID(setID)` | Optional — for Shards-style inline metrics |

### Weekly quest completion
| Need | API | Notes |
|---|---|---|
| Quest completion check | `C_QuestLog.IsQuestFlaggedCompleted(questID)` | Stale briefly post-instance; re-check on PEW |
| Quest objective progress | `C_QuestLog.GetQuestObjectives(questID)` | For multi-objective weeklies if needed |
| Bulk completion history | `C_QuestLog.GetAllCompletedQuestIDs()` | For login bulk init |
| Weekly reset countdown | `C_DateAndTime.GetSecondsUntilWeeklyReset()` | Compare against stored `lastResetEpoch` |

### Bountiful Delves *(API confirmed; completion IDs pending)*
| Need | API | Notes |
|---|---|---|
| Active Delve POIs in a zone | `C_AreaPoiInfo.GetDelvesForMap(uiMapID)` | Confirmed via probe |
| Bountiful filter | `info.atlasName == "delves-bountiful"` | Other atlases: `delves-regular`, etc. |
| Cross-zone dedupe | `info.isPrimaryMapForPOI` | True only on the canonical map for the POI |
| Daily reset | `GetQuestResetTime()` | Daily-reset only |
| Per-Delve completion | `IsQuestFlaggedCompleted(delveQuestID)` | Per-Delve kill-credit IDs harvest pending |
| Dynamic zone discovery | `C_Map.GetMapInfo` + `GetMapChildrenInfo` from continent ancestor | Avoids missing zones (e.g. Quel'Danas) that a static list might skip |

### Out
- `C_AreaPoiInfo.GetEventsForMap` + zone-list scanning — replaced by `C_EventScheduler`.
- `IsAreaPOITimed` / `GetAreaPOISecondsLeft` — replaced by `startTime` / `endTime` epochs.
- `ns.fixedCadence` schedule-fallback hack — no longer needed.
- `GetSavedWorldBossInfo` — never populated in Midnight; we use kill-credit quest IDs.

## Build Sequence

1. **Events surface** — `C_EventScheduler` subscriber for ongoing + scheduled, plus a supplementary `C_AreaPoiInfo.GetEventsForMap` scan over dynamically-discovered Midnight zones (Prey is map-only; the merge handles it). Click-hook into `OpenMapToEventPoi`.
2. **Broker text** — `N/M weeklies done · NextEvent` formatter wired to both the events cache and the weekly checklist state.
3. **Weekly checklist** — render existing `ns.weeklies` rows in the new tooltip section.
4. **Multi-questID slot support** — Core change: accept `{ questIDs = {…} }` alongside single `questID`. Promote Liadrin pool + Void Assault zone pair out of `ns.candidateWeeklies`.
5. **Alts Mode 1** — roll-up summary in tooltip.
6. **Alts Mode 2** — detail panel frame.
7. **Settings panel** — simplified hierarchy.
8. **Bountiful Delves *(Tier 2.5)*** — POI scan via `GetDelvesForMap` + atlas filter + dedupe + tooltip section. Per-Delve completion + alts column gated on harvest of per-Delve quest IDs (Q21).
9. **Minimap button + LibDBIcon registration** — already in scaffold.

## Open Questions for Resolution

| # | Item | Status |
|---|---|---|
| 1–7 | Out-of-scope items (Silvermoon Dungeon, Voidforge, Housing, Ritual Sites, Patron Orders, Aethas/TW slot, A Call to Battle) | **Resolved out of scope** — ceded to Midnight Routine. |
| 8 | ~~Midnight: Void Assaults objective format~~ | **Obsolete** — folded into Q11 (Liadrin pool). |
| 9 | ~~Lady Liadrin Weekly~~ | **Resolved (harvest 2026-05-12):** choice pool of 7 known IDs (93769 Housing, 93889 Soiree, 93892 Stormarion Assault, 93909 Delves, 93911 Dungeons, 94457 Battlegrounds, 95842 Void Assaults). Up to 4 offered per char per week; completing one locks the others. Slot tracking: `any(IsQuestFlaggedCompleted)` over pool. |
| 10 | ~~Stormarion Assault weekly~~ | **Resolved:** "Stand Your Ground" 94581. |
| 11 | **Prey Hunt contract IDs** | NM weekly 94446 resolved. 12 individual per-tier contract IDs still TBD for the `N/H/NM` display. |
| 12 | **Soiree direct weekly** | "Fortify the Runestones" quest ID still TBD. 93889 is the Liadrin-pool variant, not this. |
| 13 | **Bountiful Delve weekly** | Quest ID TBD. |
| 14 | **Void Assault zone-rotation pool** | Confirmed 94385 (Eversong) + 94386 (Zul'Aman). Harandar / Voidstorm variants likely exist; harvest when rotation lands. |
| 15 | **`rewardsClaimed` semantic** *(API)* | Both probe chars at 0 events/0 rewards → all `false`. Need a positive-control char (some events done this week) to verify whether it tracks weekly cap or per-instance claim. Not blocking. |
| 16 | ~~Slayer's Rise absence~~ *(API)* | **Resolved (2026-05-12 probe):** not surfaced by `C_EventScheduler` or `GetEventsForMap`; widget set 1795 (Stormarion) was empty at probe time. Treat as a Stormarion Assault sub-wave, not a separate slot. Revisit if a future probe during an active wave reveals a separate POI. |
| 17 | ~~Shards of Dundun reload mechanic~~ *(currency)* | **Resolved (2026-05-12 probe):** currencyID **3376**, `maxQuantity=8`, `rechargingCycleDurationMS=0`. No timed reload — pure weekly-reset budget. **Shards row dropped from scope.** Blizzard's inline "6/8" on the Abundance event tooltip is sufficient. |
| 18 | ~~Bountiful Delve POI API~~ *(Tier 2.5)* | **Resolved (2026-05-12 probe):** `C_AreaPoiInfo.GetDelvesForMap(mapID)` returns delves; filter by `atlasName = "delves-bountiful"`, dedupe via `isPrimaryMapForPOI`. Per-Delve completion quest IDs still need a harvest pass — see Q21. |
| 19 | **Currency IDs** | Harvested via probe: Shard of Dundun **3376**, Field Accolade **3405**, Unalloyed Abundance **3377**, Dawnlight Manaflux **3378** (Soiree-related, 5/8 budget, same shape as Shards). Latent Arcana not present on probe char (likely unlocked at Soiree progression). All currently **dropped from scope** — Blizzard shows them inline. |
| 20 | **World-boss weekly reset behaviour** | The four kill-credit quest IDs (92560 / 92123 / 92034 / 92636) reset weekly *(assumed)*; verify at next reset. If they're achievement-style we need a different approach. |
| 21 | **Per-Bountiful-Delve completion quest IDs** *(Tier 2.5)* | Harvest pending — clear a bountiful on a probed char, observe `QUEST_TURNED_IN`. 3 distinct bountifuls seen this rotation (Grudge Pit, Sunkiller Sanctum, Atal'Aman); Parhelion Plaza on Quel'Danas confirmed visually as a 4th. |
| 22 | **Prey POI integration** *(events surface)* | Prey is a continuous event POI on the Silvermoon map (areaPoiID 8742) but is **not** in `C_EventScheduler`. To show "Prey ongoing" we merge scheduler results with a per-zone `GetEventsForMap` scan. Cheap; just a code-pattern note for the events module. |

## General Risks

- **Quest IDs are patch-fragile.** Each minor patch can shift quest IDs. Maintain `ns.weeklies` (and any Bountiful Delve table) in `Data.lua` and treat patch days as a re-harvest trigger.
- **`C_EventScheduler` data lag.** `RequestEvents()` is server-throttled; on a fresh login, expect a brief window where `HasData()` returns false. Gate reads on `HasData()` and refresh on `EVENT_SCHEDULER_UPDATE`. Don't show stale countdowns.
- **`continent` field unreliable.** Probe showed `GetActiveContinentName()` returning "Khaz Algar" while events were Midnight ones. Don't use it for expansion detection — rely on the per-event `mapID`.
- **Slayer's Rise / Bountiful Delves / Prey missing from `C_EventScheduler`.** Each surfaces via `C_AreaPoiInfo` (`GetDelvesForMap` for delves, `GetEventsForMap` for Prey, sub-widget of Stormarion for Slayer's Rise). Keep them as optional sections that no-op gracefully when their source returns nothing.
- **Static zone lists are fragile.** The initial probe missed Isle of Quel'Danas (Parhelion Plaza bountiful delve). Discover Midnight zones dynamically via `C_Map.GetMapInfo` + `GetMapChildrenInfo` from the continent ancestor; treat any hardcoded zone list as a fallback only.
- **Multi-questID slot Core change** is small but a regression risk for existing single-`questID` rows — keep the Core read backwards-compatible.
- **Bountiful Delves complexity creep** — the per-alt completion roll-up is the value-add, but it's the part with the most moving parts (POI discovery + quest harvest + daily reset + alt aggregation). Ship the other tiers first; revisit only when their foundation is solid.
