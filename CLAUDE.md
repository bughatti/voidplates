# VoidPlates — enemy nameplates

**Status:** v1.0.0, first public release 2026-10-26. Built 2026-10-22 from scratch on Blizzard APIs. See memory `voidplates-voidframes-projects`: written from scratch, never copied from or marketed against another addon.

| File | Role |
|---|---|
| `Core.lua` | Defaults, colors, `VP:Get/Set`, options panel (Esc → Options → AddOns → VoidPlates), `/vplates` |
| `Plates.lua` | One frame per nameplate, parented to Blizzard's plate; hides Blizzard's `plate.UnitFrame` (hooked `Show` + driver `OnNamePlateAdded`) |

**12.x rules used:**
- Health: `SetMinMaxValues(0, UnitHealthMax)` + `SetValue(UnitHealth)` (secret-safe, same as CompactUnitFrame).
- Cast bar: VRT FocusKickBar pattern — `UnitCastingDuration` + `SetTimerDuration`, kick color via `SetVertexColorFromBoolean(notInterruptible, ...)`, important via `C_Spell.IsSpellImportant` → `SetAlphaFromBoolean`.
- Auras: Blizzard filter strings pick them (`HARMFUL|PLAYER|INCLUDE_NAME_PLATE_ONLY`, `HARMFUL|CROWD_CONTROL`, `HELPFUL|RAID_PLAYER_DISPELLABLE`); duration via `C_UnitAuras.GetAuraDuration` → `Cooldown:SetCooldownFromDurationObject`.
- Threat: `UnitDetailedThreatSituation` isTanking → `SetVertexColorFromBoolean` (role-aware).
- Target/focus: compare plate frames (`C_NamePlate.GetNamePlateForUnit("target")`), never `UnitIsUnit` on secrets.
- Raid mark index is secret: texture path built from it → `SetTexture` in pcall.
- Personal resource bar (`player`) and widget-only plates stay Blizzard's.
