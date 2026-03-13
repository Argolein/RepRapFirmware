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
  - Local extruder phase is coupled to weighted X/Y phase advance for better sync with shaped XY motion.
- CAN path hardening/compatibility:
  - CAN extruder-only moves keep legacy-safe behavior (no late shaping on remote move frame).
  - Extruder-only CAN scheduling includes minimum lead-time guard for transport jitter.
  - CAN extruder-only timing is pinned to nominal move start (no weighted XY phase shift) to avoid angle-dependent flow jitter.
  - Capability guard for movement PA snapshot support remains active.
  - Added capability-negotiated CAN extruder profile v2 path (`movementLinearShapedV2`) with per-phase PA + smooth-time payload.
  - Legacy fallback remains automatic for non-capable boards and mixed/unsupported cases.
  - Fixed CAN movement OOS diagnostics for 4-bit motion sequence IDs (`SeqMask=0x0f`): "2-behind" now matches `0x0E` (was stale `0x7E` from 7-bit logic).
- Pressure advance improvements (`M572`):
  - Per-tool PA storage and per-move snapshotting.
  - `M572 T<seconds>` added for PA smooth time (seconds, Klipper-compatible unit, range `0.0..0.2`).
  - `M572 S... T...` parsing fixed to handle both parameters together reliably.
- Lookahead/cruise improvements (`M566 R`):
  - Added Klipper-like minimum cruise ratio parameter `R` to `M566` (range `0.00..0.99`, default `0.50`).
  - Planner integration in both `DDA::DoLookahead` and `DDA::RecalculateMove` to limit excessive accel/decel-only phases and preserve a minimum cruise portion on XY moves.
  - Follow-up tuning: removed duplicate MCR clamping from `DDA::DoLookahead` and kept a single enforcement point in `DDA::RecalculateMove` to avoid over-constraining travel moves.
- Crash prevention fixes for segment overlap:
  - PA smoothing pre-segment cannot start before move start.
  - If a time-shifted segment still overlaps an executing segment, insertion is clamped to executing segment end (no emergency halt).
  - PA smoothing post-segment (decel phase) is now clamped to not start at or after the move end time, preventing segment insertion into the next queued move's territory (see `Move::AddLinearSegments`).
- Code-review fixes (2026-03-04, second session):
  - `GCodes.cpp`: Fixed indentation inconsistency in `DoStraightMove` and `DoArcMove` where PA snapshot lines had one extra tab level (cosmetic but tracked to prevent future merge confusion).
  - `Move2.cpp` (`M572 D<n>` fallback): When `D<n>` specifies an extruder not assigned to any tool, PA is now applied directly to the extruder shaper instead of returning an error. This restores backward compatibility for bare-extruder configs (`M572 D0 S0.05` without a defined tool). PA smooth time (`T`) is silently ignored in the fallback path since it is tool-level state.
  - `DDA.cpp` (`hasRemoteAxisDrivers`): The remote-driver scan now only checks X and Y axes (index 0 and 1). Previously any CAN driver on any axis (e.g. CAN-connected Z) would disable per-axis XY split shaping, even though Z drivers are irrelevant to XY shaping semantics.

## Current Status
- Code status: feature-complete for planned scope, including capability-negotiated CAN extruder PA-profile v2 implementation.
- Validation status: `Duet3Mini5plus`, `FMDC_V03`, and `TOOL1LC` all build clean after v2 changes; on-printer validation pending.
- Known residual gap vs Klipper: move-level CAN protocol is still descriptor-based (not host step-streaming), so edge-case continuity can still differ from Klipper in pathological segment patterns.
- Known minor gap: local PA smoothing is now area-conserving under move-boundary clamps, but still uses a compact 3-lobe approximation instead of Klipper's full continuous integral.

## Design Analysis (2026-03-05): Klipper-like Centralized CAN Motion
### Objective
- Determine whether Duet 3 Mini 5+ can handle a more Klipper-like architecture where heavy PA/input-shaping math is centralized and the CAN toolboard mainly executes timing-precise step output.

