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
- [x] Verified compile for Duet3Mini5plus, FMDC_V03, and TOOL1LC on 2026-04-30 with 3.6 dependency pins

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
- Workspace structure clarification (2026-02-09):
  - Not every GitHub fork has a top-level folder under `GitHub-Development`.
  - Active dependency repos are intentionally kept under `../RRF-Build-Helper/rrf-local/deps/`.
  - Mapping is controlled via each repo's Git remotes (`origin`, optional `fork`), not by folder names.
- Critical build target clarification (2026-02-09):
  - `RepRapFirmware/FMDC_V03` is not the `TOOL1LC` expansion firmware target.
  - Local helper script in this repo was renamed to `Scripts/build_duet3mini_fmdc.sh` to avoid 1LC naming confusion.
  - Correct `TOOL1LC` build target lives in `../RRF-Build-Helper/rrf-local/deps/Duet3Expansion` as Eclipse config `TOOL1LC`.
  - Correct 1LC binary path: `../RRF-Build-Helper/rrf-local/deps/Duet3Expansion/TOOL1LC/Duet3Firmware_TOOL1LC.bin`.
- Duet3Expansion patch status (2026-02-09):
  - Local repo: `../RRF-Build-Helper/rrf-local/deps/Duet3Expansion`
  - Commit: `3cedbc98` (`Use per-move PA snapshot for TOOL1LC CAN moves`)
  - Branch pushed to user fork: `feature/tool1lc-adaptive-pa-snapshot`
  - Fork URL: `https://github.com/Argolein/Duet3Expansion`
- Continuation workflow:
  - Mainboard-side work remains in this repo (`RepRapFirmware`), branch `adaptive-pa` (commit `e5665ed8c`).
  - Toolboard-side work for 1LC remains in `Duet3Expansion`.
  - CAN message format changes must remain compatible with pinned CANlib commit in `RRF-Build-Helper/versions.lock`.
- Build validation on 2026-04-30:
  - Corrected CANlib dependency from `36bd5d3d4a676330b8cf67919d622570f91f97c7` to `65e6fcfda056582d28494a6fbec791c45263230a` in `../RRF-Build-Helper/versions.lock`, because TOOL1LC requires `movementLinearShapedV2` in addition to the PA snapshot fields.
  - Built with Arm GNU Toolchain `12.2.1` from `../RRF-Build-Helper/rrf-local/tools/toolchains/arm-gnu-toolchain-12.2.mpacbti-rel1-darwin-arm64-arm-none-eabi`.
  - Fresh outputs:
    - `Duet3Mini5plus/Duet3Firmware_Mini5plus.bin` / `.uf2`
    - `FMDC_V03/Duet3Firmware_FMDC.bin` / `.uf2`
    - `../RRF-Build-Helper/rrf-local/deps/Duet3Expansion/TOOL1LC/Duet3Firmware_TOOL1LC.bin`

## Fast Rebuild Runbook
Use this exact workflow for the next Mini5+ + TOOL1LC adaptive-PA build. The slow path on 2026-04-30 came from two issues: Eclipse picked Homebrew Arm GCC 15.2 first, and the old CANlib pin `36bd5d3` compiled Mini5+ but failed TOOL1LC because it did not contain `movementLinearShapedV2`.

1. Work from the RRF repo:

```bash
cd /Users/ArgoMac/GitHub-Development/RepRapFirmware
```

2. Verify the intended source revisions before building:

```bash
git status --short --branch
git log -1 --oneline
git -C /Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local/deps/Duet3Expansion status --short --branch
git -C /Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local/deps/Duet3Expansion log -1 --oneline
```

Expected adaptive-PA build state on 2026-04-30:
- RepRapFirmware branch: `adaptive-pa`
- Duet3Expansion branch: `adaptive-PA-PR`
- Duet3Expansion may have a local modified `src/CAN/CanInterface.cpp`; do not revert it unless explicitly requested.

