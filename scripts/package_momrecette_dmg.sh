#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/build/dmg"
DERIVED_DATA_DIR="${BUILD_ROOT}/DerivedData"
STAGE_DIR="${BUILD_ROOT}/stage"
OUTPUT_DIR="${ROOT_DIR}/dist"

APP_NAME="MomRecette"
APP_BUNDLE_ID="com.villeneuves.MomRecette"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-Release}"
BUILD_DESTINATION="${BUILD_DESTINATION:-platform=macOS,variant=Mac Catalyst}"
XCODE_CODE_SIGNING_ALLOWED="${XCODE_CODE_SIGNING_ALLOWED:-NO}"
XCODE_CODE_SIGNING_REQUIRED="${XCODE_CODE_SIGNING_REQUIRED:-NO}"
XCODE_CODE_SIGN_IDENTITY="${XCODE_CODE_SIGN_IDENTITY:-}"
DATA_SOURCE_DIR="${MOMRECETTE_DATA_DIR:-${HOME}/Library/Containers/${APP_BUNDLE_ID}/Data/Documents}"
DATA_ARCHIVE_NAME="MomRecette Data.zip"
DATA_ARCHIVE_PATH="${STAGE_DIR}/${DATA_ARCHIVE_NAME}"
README_PATH="${STAGE_DIR}/README.txt"
INSTALLER_PATH="${STAGE_DIR}/Install MomRecette Data.command"
PACKAGE_INFO_PATH="${STAGE_DIR}/PACKAGE_INFO.txt"
DMG_BACKGROUND_ASSET_PATH="${ROOT_DIR}/scripts/assets/momrecette-dmg-background.png"
DMG_BACKGROUND_NAME="momrecette-dmg-background.png"
DMG_BACKGROUND_STAGE_DIR="${STAGE_DIR}/.background"
DMG_BACKGROUND_STAGE_PATH="${DMG_BACKGROUND_STAGE_DIR}/${DMG_BACKGROUND_NAME}"
RW_DMG_PATH="${BUILD_ROOT}/${APP_NAME}-layout.dmg"
MOUNT_DEVICE=""
MOUNT_VOLUME_PATH=""
MOUNT_VOLUME_NAME=""

build_setting() {
  local key="$1"
  printf '%s\n' "${BUILD_SETTINGS}" | awk -F ' = ' -v key="${key}" '$1 ~ ("^[[:space:]]*" key "$") { print $2; exit }'
}

cleanup_mount() {
  if [[ -n "${MOUNT_DEVICE}" ]]; then
    hdiutil detach "${MOUNT_DEVICE}" >/dev/null 2>&1 || true
    MOUNT_DEVICE=""
  fi
  MOUNT_VOLUME_PATH=""
  MOUNT_VOLUME_NAME=""
}

trap cleanup_mount EXIT

rm -rf "${BUILD_ROOT}"
mkdir -p "${DERIVED_DATA_DIR}" "${STAGE_DIR}" "${OUTPUT_DIR}"

echo "Resolving ${APP_NAME} build metadata..."
BUILD_SETTINGS="$(xcodebuild -showBuildSettings \
  -project "${ROOT_DIR}/MomRecette.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration "${BUILD_CONFIGURATION}" \
  -destination "${BUILD_DESTINATION}")"

APP_VERSION="$(build_setting MARKETING_VERSION)"
APP_BUILD="$(build_setting CURRENT_PROJECT_VERSION)"

if [[ -z "${APP_VERSION}" ]]; then
  echo "Could not resolve MARKETING_VERSION from Xcode build settings." >&2
  exit 1
fi

if [[ -z "${APP_BUILD}" ]]; then
  echo "Could not resolve CURRENT_PROJECT_VERSION from Xcode build settings." >&2
  exit 1
fi

if [[ ! -f "${DMG_BACKGROUND_ASSET_PATH}" ]]; then
  echo "DMG background asset is missing: ${DMG_BACKGROUND_ASSET_PATH}" >&2
  exit 1
fi

DMG_RELEASE_NAME="${APP_NAME}-${APP_VERSION}-${APP_BUILD}.dmg"
DMG_RELEASE_PATH="${OUTPUT_DIR}/${DMG_RELEASE_NAME}"
DMG_LATEST_NAME="${APP_NAME}.dmg"
DMG_LATEST_PATH="${OUTPUT_DIR}/${DMG_LATEST_NAME}"
PACKAGE_TIMESTAMP="$(date +"%Y-%m-%d %H:%M:%S %z")"

