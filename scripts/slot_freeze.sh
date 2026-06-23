#!/usr/bin/env bash
# Freeze this slot's venv → runs/staging/requirements.lock so children rebuild from
# cache (hardlinks). Run before GIT_LOCK so the lock covers only shared-.git ops.
# Idempotent; no-op without a venv.
# Usage: slot_freeze.sh <N>
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

UV="$(command -v uv || echo "$HOME/.local/bin/uv")"
N="$1"
staging=".worktrees/slot-${N}/runs/staging"

[ -d "$staging/.venv" ] || exit 0
VIRTUAL_ENV="$staging/.venv" "$UV" pip freeze > "$staging/requirements.lock"
