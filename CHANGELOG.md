# Broker: MidnightEvents — Changelog

User-facing changes, newest first. Internal and dev-tooling work lives in the
git history, not here.

## [v1.0.3](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v1.0.3) — 2026-06-13

- feat: **Bonus Event Weekly** now recognises the **Arena Skirmishes** variant ("The Arena Calls") — the rotation is complete, so whichever bonus event is active this week is detected and annotated.
- fix: **Saltheril's Soiree** no longer hides on characters below max level — it's playable sub-90, so the row now shows for low-level alts too.

## [v1.0.2](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v1.0.2) — 2026-06-03

- feat: new **Beacon of Hope (Nullaeus Cache)** weekly row — ticks ✓ once you loot a Nullaeus Cache (the nemesis cache from a Beacon of Hope delve run), and resets each week. Replaces the old "coming soon" placeholder.
- fix: **Voidcores transmuted** no longer shows `NN/??` on characters that haven't visited Decimus yet this week — it borrows the season cap from any of your characters who have, so the number is right warband-wide.

## [v1.0.1](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v1.0.1) — 2026-06-03

- feat: optional **Show minimap button** toggle in Settings — hide the minimap icon if you run a broker bar (Bazooka, TitanPanel, ElvUI, …). On by default.

## [v1.0.0](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v1.0.0) — 2026-06-02

First stable release.

- feat: Lady Liadrin's Weekly now covers all twelve pool options; Bonus Event Weekly recognises six of the seven rotating events — whichever you pick is detected and annotated.
- fix: Voidcores transmuted no longer resets to zero each week — it's a season-long total with a rising cap, so the value carries over (shows `NN/??` with a brief "visit Decimus" prompt until your next Voidstorm visit syncs the new cap).
- Delver's Bounty row shows a greyed *coming soon* pending one more piece of in-game verification.

## [v0.9.9-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.9.9-beta) — 2026-06-02

- fix: tooltip no longer errors on hover once the Myth Crests row activates at your weekly reset.
- fix: *A Nightmarish Task* no longer shows a stale `0/3` after you've completed it.
- feat: partially-complete weeklies show a yellow in-progress dot between "not started" and "done" (most useful for Prey Hunts).

## [v0.9.8-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.9.8-beta) — 2026-05-31

- feat: **Myth Crests (Delves)** weekly row tracks crests looted from bountiful delves toward the weekly cap (delve-sourced only; max-level). Greys out as *from next reset* on a fresh or mid-week install, then activates automatically at your next reset.
- feat: World Boss row now matches the other This Week rows visually.

## [v0.9.7-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.9.7-beta) — 2026-05-29

- feat: Alts panel restyled with a dark "smoke-glass" look; the opacity slider now affects only the pane so the edges stay crisp.
- feat: ESC closes the Alts panel.

## [v0.9.6-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.9.6-beta) — 2026-05-27

- feat: **Saltheril's Soiree** weekly row — pick one of four subfactions; the row annotates your pick and shows ✓ on completion (max-level).
- feat: Soiree moved out of Now into its own This Week row.

## [v0.9.5-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.9.5-beta) — 2026-05-27

- feat: Now-section events show their active zone in parentheses (e.g. *Void Assaults (Eversong Woods)*).
- feat: *A Nightmarish Task* appends live objective progress (e.g. `(Prey Hunts, 1/3)`).
- fix: *Abundance: Skinning Den* now reads as *(Zul'Aman)* instead of *(Eversong Woods)*.

## [v0.9.4-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.9.4-beta) — 2026-05-26

- fix: Alts panel auto-sizes to its columns so newer rows no longer spill past the right edge.
- feat: level-gated rows show `—` instead of `✗` on characters that can't yet do them.

## [v0.9.3-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.9.3-beta) — 2026-05-26

- feat: **Prey Hunts** row with a per-tier breakdown (`Normal X/4 · Hard Y/4 · Nightmare Z/4`).
- feat: **Featured Dungeon** weekly, **Hope in the Darkest Corners** (sub-90), **Gnawing Curiosity**, and the Bonus Event *Emissary of War* variant.
- feat: focused tooltip for sub-90 alts; pick annotations appear immediately on accept; tooltip Alts roll-up dropped in favour of the dedicated panel.
- fix: tooltip Lua error from an unaccepted string pattern.

## [v0.9.2-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.9.2-beta) — 2026-05-26

- feat: **Delver's Bounty** and **Arcantina** (`N/9 patrons`) weekly rows.
- feat: Alts panel title bar carries the `(N tracked, M hidden)` summary.

## [v0.9.1-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.9.1-beta) — 2026-05-24

- fix: Mining Voidburrow shows a real countdown instead of bare "active".
- fix: Liadrin's Weekly pick no longer drifts to the wrong pool member.
- fix: abandoning a weekly clears the cached "(picked)" annotation immediately.

## [v0.9.0-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.9.0-beta) — 2026-05-24

- feat: amber **turn in!** indicator when a weekly's objectives are done but not yet handed in.
- feat: right-click an Alts-panel row to hide it, with a *Show hidden characters* toggle (default off).

## [v0.7.0-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.7.0-beta) — 2026-05-24

- feat: Bountiful Delves annotate today's story variant, with a ✓ when the matching achievement criterion is done.
- feat: Void Assault shows the active rotating zone; Bonus Event Weekly row added; Liadrin pool completed.
- feat: colour-tiered This Week annotations and static disambiguation hints.

## [v0.6.0-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.6.0-beta) — 2026-05-16

- feat: **Voidforge progress** section (Voidcores transmuted, Nilhammer empowered) scraped from Decimus in Voidstorm.
- feat: Bountiful Delve story variants with per-delve achievement ✓.

## [v0.5.0-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.5.0-beta) — 2026-05-15

- fix: render paths run untainted — widget arithmetic isolated into a ticker writing a plain cache, fixing taint that broke event-panel widget tooltips, the broker click, and Settings.
- fix: Alts-panel header tooltip uses a private frame so it no longer taints Blizzard tooltips.
- fix: skip Bountiful Delve cache writes in the first 5 minutes after the daily reset (stale rotation snapshot).

## [v0.4.0-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.4.0-beta) — 2026-05-14

- feat: Now / Upcoming / Bountiful Delves accuracy overhaul.
- feat: Impending Void Incursion "X% built" progress with a firing detector.
- feat: zone-map ingest picks up more events (Void Incursion, Abyss Anglers, Prey, zone copies).

## [v0.3.0-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.3.0-beta) — 2026-05-12

- feat: per-character This Week section (World Boss + tracked weekly quests).
- feat: detached Alts panel (Shift-Right-click), Bountiful Delves section, Liadrin pick annotation, native Settings panel.

## [v0.2.0-beta](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.2.0-beta) — 2026-05-12

- feat: first public beta — Now + Upcoming via `C_EventScheduler`, broker bar soonest-event tag, LibDBIcon minimap button.

## [v0.1.0-alpha](https://github.com/darktrine-addons/Broker_MidnightEvents/releases/tag/v0.1.0-alpha) — 2026-05-10

- chore: internal scaffold; feature work began.