echo "Building ${APP_NAME}.app for Mac Catalyst..."
xcodebuild build \
  -project "${ROOT_DIR}/MomRecette.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration "${BUILD_CONFIGURATION}" \
  -destination "${BUILD_DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  CODE_SIGNING_ALLOWED="${XCODE_CODE_SIGNING_ALLOWED}" \
  CODE_SIGNING_REQUIRED="${XCODE_CODE_SIGNING_REQUIRED}" \
  CODE_SIGN_IDENTITY="${XCODE_CODE_SIGN_IDENTITY}"

APP_PATH="$(find "${DERIVED_DATA_DIR}/Build/Products" -path "*${BUILD_CONFIGURATION}-maccatalyst/${APP_NAME}.app" -print -quit)"
if [[ -z "${APP_PATH}" ]]; then
  echo "Could not locate ${APP_NAME}.app in ${DERIVED_DATA_DIR}/Build/Products" >&2
  exit 1
fi

echo "Staging app bundle..."
ditto "${APP_PATH}" "${STAGE_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGE_DIR}/Applications"
mkdir -p "${DMG_BACKGROUND_STAGE_DIR}"
cp "${DMG_BACKGROUND_ASSET_PATH}" "${DMG_BACKGROUND_STAGE_PATH}"

if [[ -d "${DATA_SOURCE_DIR}" ]]; then
  echo "Archiving live data from ${DATA_SOURCE_DIR}..."
  ditto -c -k --norsrc --keepParent "${DATA_SOURCE_DIR}" "${DATA_ARCHIVE_PATH}"
  PACKAGED_DATA_STATUS="included"
  PACKAGED_DATA_ENTRY="${DATA_ARCHIVE_NAME}"
  PACKAGED_DATA_BYTES="$(stat -f '%z' "${DATA_ARCHIVE_PATH}")"
else
  echo "No live data found at ${DATA_SOURCE_DIR}; creating DMG with app only."
  PACKAGED_DATA_STATUS="not included"
  PACKAGED_DATA_ENTRY="<none>"
  PACKAGED_DATA_BYTES="0"
fi

cat > "${README_PATH}" <<DOC
MomRecette Release DMG
=====================

Contents:
- MomRecette.app
- ${DATA_ARCHIVE_NAME} (full sandbox Documents payload, when available)
- Install MomRecette Data.command
- PACKAGE_INFO.txt

Recommended install / upgrade flow:
1. Drag MomRecette.app into Applications.
2. If Finder asks, choose Replace to upgrade the installed app.
3. Launch the app once, then quit it.
4. Run "Install MomRecette Data.command" if you want to restore the packaged Documents payload.

The packaged archive contains the full live Documents payload, including the recipe database and RecipePhotos folder, when that data exists on this Mac.
If no live data archive was packaged, the app will still launch using its bundled seed data.
If packaged data is installed over an existing container, the installer creates a backup on the Desktop before replacing files.
DOC

cat > "${INSTALLER_PATH}" <<'DOC'
#!/bin/bash

set -euo pipefail

APP_BUNDLE_ID="com.villeneuves.MomRecette"
DMG_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCHIVE_PATH="${DMG_DIR}/MomRecette Data.zip"
LEGACY_SOURCE_DIR="${DMG_DIR}/MomRecette Data"
TARGET_DIR="${HOME}/Library/Containers/${APP_BUNDLE_ID}/Data/Documents"
TIMESTAMP="$(date +"%Y%m%d-%H%M%S")"
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/momrecette-data-install.XXXXXX")"
SOURCE_DIR=""

cleanup() {
  rm -rf "${TEMP_DIR}"
}

trap cleanup EXIT

if [[ -f "${ARCHIVE_PATH}" ]]; then
  ditto -x -k --norsrc "${ARCHIVE_PATH}" "${TEMP_DIR}"
  SOURCE_DIR="${TEMP_DIR}/Documents"
elif [[ -d "${LEGACY_SOURCE_DIR}" ]]; then
  SOURCE_DIR="${LEGACY_SOURCE_DIR}"
else
  osascript -e 'display dialog "No packaged MomRecette Data archive was found in this DMG." buttons {"OK"} default button "OK"'
  exit 1
fi

if [[ ! -d "${SOURCE_DIR}" ]]; then
  osascript -e 'display dialog "The packaged MomRecette Data archive could not be expanded." buttons {"OK"} default button "OK"'
  exit 1
fi

mkdir -p "${TARGET_DIR}"

if find "${TARGET_DIR}" -mindepth 1 -maxdepth 1 | read -r _; then
  CHOICE="$(osascript -e 'button returned of (display dialog "Existing MomRecette data was found. The installer will back it up to your Desktop and then replace it with the packaged data. Continue?" buttons {"Cancel","Continue"} default button "Continue" cancel button "Cancel")')"
  if [[ "${CHOICE}" != "Continue" ]]; then
    exit 1
  fi

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
DOC

chmod +x "${INSTALLER_PATH}"

cat > "${PACKAGE_INFO_PATH}" <<DOC
App: ${APP_NAME}
Bundle ID: ${APP_BUNDLE_ID}
Version: ${APP_VERSION}
Build: ${APP_BUILD}
Packaged At: ${PACKAGE_TIMESTAMP}
Build Configuration: ${BUILD_CONFIGURATION}
Build Destination: ${BUILD_DESTINATION}
Code Signing Allowed: ${XCODE_CODE_SIGNING_ALLOWED}
Code Signing Required: ${XCODE_CODE_SIGNING_REQUIRED}
Code Signing Identity: ${XCODE_CODE_SIGN_IDENTITY:-<none>}
Live Data Source: ${DATA_SOURCE_DIR}
Live Data: ${PACKAGED_DATA_STATUS}
Live Data Entry: ${PACKAGED_DATA_ENTRY}
Live Data Archive Bytes: ${PACKAGED_DATA_BYTES}
DMG Background Asset: ${DMG_BACKGROUND_ASSET_PATH}
DMG Window Layout: custom Finder icon layout
Release DMG: ${DMG_RELEASE_NAME}
Latest DMG Alias: ${DMG_LATEST_NAME}
DOC

rm -f "${RW_DMG_PATH}" "${DMG_RELEASE_PATH}" "${DMG_LATEST_PATH}"

echo "Creating writable DMG layout image..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${STAGE_DIR}" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "${RW_DMG_PATH}"

echo "Applying custom DMG window layout..."
ATTACH_OUTPUT="$(hdiutil attach "${RW_DMG_PATH}" -readwrite -noverify -noautoopen)"
MOUNT_DEVICE="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk '/Apple_HFS/ { print $1; exit }')"
if [[ -z "${MOUNT_DEVICE}" ]]; then
  echo "Could not determine mounted device for ${RW_DMG_PATH}" >&2
  exit 1
fi
MOUNT_VOLUME_PATH="$(printf '%s\n' "${ATTACH_OUTPUT}" | awk '/Apple_HFS/ { $1=""; $2=""; sub(/^[ \t]+/, ""); print; exit }')"
MOUNT_VOLUME_NAME="${MOUNT_VOLUME_PATH##*/}"
if [[ -z "${MOUNT_VOLUME_PATH}" || -z "${MOUNT_VOLUME_NAME}" ]]; then
  echo "Could not determine mounted volume path for ${RW_DMG_PATH}" >&2
  exit 1
fi

osascript <<OSA
 tell application "Finder"
   tell disk "${MOUNT_VOLUME_NAME}"
     open
     delay 1
     tell container window
       set current view to icon view
       set toolbar visible to false
       set statusbar visible to false
       set bounds to {120, 120, 880, 600}
     end tell

     set viewOptions to the icon view options of container window
     tell viewOptions
       set arrangement to not arranged
       set icon size to 88
       set text size to 13
     end tell
     set background picture of viewOptions to POSIX file "${MOUNT_VOLUME_PATH}/.background/${DMG_BACKGROUND_NAME}" as alias

     try
       set extension hidden of item "${DATA_ARCHIVE_NAME}" to true
     end try
     try
       set extension hidden of item "Install MomRecette Data.command" to true
     end try
     try
       set extension hidden of item "README.txt" to true
     end try
     try
       set extension hidden of item "PACKAGE_INFO.txt" to true
     end try

     set position of item "${APP_NAME}.app" to {150, 230}
     set position of item "Applications" to {590, 230}
     if exists item "${DATA_ARCHIVE_NAME}" then set position of item "${DATA_ARCHIVE_NAME}" to {120, 390}
     if exists item "Install MomRecette Data.command" then set position of item "Install MomRecette Data.command" to {380, 390}
     if exists item "README.txt" then set position of item "README.txt" to {640, 376}
     if exists item "PACKAGE_INFO.txt" then set position of item "PACKAGE_INFO.txt" to {640, 418}

     update without registering applications
     delay 2
     close
     open
     delay 1
   end tell
 end tell
OSA

sync
cleanup_mount

sleep 1

echo "Creating ${DMG_RELEASE_PATH}..."
if ! hdiutil convert "${RW_DMG_PATH}" -ov -format UDZO -o "${DMG_RELEASE_PATH}"; then
  echo "DMG conversion failed after a successful app build, staging pass, and Finder layout pass." >&2
  echo "Writable DMG remains available at: ${RW_DMG_PATH}" >&2
  exit 1
fi

rm -f "${RW_DMG_PATH}"
cp "${DMG_RELEASE_PATH}" "${DMG_LATEST_PATH}"

echo "DMG created:"
echo "  ${DMG_RELEASE_PATH}"
echo "  ${DMG_LATEST_PATH}"
