#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNAPSE_ROOT="${SYNAPSE_ROOT:-$HOME/Dev/Synapse}"
RECONCILE_SCRIPT="$SYNAPSE_ROOT/scripts/reconcile_minutes_inbox.py"
PROJECT_LABEL="${PROJECT_LABEL:-$(basename "$PROJECT_ROOT")}"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/reconcile_minutes.sh [minute-file]

Behavior:
  - if a minute file path is provided, use it
  - otherwise use the latest `minute-YYYYMMDD.md` file in the repo root

Environment overrides:
  SYNAPSE_ROOT   Path to the Synapse workspace (default: ~/Dev/Synapse)
  PROJECT_LABEL  Label written into Minutes Inbox tasks (default: repo folder name)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "$RECONCILE_SCRIPT" ]]; then
  echo "Missing canonical reconcile script: $RECONCILE_SCRIPT" >&2
  echo "Set SYNAPSE_ROOT if Synapse is located elsewhere." >&2
  exit 1
fi

if [[ $# -ge 1 ]]; then
  MINUTES_FILE="$1"
  if [[ "$MINUTES_FILE" != /* ]]; then
    MINUTES_FILE="$PROJECT_ROOT/$MINUTES_FILE"
  fi
else
  shopt -s nullglob
  minute_files=("$PROJECT_ROOT"/minute-*.md)
  shopt -u nullglob
  if [[ ${#minute_files[@]} -eq 0 ]]; then
    echo "No minute-YYYYMMDD.md file found in $PROJECT_ROOT" >&2
    exit 1
  fi
  IFS=$'\n' read -r -d '' -a sorted_files < <(printf '%s\n' "${minute_files[@]}" | sort && printf '\0')
  last_index=$((${#sorted_files[@]} - 1))
  MINUTES_FILE="${sorted_files[$last_index]}"
fi

if [[ ! -f "$MINUTES_FILE" ]]; then
  echo "Minutes file not found: $MINUTES_FILE" >&2
  exit 1
fi

echo "Reconciling minutes: $MINUTES_FILE"
python3 "$RECONCILE_SCRIPT" \
  --minutes-file "$MINUTES_FILE" \
  --project-label "$PROJECT_LABEL" \
  --repo-path "$PROJECT_ROOT"