### Hardware/firmware constraints observed in code
- Mainboard CPU: SAME5x at 120MHz (`../RRF-Build-Helper/rrf-local/deps/CoreN2G/src/Core.h`).
- Toolboard CPU: SAMC21 at 48MHz (`../RRF-Build-Helper/rrf-local/deps/CoreN2G/src/Core.h`).
- Duet 3 step clock: 750kHz (`src/RepRapFirmware.h`, `src/Movement/StepTimer.cpp`).
- CAN link default: 1Mbps, no BRS in current protocol (`../RRF-Build-Helper/rrf-local/deps/CANlib/doc/Duet3CAN-FDProtocol.md`).
- Motion preparation lead-time: 25ms absolute minimum, 50ms usual (`src/Movement/MoveTiming.h`).
- Current CAN move frame is per-move (`CanMessageMovementLinearShaped`) with one scalar PA value and optional late shaping flag (`../RRF-Build-Helper/rrf-local/deps/CANlib/src/CanMessageFormats.h`).

### Gap vs Klipper architecture
- Klipper host precomputes detailed step timing and sends queued step commands (`queue_step`) significantly ahead of execution (`docs/Code_Overview.md` in Klipper repo).
- Current RRF CAN flow sends compact move descriptors; remote board still computes local segment math.
- Therefore, behavior can differ most on remote extruder PA smooth-time coupling under rapidly changing XY dynamics.

### Feasibility conclusion
- Mainboard compute headroom: **sufficient** for centralized PA/input-shaping calculations.
- Limiting factor is **CAN protocol/bandwidth model**, not raw CPU on Duet 3 Mini 5+.
- A literal Klipper-style per-step stream over current 1Mbps CAN (without BRS) is high risk for saturation/jitter in worst-case high-step-rate extrusion and is not the recommended path.

### Recommended implementation direction (next step)
- Introduce a **new CAN extruder motion message (v2)** for extruder-only remote boards:
  - Keep one-frame-per-move semantics (avoid multi-frame pairing races).
  - Carry richer per-move extruder compensation profile (beyond single scalar PA).
  - Leave existing `movementLinearShaped` path unchanged for backward compatibility and mixed-axis remote boards.
- Add a capability bit in board announce so mainboard can negotiate v2/fallback safely.
- Mainboard (Mini 5+) computes profile centrally in `DDA::Prepare`.
- Toolboard (1LC) executes profile deterministically with minimal additional math.

### Why this is preferred
- Preserves RRF’s deterministic MCU architecture and current safety model.
- Avoids CAN reordering/association risks from multi-message profile attachment.
- Keeps CAN traffic bounded and predictable at one motion frame per move.
- Gives most of Klipper-like quality gain where it matters (remote extruder PA timing) without full protocol rewrite.

### Implementation readiness
- Mainboard files expected:
  - `src/Movement/DDA.cpp`
  - `src/CAN/CanMotion.cpp`
  - `src/CAN/CanInterface.cpp` (announce capability)
- Shared protocol:
  - `../RRF-Build-Helper/rrf-local/deps/CANlib/src/CanMessageFormats.h`
- Toolboard files expected:
  - `../RRF-Build-Helper/rrf-local/deps/Duet3Expansion/src/CAN/CanInterface.cpp`
  - `../RRF-Build-Helper/rrf-local/deps/Duet3Expansion/src/Movement/Move.cpp`