3. Verify dependency pins. This build is for 3.6, not 3.5 and not 3.7:

```bash
sed -n '1,20p' /Users/ArgoMac/GitHub-Development/RRF-Build-Helper/versions.lock
```

Required lockfile entries:
- `CoreN2G https://github.com/Duet3D/CoreN2G.git 30588fdd974b83f969a5dec64b373f9809b695f0`
- `RRFLibraries https://github.com/Duet3D/RRFLibraries.git e89e081b98a87c00ae3d6cadc722e5adf6dd6a85`
- `FreeRTOS https://github.com/Duet3D/FreeRTOS.git 476b89a5fcc0adda13798d471f41d93b2f5db3fd`
- `CANlib https://github.com/Argolein/CANlib.git 65e6fcfda056582d28494a6fbec791c45263230a`
- `WiFiSocketServerRTOS https://github.com/Duet3D/WiFiSocketServerRTOS.git 76ec022c1846694baf0fdd081a9b97c33b6eb6c5`
- `LibTinyusb https://github.com/Duet3D/LibTinyusb.git cb6c86b8f71e278e78b34545a5b629ad6e7b96fa`

Do not use CANlib `36bd5d3d4a676330b8cf67919d622570f91f97c7` for this combined build. It has `pressureAdvanceClocks` and `supportsMovementPaSnapshot`, but not `movementLinearShapedV2`/`supportsMovementLinearShapedV2`, so TOOL1LC fails in `src/Movement/Move.cpp`.

4. If dependencies need to be reset to the lockfile, run:

```bash
/Users/ArgoMac/GitHub-Development/RRF-Build-Helper/scripts/bootstrap_rrf_env.sh \
  --rrf-dir /Users/ArgoMac/GitHub-Development/RepRapFirmware \
  --local-base /Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local \
  --versions-lock /Users/ArgoMac/GitHub-Development/RRF-Build-Helper/versions.lock
```

After bootstrap, verify CANlib contains all required fields:

```bash
rg -n 'movementLinearShapedV2|supportsMovementLinearShapedV2|pressureAdvanceClocks|supportsMovementPaSnapshot' \
  /Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local/deps/CANlib/src/CanMessageFormats.h
```

5. Use Arm GNU Toolchain 12.2.1 explicitly. Do not rely on `which arm-none-eabi-g++`, because Homebrew may point to GCC 15.2 and RRF 3.6 fails there in `ExceptionHandlers.cpp`.

```bash
export ARM_GCC_12=/Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local/tools/toolchains/arm-gnu-toolchain-12.2.mpacbti-rel1-darwin-arm64-arm-none-eabi/bin
export ArmGccPath="$ARM_GCC_12"
export PATH="$ARM_GCC_12:$PATH"
arm-none-eabi-g++ --version | sed -n '1p'
```

Expected first line:

```text
arm-none-eabi-g++ (Arm GNU Toolchain 12.2 (Build arm-12-mpacbti.34)) 12.2.1 20230214
```

If that toolchain folder is missing, download the Darwin arm64 `12.2.mpacbti-rel1` archive from Arm into:

```text
/Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local/tools/toolchains/
```

and extract it there. Keep the extracted directory name exactly:

```text
arm-gnu-toolchain-12.2.mpacbti-rel1-darwin-arm64-arm-none-eabi
```

6. Build Mini5+. This script also builds `FMDC_V03`; FMDC is not TOOL1LC.

```bash
date -u '+MINI_BUILD_START_UTC=%Y-%m-%dT%H:%M:%SZ'
bash Scripts/build_duet3mini_fmdc.sh
```

Expected fresh outputs:
- `/Users/ArgoMac/GitHub-Development/RepRapFirmware/Duet3Mini5plus/Duet3Firmware_Mini5plus.bin`
- `/Users/ArgoMac/GitHub-Development/RepRapFirmware/Duet3Mini5plus/Duet3Firmware_Mini5plus.uf2`
- `/Users/ArgoMac/GitHub-Development/RepRapFirmware/FMDC_V03/Duet3Firmware_FMDC.bin`
- `/Users/ArgoMac/GitHub-Development/RepRapFirmware/FMDC_V03/Duet3Firmware_FMDC.uf2`

