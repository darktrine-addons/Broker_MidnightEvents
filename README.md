# Broker: MidnightEvents

A [LibDataBroker](https://www.wowace.com/projects/libdatabroker-1-1) plugin that surfaces World of Warcraft: Midnight world event timers and weekly activity progress in any broker bar.

The single broker button shows the next firing world event in its text and exposes a structured tooltip with three collapsible sections: live event countdowns, the current character's weekly checklist (Prey, world bosses, Soiree, Vault, Patron Orders, …), and a roll-up of alts as they log in.

Retail only. Requires Midnight (Interface 120005+) and a broker host such as Arcana (recommended), ElvUI, Bazooka, Broker2FuBar, or TitanPanel.

## Status

**Pre-alpha — empty scaffold.** The folder structure, addon boilerplate, and design document are in place; no features are wired in yet. See [`design/design.md`](design/design.md) for the full implementation plan.

## Planned Features

- **Live event timers** — Abundance (8 h rotation), Stormarion Assault (30 min), Slayer's Rise PvP rotation (30 min), Bountiful Delve daily reset
- **Weekly checklist** — Prey hunts, world boss lockouts, Saltheril's Soiree, Stormarion weekly quest, Legends of the Haranir, Great Vault progress, Patron Orders per profession
- **Alt roll-up** — passive snapshot of each character's weekly state on login; no other addon required
- **Native Settings panel** — toggle each section and individual events
- **Minimap button** — drag-to-reposition icon via LibDBIcon

## Installation (planned)

The recommended path will be a package manager: **CurseForge app**, **WowUp**, or the **Wago app** — search for "Broker: MidnightEvents" and one-click install.

For manual installation:

1. Download the latest release zip from [GitHub Releases](https://github.com/darktrine-addons/Broker_MidnightEvents/releases), CurseForge, or Wago.io
2. Extract the `Broker_MidnightEvents` folder into your addons directory:
   - **Windows**: `World of Warcraft\_retail_\Interface\AddOns\`
   - **macOS**: `Applications/World of Warcraft/_retail_/Interface/AddOns/`
3. Restart World of Warcraft or `/reload`

## Technical Details

### File Structure

- `Broker_MidnightEvents.toc` — Addon metadata and load order
- `Core.lua` — Broker object, event handling, tooltip, click logic
- `Settings.lua` — Saved-variable defaults and Settings panel registration
- `Locales/Locales.xml` — Locale file manifest (enUS baseline)
- `Libs/` — bundled libraries: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0
- `design/` — design documents and research notes (excluded from release zips)

### Saved Variables

- `Broker_MidnightEventsDB` — all settings plus the LibDBIcon minimap position sub-table (`minimapIcon`)

## Compatibility

- **WoW Version**: Retail (Midnight, Interface 120005+)
- **Dependencies**: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0 (all bundled)
- **Broker display**: any LDB-compatible display (ElvUI, Bazooka, Broker2FuBar, TitanPanel, etc.)

## Contributing

Issues and pull requests are welcome.

## License

Licensed under [GPL-2.0](https://www.gnu.org/licenses/gpl-2.0.html). The full license text is in the `LICENSE` file in the source distribution.
