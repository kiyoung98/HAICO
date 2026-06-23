#!/usr/bin/env bash
# Campaign startup: validate preconditions, build the base venv, prepare data,
# detect hardware, freeze campaign.json. Only validates/applies/records.
# Usage: bootstrap.sh run_tag=<tag> [gpus=all] [wall_minutes=<override>] [cpu_threads=<override>]
# wall_minutes/score_noise default from task.md frontmatter. cpu_threads (OMP/BLAS
# cap, default nproc/n_slots): set explicitly when co-tenant campaigns share a host.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

UV="$(command -v uv || echo "$HOME/.local/bin/uv")"
PYTHON_SPEC="3.13"   # uv-managed CPython; swap to a python3.13 path here if needed

run_tag=""; gpus="all"; wall_minutes=""; cpu_threads=""
for kv in "$@"; do
  case "$kv" in
    run_tag=*)      run_tag="${kv#*=}" ;;
    gpus=*)         gpus="${kv#*=}" ;;
    wall_minutes=*) wall_minutes="${kv#*=}" ;;
    cpu_threads=*)  cpu_threads="${kv#*=}" ;;
    *) echo "bootstrap: unknown arg '$kv'" >&2; exit 2 ;;
  esac
done
[ -n "$run_tag" ] || { echo "bootstrap: run_tag=<tag> is required" >&2; exit 2; }

# --- preconditions ---
# Bootstrap on a task branch (the campaign trunk); draft nodes branch off HEAD.
case "$(git rev-parse --abbrev-ref HEAD)" in
  agent/*) echo "bootstrap: bootstrap on a task branch, not a node branch" >&2; exit 1 ;;
esac
[ -z "$(git status --porcelain)" ] \
  || { echo "bootstrap: working tree not clean" >&2; exit 1; }
if git for-each-ref --format='%(refname)' "refs/heads/agent/${run_tag}/" | grep -q .; then
  echo "bootstrap: agent/${run_tag}/* branches already exist" >&2; exit 1
fi
[ ! -e "runs/${run_tag}" ] || { echo "bootstrap: runs/${run_tag} already exists" >&2; exit 1; }

# --- fairness gate: refuse if a solver-view file can reach the held-out ---
scripts/validate_task.sh . || { echo "bootstrap: validate_task failed (see above)" >&2; exit 1; }

# --- domain defaults from task.md frontmatter (campaign.json is derived, not hand-written) ---
# wall_minutes = total per-node wall-clock; score_noise = run-to-run score std.
fm() { awk -v k="$1:" '/^---[[:space:]]*$/{n++; next} n==1 && $1==k {print $2; exit}' task.md; }
wall_minutes="${wall_minutes:-$(fm wall_minutes)}"; wall_minutes="${wall_minutes:-120}"
score_noise="$(fm score_noise)"; score_noise="${score_noise:-0.0}"

# --- base venv (uv) + CUDA gate (a venv that can't see the GPU poisons every node) ---
# uv hardlinks from ~/.cache/uv, so disk scales with distinct package sets, not nodes.
if [ ! -d .base-venv ]; then
  "$UV" venv --python "$PYTHON_SPEC" .base-venv
  VIRTUAL_ENV=.base-venv "$UV" pip install --quiet -r requirements.txt
fi
.base-venv/bin/python -c "import torch; assert torch.cuda.is_available(), 'CUDA not available'" \
  || { echo "bootstrap: CUDA gate failed (venv can't see the GPU)" >&2; exit 1; }

# --- base lock: first-draft nodes rebuild their venv from this ---
mkdir -p "runs/${run_tag}"
VIRTUAL_ENV=.base-venv "$UV" pip freeze > "runs/${run_tag}/base.lock"

# --- public data (prepare.py) + held-out (secret/, sealed scorer-side) ---
.base-venv/bin/python prepare.py
[ -n "$(ls -A data 2>/dev/null)" ] || echo "bootstrap: note: data/ empty after prepare.py (ok for an oracle-only task)" >&2
if [ -f secret/reference.py ]; then
  PYTHONPATH=. .base-venv/bin/python secret/reference.py \
    || { echo "bootstrap: secret/reference.py failed to materialize the held-out" >&2; exit 1; }
fi

# --- hardware detection ---
if [ "$gpus" = "all" ]; then
  mapfile -t gpu_ids < <(nvidia-smi --query-gpu=index --format=csv,noheader)
  gpus="$(IFS=,; echo "${gpu_ids[*]}")"
else
  IFS=',' read -r -a gpu_ids <<< "$gpus"
fi
n_slots="${#gpu_ids[@]}"
[ "$n_slots" -ge 1 ] || { echo "bootstrap: no GPUs detected" >&2; exit 1; }
# Per-run CPU thread cap: default = host cores split across this campaign's slots.
# Co-tenant campaigns: pass cpu_threads= so the caps sum to <= nproc.
cpu_threads="${cpu_threads:-$(( $(nproc) / n_slots ))}"
[ "$cpu_threads" -ge 1 ] || cpu_threads=1
# smallest GPU total VRAM (MB), if heterogeneous
vram_total_mb="$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | sort -n | head -1)"

# --- persist campaign.json (the durable source of truth) ---
mkdir -p "runs/${run_tag}"
cat > "runs/${run_tag}/campaign.json" <<JSON
{
  "run_tag": "${run_tag}",
  "gpus": "${gpus}",
  "n_slots": ${n_slots},
  "vram_total_mb": ${vram_total_mb},
  "wall_minutes": ${wall_minutes},
  "score_noise": ${score_noise},
  "cpu_threads": ${cpu_threads}
}
JSON

echo "bootstrap ok: run_tag=${run_tag} gpus=${gpus} n_slots=${n_slots} vram_total_mb=${vram_total_mb} wall_minutes=${wall_minutes} score_noise=${score_noise} cpu_threads=${cpu_threads}"
