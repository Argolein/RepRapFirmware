# PLANS.md

## Objective
Implement support for rapid pressure-advance changes (e.g. OrcaSlicer adaptive pressure advance) without forcing movement queue standstill, using a RAM-efficient per-tool snapshot model per queued move.

## Open questions
- (none)

## Approved plan
- Add a tool-level pressure-advance value in `Tool` and expose/report it as per-tool data.
- Change `M572` handling to set/report PA per tool:
  - `M572 S...` with no `D` targets current tool.
  - `M572 D... S...` maps extruders to owning tools and applies one tool PA value.
  - Reject ambiguous per-extruder updates that would only partially target a multi-extruder tool.
- Snapshot PA into each queued move (`RawMove`) and carry it into `DDA` so prepared segments use the per-move snapshot, not live mutable PA.
- Use the snapshot in acceleration limiting and segment generation for extruders.
- Keep CAN remote PA update behavior unchanged for now; retain explicit note of residual limitation for remote queue semantics.

## Implementation status
- [ ] Not started
- [ ] In progress
- [x] Done
- [x] Verified compile for Duet3Mini5plus + FMDC_V03 on 2026-02-09

## Decisions
- Per-tool semantics selected for PA.
- Multi-extruder tools must not be partially targeted by extruder list updates; reject and require setting at tool scope.
- `M572 D... S...` must fail if any selected extruder does not map to a tool (no silent partial application).
- Reporting should be per tool.
- `M572` updates no longer force standstill just because remote extruders are involved; remote PA now follows per-move snapshots.
- For CAN extruders, PA is now transmitted per movement message as a per-move snapshot (`pressureAdvanceClocks`) and consumed on the remote board for segment generation.
- `movementLinearShaped` receiver now validates message length and `numDrivers` before queuing moves.
- CAN announce now includes a capability bit for movement-PA snapshots; main board refuses to send motion to boards that do not advertise this capability and raises an emergency stop to avoid undefined mixed-firmware behavior.

## Notes
- Build/smoke tests will be requested before running a full build.
- Local build environment is in `../RRF-Build-Helper/rrf-local` and project links in `../RRF-Build-Helper/rrf-workspace-links`.
- If `../RRF-Build-Helper` is missing, recreate it from `https://github.com/Argolein/RRF-Build-Helper` and run `scripts/bootstrap_rrf_env.sh` there before firmware builds.
- Headless build validated with outputs:
  - `Duet3Mini5plus/Duet3Firmware_Mini5plus.bin` / `.uf2`
  - `FMDC_V03/Duet3Firmware_FMDC.bin` / `.uf2`
- Remaining validation step: hardware print test with OrcaSlicer adaptive pressure advance (rapid M572 updates) to confirm no print artefacts/regressions.
- Additional validation done on 2026-02-09: implemented and built explicit error path for unmatched extruders in `M572 D... S...`.
- Additional validation done on 2026-02-09: implemented CAN per-move PA snapshot transport and rebuilt both `Duet3Mini5plus` and `FMDC_V03` successfully.
- Dependency touched for local build/test compatibility: `/Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local/deps/CANlib/src/CanMessageFormats.h` (added `pressureAdvanceClocks` to `CanMessageMovementLinearShaped`).
- CANlib patch is prepared as commit `727a0dd` on local branch `feature/can-pa-per-move-snapshot` in `/Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local/deps/CANlib`; pushing to user fork is pending fork remote details.
- Additional validation done on 2026-02-09: added CAN announce capability bit (`supportsMovementPaSnapshot`) and rebuilt both firmware targets successfully.
- Additional robustness fix on 2026-02-09: `supportsMovementPaSnapshot` is now refreshed on every announce (not only when board type text changes), avoiding stale capability state.
