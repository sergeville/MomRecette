#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/build/dmg"
DERIVED_DATA_DIR="${BUILD_ROOT}/DerivedData"
STAGE_DIR="${BUILD_ROOT}/stage"
OUTPUT_DIR="${ROOT_DIR}/dist"

APP_NAME="MomRecette"
APP_BUNDLE_ID="com.villeneuves.MomRecette"
DATA_SOURCE_DIR="${MOMRECETTE_DATA_DIR:-${HOME}/Library/Containers/${APP_BUNDLE_ID}/Data/Documents}"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
README_PATH="${STAGE_DIR}/README.txt"
INSTALLER_PATH="${STAGE_DIR}/Install MomRecette Data.command"

rm -rf "${BUILD_ROOT}"
mkdir -p "${DERIVED_DATA_DIR}" "${STAGE_DIR}" "${OUTPUT_DIR}"

echo "Building ${APP_NAME}.app for Mac Catalyst..."
xcodebuild build \
  -project "${ROOT_DIR}/MomRecette.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -destination "platform=macOS,variant=Mac Catalyst" \
  -derivedDataPath "${DERIVED_DATA_DIR}"

APP_PATH="$(find "${DERIVED_DATA_DIR}/Build/Products" -path "*Release-maccatalyst/${APP_NAME}.app" -print -quit)"
if [[ -z "${APP_PATH}" ]]; then
  echo "Could not locate ${APP_NAME}.app in ${DERIVED_DATA_DIR}/Build/Products" >&2
  exit 1
fi

echo "Staging app bundle..."
ditto "${APP_PATH}" "${STAGE_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGE_DIR}/Applications"

if [[ -d "${DATA_SOURCE_DIR}" ]]; then
  echo "Staging live data from ${DATA_SOURCE_DIR}..."
  ditto "${DATA_SOURCE_DIR}" "${STAGE_DIR}/MomRecette Data"
else
  echo "No live data found at ${DATA_SOURCE_DIR}; creating DMG with app only."
fi

cat > "${README_PATH}" <<'EOF'
MomRecette DMG
=============

Contents:
- MomRecette.app
- MomRecette Data (current sandbox Documents contents, when available)
- Install MomRecette Data.command

Recommended install flow:
1. Drag MomRecette.app into Applications.
2. Launch the app once, then quit it.
3. Run "Install MomRecette Data.command" to copy the packaged data into:
   ~/Library/Containers/com.villeneuves.MomRecette/Data/Documents

If no live data folder was packaged, the app will still launch using its bundled seed data.
EOF

cat > "${INSTALLER_PATH}" <<'EOF'
#!/bin/bash

set -euo pipefail

APP_BUNDLE_ID="com.villeneuves.MomRecette"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)/MomRecette Data"
TARGET_DIR="${HOME}/Library/Containers/${APP_BUNDLE_ID}/Data/Documents"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"

if [[ ! -d "${SOURCE_DIR}" ]]; then
  osascript -e 'display dialog "No packaged MomRecette Data folder was found in this DMG." buttons {"OK"} default button "OK"'
  exit 1
fi

mkdir -p "${TARGET_DIR}"

if find "${TARGET_DIR}" -mindepth 1 -maxdepth 1 | read -r _; then
  BACKUP_DIR="${HOME}/Desktop/MomRecette Data Backup ${TIMESTAMP}"
  mkdir -p "${BACKUP_DIR}"
  while IFS= read -r item; do
    name="$(basename "${item}")"
    ditto "${item}" "${BACKUP_DIR}/${name}"
  done < <(find "${TARGET_DIR}" -mindepth 1 -maxdepth 1)
fi

while IFS= read -r item; do
  name="$(basename "${item}")"
  rm -rf "${TARGET_DIR:?}/${name}"
  ditto "${item}" "${TARGET_DIR}/${name}"
done < <(find "${SOURCE_DIR}" -mindepth 1 -maxdepth 1)

osascript -e 'display dialog "MomRecette data installed successfully." buttons {"OK"} default button "OK"'
EOF

chmod +x "${INSTALLER_PATH}"

rm -f "${DMG_PATH}"
echo "Creating ${DMG_PATH}..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "DMG created: ${DMG_PATH}"