7. Build TOOL1LC. Use the same Eclipse workspace and the same exported `ArmGccPath`/`PATH`. This is the exact command sequence that worked on 2026-04-30:

```bash
LOCAL_BASE=/Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local
ROOT_DIR=/Users/ArgoMac/GitHub-Development/RepRapFirmware
DEPS_DIR="$LOCAL_BASE/deps"
LINKS_DIR="$LOCAL_BASE/links"
WS_DIR="$LOCAL_BASE/eclipse"
HOME_DIR="$LOCAL_BASE/home"
TOOLS_BIN_DIR="$LOCAL_BASE/tools/bin"
ECLIPSE_BASE="$LOCAL_BASE/tools/Eclipse.app/Contents/Eclipse"
LAUNCHER_JAR=$(ls "$ECLIPSE_BASE"/plugins/org.eclipse.equinox.launcher_*.jar | head -n1)

mkdir -p "$LINKS_DIR" "$WS_DIR" "$HOME_DIR" "$TOOLS_BIN_DIR"
ln -sfn "$DEPS_DIR/Qfplib-M0-full" "$LINKS_DIR/Qfplib-M0-full"
ln -sfn "$DEPS_DIR/Duet3Expansion" "$LINKS_DIR/Duet3Expansion"
ln -sfn "$DEPS_DIR/CoreN2G" "$LINKS_DIR/CoreN2G"
ln -sfn "$DEPS_DIR/RRFLibraries" "$LINKS_DIR/RRFLibraries"
ln -sfn "$DEPS_DIR/FreeRTOS" "$LINKS_DIR/FreeRTOS"
ln -sfn "$DEPS_DIR/CANlib" "$LINKS_DIR/CANlib"
ln -sfn "$ROOT_DIR/Tools/CrcAppender/macos-x86_64/CrcAppender" "$TOOLS_BIN_DIR/CrcAppender"

export HOME="$HOME_DIR"
export ArmGccPath="$ARM_GCC_12"
export PATH="$ARM_GCC_12:$TOOLS_BIN_DIR:$PATH"

BASE_ARGS=(-consoleLog -nosplash -application org.eclipse.cdt.managedbuilder.core.headlessbuild -data "$WS_DIR" -no-indexer)

java -jar "$LAUNCHER_JAR" "${BASE_ARGS[@]}" \
  -import "$LINKS_DIR/Qfplib-M0-full" \
  -import "$LINKS_DIR/Duet3Expansion"

for target in \
  Qfplib-M0-full/SAMC21 \
  CoreN2G/SAMC21_CAN_RTOS \
  RRFLibraries/SAMC21_RTOS \
  FreeRTOS/SAMC21 \
  CANlib/SAMC21_RTOS \
  Duet3Expansion/TOOL1LC; do
  echo "==> Building $target"
  java -jar "$LAUNCHER_JAR" "${BASE_ARGS[@]}" -cleanBuild "$target" || exit $?
done
```

If Eclipse says a project already exists during import, that is not a source problem. Continue with the explicit `-cleanBuild` target list above.

Expected TOOL1LC output:

```text
/Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local/deps/Duet3Expansion/TOOL1LC/Duet3Firmware_TOOL1LC.bin
```

8. Verify artifacts after the build. Check timestamps are later than the recorded `*_BUILD_START_UTC`, check versions, and save hashes in the session notes:

