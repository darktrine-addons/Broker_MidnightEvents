# Broker_MidnightEvents — Harvest Notes

Provenance log for the weekly-quest IDs that appear in `Data.lua`. Kept in
`design/` (excluded from release packaging via `.pkgmeta` `ignore: design`)
so the shipped addon stays lean while the curation history remains
auditable here.

Update this file when:
- A harvest pass adds, promotes, or scopes-out a questID in `Data.lua`.
- A prior assumption is corrected (note the wrong assumption + correction).
- Wowhead/wiki crosschecks are run.

## DevHarvest workflow

`DevHarvest.lua` writes two SavedVariables (declared in the TOC):

- `Broker_MidnightEventsHarvest` — per-char snapshot of active + completed
  quest IDs above ID 85000. Overwritten on every refresh; mirrors the live
  quest log.
- `Broker_MidnightEventsQuestCatalogue` — account-wide write-once index
  keyed by questID, capturing first-acceptance metadata (giver, source,
  zone, frequency, title). Accumulates across every char that accepts a
  new high-ID quest.

To run a harvest pass:

1. Log target char, `/reload` to flush SavedVariables.
2. Accept new weeklies (Silvermoon hub is the densest source).
3. `/reload` again to flush.
4. Read `Broker_MidnightEvents.lua` in
   `WTF/Account/<ACCOUNT>/SavedVariables/`.
5. Curate: Wowhead-crosscheck each new questID, decide in-scope / candidate
   / OOS, and update `Data.lua` + this file.

Pre-release cleanup (before tagging a new version):

- Drop `DevHarvest.lua` from the TOC load order (file stays in repo).
- Drop `Broker_MidnightEventsHarvest` and
  `Broker_MidnightEventsQuestCatalogue` from the TOC `## SavedVariables`
  line.

## 2026-05-12 — first harvest pass (Midnight 12.0.5/12.0.7)

Chars contributing: Elune/Artherio (Silvermoon hub accept stream),
Elune/Sundowner (PEW scan of pre-existing weeklies plus Void Assault
auto-push), Elune/Shatanaris (cross-check reload).

### Promoted to ns.weeklies

| questID | Title | Slot | Basis |
|---|---|---|---|
| 89507 | Abundant Offerings | Abundance weekly | Sundowner pew-scan; objective "Earn 20,000 points in Abundance harvests" matches the Tier 1 Abundance event. |
| 94581 | Stand Your Ground | Stormarion Assault weekly | Wowhead-confirmed as the Voidstorm WQ tied to the Stormarion Assault event. |
| 94446 | A Nightmarish Task | Prey NM tier weekly | Wowhead-confirmed "Complete 3 Nightmare Hunts in Prey"; matches design's NM 3/3 objective. |
| 89268 | Lost Legends | Haranir scenario | Pre-existing. |

### Architectural finding: Lady Liadrin is a choice pool, not an umbrella

A prior note in `Data.lua` had claimed the `Midnight: <X>` family (93769,
93889, 93892, 93909, 93911, 94457, 95842) were one-time intro/unlock
quests that flagged permanently. That was wrong. They are Liadrin's
weekly *choice pool*: she offers ~4 of the 7 per char per week;
completing one locks the others on that char. All freq=3, all reward
Spark of Radiance + Apex Cache.

This week (identical for both Artherio and Shatanaris): 93769, 93889,
93909, 93911 were the four offered. The other three (93892, 94457,
95842) are extant on Wowhead and presumably surface in a different
rotation week — re-harvest at next reset.

Cross-check (Shatanaris reload): added 5 stale pew-scan rows and 0 new
accepts. Write-once dedupe absorbed her Liadrin acceptances into
Artherio's catalogue entries, confirming the IDs are real and the
offered subset was identical for both chars.

### Architectural finding: Aethas Sunreaver slot is OOS

Artherio's accept on the PvP slot was 93613 "A Savage Path Through
Time" (freq=2, giver Archmage Aethas Sunreaver). Wowhead classifies it
as the Timewalking weekly (5 TW dungeons). Design originally scoped IN
"A Call to Battle" off Aethas, but if Aethas's slot rotates through
TW + PvP + other non-event content, the slot is not event-tied as a
whole. Decision (May 2026): move the entire Aethas slot to out-of-scope,
regardless of which variant gives at a given reset.

