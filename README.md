# Broker: MidnightEvents

> 🚧 **Beta in active development.** All listed features work and the addon is daily-driver stable across multiple characters, but the surface is still evolving — expect occasional polish-level changes between releases. Feedback, bug reports, and feature ideas welcome on the [issue tracker](https://github.com/darktrine-addons/Broker_MidnightEvents/issues).

**A compact world-event timer + per-character weekly checklist for WoW Midnight, served through any LibDataBroker host.**

The broker bar always shows the most-urgent event — a wave countdown, a "FIRING NOW!" for the Void Incursion, a Skinning Den firing in 12 minutes. Hover the bar (or open the minimap button) and a structured tooltip unfolds: what's happening right now, what's coming in the next 24 hours, today's bountiful Delve rotation with its rotating story variant, your character's full weekly checklist (world boss, the Saltheril's Soiree / Lady Liadrin / Bonus Event picks, Featured Dungeon, Prey Hunts, Delver's Bounty, Arcantina, the myth-crest delve grind, and more), and Voidforge progress. A separate smoke-glass panel rolls the same weekly state up across every alt.

Most rows are annotated with the detail you'd otherwise alt-tab for — which subfaction or dungeon you picked this week, the active Void Assault zone, your per-tier Prey hunt counts, your crest progress toward the weekly cap — and rows you can't do yet (max-level weeklies on a levelling alt) hide themselves instead of nagging.

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
- **Now** — currently-firing events, sorted by urgency: firing > closer-to-firing progress bars > soonest countdowns > untimed continuous (Stormarion Assault between waves, Legends of the Haranir, etc.). Rotating events show their active zone in parentheses even when you're elsewhere — *Void Assaults (Eversong Woods)*, *Saltheril's Soiree (Eversong Woods)*.
- **Upcoming (next 24h)** — scheduler-driven next fires, ordered by when they happen (matches Blizzard's events panel order).
- **Bountiful Delves (today)** — today's rotation with each delve's active **story variant** in parentheses; a green ✓ next to the story name means this character has the matching achievement criterion (per-delve "Stories" achievement, 61724–61733) already completed.
- **This Week (CharName)** — the per-character weekly checklist, the heart of the addon. Tracks World Boss, Abundant Offerings, Stand Your Ground, A Nightmarish Task (with live `x/3` objective count), Lady Liadrin's Weekly, Bonus Event Weekly and Saltheril's Soiree (each annotated with the choice you picked), Featured Dungeon (with this week's dungeon), Void Assault (active zone), Lost Legends, Gnawing Curiosity, Delver's Bounty, Arcantina (with lifetime patron progress), Prey Hunts (per-tier `Normal x/4 · Hard x/4 · Nightmare x/4`), and the **Myth Crests (Delves)** counter toward the weekly cap. Outstanding rows sit up top in white, completed rows dim with a green ✓, and an amber `turn in!` state flags weeklies whose objectives are done but the quest is still in your log. Rows you can't do yet — max-level weeklies on a levelling alt — hide automatically rather than showing a permanent ✗; on sub-90 alts a Halduron levelling weekly (*Hope in the Darkest Corners*) takes the Featured Dungeon slot.
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

Issues and pull requests are welcome.

## License

Licensed under [GPL-2.0](https://www.gnu.org/licenses/gpl-2.0.html). The full license text is in the `LICENSE` file in the source distribution.

## Changelog

### v0.9.9-beta — crash fix + weekly-row polish

**Fixes:**
- **Tooltip no longer errors on hover** once the Myth Crests row goes active at your weekly reset. (A sort-ordering bug surfaced the moment a partly-filled crest counter sat alongside the other rows.) If you saw a `Core.lua` error hovering the broker, this clears it.
- **A Nightmarish Task** no longer shows a stale `0/3` after you've completed it — the count only appears while the quest is in your log; once done the row just shows the ✓.

**Improvements:**
- **Partially-complete weeklies** now show a yellow in-progress dot instead of the red ✗, a visible step between "not started" and "done" (most useful for Prey Hunts mid-grind).

### v0.9.8-beta — Myth crest delve counter

**New features:**
- **Myth Crests (Delves)** weekly row tracks your progress toward the weekly cap of mythic crests looted from bountiful delves. Counts only delve-sourced crests — raid and dungeon crests don't count. Max-level only.
- Because the count can only be tallied while the addon is loaded, the row greys out as *from next reset* on a fresh or mid-week install and activates automatically at your next weekly reset, so it never shows a misleading partial total.

**Improvements:**
- **World Boss row** now matches the other This Week rows visually — the boss name sits as a grey parenthetical in the label, with just the ✓/✗ in the value column.

### v0.9.7-beta — Alts panel restyle

**Improvements:**
- **Alts panel adopts a modern dark "smoke-glass" look** — solid dark backdrop, thin amber accent border, amber title, subtle separators under the title and column header. The background-opacity slider now only affects the pane, so the edges stay crisp at any transparency.
- **ESC closes the Alts panel**, with a small `esc` hint next to the close button.

### v0.9.6-beta — Saltheril's Soiree row

**New features:**
- **Saltheril's Soiree** is now a tracked weekly in This Week. Pick one of four subfactions from Lord Saltheril (Magisters / Blood Knights / Farstriders / Shades of the Row); the row annotates `(<subfaction> picked)` once the Fortify the Runestones variant lands in your log, and ✓ when it's complete. Sub-90 alts skip the row (gated on max level).

**Improvements:**
- **Soiree drops out of Now** alongside Prey — it's a weekly progression activity, not a timed event, so the dedicated This Week row owns its display.

### v0.9.5-beta — zone labels in Now + objective counts + Skinning Den fix

**New features:**
- **Now-section events show their active zone in parentheses** — e.g. `Void Assaults (Eversong Woods)`, `Saltheril's Soiree (Eversong Woods)`. The label fills in even when you're outside the active zone (uses the canonical-zone signal from the POI data). Events whose name already carries the zone (Abundance variants) skip the suffix to avoid `Abundance: Mining Voidburrow (Voidstorm)` redundancy.
- **A Nightmarish Task** now appends live objective progress: `A Nightmarish Task (Prey Hunts, 1/3)`. Reads from the active quest log; falls back to `0/3` when the quest isn't picked up yet.

**Fixes:**
- **Abundance: Skinning Den** now correctly reads as `(Zul'Aman)` instead of `(Eversong Woods)`. Blizzard cross-lists the POI in adjacent zones' map data; we now honour the `isPrimaryMapForPOI` flag so the canonical zone wins.

### v0.9.4-beta — Alts panel polish

**Improvements:**
- **Alts panel auto-sizes to its columns** so the recently-added rows (Featured Dungeon, Hope, Prey Hunts, Gnawing Curiosity, Delver's Bounty, …) no longer spill past the right edge.
- **Level-gated rows show `—` (em-dash) instead of `✗`** on characters that can't yet do them — sub-90 alts no longer read as having "missed" the World Boss, Liadrin's Weekly, etc.

### v0.9.3-beta — more weeklies + smarter Prey + level-aware tooltip

**New features:**
- **Prey Hunts** now lives in This Week with a full per-tier breakdown: `Normal X/4 · Hard Y/4 · Nightmare Z/4`. Done ✓ once you've hit the unlock-tier cap (4 / 8 / 12 hunts). Tiers above your unlock are hidden so the row stays tight on levelling alts. Replaces the bare `active` placeholder under Now.
- **Featured Dungeon** weekly tracking Halduron Brightwing's "do one Midnight dungeon" — renders as `Featured Dungeon (<dungeon name>)` once you've picked up this week's variant. Eight dungeons rotate one per week; any difficulty counts, Follower included.
- **Hope in the Darkest Corners** (sub-90 row from Halduron) — surfaces while levelling, vanishes the moment you hit 90 and Halduron switches to Featured Dungeon.
- **Gnawing Curiosity** weekly — Naleidea Rivergleam's auto-credited weekly fired by your warband's first T4+ delve completion. Voidlight Marl reward.
- **Bonus Event Weekly** now recognises **Emissary of War** (Mythic Dungeons variant) alongside the existing Delves and Battle variants.

**Improvements:**
- **Sub-90 alts get a focused tooltip.** World Boss, A Nightmarish Task, Lady Liadrin's Weekly, Bonus Event Weekly, and Featured Dungeon are hidden on characters below max level instead of showing as permanent ✗.
- **Picks annotation appears immediately on quest accept.** Previously you had to `/reload` after picking up a Liadrin choice or Featured Dungeon for the row to display which one you took.
- **Tooltip dropped the Alts roll-up section.** Shift-RightClick still opens the dedicated Alts panel, which carries the same information with better fidelity.

**Fixes:**
- Tooltip Lua error from a pattern WoW's parser doesn't accept. Tooltip rendering should never surface a script error again from this path.

### v0.9.2-beta — new weeklies + polish

**New features:**
- **Delver's Bounty** weekly row in This Week. Tracks the Beacon of Hope → Nullaeus → Delver's Bounty → Hidden Trove chain. Done state flips on Hidden Trove turn-in.
- **Arcantina** weekly row, with `(N/9 patrons)` lifetime annotation. Weekly side tracks the visit (quest 93767, resets every week); the patron count is your running progress across the nine-quest collection that awards the "Old Soldiers" achievement.

**Improvements:**
- **Alts panel** title bar now carries the `(N tracked, M hidden)` summary directly. The header row gets its rightmost column back, no longer overlapping the floating count.

### v0.9.1-beta — bugfix refresh

**Fixes:**
- **Mining Voidburrow timer** now shows a real countdown instead of bare "active." Reads the timer from the POI's tooltip widget when Blizzard's seconds-left API returns nil.
- **Liadrin's Weekly pick** no longer drifts to the wrong pool member on characters who have rotated through picks over multiple weeks. Derives strictly from the active quest log.
- **Abandoning a weekly** now clears the cached "(picked)" annotation immediately, instead of waiting until turn-in.

### v0.9.0-beta — feature-complete

Polish + last functional gaps before v1.0 stable.

**New features:**
- **"Turn in!" indicator** on This Week rows. When a weekly's objectives are complete but the quest is still in the active log (you've done the work, haven't visited the NPC), the row renders amber `turn in!` between the in-progress and done states. Catches the "I thought I was done" confusion when objectives flip but `IsQuestFlaggedCompleted` waits on the handoff.
- **Right-click any character row** in the detached Alts panel to hide it. Hidden characters disappear from the panel; a `"N hidden"` count surfaces in the panel summary. Companion *Settings → Alts panel → "Show hidden characters"* toggle (default off) brings them back as extra-dim rows that right-click un-hides. Useful for decluttering long-inactive alts without losing their data.

### v0.7.0-beta

**New features:**
- **Bountiful Delves** now annotate each row with today's active **story variant** in parentheses; a green ✓ next to the story name means this character has the matching `<Delve> Stories` achievement criterion (61724–61733) completed. Fuzzy-matches story names against criterion text (Levenshtein ≤ 2) so Blizzard typos in widget data still resolve to the correct criterion.
- **Void Assault** row shows the active rotating zone — *"Void Assault (Zul'Aman)"* / *"Void Assault (Eversong Woods)"* — instead of the generic "(active zone)" placeholder.
- **Bonus Event Weekly** row tracking Archmage Aethas Sunreaver's weekly bonus-event quest (Cache of Quel'Thalas Treasures rewards). Same "(picked, N/M)" annotation as the Liadrin row.
- **Lady Liadrin's pool** completed with the two missing pool members (`93890 Midnight: Abundance`, `93910 Midnight: Prey`).

**Improvements:**
- **Color-tiered This Week annotations:** row name (white) — actionable label; static hint + parens + dynamic-annotation text (grey) — context; progress N/M (warm gold) — variable data the eye should land on.
- **Static disambiguation hints** on opaque-named rows: *Stand Your Ground (Stormarion Assault)*, *A Nightmarish Task (Prey Hunts)*, *Lost Legends (Legends of the Haranir)*.
- **Void Incursion** progress + firing detection now matches by event name — every zone variant gets the same widget probe and heuristic without per-POI hardcoding.

**Fixes:**
- Pool-pick detection is fully self-healing — re-derives every refresh from current game state, so characters who completed a pool member before the feature was deployed retroactively display the correct annotation.

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
