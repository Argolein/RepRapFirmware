#!/usr/bin/env bash
set -euo pipefail

# Build script for:
# - Duet 3 Mini 5+ main firmware (RepRapFirmware/Duet3Mini5plus)
# - Duet 1LC expansion firmware (RepRapFirmware/FMDC_V03)
#
# It assumes this repository is the workspace root and dependency repos exist at:
#   .workspace-deps/CoreN2G
#   .workspace-deps/RRFLibraries
#   .workspace-deps/FreeRTOS
#   .workspace-deps/CANlib
#   .workspace-deps/WiFiSocketServerRTOS
#   .workspace-deps/LibTinyusb

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER_BASE="${ROOT_DIR}/../RRF-Build-Helper"
LOCAL_BASE="${RRF_LOCAL_BASE:-${HELPER_BASE}/rrf-local}"
if [[ ! -d "${LOCAL_BASE}" && -d "${HELPER_BASE}/.rrf-local" ]]; then
  LOCAL_BASE="${HELPER_BASE}/.rrf-local"
elif [[ ! -d "${LOCAL_BASE}" && -d "${ROOT_DIR}/../.rrf-local" ]]; then
  LOCAL_BASE="${ROOT_DIR}/../.rrf-local"
fi
DEPS_DIR="${LOCAL_BASE}/deps"
WS_DIR="${LOCAL_BASE}/eclipse"
HOME_DIR="${LOCAL_BASE}/home"
TOOLS_BIN_DIR="${LOCAL_BASE}/tools/bin"
LINKS_DIR="${LOCAL_BASE}/links"

# Prefer a local Eclipse copy first, then /Applications
ECLIPSE_CANDIDATES=(
  "${LOCAL_BASE}/tools/Eclipse.app/Contents/Eclipse"
  "${LOCAL_BASE}/tools/Eclipse CPP.app/Contents/Eclipse"
  "${ROOT_DIR}/.workspace-tools/Eclipse.app/Contents/Eclipse"
  "${ROOT_DIR}/.workspace-tools/Eclipse CPP.app/Contents/Eclipse"
  "/Applications/Eclipse.app/Contents/Eclipse"
  "/Applications/Eclipse CPP.app/Contents/Eclipse"
)

ECLIPSE_BASE=""
for c in "${ECLIPSE_CANDIDATES[@]}"; do
  if [[ -d "${c}" ]]; then
    ECLIPSE_BASE="${c}"
    break
  fi
done

if [[ -z "${ECLIPSE_BASE}" ]]; then
  echo "No Eclipse installation found. Install Eclipse CDT (e.g. brew install --cask eclipse-cpp)."
  exit 2
fi

LAUNCHER_JAR="$(ls "${ECLIPSE_BASE}"/plugins/org.eclipse.equinox.launcher_*.jar 2>/dev/null | head -n1 || true)"
if [[ -z "${LAUNCHER_JAR}" ]]; then
  echo "Eclipse launcher jar not found under: ${ECLIPSE_BASE}"
  exit 2
fi

# Sanity checks for dependency repos
for dep in CoreN2G RRFLibraries FreeRTOS CANlib WiFiSocketServerRTOS LibTinyusb; do
  if [[ ! -f "${DEPS_DIR}/${dep}/.project" ]]; then
    echo "Missing dependency project: ${DEPS_DIR}/${dep}"
    exit 2
  fi
done

# Ensure LibTinyusb submodule content is present. Without this, CoreN2G may fail
# with "tusb.h: No such file or directory" when LibTinyusb was cloned without submodules.
if [[ ! -f "${DEPS_DIR}/LibTinyusb/src/tinyusb/src/tusb.h" ]]; then
  echo "Initializing LibTinyusb submodule (src/tinyusb)..."
  git -C "${DEPS_DIR}/LibTinyusb" submodule update --init --recursive
fi

# CrcAppender required by post-build steps
if [[ ! -x "${TOOLS_BIN_DIR}/CrcAppender" ]]; then
  mkdir -p "${TOOLS_BIN_DIR}"
  ln -sf "${ROOT_DIR}/Tools/CrcAppender/macos-x86_64/CrcAppender" "${TOOLS_BIN_DIR}/CrcAppender"
fi

rm -rf "${WS_DIR}"
mkdir -p "${WS_DIR}" "${HOME_DIR}"
export HOME="${HOME_DIR}"
export PATH="${TOOLS_BIN_DIR}:${PATH}"