### Scoped out

| questID | Title | Reason | Source |
|---|---|---|---|
| 93613 | A Savage Path Through Time | Timewalking weekly (Aethas slot) | Artherio accept (Aethas Sunreaver) |
| 93697 | Shimmering Melodies | Profession/enchanting (20 Eversinging Dust → Dolothos) | Artherio accept (Dolothos) |
| 93755 | Den of Nalorakk | Dungeon weekly (Zul'Aman boss credit) | Artherio accept (Halduron Brightwing) |
| 94790 | Research Console: Exploring the Void | Generic Voidstorm WQ weekly | Artherio pew-scan |
| 95413 | Community Engagement | Housing weekly (Vaeli endeavor trader) | Artherio accept (Vaeli) |

### Candidate notes (sample size & basis)

- **91700 Darkness Unmade** — freq=2: eliminate 2 rares in Stormarion
  Citadel, drops Stormarion Core (suggested 3 players). Sample size 1
  (Artherio pew-scan). May be a bonus Stormarion weekly worth its own
  row; needs another char to confirm.
- **95468 Hope in the Darkest Corners** — freq=2: complete WQs +
  Dungeons + Delves in Midnight zones, rewards Quel'Thalas Adventurer's
  Cache. Generic adventurer umbrella; most likely OOS but held pending
  final scope call. Source: Sundowner pew-scan.

### World boss history

An earlier attempt used 93913 "Midnight: World Boss" as an umbrella
quest, on the theory it would flag once any world boss was killed. It
flagged on Shatanaris even though she had killed no boss that week —
i.e. it really was a one-time intro/unlock, not a weekly tracker (this
category was real, separate from the Liadrin choice pool). Replaced
with per-boss kill-credit quests (92560 / 92123 / 92034 / 92636). Their
weekly-reset behaviour is still TBD; confirm at next reset.

## Remaining harvest gaps

1. **Saltheril's Soiree direct weekly** ("Fortify the Runestones",
   Eversong) — quest ID still unknown. 93889 is the Liadrin-umbrella
   variant, not the direct weekly.
2. **Bountiful Delve weekly** — unknown ID.
3. **Prey contract IDs** — 12 individual contracts (4 zones × 3 tiers)
   for the per-tier N/H/NM display.
4. **Tier 3 currency IDs** — Shards of Dundun, Field Accolades,
   Latent Arcana.
5. **Liadrin pool — week-2 cross-check** — does the offered 4-of-7
   rotate? If yes, new pool members may exist beyond the 7 known.
6. **Void Assault zone rotation** — confirmed 94385 (Eversong) +
   94386 (Zul'Aman). Harandar/Voidstorm variants likely exist; harvest
   when rotation lands.

## Candidate weeklies (not yet promoted)

Harvested IDs whose classification is still uncertain (sample size 1, scope
ambiguous, etc.). Promote to `ns.weeklies` in `Data.lua` when ready.

- `91700` **Darkness Unmade** — freq=2: kill 2 rares in Stormarion Citadel,
  drops Stormarion Core. Distinct from Stand Your Ground; may merit its own
  row or fold into a Stormarion umbrella.
- `95468` **Hope in the Darkest Corners** — freq=2: complete WQs / Dungeons /
  Delves in Midnight zones; rewards Quel'Thalas Adventurer's Cache. Likely
  OOS umbrella (Midnight Routine territory), pending final scope call.

## Out-of-scope (ceded to Midnight Routine)

Harvested IDs that map to design out-of-scope content. Listed for reference
only; uncomment back into Data.lua only if scope changes.

| Quest ID | Title                                       | Reason                            |
|----------|---------------------------------------------|-----------------------------------|
| 93613    | A Savage Path Through Time                  | Timewalking weekly (Aethas slot)  |
| 93697    | Shimmering Melodies                         | Profession/enchanting             |
| 93755    | Den of Nalorakk                             | Dungeon weekly                    |
| 94790    | Research Console: Exploring the Void        | Generic Voidstorm WQ weekly       |
| 95413    | Community Engagement                        | Housing weekly (Vaeli)            |
