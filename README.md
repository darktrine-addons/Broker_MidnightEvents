# Broker: MidnightEvents

> 🚧 **Beta in active development.** All listed features work and the addon is daily-driver stable across multiple characters, but the surface is still evolving — expect occasional polish-level changes between releases. Feedback, bug reports, and feature ideas welcome on the [issue tracker](https://github.com/darktrine-addons/Broker_MidnightEvents/issues).

**A compact world-event timer + associated mini weekly checklist for WoW Midnight, served through any LibDataBroker host.**

The broker bar always shows the most-urgent event — a wave countdown, a "FIRING NOW!" for the Void Incursion, a Skinning Den firing in 12 minutes. Hover the bar (or open the minimap button) and a structured tooltip unfolds: what's happening right now, what's coming in the next 24 hours, today's bountiful Delve rotation with its rotating story variant, your character's weekly checklist, Voidforge progress, and a roll-up across all your alts.

Retail only. Requires Midnight (Interface 120005+). Works with any LibDataBroker host (Arcana, ElvUI, Bazooka, Broker2FuBar, TitanPanel, …); minimap-button entry point is built in for users who don't run a broker bar.

## Is this for you?

**Yes, probably** — if you:

- Want one-glance answers to "what world event is next" and "what haven't I done this week" without alt-tabbing to a browser
- Run multiple characters and want their weekly state visible without logging into each
- Like compact at-a-glance UIs that get out of the way; tooltip only opens on hover
- Already use a broker bar host *or* are happy with a minimap button

**Probably not** — if you:

- Want a comprehensive checklist of *every* weekly (Patron Orders, professions, housing, M+, vault breakdown). Use [Midnight Routine](https://www.curseforge.com/wow/addons/midnight-routine) for that breadth; this addon is intentionally focused on **events and the weeklies tied to them**, designed to coexist
- Want a separate always-visible window per activity (this is a single hover tooltip)
- Run only Classic / non-retail

## Features

### Broker bar
- **Soonest event tag** — auto-picks the most-urgent of: an event firing imminently (`Stormarion Assault next 12m`), an event genuinely happening now (`Abundance: Mining Voidburrow 42m left`), a building event close to firing (`VoidIncursion 94% built`), or a confirmed live firing (`VoidIncursion FIRING NOW!` in amber).
- **Weekly progress** chunk — `Weeklies 3/7` (or `All done` once everything's ticked).
- Both halves toggleable independently in the Settings panel.

### Tooltip sections
- **Now** — currently-firing events, sorted by urgency: firing > closer-to-firing progress bars > soonest countdowns > untimed continuous (Stormarion Assault between waves, Legends of the Haranir, Prey, etc.).
- **Upcoming (next 24h)** — scheduler-driven next fires, ordered by when they happen (matches Blizzard's events panel order).
- **Bountiful Delves (today)** — today's rotation with each delve's active **story variant** in parentheses; a green ✓ next to the story name means this character has the matching achievement criterion (per-delve "Stories" achievement, 61724–61733) already completed.
- **This Week (CharName)** — per-character weekly checklist: World Boss, Abundant Offerings, Stand Your Ground, A Nightmarish Task, Lady Liadrin's Weekly (with which choice you picked annotated), Void Assault active zone, Lost Legends. Outstanding rows up top in white, completed rows dim with a green ✓.
- **Voidforge progress** — per-character N/M counters scraped from Decimus's bars in Voidstorm: *Voidcores transmuted* (weekly bonus-roll allowance), *Nilhammer empowered* (lifetime 0–4, gates the Ascendant Nilhammer upgrade). Only populates after the character has been near Decimus once; persists across sessions.
- **Alts roll-up** — aggregate "X / Y done" per activity across every character you've logged into with the addon enabled. Stale chars (no login since the most recent weekly reset) are excluded so the aggregate reflects only fresh data.

### Detached Alts panel
- **Shift-Right-click** the broker (or minimap button) opens a scrollable per-alt grid showing every tracked character's weekly state at a glance.
- Class-coloured names, **WBoss / AbunO / SYG / NightT / LiadW / VoidA / LL** column headers (hover for the full label), drag-to-reposition, geometry persists.
- Background opacity tunable in Settings (10–100 %, default 60 % — slightly transparent like a tooltip).

### Settings panel
- *Escape → Options → AddOns → Broker: MidnightEvents*, or **Right-click** the broker / minimap button.
- Per-section visibility toggles for every tooltip section (Now / Upcoming / Bountiful Delves / This Week / Voidforge / Alts).
- World Boss row visibility in the This Week section.
- Broker bar split toggles (show weekly progress / show next-event tag).
- Alts panel background opacity slider.

### Minimap button
- Built-in via LibDBIcon — useful if you don't run a broker bar host. One-toggle off in settings (default on).

## Click interactions

| Click | Action |
|---|---|
| **Left-click** | Open Blizzard's events panel, pinned to the first active POI |
| **Right-click** | Open the Settings panel |
| **Shift-Right-click** | Toggle the detached Alts panel |
| **Hover** | Show the structured tooltip |

Identical on the broker bar entry and the minimap button.

## Installation

The recommended path is a package manager: **CurseForge app**, **WowUp**, or the **Wago app** — search for *Broker: MidnightEvents* and one-click install.

For manual installation:

1. Download the latest release zip from [GitHub Releases](https://github.com/darktrine-addons/Broker_MidnightEvents/releases), CurseForge, or Wago.io
2. Extract the `Broker_MidnightEvents` folder into your addons directory:
   - **Windows**: `World of Warcraft\_retail_\Interface\AddOns\`
   - **macOS**: `Applications/World of Warcraft/_retail_/Interface/AddOns/`
3. Restart World of Warcraft or `/reload`

## Slash commands

Diagnostic commands intended for bug reports; not needed for normal use.

| Command | What it does |
|---|---|
| `/mediag` | Captures every relevant API surface (scheduler entries, map POIs, widget sets, addon state) to `Broker_MidnightEventsDB._diag`. After `/reload` flushes the SavedVariables file, paste the `_diag` block into a bug report. |
| `/mesched` | Prints `C_EventScheduler.GetOngoingEvents` + `GetScheduledEvents` summary to chat. |
| `/mepois` | Prints event POIs from the continent + Midnight zone maps to chat. |
| `/mewidget <setID>` | Prints the full contents of a Blizzard UI widget set to chat (per-widget visualization info). |

## Technical notes

### File structure
- `Broker_MidnightEvents.toc` — addon metadata and load order
- `Data.lua` — static tables: weeklies, world bosses, known POI names, widget overrides, story-achievement map, Voidforge progress schema, firing heuristics
- `Settings.lua` — SavedVariables defaults, migrations, weekly-reset detection, Settings panel registration
- `Events.lua` — scheduler + map POI ingest, single source of truth for what's active / upcoming, with per-zone scans and name caches
- `Core.lua` — broker text, tooltip rendering, click handlers, ticker-isolated widget reads, slash commands
- `AltsPanel.lua` — detached per-alt grid panel

### Taint posture (12.x protected-data model)
The addon reads several values Blizzard's 12.x runtime treats as *secret* (widget bar values, scheduler timestamps). Doing arithmetic on those values taints the calling execution context, and that taint propagates to anything the context touches. The addon contains this rigorously:

- A **dedicated 2-second ticker** does all the widget-bar arithmetic; results land in plain Lua tables. Render paths only read those tables — no arithmetic on secrets, no taint propagation.
- **Private `GameTooltipTemplate` frames** for every hover surface the addon owns (main tooltip + alts-panel column-header tooltip). Blizzard's shared `GameTooltip` is never written to from the addon's tainted context.
- **No custom field writes onto Blizzard frames.** Addon state lives in addon-local tables or weak side-tables keyed by frame.

### Saved variables
- `Broker_MidnightEventsDB` — settings, minimap icon position (LibDBIcon), per-character snapshots, event name cache, alts panel geometry.

### Compatibility
- **WoW version**: Retail (Midnight, Interface 120005+)
- **Dependencies**: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0 (all bundled)
- **Broker display**: optional — any LDB-compatible host works (Arcana, ElvUI, Bazooka, Broker2FuBar, TitanPanel, …). If you don't run one, the built-in minimap button is a full-equivalent entry point.

## Contributing

Issues and pull requests are welcome.

## License

Licensed under [GPL-2.0](https://www.gnu.org/licenses/gpl-2.0.html). The full license text is in the `LICENSE` file in the source distribution.

## Changelog

### v0.6.0-beta

**New features:**
- **Voidforge progress section** — per-character N/M counters scraped live from Decimus's bars in Voidstorm: *Voidcores transmuted* (weekly bonus-roll allowance, cap rises +2/week per Midnight S1) and *Nascent Nilhammer empowered* (lifetime 0–4, terminal grants Ascendant Nilhammer for weapon/trinket upgrades). Cache only refreshes when near Decimus; last-known value persists while you're away.
- **Bountiful Delve story variants** — every bountiful delve row now shows today's active story in parentheses (e.g. "Atal'Aman (Toadly Unbecoming)") plus a green ✓ when this character has the matching per-delve Stories achievement criterion completed.

**Improvements:**
- `/mediag` dev diagnostic broadened to capture the wider POI surface, common UI widget containers, and a brute-force small-`barMax` StatusBar scan for finding bounded counters that aren't tied to event/delve POIs.

### v0.5.x — taint-containment series

**Fixes:**
- **Render paths now run untainted.** Widget-bar arithmetic was tainting render contexts every frame, propagating taint into the events-panel widget tooltips (Stormarion / Abundance), the broker click that opens the events panel (protected `SetPassThroughButtons` cascade), and the Settings panel paths. Fixed by isolating the arithmetic into a dedicated 2-second ticker that writes to a plain Lua cache; render paths read the cache only.
- **Alts-panel header tooltip uses a private frame.** Hovering an abbreviated column header was writing to the shared `GameTooltip` from the addon's tainted context, breaking unrelated Blizzard widget tooltips. Now uses its own `GameTooltipTemplate` frame.
- **Bountiful Delves**: skip cache writes during the first 5 minutes after the daily reset. The API briefly returns both yesterday's outgoing and today's incoming rotation in a single snapshot at the reset moment, which previously persisted as permanent stale state.

### v0.4.0-beta

- **Now / Upcoming / Bountiful Delves accuracy overhaul** — scheduler-scheduled `endTime` is the variant's fire time (verified empirically), upcoming order matches Blizz events panel, stale bountiful entries pruned via per-entry timestamps.
- **Impending Void Incursion progress** — "X% built" rendered with colour-graded urgency (cyan / white / amber at <50 / <90 / ≥90), plus an empirical "FIRING NOW!" detector that propagates to the broker text.
- **Map-event ingest** — zone-map scan now picks up Void Incursion, Abyss Anglers, A Sea Voidage, Prey, and zone-copies of Stormarion / Haranir / Void Assaults that the continent-only scan was missing.
- **Tooltip Alts section** uses full weekly labels instead of short abbreviations.
- **Alts panel** is 60 % transparent by default with a Settings slider (10–100 %) and full-name hover tooltips on the abbreviated column headers.

### v0.3.0-beta

- **Per-character "This Week" section** with World Boss + tracked weekly quests. Outstanding rows top in white, completed rows dim with a green ✓.
- **Detached Alts panel** (Shift-Right-click) with scrollable per-alt grid.
- **Bountiful Delves** section: today's rotation with completion tracking (entries disappear from visible → cached as done).
- **Lady Liadrin's Weekly** annotated with which choice the character picked.
- **Native Settings panel** with per-section toggles.

### v0.2.0-beta

- Initial public beta on GitHub.
- **Now + Upcoming sections** driven by `C_EventScheduler`.
- **Broker bar** picks the soonest event tag automatically.
- **LibDBIcon minimap button**.

### v0.1.0-alpha

Internal scaffold; feature work began.
