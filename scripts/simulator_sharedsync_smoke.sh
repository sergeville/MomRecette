#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PHONE_NAME="${MOMRECETTE_SMOKE_PHONE_NAME:-iPhone 15 Plus}"
TABLET_NAME="${MOMRECETTE_SMOKE_TABLET_NAME:-iPad Pro 11-inch (M5)}"
SHARED_SYNC_ROOT="${MOMRECETTE_SHARED_SYNC_ROOT:-$HOME/Documents/MomRecette-Simulator}"
DERIVED_DATA_PATH="${MOMRECETTE_SMOKE_DERIVED_DATA:-/tmp/MomRecetteSimulatorSmoke}"
BUNDLE_ID="com.villeneuves.MomRecette"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/MomRecette.app"
CLEAN_SHARED_SYNC=0
SKIP_BUILD=0

usage() {
  cat <<'EOF'
Prepare a repeatable two-simulator SharedSync smoke run for MomRecette.

Usage:
  bash scripts/simulator_sharedsync_smoke.sh [options]

Options:
  --phone-name <name>     Simulator device name to use as the phone source.
  --tablet-name <name>    Simulator device name to use as the tablet target.
  --shared-root <path>    Parent root for MOMRECETTE_SHARED_SYNC_ROOT.
  --clean                 Remove the SharedSync folder and reset MomRecette app data first.
  --skip-build            Reuse the existing simulator build if present.
  --help                  Show this help text.

Environment overrides:
  MOMRECETTE_SMOKE_PHONE_NAME
  MOMRECETTE_SMOKE_TABLET_NAME
  MOMRECETTE_SHARED_SYNC_ROOT
  MOMRECETTE_SMOKE_DERIVED_DATA
EOF
}

resolve_simulator_udid() {
  local device_name="$1"
  xcrun simctl list devices available | awk -v target="$device_name" '
    index($0, target " (") {
      match($0, /\(([A-F0-9-]{36})\)/)
      if (RSTART > 0) {
        print substr($0, RSTART + 1, RLENGTH - 2)
        exit
      }
    }
  '
}

device_is_booted() {
  local udid="$1"
  xcrun simctl list devices | grep -q "$udid.*(Booted)"
}

boot_simulator_fresh() {
  local device_name="$1"
  local udid="$2"
  local attempt

  xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true

  for attempt in 1 2; do
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    open -a Simulator --args -CurrentDeviceUDID "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b
    sleep 2

    if device_is_booted "$udid"; then
      return 0
    fi

    echo "Simulator '$device_name' did not stay booted on attempt $attempt. Retrying..." >&2
    xcrun simctl shutdown "$udid" >/dev/null 2>&1 || true
    sleep 1
  done

  echo "Simulator '$device_name' failed to remain booted." >&2
  exit 1
}

reset_app_state() {
  local udid="$1"
  xcrun simctl terminate "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$udid" "$BUNDLE_ID" >/dev/null 2>&1 || true
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phone-name)
      PHONE_NAME="${2:?Missing value for --phone-name}"
      shift 2
      ;;
    --tablet-name)
      TABLET_NAME="${2:?Missing value for --tablet-name}"
      shift 2
      ;;
    --shared-root)
      SHARED_SYNC_ROOT="${2:?Missing value for --shared-root}"
      shift 2
      ;;
    --clean)
      CLEAN_SHARED_SYNC=1
      shift
      ;;
    --skip-build)
      SKIP_BUILD=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

PHONE_UDID="$(resolve_simulator_udid "$PHONE_NAME")"
TABLET_UDID="$(resolve_simulator_udid "$TABLET_NAME")"

if [[ -z "$PHONE_UDID" ]]; then
  echo "Unable to find an available simulator named: $PHONE_NAME" >&2
  exit 1
fi

if [[ -z "$TABLET_UDID" ]]; then
  echo "Unable to find an available simulator named: $TABLET_NAME" >&2
  exit 1
fi

SHARED_SYNC_FOLDER="$SHARED_SYNC_ROOT/SharedSync"
mkdir -p "$SHARED_SYNC_ROOT"

if [[ "$CLEAN_SHARED_SYNC" -eq 1 ]]; then
  rm -rf "$SHARED_SYNC_FOLDER"
fi

mkdir -p "$SHARED_SYNC_FOLDER"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  xcodebuild build \
    -project "$PROJECT_ROOT/MomRecette.xcodeproj" \
    -scheme MomRecette \
    -destination "platform=iOS Simulator,name=$PHONE_NAME" \
    -derivedDataPath "$DERIVED_DATA_PATH"
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at: $APP_PATH" >&2
  echo "Run without --skip-build or fix MOMRECETTE_SMOKE_DERIVED_DATA." >&2
  exit 1
fi

open -a Simulator >/dev/null 2>&1 || true

boot_simulator_fresh "$PHONE_NAME" "$PHONE_UDID"
boot_simulator_fresh "$TABLET_NAME" "$TABLET_UDID"

if [[ "$CLEAN_SHARED_SYNC" -eq 1 ]]; then
  reset_app_state "$PHONE_UDID"
  reset_app_state "$TABLET_UDID"
fi

xcrun simctl install "$PHONE_UDID" "$APP_PATH"
xcrun simctl install "$TABLET_UDID" "$APP_PATH"

xcrun simctl terminate "$PHONE_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl terminate "$TABLET_UDID" "$BUNDLE_ID" >/dev/null 2>&1 || true

SIMCTL_CHILD_MOMRECETTE_DISABLE_CLOUDKIT=1 \
SIMCTL_CHILD_MOMRECETTE_SHARED_SYNC_ROOT="$SHARED_SYNC_ROOT" \
  xcrun simctl launch "$PHONE_UDID" "$BUNDLE_ID"

SIMCTL_CHILD_MOMRECETTE_DISABLE_CLOUDKIT=1 \
SIMCTL_CHILD_MOMRECETTE_SHARED_SYNC_ROOT="$SHARED_SYNC_ROOT" \
  xcrun simctl launch "$TABLET_UDID" "$BUNDLE_ID"

cat <<EOF

Two-simulator SharedSync smoke setup is ready.

Phone simulator:
  $PHONE_NAME
  $PHONE_UDID

Tablet simulator:
  $TABLET_NAME
  $TABLET_UDID

SharedSync parent root:
  $SHARED_SYNC_ROOT

SharedSync folder:
  $SHARED_SYNC_FOLDER

Expected queue files:
  $SHARED_SYNC_FOLDER/MomRecette-Sync-Queue.json
  $SHARED_SYNC_FOLDER/MomRecette-Latest-Backup.json

Recommended manual smoke flow:
1. Use the phone simulator as the source device if it has recipes.
2. Open Sync and complete the primary SharedSync action shown there.
3. Open Sync on the tablet simulator and initialize from the shared backup when offered.
4. Background/foreground the target simulator to validate automatic queue pull behavior.
5. Record the observed result in minute-$(date +%Y%m%d).md.

$(if [[ "$CLEAN_SHARED_SYNC" -eq 1 ]]; then printf 'This run used --clean, so both simulators now start from a fresh MomRecette app install.\n'; fi)
EOF
