#!/usr/bin/env bash
# Campaign startup: validate preconditions, build the base venv, prepare data,
# detect hardware, and freeze campaign.json. Deterministic — choosing the params
# happens upstream (the launch prompt); this only validates, applies, records.
# Usage: bootstrap.sh run_tag=<tag> [gpus=all] [train_minutes=120] [sample_minutes=60] [smoke_seconds=120]
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

UV="$(command -v uv || echo "$HOME/.local/bin/uv")"
PYTHON_SPEC="3.13"   # uv-managed CPython; swap to a python3.13 path here if needed

run_tag=""; gpus="all"; train_minutes=120; sample_minutes=60; smoke_seconds=120; noise_sigma=0.004
for kv in "$@"; do
  case "$kv" in
    run_tag=*)        run_tag="${kv#*=}" ;;
    gpus=*)           gpus="${kv#*=}" ;;
    train_minutes=*)  train_minutes="${kv#*=}" ;;
    sample_minutes=*) sample_minutes="${kv#*=}" ;;
    smoke_seconds=*)  smoke_seconds="${kv#*=}" ;;
    noise_sigma=*)    noise_sigma="${kv#*=}" ;;
    *) echo "bootstrap: unknown arg '$kv'" >&2; exit 2 ;;
  esac
done
[ -n "$run_tag" ] || { echo "bootstrap: run_tag=<tag> is required" >&2; exit 2; }

# --- preconditions ---
[ "$(git rev-parse --abbrev-ref HEAD)" = "agent/root" ] \
  || { echo "bootstrap: must be on agent/root" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] \
  || { echo "bootstrap: working tree not clean" >&2; exit 1; }
if git for-each-ref --format='%(refname)' "refs/heads/agent/${run_tag}/" | grep -q .; then
  echo "bootstrap: agent/${run_tag}/* branches already exist" >&2; exit 1
fi
[ ! -e "runs/${run_tag}" ] || { echo "bootstrap: runs/${run_tag} already exists" >&2; exit 1; }

# --- base venv (uv) + CUDA gate (a venv that can't see the GPU poisons every node) ---
# uv installs hardlink from ~/.cache/uv: the base venv shares package inodes with
# the cache, and every node venv reconstructed from a lock shares them too. Disk
# scales with distinct package SETS, not node count.
if [ ! -d .base-venv ]; then
  "$UV" venv --python "$PYTHON_SPEC" .base-venv
  VIRTUAL_ENV=.base-venv "$UV" pip install --quiet -r requirements.txt
fi
.base-venv/bin/python -c "import torch; assert torch.cuda.is_available(), 'CUDA not available'" \
  || { echo "bootstrap: CUDA gate failed (venv can't see the GPU)" >&2; exit 1; }

# --- base lock: first-draft nodes reconstruct their venv from this (cache hardlinks) ---
mkdir -p "runs/${run_tag}"
VIRTUAL_ENV=.base-venv "$UV" pip freeze > "runs/${run_tag}/base.lock"

# --- data + gate ---
.base-venv/bin/python prepare.py
for f in train val test; do
  [ -s "data/mp20_ps_${f}.pt" ] || { echo "bootstrap: data/mp20_ps_${f}.pt missing" >&2; exit 1; }
done

# --- hardware detection ---
if [ "$gpus" = "all" ]; then
  mapfile -t gpu_ids < <(nvidia-smi --query-gpu=index --format=csv,noheader)
  gpus="$(IFS=,; echo "${gpu_ids[*]}")"
else
  IFS=',' read -r -a gpu_ids <<< "$gpus"
fi
n_slots="${#gpu_ids[@]}"
[ "$n_slots" -ge 1 ] || { echo "bootstrap: no GPUs detected" >&2; exit 1; }
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
  "train_minutes": ${train_minutes},
  "sample_minutes": ${sample_minutes},
  "smoke_seconds": ${smoke_seconds},
  "noise_sigma": ${noise_sigma}
}
JSON

echo "bootstrap ok: run_tag=${run_tag} gpus=${gpus} n_slots=${n_slots} vram_total_mb=${vram_total_mb} train_minutes=${train_minutes} sample_minutes=${sample_minutes} smoke_seconds=${smoke_seconds} noise_sigma=${noise_sigma}"
