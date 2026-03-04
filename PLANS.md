# PLANS.md

## Objective
Port Klipper-style per-axis input shaping (resonance compensation) to RepRapFirmware so X and Y can be configured independently via `M593`, while keeping current performance constraints on Duet3 Mini5+ and Duet 1LC tool board.

## Open questions
- (none)

## Approved plan
- Review current input shaping pipeline (`AxisShaper`, `Move`, `DDA`, segment generation) to identify all places that assume a single shaper instance.
- Extend the data model to hold per-axis shapers (X/Y only) and expose/report them in the object model.
- Extend `M593` parsing to accept axis letters; behavior:
  - No axis specified: apply to both X and Y (backward compatible).
  - Axis specified: apply only to that axis.
  - Reject invalid axis letters or unsupported axes.
- Update move preparation and segment generation to use the axis-specific shaper for each axis during shaping calculations, and compute the required prepare-advance time as the max of the active axis shapers for the move.
- Update any CAN-related input shaping paths according to the resolved open question.
- Add/adjust tests or debug checks where available; at minimum add a config example or sanity check path for `M593` axis selection.

## Implemented Features (This Branch)
- Per-axis input shaping via `M593`:
  - `M593 X ...` and `M593 Y ...` configure axes independently.
  - `M593` without axis keeps legacy behavior (apply to both X+Y and keep global shaper path for remotes/extruders).
- Per-axis shaping integration in motion pipeline:
  - Axis-specific shapers are used during segment generation.
  - Shared-motor kinematics (CoreXY/CoreXZ/etc.) are split into Cartesian X/Y shaping contributions before merge.
- Phase-centered shaping:
  - Per-axis phase advance is computed from impulse centroid and applied to start-time alignment.
  - Extruder phase is coupled to weighted X/Y phase advance for better sync with shaped XY motion.
- CAN path hardening/compatibility:
  - CAN extruder-only moves keep legacy-safe behavior (no late shaping on remote move frame).
  - Extruder-only CAN scheduling includes minimum lead-time guard for transport jitter.
  - Capability guard for movement PA snapshot support remains active.
- Pressure advance improvements (`M572`):
  - Per-tool PA storage and per-move snapshotting.
  - `M572 T<seconds>` added for PA smooth time (seconds, Klipper-compatible unit, range `0.0..0.2`).
  - `M572 S... T...` parsing fixed to handle both parameters together reliably.
- Lookahead/cruise improvements (`M566 R`):
  - Added Klipper-like minimum cruise ratio parameter `R` to `M566` (range `0.00..0.99`, default `0.50`).
  - Planner integration in both `DDA::DoLookahead` and `DDA::RecalculateMove` to limit excessive accel/decel-only phases and preserve a minimum cruise portion on XY moves.
- Crash prevention fixes for segment overlap:
  - PA smoothing pre-segment cannot start before move start.
  - If a time-shifted segment still overlaps an executing segment, insertion is clamped to executing segment end (no emergency halt).
  - PA smoothing post-segment (decel phase) is now clamped to not start at or after the move end time, preventing segment insertion into the next queued move's territory (see `Move::AddLinearSegments`).
- Code-review fixes (2026-03-04, second session):
  - `GCodes.cpp`: Fixed indentation inconsistency in `DoStraightMove` and `DoArcMove` where PA snapshot lines had one extra tab level (cosmetic but tracked to prevent future merge confusion).
  - `Move2.cpp` (`M572 D<n>` fallback): When `D<n>` specifies an extruder not assigned to any tool, PA is now applied directly to the extruder shaper instead of returning an error. This restores backward compatibility for bare-extruder configs (`M572 D0 S0.05` without a defined tool). PA smooth time (`T`) is silently ignored in the fallback path since it is tool-level state.
  - `DDA.cpp` (`hasRemoteAxisDrivers`): The remote-driver scan now only checks X and Y axes (index 0 and 1). Previously any CAN driver on any axis (e.g. CAN-connected Z) would disable per-axis XY split shaping, even though Z drivers are irrelevant to XY shaping semantics.

