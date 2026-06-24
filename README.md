# HACO: Human-AI Co-discovery system

[![arXiv](https://img.shields.io/badge/arXiv-2606.22866-b31b1b.svg)](https://arxiv.org/abs/2606.22866)
[![Blog](https://img.shields.io/badge/Blog-MaskGXT-blue.svg)](https://sungsoo-ahn.github.io/blog/2026/maskgxt-ai-coscientist/)

An **AI co-scientist** for crystal structure prediction (CSP). It searches
generative paradigms and architectures across fields, transfers a promising one
into CSP, and refines it under sparse human guidance to discover new algorithms
(e.g., [MaskGXT](https://github.com/kiyoung98/MaskGXT)).

Mechanically, it is an autonomous loop that searches for the best `train.py`,
running indefinitely if no human intervenes.

![Agent overview](assets/haco.gif)

*Tree search over a git DAG of `train.py` variants. `idea`+`draft` open new
(paradigm, architecture) branches, `improve` refines, `debug` repairs a crash.
Sparse human interventions inject objective / domain mechanisms.*

![Autoresearch trajectory](assets/autoresearch.png)

*Validation METRe across search trials. Blue: autonomous agent steps. Orange:
sparse human interventions.*

Explore the full search tree interactively at
**[kiyoung98.github.io/HACO](https://kiyoung98.github.io/HACO/)**.

## Problem

- **Task** — given a composition, generate a crystal structure (lattice +
  fractional coordinates).
- **Data** — MP-20 polymorph split (`data/mp20_ps_{train,val,test}.pt`):
  polymorphs of one composition stay on the same split. The search scores on
  `val`; `test` is held out.
- **Metric** — **METRe** ([arXiv:2509.12178](https://arxiv.org/abs/2509.12178)):
  the fraction of references matched by generated crystals. Higher is better.

## Structure

- **Orchestrator** (LLM) — the loop: decides operator / parent / strategy, calls
  `scripts/*.sh`, dispatches subagents, commits each result. Never writes code.
- **6 subagents**
  - `idea` — pick a (paradigm, architecture) pair
  - `draft` — instantiate `train.py`
  - `improve` — one change
  - `debug` — fix a crash
  - `smoke` — pre-run check
  - `analyze` — judge the run
- **Memory = git** — every node is a commit under `agent/<run_tag>/*`; `git log`
  is the whole state. Heavy artifacts live in `runs/<run_tag>/<sha>/`.

## Files

Repo layout (tracked files only):

```
HACO/
├── program.md                 the orchestrator loop
├── contract.md                shared rules read by every subagent
├── prepare.py                 one-time data setup → data/mp20_ps_{train,val,test}.pt
├── evaluate.py                METRe score function
├── csp_methods.md             novelty boundary read by the idea subagent
├── requirements.txt           Python dependency
├── scripts/                   bootstrap + parallel-slot plumbing (bash)
│   ├── bootstrap.sh           build base venv (uv), prepare data, detect GPUs, write campaign.json
│   └── slot_*.sh              register / run / parse / reconcile / finalize a run slot
├── .claude/agents/            the 6 subagent prompts
│   ├── idea.md  draft.md  improve.md
│   └── debug.md  smoke.md  analyze.md
└── assets/                    README figures
```

## Run

**1. Bootstrap** — human, in the shell: clone, branch a fresh `agent/root`
trunk off `main`, then bootstrap (clean tree required).

```
git clone https://github.com/kiyoung98/HACO && cd HACO
git checkout -b agent/root
scripts/bootstrap.sh run_tag=<run_tag> [gpus=all] [train_minutes=120] [sample_minutes=60] [smoke_seconds=120]
```

Only `run_tag` is required; omitted arguments use their defaults (`gpus`=all,
`train_minutes`=120, `sample_minutes`=60, `smoke_seconds`=120).

**2. Launch** — start Claude Code with `--dangerously-skip-permissions` in tmux
and send:

```
You are the orchestrator of the HACO campaign run_tag=<run_tag>.
Read program.md, then run the loop.
```

## Citation

```bibtex
@misc{seong2026haco,
      title={Discovering Crystal Structure Prediction Algorithms with an AI Co-Scientist}, 
      author={Kiyoung Seong and Nayoung Kim and Sungsoo Ahn},
      year={2026},
      eprint={2606.22866},
      archivePrefix={arXiv},
      primaryClass={cs.LG},
      url={https://arxiv.org/abs/2606.22866}, 
}
```

## License

MIT (see [LICENSE](LICENSE)). Portions of `evaluate.py` and `prepare.py` are
derived from the [OMatG project](https://github.com/FERMat-ML/OMatG) (MIT); see
the attribution comments in those files.
