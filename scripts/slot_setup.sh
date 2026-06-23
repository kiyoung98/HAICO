#!/usr/bin/env bash
# Step 2: create a slot worktree, COW-clone the venv, and write the [RUNNING]
# placeholder commit. Deterministic given the decided inputs. Free text (pair,
# pair) arrives via file so the shell never re-evaluates it.
# Usage: slot_setup.sh <N> <parent_ref> <branch> <run_tag> <op> <pair_file> [parent_sha]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

UV="$(command -v uv || echo "$HOME/.local/bin/uv")"
PYTHON_SPEC="3.13"
EXTRA_INDEX="https://download.pytorch.org/whl/cu121"   # matches requirements.txt

N="$1"; parent_ref="$2"; branch="$3"; run_tag="$4"; op="$5"
pair_file="$6"; parent_sha="${7:-}"
WT=".worktrees/slot-${N}"

git worktree add -b "$branch" "$WT" "$parent_ref"
ln -s ../../data "$WT/data"                       # repo/data, relative to the worktree
chmod 444 "$WT/evaluate.py" "$WT/prepare.py" "$WT/requirements.txt" \
          "$WT/program.md" "$WT/contract.md"
mkdir -p "$WT/runs/staging"

# Isolated venv via uv: reconstruct from a lockfile, never copy. uv installs
# hardlink from ~/.cache/uv, so each slot owns its own venv tree but shares
# package bytes with the cache (and every venv built from the same lock). A
# slot's later `uv pip install` only adds new cache entries — it never mutates a
# parent's or sibling's files. (cp -a would break the cache hardlinks → full
# copy; cp -al would pollute shared inodes.) Reconstruct from the parent's lock
# so children inherit the parent's extra packages (mace/e3nn/...) for free.
"$UV" venv --python "$PYTHON_SPEC" "$WT/runs/staging/.venv"
if [ -n "$parent_sha" ] && [ -f "runs/${run_tag}/${parent_sha}/requirements.lock" ]; then
  lock="runs/${run_tag}/${parent_sha}/requirements.lock"; venv_src="parent"
else
  lock="runs/${run_tag}/base.lock"; venv_src="base"
fi
# unsafe-best-match: the lock pins exact versions across PyPI + the torch index;
# without it uv resolves each package on the first index only and pinned versions
# (e.g. certifi) on PyPI become unsatisfiable.
VIRTUAL_ENV="$WT/runs/staging/.venv" "$UV" pip install --quiet \
  --extra-index-url "$EXTRA_INDEX" --index-strategy unsafe-best-match -r "$lock"

pair="$(cat "$pair_file")"
msg_args=(-m "${op}: [RUNNING]" -m "pair: ${pair}")
[ -n "$parent_sha" ] && msg_args+=(-m "parent: ${parent_sha}")
git -C "$WT" commit --allow-empty "${msg_args[@]}"

echo "slot_setup ok: slot=${N} branch=${branch} venv=${venv_src}"