## Current Status
- Code status: feature-complete for planned scope, with additional safety hardening and code-review fixes applied.
- Validation status: all fixes compile; hardware re-validation required after this session's changes (see Handoff).
- Known residual gap vs Klipper: PA smooth-time math is still an approximation in RRF (not full Klipper integral model), especially relevant for remote CAN extrusion timing edge cases.
- Known minor gap: if PA smooth time exceeds the decel phase duration, the post-segment is skipped and the effective PA contribution is ~75% instead of 100% for that phase end. Acceptable for typical smooth time values (≤0.04 s).

## Implementation status
- [ ] Not started
- [x] In progress
- [ ] Done (pending on-printer validation after latest crash fix)

## Decisions
- Use existing `M593` and add axis selection; no new G-code.
- Scope is X/Y only.
- Keep current list of shaper types (no new types).
- Keep legacy global shaper behavior for CAN expansion updates; axis-specific changes do not alter remote shaper updates.
- Extruders and remotes continue to use the legacy/global shaper to avoid per-axis ambiguity.
- For CAN extruder-only moves, disable late input shaping in the CAN movement frame and track those extruder segments locally without shaping to avoid flow artefacts when X/Y shapers differ.
- For shared-motor kinematics (e.g. CoreXY), split each motor move into Cartesian X and Y contributions and apply the corresponding axis shaper to each contribution before segment merge, then reconcile exact motor step totals.
- Apply a per-axis phase advance (impulse centroid) so shaped motion is time-centred across move boundaries; keep this disabled for axis moves with remote CAN drivers to preserve legacy remote timing semantics.
- For extruder timing coupling, shift extruder segment start by a direction-weighted XY phase advance and send CAN extruder-only movement frames at that shifted start time to keep PA/extrusion aligned with phase-centred XY motion.
- Add Klipper-style PA smoothing control via `M572 T<seconds>` (range `0.0..0.2`), stored per tool and snapshotted per move.
- PA smoothing value is in seconds so Klipper `pressure_advance_smooth_time` values can be transferred directly.
- `M572` now safely parses combined `S` and `T` in one command (`M572 S... T...`) without parameter-order ambiguity.
- `M566 R` introduces minimum cruise ratio control with Klipper-compatible semantics (default `0.50`), scoped to XY lookahead/recalculation where it improves print quality most.
- Safety fix for PA smoothing: do not insert smoothing segments before the move start time; this prevents "Code 3 move error" overlap with already-executing segments.
- Safety hardening in segment insertion: if a time-shifted segment still requests an overlap with an executing segment, clamp insertion start to executing-segment end instead of halting.
- PA post-segment boundary: decel PA post-segment is skipped if it would start at or after the move end time, preventing insertion conflicts with the next queued move.
- `M572 D<n>` backward compatibility: extruders without a tool fall back to direct extruder-shaper update (legacy path); smooth time (`T`) is ignored in that case.
- `hasRemoteAxisDrivers` scope: only X and Y axis CAN drivers disable per-axis XY split shaping; other CAN axes (Z, etc.) are irrelevant.
- Indentation in `GCodes.cpp` `DoStraightMove`/`DoArcMove` PA snapshot block corrected.

## Handoff
- Agent: Claude Code (Sonnet 4.6)
- Date: 2026-03-04
- Completed this session:
  - Full code review of all branch changes (committed + working tree) against Klipper reference.
  - Fixed indentation inconsistency in `src/GCodes/GCodes.cpp` (`DoStraightMove` and `DoArcMove` PA snapshot blocks).
  - Fixed `M572 D<n>` to fall back to direct extruder-shaper update when no tool is defined, restoring backward compatibility for bare-extruder configs.
  - Fixed `hasRemoteAxisDrivers` in `src/Movement/DDA.cpp` to only scan X and Y axes (was scanning all axes, unnecessarily disabling XY split shaping when e.g. Z was on CAN).
  - Fixed PA smoothing post-segment in `src/Movement/Move.cpp`: decel post-segment is now skipped if it would start at or after the move end time, preventing insertion into the next move's territory.
  - Updated `PLANS.md` with all findings, decisions, and open items.
