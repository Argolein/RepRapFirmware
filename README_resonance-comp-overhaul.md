# Resonance Compensation Overhaul (RRF Branch Notes)

This document summarizes the new motion features and G-code parameters introduced on branch `resonance-comp-overhaul`.

## Scope

- Per-axis input shaping (X/Y) in RepRapFirmware
- Pressure advance smooth time (seconds, Klipper-compatible unit)
- Optional Klipper-like corner limiter via `M566 P2`
- Klipper-like minimum cruise ratio via `M566 R`
- CAN timing hardening for extruder-only moves

## New / Extended G-code Behavior

### `M593` (Input Shaping)

`M593` now supports per-axis configuration.

- `M593 P"zvdd" F40 S0.10`
- Legacy behavior: applies to X and Y together and updates global legacy shaper path (used by remotes/extruders).

- `M593 X P"zvdd" F49.2 S0.10`
- Configure only X axis shaper.

- `M593 Y P"zvdd" F25.6 S0.10`
- Configure only Y axis shaper.

- `M593 X`
- Query X axis shaping config.

- `M593 Y`
- Query Y axis shaping config.

Supported shaper types in this branch include:

- `none`
- `zvd`, `zvdd`, `zvddd`
- `mzv`
- `ei2`, `ei3`
- `custom`

### `M572` (Pressure Advance)

`M572` now supports smooth time in seconds with `T`.

- `M572 S0.03`
- Set PA for current tool.

- `M572 D0 S0.03`
- Set PA for the tool that owns extruder `0`.

- `M572 D0 S0.03 T0.10`
- Set PA plus smooth time (`0.10` seconds).

- `M572 D0`
- Report tool PA, example: `Tool pressure advance: T0 0.0300 (smooth 0.100)`.

Parameter notes:

- `S` = pressure advance value
- `T` = PA smooth time in seconds
- `T` range in this branch: `0.0 .. 0.2`

Compatibility notes:

- `T` is intentionally in seconds so Klipper `pressure_advance_smooth_time` values are directly transferable.
- For extruders not mapped to a tool (`M572 D<n>` fallback), PA may be applied via legacy extruder-shaper path and smooth time is ignored.

### `M566 P` (Jerk Policy)

The new corner logic is enabled with:

- `M566 P2`
- `M566 P2 R0.50`

Behavior:

- `P2` (and higher) keeps existing instant-DV logic and adds an additional junction-deviation-like corner speed limiter for XY corners.
- This is intended to bring corner handling closer to Klipper behavior.

Minimum cruise ratio:

- `R` sets the minimum fraction of move distance that should remain in constant-speed (cruise) phase.
- Range in this branch: `0.00 .. 0.99`
- Default in this branch: `0.50` (same default value as Klipper `minimum_cruise_ratio`)
- Example: `M566 R0.50`

## CAN / Toolboard Notes

- CAN extruder-only moves use hardened scheduling (minimum lead-time guard).
- For remote CAN extruders, legacy-safe shaping behavior is kept to avoid per-axis ambiguity on remotes.
- Capability checks for movement PA snapshot support remain active.

## Recommended Start Point

For CoreXY-style machines with tuned values:

```gcode
M566 P2 R0.50
M593 X P"zvdd" F49.2 S0.10
M593 Y P"zvdd" F25.6 S0.10
M572 D0 S0.03 T0.10
```

Adjust from there based on ringing and corner quality.

## Known Limitations

- PA smooth-time implementation is close in behavior, but not a full mathematical clone of Klipper's integral model.
- In very short decel phases with large smooth time, a small part of the ideal post-smoothing contribution may be skipped to preserve segment safety.

## Build Outputs (Current)

- Mainboard (Mini5+): `Duet3Mini5plus/Duet3Firmware_Mini5plus.bin`
- Mainboard (FMDC): `FMDC_V03/Duet3Firmware_FMDC.bin`
- Toolboard (1LC): `../RRF-Build-Helper/rrf-local/deps/Duet3Expansion/TOOL1LC/Duet3Firmware_TOOL1LC.bin`

Version alignment target: `3.6.2-beta.1` on both mainboard and toolboard.
