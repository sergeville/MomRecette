#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${ROOT_DIR}/build/sergeiPhone"
TEMP_PROJECT_ROOT="${BUILD_ROOT}/project"
DERIVED_DATA_DIR="${BUILD_ROOT}/DerivedData"
ARCHIVE_ROOT="${BUILD_ROOT}/archives"
ARCHIVE_PATH="${ARCHIVE_ROOT}/sergeiPhone.xcarchive"
EXPORT_ROOT="${BUILD_ROOT}/export"
EXPORT_OPTIONS_PATH="${BUILD_ROOT}/ExportOptions.plist"
OUTPUT_DIR="${ROOT_DIR}/dist"

APP_NAME="MomRecette"
APP_BUNDLE_ID="com.villeneuves.MomRecette"
EXPORT_BASENAME="${EXPORT_BASENAME:-sergeiPhone}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-Release}"
IOS_DESTINATION="${IOS_DESTINATION:-generic/platform=iOS}"
IOS_EXPORT_METHOD="${IOS_EXPORT_METHOD:-development}"
ALLOW_PROVISIONING_UPDATES="${ALLOW_PROVISIONING_UPDATES:-NO}"
DATA_SOURCE_DIR="${MOMRECETTE_DATA_DIR:-${HOME}/Library/Containers/${APP_BUNDLE_ID}/Data/Documents}"
LIVE_RECIPES_PATH="${DATA_SOURCE_DIR}/momrecette.json"
LIVE_GROCERY_LIST_PATH="${DATA_SOURCE_DIR}/momrecette-grocery-list.json"
LIVE_PHOTO_DIR="${DATA_SOURCE_DIR}/RecipePhotos"
LIVE_INGREDIENT_CARD_DIR="${DATA_SOURCE_DIR}/RecipeIngredientCards"
PACKAGE_INFO_PATH="${EXPORT_ROOT}/PACKAGE_INFO.txt"

build_setting() {
  local key="$1"
  printf '%s\n' "${BUILD_SETTINGS}" | awk -F ' = ' -v key="${key}" '$1 ~ ("^[[:space:]]*" key "$") { print $2; exit }'
}

run_xcodebuild() {
  local -a cmd=(xcodebuild "$@")
  if [[ "${ALLOW_PROVISIONING_UPDATES}" == "YES" ]]; then
    cmd+=("-allowProvisioningUpdates")
  fi
  "${cmd[@]}"
}

if ! command -v rsync >/dev/null 2>&1; then
  echo "rsync is required to prepare the temporary iPhone export workspace." >&2
  exit 1
fi

rm -rf "${BUILD_ROOT}"
mkdir -p "${TEMP_PROJECT_ROOT}" "${DERIVED_DATA_DIR}" "${ARCHIVE_ROOT}" "${EXPORT_ROOT}" "${OUTPUT_DIR}"

echo "Resolving ${APP_NAME} iPhone build metadata..."
BUILD_SETTINGS="$(run_xcodebuild -showBuildSettings \
  -project "${ROOT_DIR}/MomRecette.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration "${BUILD_CONFIGURATION}" \
  -destination "${IOS_DESTINATION}")"

APP_VERSION="$(build_setting MARKETING_VERSION)"
APP_BUILD="$(build_setting CURRENT_PROJECT_VERSION)"
DEVELOPMENT_TEAM="$(build_setting DEVELOPMENT_TEAM)"

if [[ -z "${APP_VERSION}" || -z "${APP_BUILD}" || -z "${DEVELOPMENT_TEAM}" ]]; then
  echo "Could not resolve iPhone export metadata from Xcode build settings." >&2
  exit 1
fi

IPA_RELEASE_NAME="${EXPORT_BASENAME}-${APP_VERSION}-${APP_BUILD}.ipa"
IPA_RELEASE_PATH="${OUTPUT_DIR}/${IPA_RELEASE_NAME}"
IPA_LATEST_PATH="${OUTPUT_DIR}/${EXPORT_BASENAME}.ipa"
DIST_PACKAGE_INFO_PATH="${OUTPUT_DIR}/${EXPORT_BASENAME}-PACKAGE_INFO.txt"
PACKAGE_TIMESTAMP="$(date +"%Y-%m-%d %H:%M:%S %z")"
TEMP_RESOURCES_DIR="${TEMP_PROJECT_ROOT}/Resources"
TEMP_RECIPE_PHOTO_DIR="${TEMP_RESOURCES_DIR}/RecipePhotos"
TEMP_INGREDIENT_CARD_DIR="${TEMP_RESOURCES_DIR}/RecipeIngredientCards"
TEMP_RECIPE_BUNDLE_PATH="${TEMP_RESOURCES_DIR}/momrecette_bundle.json"
TEMP_GROCERY_BUNDLE_PATH="${TEMP_RESOURCES_DIR}/momrecette-grocery-list.json"

echo "Preparing temporary iPhone export workspace..."
rsync -a \
  --exclude '.git' \
  --exclude 'build' \
  --exclude 'dist' \
  --exclude '.DS_Store' \
  "${ROOT_DIR}/" "${TEMP_PROJECT_ROOT}/"

LIVE_RECIPE_STATUS="repo bundled seed"
LIVE_GROCERY_STATUS="not included"
LIVE_PHOTO_STATUS="repo bundled photos"
LIVE_PHOTO_COUNT="0"
LIVE_INGREDIENT_CARD_STATUS="not included"
LIVE_INGREDIENT_CARD_COUNT="0"