- Validation plan:
  - Keep legacy fallback path active.
  - Add M122 diagnostics counters for v2 usage/fallback.
  - Re-run PA tower + high-speed perimeter test with CAN extruder and compare against current branch.

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
- For extruder timing coupling, shift local extruder segment start by a direction-weighted XY phase advance for phase-centred alignment; keep CAN extruder-only movement start at nominal move start for timing robustness.
- Add Klipper-style PA smoothing control via `M572 T<seconds>` (range `0.0..0.2`), stored per tool and snapshotted per move.
- PA smoothing value is in seconds so Klipper `pressure_advance_smooth_time` values can be transferred directly.
- `M572` now safely parses combined `S` and `T` in one command (`M572 S... T...`) without parameter-order ambiguity.
- `M566 R` introduces minimum cruise ratio control with Klipper-compatible semantics (default `0.50`), scoped to XY lookahead/recalculation where it improves print quality most.
- `M566 R` enforcement was refined to a single clamp site (`DDA::RecalculateMove`) after observing travel moves being over-limited by duplicate lookahead + recalc clamping.
- Safety fix for PA smoothing: do not insert smoothing segments before the move start time; this prevents "Code 3 move error" overlap with already-executing segments.
- Safety hardening in segment insertion: if a time-shifted segment still requests an overlap with an executing segment, clamp insertion start to executing-segment end instead of halting.
- PA post-segment boundary: decel PA post-segment is skipped if it would start at or after the move end time, preventing insertion conflicts with the next queued move.
- PA smoothing boundary handling: pre/post smoothing lobes are clamped to valid in-move start times instead of being dropped, preserving total PA contribution when smooth time exceeds phase/move bounds.
- CAN extruder profile v2: mainboard sends `movementLinearShapedV2` only when the remote board advertises support; otherwise it falls back to legacy `movementLinearShaped`.
- `movementLinearShapedV2` stays one-frame-per-move and adds per-phase PA (`accel/decel`) plus smooth-time (in step clocks) while keeping legacy compatibility.
- Build/version compatibility: keep `TimeSuffix` empty on both mainboard and TOOL1LC firmware builds to avoid false "Incompatible software versions" caused by differing build times.
- `M572 D<n>` backward compatibility: extruders without a tool fall back to direct extruder-shaper update (legacy path); smooth time (`T`) is ignored in that case.
- `hasRemoteAxisDrivers` scope: only X and Y axis CAN drivers disable per-axis XY split shaping; other CAN axes (Z, etc.) are irrelevant.
- Indentation in `GCodes.cpp` `DoStraightMove`/`DoArcMove` PA snapshot block corrected.

## Handoff
- Agent: Codex
- Date: 2026-03-05
- Completed this session:
  - Implemented CAN protocol extension for extruder motion profile v2 (`movementLinearShapedV2`) in CANlib, including announce capability bit.
  - Implemented capability negotiation and safe fallback on main firmware (`CanMotion`, `ExpansionManager`, announce handling).
  - Added remote receive/execute support for v2 in both RRF expansion mode and Duet3Expansion (`CommandProcessor`/`Move` paths).
  - Ported PA smoothing support to Duet3Expansion move segmentation (`accel/decel/smooth` profile) with in-move smoothing clamps and overlap hardening.
  - Aligned main/toolboard firmware date suffix handling (removed build-time suffix) to prevent false version-mismatch warnings.
  - Rebuilt main binaries and toolboard binary successfully:
    - `Duet3Mini5plus/Duet3Firmware_Mini5plus.bin`
    - `FMDC_V03/Duet3Firmware_FMDC.bin`
    - `../RRF-Build-Helper/rrf-local/deps/Duet3Expansion/TOOL1LC/Duet3Firmware_TOOL1LC.bin`
- Stopped at:
  - Code + build complete; no on-printer validation run in this session.
- Next step:
  - Flash Mini 5+ and TOOL1LC together, then run PA tower + fast line tests to confirm random offset artefacts are resolved with v2 path.
- Open blockers:
  - Hardware validation pending.
- Decisions made this session:
  - Keep one-frame-per-move CAN semantics and add richer PA profile inside a new movement message type instead of multi-message profile attachment.
  - Enable v2 only for extruder-only remote moves on boards that explicitly advertise support; fallback to legacy path otherwise.

## Open items (non-blocking, future sessions)
- `M593 X` query (no params) returns `"X: "` with empty body when the axis shaper type is `none`. Fix: propagate the current config string from `AxisShaper::Configure` even for the no-params query path, or special-case the empty reply.
- `M572` report format changed from per-extruder to per-tool; verify DWC parses the new format correctly.
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
