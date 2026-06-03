# Broker: MidnightEvents

> ✅ **Stable (v1.0), actively maintained.** Daily-driver stable across multiple characters. Midnight is a living expansion, so new weeklies and the odd quest-ID shift get folded in as they appear. Feedback, bug reports, and feature ideas welcome on the [issue tracker](https://github.com/darktrine-addons/Broker_MidnightEvents/issues).

**A compact world-event timer + per-character weekly checklist for WoW Midnight, served through any LibDataBroker host.**

The broker bar always shows the most-urgent event — a wave countdown, a "FIRING NOW!" for the Void Incursion, a Skinning Den firing in 12 minutes. Hover the bar (or open the minimap button) and a structured tooltip unfolds: what's happening right now, what's coming in the next 24 hours, today's bountiful Delve rotation with its rotating story variant, your character's full weekly checklist (world boss, the Saltheril's Soiree / Lady Liadrin / Bonus Event picks, Featured Dungeon, Prey Hunts, Beacon of Hope, Arcantina, the myth-crest delve grind, and more), and Voidforge progress. A separate smoke-glass panel rolls the same weekly state up across every alt.

Most rows are annotated with the detail you'd otherwise alt-tab for — which subfaction or dungeon you picked this week, the active Void Assault zone, your per-tier Prey hunt counts, your crest progress toward the weekly cap — and rows you can't do yet (max-level weeklies on a levelling alt) hide themselves instead of nagging.

Retail only. Requires Midnight (Interface 120005+). Works with any LibDataBroker host (Arcana, ElvUI, Bazooka, Broker2FuBar, TitanPanel, …); minimap-button entry point is built in for users who don't run a broker bar.

## Is this for you?

**Yes, probably** — if you:

- Want one-glance answers to "what world event is next" and "what haven't I done this week" without alt-tabbing to a browser
- Run multiple characters and want their weekly state visible without logging into each
- Like compact at-a-glance UIs that get out of the way; tooltip only opens on hover
- Already use a broker bar host *or* are happy with a minimap button

**Probably not** — if you:

- Want a comprehensive checklist of *every* weekly (Patron Orders, professions, housing, M+, vault breakdown). Use Midnight Routine ([Curseforge](https://www.curseforge.com/wow/addons/midnight-routine)|[Wago](https://addons.wago.io/addons/QN53j5KB)|[GH](https://github.com/LoyalFTW/Midnight-Routine/releases)) for that breadth; this addon is intentionally focused on **events and the weeklies tied to them**, designed to coexist
- Want a separate always-visible window per activity (this is a single hover tooltip)
- Run only Classic / non-retail

## Features

### Broker bar
- **Soonest event tag** — auto-picks the most-urgent of: an event firing imminently (`Stormarion Assault next 12m`), an event genuinely happening now (`Abundance: Mining Voidburrow 42m left`), a building event close to firing (`VoidIncursion 94% built`), or a confirmed live firing (`VoidIncursion FIRING NOW!` in amber).
- **Weekly progress** chunk — `Weeklies 3/7` (or `All done` once everything's ticked).
- Both halves toggleable independently in the Settings panel.

### Tooltip sections
- **Now** — currently-firing events, sorted by urgency: firing > closer-to-firing progress bars > soonest countdowns > untimed continuous (Stormarion Assault between waves, Legends of the Haranir, etc.). Rotating events show their active zone in parentheses even when you're elsewhere — *Void Assaults (Eversong Woods)*, *Saltheril's Soiree (Eversong Woods)*.
- **Upcoming (next 24h)** — scheduler-driven next fires, ordered by when they happen (matches Blizzard's events panel order).
- **Bountiful Delves (today)** — today's rotation with each delve's active **story variant** in parentheses; a green ✓ next to the story name means this character has the matching achievement criterion (per-delve "Stories" achievement, 61724–61733) already completed.
- **This Week (CharName)** — the per-character weekly checklist, the heart of the addon. Tracks World Boss, Abundant Offerings, Stand Your Ground, A Nightmarish Task (with live `x/3` objective count), Lady Liadrin's Weekly, Bonus Event Weekly and Saltheril's Soiree (each annotated with the choice you picked), Featured Dungeon (with this week's dungeon), Void Assault (active zone), Lost Legends, Gnawing Curiosity, Beacon of Hope, Arcantina (with lifetime patron progress), Prey Hunts (per-tier `Normal x/4 · Hard x/4 · Nightmare x/4`), and the **Myth Crests (Delves)** counter toward the weekly cap. Outstanding rows sit up top in white, completed rows dim with a green ✓, and an amber `turn in!` state flags weeklies whose objectives are done but the quest is still in your log. Rows you can't do yet — max-level weeklies on a levelling alt — hide automatically rather than showing a permanent ✗; on sub-90 alts a Halduron levelling weekly (*Hope in the Darkest Corners*) takes the Featured Dungeon slot.
- **Voidforge progress** — per-character N/M counters scraped from Decimus's bars in Voidstorm: *Voidcores transmuted* (weekly bonus-roll allowance), *Nilhammer empowered* (lifetime 0–4, gates the Ascendant Nilhammer upgrade). Only populates after the character has been near Decimus once; persists across sessions.

Every tooltip section can be toggled off individually in Settings.

### Detached Alts panel
- **Shift-Right-click** the broker (or minimap button) opens a scrollable per-alt grid showing every tracked character's weekly state at a glance.
- Modern dark **smoke-glass** styling — solid backdrop, thin amber border, amber title. Auto-sizes to the number of tracked weeklies, and closes on **ESC** or its close button.
- Class-coloured names, abbreviated column headers (hover for the full label), drag-to-reposition, geometry persists. Weeklies a character can't do yet show `—` instead of a misleading ✗.
- **Right-click a row to hide** that character; a *Show hidden characters* toggle in Settings brings them back dimmed for un-hiding.
- Background opacity tunable in Settings (10–100 %, default 60 % — the pane goes translucent while the border stays crisp).

### Settings panel
- *Escape → Options → AddOns → Broker: MidnightEvents*, or **Right-click** the broker / minimap button.
- Per-section visibility toggles for every tooltip section (Now / Upcoming / Bountiful Delves / This Week / Voidforge).
- World Boss row visibility in the This Week section.
- Broker bar split toggles (show weekly progress / show next-event tag).
- *Show minimap button* toggle (default on) — turn the minimap icon off if you run a broker bar.
- Alts panel background opacity slider.
- *Show hidden characters* toggle paired with the right-click-to-hide gesture in the Alts panel.

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

Issues and pull requests are welcome on [github](https://github.com/darktrine-addons/Broker_MidnightEvents/)

## License

Licensed under [GPL-2.0](https://www.gnu.org/licenses/gpl-2.0.html). The full license text is in the `LICENSE` file in the source distribution.

## Changelog

See [CHANGELOG.md](https://github.com/darktrine-addons/Broker_MidnightEvents/blob/main/CHANGELOG.md) for the full version history. The notes for each release are also posted with the download on CurseForge and Wago.