if [[ -f "${LIVE_RECIPES_PATH}" ]]; then
  cp "${LIVE_RECIPES_PATH}" "${TEMP_RECIPE_BUNDLE_PATH}"
  LIVE_RECIPE_STATUS="live momrecette.json bundled as seed"
fi

if [[ -f "${LIVE_GROCERY_LIST_PATH}" ]]; then
  cp "${LIVE_GROCERY_LIST_PATH}" "${TEMP_GROCERY_BUNDLE_PATH}"
  LIVE_GROCERY_STATUS="live grocery list bundled as seed"
else
  rm -f "${TEMP_GROCERY_BUNDLE_PATH}"
fi

if [[ -d "${LIVE_PHOTO_DIR}" ]]; then
  mkdir -p "${TEMP_RECIPE_PHOTO_DIR}"
  rsync -a --exclude '.DS_Store' "${LIVE_PHOTO_DIR}/" "${TEMP_RECIPE_PHOTO_DIR}/"
  LIVE_PHOTO_STATUS="live RecipePhotos merged over bundled photos"
  LIVE_PHOTO_COUNT="$(find "${LIVE_PHOTO_DIR}" -type f | wc -l | tr -d ' ')"
fi

if [[ -d "${LIVE_INGREDIENT_CARD_DIR}" ]]; then
  mkdir -p "${TEMP_INGREDIENT_CARD_DIR}"
  rsync -a --exclude '.DS_Store' "${LIVE_INGREDIENT_CARD_DIR}/" "${TEMP_INGREDIENT_CARD_DIR}/"
  LIVE_INGREDIENT_CARD_STATUS="live RecipeIngredientCards merged over bundled ingredient cards"
  LIVE_INGREDIENT_CARD_COUNT="$(find "${LIVE_INGREDIENT_CARD_DIR}" -type f | wc -l | tr -d ' ')"
fi

cat > "${EXPORT_OPTIONS_PATH}" <<DOC
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>compileBitcode</key>
  <false/>
  <key>destination</key>
  <string>export</string>
  <key>method</key>
  <string>${IOS_EXPORT_METHOD}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>${DEVELOPMENT_TEAM}</string>
  <key>thinning</key>
  <string>&lt;none&gt;</string>
</dict>
</plist>
DOC

echo "Archiving ${APP_NAME} for iPhone export..."
run_xcodebuild archive \
  -project "${TEMP_PROJECT_ROOT}/MomRecette.xcodeproj" \
  -scheme "${APP_NAME}" \
  -configuration "${BUILD_CONFIGURATION}" \
  -destination "${IOS_DESTINATION}" \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -archivePath "${ARCHIVE_PATH}"

echo "Exporting ${EXPORT_BASENAME}.ipa..."
run_xcodebuild -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_ROOT}" \
  -exportOptionsPlist "${EXPORT_OPTIONS_PATH}"

EXPORTED_IPA_PATH="$(find "${EXPORT_ROOT}" -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "${EXPORTED_IPA_PATH}" ]]; then
  echo "xcodebuild export succeeded but no IPA was found in ${EXPORT_ROOT}." >&2
  exit 1
fi

cat > "${PACKAGE_INFO_PATH}" <<DOC
Artifact Base Name: ${EXPORT_BASENAME}
App: ${APP_NAME}
Bundle ID: ${APP_BUNDLE_ID}
Version: ${APP_VERSION}
Build: ${APP_BUILD}
Packaged At: ${PACKAGE_TIMESTAMP}
Build Configuration: ${BUILD_CONFIGURATION}
Destination: ${IOS_DESTINATION}
Export Method: ${IOS_EXPORT_METHOD}
Allow Provisioning Updates: ${ALLOW_PROVISIONING_UPDATES}
Development Team: ${DEVELOPMENT_TEAM}
Live Data Source: ${DATA_SOURCE_DIR}
Recipes Seed: ${LIVE_RECIPE_STATUS}
Grocery Seed: ${LIVE_GROCERY_STATUS}
Photo Seed: ${LIVE_PHOTO_STATUS}
Photo File Count: ${LIVE_PHOTO_COUNT}
Ingredient Card Seed: ${LIVE_INGREDIENT_CARD_STATUS}
Ingredient Card File Count: ${LIVE_INGREDIENT_CARD_COUNT}
Archive Path: ${ARCHIVE_PATH}
Export Root: ${EXPORT_ROOT}
Release IPA: ${IPA_RELEASE_NAME}
Latest IPA Alias: ${EXPORT_BASENAME}.ipa
DOC

rm -f "${IPA_RELEASE_PATH}" "${IPA_LATEST_PATH}" "${DIST_PACKAGE_INFO_PATH}"
cp "${EXPORTED_IPA_PATH}" "${IPA_RELEASE_PATH}"
cp "${IPA_RELEASE_PATH}" "${IPA_LATEST_PATH}"
cp "${PACKAGE_INFO_PATH}" "${DIST_PACKAGE_INFO_PATH}"

echo "IPA created:"
echo "  ${IPA_RELEASE_PATH}"
echo "  ${IPA_LATEST_PATH}"
echo "  ${DIST_PACKAGE_INFO_PATH}"
