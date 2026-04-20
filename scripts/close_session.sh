#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_PATH="$PROJECT_ROOT/local/archives/session-close.log"

bash "$PROJECT_ROOT/scripts/reconcile_minutes.sh" "$@"

mkdir -p "$(dirname "$LOG_PATH")"
printf '%s close-session reconciled minutes (cwd=%s)\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${PWD}" >> "$LOG_PATH"

echo "Session-close minutes reconciliation complete."
echo "Canonical command: bash scripts/close_session.sh"
