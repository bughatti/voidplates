# Changelog

## [1.0.3] — 2026-11-07

### Fixed
- **Enemy player plates in groups could still error** ("bad argument #3 to SetVertexColorFromBoolean"), seen in dungeons. Some addons replace the game's class colors with colors that have no opacity value. VoidPlates now always uses its own complete copy of each class color.

## [1.0.2] — 2026-11-06

### Fixed
- **Enemy player plates could error** when another addon changes the game's class colors; VoidPlates now uses its own copy of the color.

### Added
- **WoW Forever** support.

## [1.0.1] — 2026-11-02

### Changed
- **Settings are per character.** Each character keeps its own VoidPlates settings, and a new character starts with the settings of the one you played last, so nothing resets when you update. If you also run a Void addon with the hub icon by your minimap (VoidBags, VoidAH, VoidGather, ...), right-click it and pick **Copy settings from...** to take another character's settings. Saved profiles stay shared, so any character can load them.

## [1.0.0] — 2026-10-26

First public release.

### Casts
- Cast bar colored by whether you can kick it (green) or not (grey).
- Kick flash: the plate pulses yellow when a kickable cast starts and turns red past halfway.
- Who the cast is aimed at, in their class color, and a white frame when it's aimed at you.
- Pink edge on casts Blizzard marks as important. Casting plates move to the front.

### The mob
- Health percent, and an optional short health number.
- Level (colored by difficulty) and an elite / rare icon beside the name.
- Colors by mob type (caster, mini-boss, boss) and by threat. Raid markers.

### Auras
- Your debuffs with timers and stacks, crowd control, purgeable buffs and enrages, and the enemy buffs Blizzard highlights.

### Less clutter
- Target arrows on your target, other plates faded.
- Small plates for pets, totems, guardians and minor mobs.
- Optional target / focus outline.

### Setup
- Profiles (save, load, delete) and reset to defaults.
- Plate, cast bar, name and aura sizes. Blizzard's clickable-area and stacking settings in the same panel.
