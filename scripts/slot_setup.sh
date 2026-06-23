#!/usr/bin/env bash
# Step 2b (unlocked): seal the solver view + build the slot venv. Per-slot isolated,
# no shared-.git mutation, runs in parallel across slots.
# Usage: slot_setup.sh <N> <run_tag> [parent_sha]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

UV="$(command -v uv || echo "$HOME/.local/bin/uv")"
PYTHON_SPEC="3.13"
EXTRA_INDEX="https://download.pytorch.org/whl/cu121"   # matches requirements.txt

N="$1"; run_tag="$2"; parent_sha="${3:-}"
WT=".worktrees/slot-${N}"

# Seal the solver view: strip secret/ + scorer + harness scripts; symlink public data/.
rm -rf "$WT/secret" "$WT/evaluate.py" "$WT/scripts"
ln -sfn ../../data "$WT/data"
# Live link to the run's directives so subagents read the human's
# runs/<run_tag>/directives.md (may not exist yet; dangling link resolves later).
mkdir -p "$WT/runs/${run_tag}"
ln -sfn "../../../../runs/${run_tag}/directives.md" "$WT/runs/${run_tag}/directives.md"
chmod 444 "$WT/prepare.py" "$WT/metric.py" "$WT/requirements.txt" \
          "$WT/contract.md" "$WT/task.md" "$WT/baselines.md" 2>/dev/null || true
mkdir -p "$WT/runs/staging"

# Isolated venv via uv: rebuild from a lock (never copy) — installs hardlink from
# ~/.cache/uv, so slots share package bytes but own their tree. Rebuild from the
# parent's lock so children inherit its extra packages for free.
"$UV" venv --python "$PYTHON_SPEC" "$WT/runs/staging/.venv"
# Inherit the parent's lock ONLY if it is a real, torch-bearing freeze; otherwise
# fall back to base.lock. A parent whose venv build failed freezes an empty/torchless
# lock — without this guard that emptiness propagates to every descendant forever.
if [ -n "$parent_sha" ] \
   && grep -q '^torch==' "runs/${run_tag}/${parent_sha}/requirements.lock" 2>/dev/null; then
  lock="runs/${run_tag}/${parent_sha}/requirements.lock"; venv_src="parent"
else
  lock="runs/${run_tag}/base.lock"; venv_src="base"
fi
# unsafe-best-match: the lock pins across PyPI + the torch index; without it uv
# resolves on the first index only and pinned versions become unsatisfiable.
VIRTUAL_ENV="$WT/runs/staging/.venv" "$UV" pip install --quiet \
  --extra-index-url "$EXTRA_INDEX" --index-strategy unsafe-best-match -r "$lock"

# Smoke gate: a silently-incomplete install (transient index/cache failure, esp.
# under cold N-way concurrency) leaves a bare venv. Fail LOUD here so the caller's
# check=True aborts the slot instead of running a torchless train.py (-> nan) and
# then freezing that bareness into the child locks. Enforces install-before-run.
"$WT/runs/staging/.venv/bin/python" -c "import torch, numpy, scipy" \
  || { echo "slot_setup: venv smoke-test failed (incomplete install) slot=${N} lock=${lock}" >&2; exit 3; }

echo "slot_setup ok: slot=${N} venv=${venv_src}"