```bash
stat -f '%Sm %z %N' -t '%Y-%m-%dT%H:%M:%S%z' \
  /Users/ArgoMac/GitHub-Development/RepRapFirmware/Duet3Mini5plus/Duet3Firmware_Mini5plus.bin \
  /Users/ArgoMac/GitHub-Development/RepRapFirmware/Duet3Mini5plus/Duet3Firmware_Mini5plus.uf2 \
  /Users/ArgoMac/GitHub-Development/RepRapFirmware/FMDC_V03/Duet3Firmware_FMDC.bin \
  /Users/ArgoMac/GitHub-Development/RepRapFirmware/FMDC_V03/Duet3Firmware_FMDC.uf2 \
  /Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local/deps/Duet3Expansion/TOOL1LC/Duet3Firmware_TOOL1LC.bin

strings /Users/ArgoMac/GitHub-Development/RepRapFirmware/Duet3Mini5plus/Duet3Firmware_Mini5plus.bin | rg 'RepRapFirmware for Duet 3 Mini 5\\+ version|version=3\\.6'
strings /Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local/deps/Duet3Expansion/TOOL1LC/Duet3Firmware_TOOL1LC.bin | rg 'Duet TOOL1LC firmware version|3\\.6'

shasum -a 256 \
  /Users/ArgoMac/GitHub-Development/RepRapFirmware/Duet3Mini5plus/Duet3Firmware_Mini5plus.bin \
  /Users/ArgoMac/GitHub-Development/RepRapFirmware/Duet3Mini5plus/Duet3Firmware_Mini5plus.uf2 \
  /Users/ArgoMac/GitHub-Development/RepRapFirmware/FMDC_V03/Duet3Firmware_FMDC.bin \
  /Users/ArgoMac/GitHub-Development/RepRapFirmware/FMDC_V03/Duet3Firmware_FMDC.uf2 \
  /Users/ArgoMac/GitHub-Development/RRF-Build-Helper/rrf-local/deps/Duet3Expansion/TOOL1LC/Duet3Firmware_TOOL1LC.bin
```

Known good 2026-04-30 version strings:
- Mini5+: `RepRapFirmware for Duet 3 Mini 5+ version 3.6.2-beta.1+3`
- TOOL1LC: `Duet TOOL1LC firmware version 3.6.2-beta.1`

Known good 2026-04-30 SHA-256 hashes:
- Mini5+ `.bin`: `8bf731d81f396247fedf1ca2718c2f4d02b39a27cab9d99adfc46e23070088b5`
- Mini5+ `.uf2`: `938ec5dc42f91e5f0b8e9c28dd567d5ec965dfcef5fae1dd55cbe477235d50d3`
- FMDC `.bin`: `6eb74e60f6d77c16d67e96ffd787af38748743e4d787912afc46dcf5eed0fc5a`
- FMDC `.uf2`: `b5ff0f054c13e8c46bcfd6c9af601ccdbee647123c8e87ed25d30534fc7dfaba`
- TOOL1LC `.bin`: `1bef76b57d0fe3ff815077269e555c5fc71d7a145782c1b6ce5ff2797bd315b8`

## Handoff
- Agent: Codex
- Date: 2026-04-30
- Completed this session:
  - Bootstrapped/rechecked 3.6 dependency pins via `../RRF-Build-Helper/versions.lock`.
  - Installed local Arm GNU Toolchain 12.2.1 in the helper toolchain directory and used it for headless Eclipse builds.
  - Rebuilt Mini5+, FMDC_V03, and TOOL1LC successfully.
  - Updated helper `versions.lock` so CANlib pins to `65e6fcfda056582d28494a6fbec791c45263230a`, which includes both PA snapshot support and `movementLinearShapedV2`.
- Stopped at:
  - Build artifacts generated and verified by timestamp, version strings, and SHA-256 hashes.
- Next step:
  - Hardware validation with matching Mini5+ and TOOL1LC firmware using OrcaSlicer adaptive pressure advance.
- Open blockers:
  - none
- Decisions made this session:
  - CANlib `36bd5d3` is insufficient for TOOL1LC; use CANlib `65e6fcf` for the adaptive PA 3.6 build.