echo "Using Eclipse base: ${ECLIPSE_BASE}"
echo "Using workspace:    ${WS_DIR}"

# Headless CDT expects a workspace-like project tree. Build from a links directory
# to keep sibling project names exactly as in Eclipse project references.
mkdir -p "${LINKS_DIR}"
ln -sfn "${ROOT_DIR}" "${LINKS_DIR}/RepRapFirmware"
ln -sfn "${DEPS_DIR}/CoreN2G" "${LINKS_DIR}/CoreN2G"
ln -sfn "${DEPS_DIR}/RRFLibraries" "${LINKS_DIR}/RRFLibraries"
ln -sfn "${DEPS_DIR}/FreeRTOS" "${LINKS_DIR}/FreeRTOS"
ln -sfn "${DEPS_DIR}/CANlib" "${LINKS_DIR}/CANlib"
ln -sfn "${DEPS_DIR}/WiFiSocketServerRTOS" "${LINKS_DIR}/WiFiSocketServerRTOS"
ln -sfn "${DEPS_DIR}/LibTinyusb" "${LINKS_DIR}/LibTinyusb"

# Configuration mapping for Duet 3 Mini 5+ stack
# CoreN2G config naming in this branch is SAME5x_SDHC_USB_RTOS.
BUILD_TARGETS=(
  "LibTinyusb/SAME5x"
  "CoreN2G/SAME5x_SDHC_USB_RTOS"
  "CoreN2G/SAME5x_CAN_SDHC_USB_RTOS"
  "RRFLibraries/SAME51_RTOS"
  "FreeRTOS/SAME51"
  "CANlib/SAME51_RTOS"
  "RepRapFirmware/Duet3Mini5plus"
  "RepRapFirmware/FMDC_V03"
)

BASE_ARGS=(
  -consoleLog
  -nosplash
  -application org.eclipse.cdt.managedbuilder.core.headlessbuild
  -data "${WS_DIR}"
  -no-indexer
)

IMPORT_ARGS=(
  "${BASE_ARGS[@]}"
  -import "${LINKS_DIR}/CoreN2G"
  -import "${LINKS_DIR}/RRFLibraries"
  -import "${LINKS_DIR}/FreeRTOS"
  -import "${LINKS_DIR}/CANlib"
  -import "${LINKS_DIR}/LibTinyusb"
  -import "${LINKS_DIR}/WiFiSocketServerRTOS"
  -import "${LINKS_DIR}/RepRapFirmware"
)

echo "Starting headless build..."
set +e
RC=0
echo ""
echo "==> Importing projects into workspace"
java -jar "${LAUNCHER_JAR}" "${IMPORT_ARGS[@]}"
IMPORT_RC=$?
if [[ ${IMPORT_RC} -ne 0 ]]; then
  RC=${IMPORT_RC}
  echo "Workspace import returned ${IMPORT_RC} (continuing with builds)"
fi

for target in "${BUILD_TARGETS[@]}"; do
  echo ""
  echo "==> Building ${target}"
  java -jar "${LAUNCHER_JAR}" "${BASE_ARGS[@]}" -cleanBuild "${target}"
  TARGET_RC=$?
  if [[ ${TARGET_RC} -ne 0 ]]; then
    RC=${TARGET_RC}
    echo "Target ${target} returned ${TARGET_RC}"
  fi
done
set -e

echo ""
echo "Headless builder exit code: ${RC}"
echo "Expected outputs:"
echo "  ${ROOT_DIR}/Duet3Mini5plus/Duet3Firmware_Mini5plus.bin"
echo "  ${ROOT_DIR}/Duet3Mini5plus/Duet3Firmware_Mini5plus.uf2"
echo "  ${ROOT_DIR}/FMDC_V03/Duet3Firmware_FMDC.bin"
echo "  ${ROOT_DIR}/FMDC_V03/Duet3Firmware_FMDC.uf2"

if [[ ${RC} -ne 0 ]]; then
  echo "Build failed. Check Eclipse metadata log:"
  echo "  ${WS_DIR}/.metadata/.log"
fi

# Eclipse/Oomph may return non-zero on shutdown even after successful build.
if [[ -f "${ROOT_DIR}/Duet3Mini5plus/Duet3Firmware_Mini5plus.bin" && -f "${ROOT_DIR}/FMDC_V03/Duet3Firmware_FMDC.bin" ]]; then
  echo "Both target binaries were generated."
  exit 0
fi

exit "${RC}"