- Stopped at:
  - Code fixes applied, PLANS.md updated. No rebuild done this session.
- Next step:
  - Rebuild `Duet3Mini5plus`, `FMDC_V03`, and `TOOL1LC` (all three affected by the DDA.cpp and Move.cpp changes).
  - Flash and run purge-line + first-layer start test.
  - Verify: no Code-3 overlap, normal Z-lift, PA and smooth time behave as expected on both local and CAN extruder.
  - Optional follow-up: improve `M593 X` query reply (currently returns `"X: "` with no config text when type is none — see open items below).
- Open blockers:
  - Hardware re-validation required after this session's changes.
- Decisions made this session:
  - `M572 D<n>` without a tool: fall back silently (no error, no warning) to extruder-shaper direct update; smooth time is ignored in fallback path.
  - `hasRemoteAxisDrivers`: only X and Y axes are checked; Z and higher axes are excluded from the remote-driver guard.
  - PA post-segment: skip (not clamp) if `postStart >= moveEndTime`; accepted ~75% PA accuracy for decel phases shorter than half the smooth time.

## Open items (non-blocking, future sessions)
- `M593 X` query (no params) returns `"X: "` with empty body when the axis shaper type is `none`. Fix: propagate the current config string from `AxisShaper::Configure` even for the no-params query path, or special-case the empty reply.
- `M572` report format changed from per-extruder to per-tool; verify DWC parses the new format correctly.
- `addSegmentWithPressureAdvance` post-segment skipped when smooth time > decel duration: consider redistributing the missing 25% contribution to the main segment as a compensation (low priority).
- Junction deviation (`M566 P2`): currently uses `min(accel, next->accel)`; could be split per move for closer Klipper fidelity (low priority).

## Notes
- 2026-03-04 (session 2): code-review fixes applied (GCodes.cpp, Move2.cpp, DDA.cpp, Move.cpp). Rebuild + hardware validation still pending.
- Build/smoke tests will be requested before running a full build.
- Local build environment is in `../RRF-Build-Helper/rrf-local` and project links in `../RRF-Build-Helper/rrf-workspace-links`.
- If `../RRF-Build-Helper` is missing, recreate it from `https://github.com/Argolein/RRF-Build-Helper` and run `scripts/bootstrap_rrf_env.sh` there before firmware builds.
- Headless build validated with outputs:
  - `Duet3Mini5plus/Duet3Firmware_Mini5plus.bin` / `.uf2`
  - `FMDC_V03/Duet3Firmware_FMDC.bin` / `.uf2`
- Correct `TOOL1LC` build target lives in `../RRF-Build-Helper/rrf-local/deps/Duet3Expansion` as Eclipse config `TOOL1LC`.
- Correct 1LC binary path: `../RRF-Build-Helper/rrf-local/deps/Duet3Expansion/TOOL1LC/Duet3Firmware_TOOL1LC.bin`.
- 2026-03-04: rebuilt `Duet3Mini5plus`, `FMDC_V03`, and `TOOL1LC` after PA smoothing and CAN timing updates.
- 2026-03-04: rebuilt again after PA-smoothing overlap fix in `src/Movement/Move.cpp` (pre-start clamp).
- 2026-03-04: rebuilt again after overlap-hardening in `src/Movement/Move.cpp` (executing-segment clamp instead of Code-3 halt).
- Latest verified output paths:
  - `Duet3Mini5plus/Duet3Firmware_Mini5plus.bin`
  - `FMDC_V03/Duet3Firmware_FMDC.bin`
  - `../RRF-Build-Helper/rrf-local/deps/Duet3Expansion/TOOL1LC/Duet3Firmware_TOOL1LC.bin`
- Version strings currently aligned on both boards: `3.6.2-beta.1`.
- If a smoke test / build step is needed, ask before starting (e.g. for C++ projects).
- Keep this file updated throughout the project.
