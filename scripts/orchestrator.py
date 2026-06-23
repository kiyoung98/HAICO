#!/usr/bin/env python3
"""Deterministic HACO driver. Replaces the program.md LLM loop.

Makes NO research decisions — `select` owns every choice (next op, parent/target,
exploration floor). The driver only routes select's plain-text plan into the
existing scripts/slot_*.sh and invokes the five subagents as `claude -p`
subprocesses. git is the only state store: op/parent are recovered from each
slot's [RUNNING] commit, never held in the driver across a detached run.

Concurrency model — fully per-slot, no cross-slot barrier:
  - A single POLLER thread tails events.log and periodically sweeps for idle
    slots. It NEVER services work itself, so polling is never blocked.
  - Each freed/idle slot is handed to its own WORKER (service_slot) in a pool.
    A worker runs the slot's whole cycle independently of every other slot:
        complete_slot : analyze (per-worktree, unlocked) -> finalize
        dispatch_slot : self-select -> slot_add -> slot_setup -> author -> run
  - GIT_LOCK serializes ONLY the shared-.git structural mutations — slot_add
    (git worktree add + next_index + the [RUNNING] commit) and finalize (git
    worktree remove). This is the "queue / wait-if-busy" device: a worker that
    needs the shared .git waits for whichever worker holds it, then proceeds.
    Everything else (the venv build, the LLM author/analyze calls, the detached
    train.py run) is per-slot isolated and runs unlocked, in parallel.
  - select is self-allocating (option A): each slot runs select over ITS OWN
    idle slot, reading live git, so two selects never contend for one slot. The
    exploration floor is therefore best-effort (read from concurrent counts),
    not a strict global barrier — the accepted trade for full per-slot async.

Usage: python3 scripts/orchestrator.py <run_tag>   (run in tmux; needs `claude`
on PATH; runs until interrupted).
"""
import json
import os
import re
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor

REPO = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                      text=True, capture_output=True, check=True).stdout.strip()
os.chdir(REPO)
AGENTS = os.path.join(REPO, ".claude", "agents")
EVENTS = os.path.join(REPO, "events.log")

run_tag = (sys.argv[1] if len(sys.argv) > 1 else
           sys.exit("usage: orchestrator.py <run_tag>"))

EVENT_RE = re.compile(r"^slot=(\d+) exit=")
PLAN_RE = re.compile(r"^slot=(\d+)\s+op=(\w+)(?:\s+(?:parent|target)=(\S+))?")
OPS = ("draft", "improve", "debug")
SWEEP_EVERY = 5.0   # seconds between idle-slot sweeps (startup + crashed-worker recovery)
RUN_VISIBLE_TIMEOUT = 5.0  # max wait for a just-launched run to appear to pgrep
# Stagger between starting NEW slot workers within one sweep. A whole fleet of
# drafts launched at t=0 hits the LLM API concurrently and triggers 429/529 storms;
# a throttled agent then burns its wall budget on retries and produces no train.py.
# Spreading the starts de-storms it. Overridable via campaign.json "dispatch_stagger".
DISPATCH_STAGGER = 8.0

# Per-role wall-clock cap (seconds) on each `claude -p` subagent. claude -p has no
# built-in session timeout, so a single hung session (e.g. a stuck WebFetch) would
# block its worker thread forever. On timeout call_agent returns "" and the node
# re-enters the normal path (no train.py -> [BUGGY]; no plan -> the slot is retried
# next sweep).
AGENT_TIMEOUTS = {"draft": 1800, "improve": 1800, "debug": 1800,
                  "select": 600, "analyze": 600}

# --- concurrency state --------------------------------------------------------
# GIT_LOCK serializes the shared-.git critical sections (slot_add / finalize).
# WORKING holds slots with a live worker, so the event tail and the idle sweep
# never start two workers for the same slot (check-and-set under WORKING_LOCK).
GIT_LOCK = threading.Lock()
WORKING = set()
WORKING_LOCK = threading.Lock()
POOL = None  # ThreadPoolExecutor, sized to n_slots in main()


# --- small subprocess helpers -------------------------------------------------
def sh(*args):
    """Run a command, raising on failure (used for git/slot_*.sh side effects)."""
    return subprocess.run(list(args), text=True, capture_output=True, check=True)


def out(*args):
    """Run a command, return stripped stdout ('' on failure)."""
    r = subprocess.run(list(args), text=True, capture_output=True)
    return r.stdout.strip()


def cfg():
    """Re-read campaign.json on every dispatch/recovery (a live edit to
    wall_minutes/score_noise takes effect next cycle)."""
    with open(f"runs/{run_tag}/campaign.json") as f:
        return json.load(f)


def gpu_for(n):
    return cfg()["gpus"].split(",")[n]


def wt_of(n):
    return f".worktrees/slot-{n}"


def py_of(n):
    return f"{wt_of(n)}/runs/staging/.venv/bin/python"


def has_train(n):
    p = f"{wt_of(n)}/train.py"
    return os.path.isfile(p) and os.path.getsize(p) > 0


def live_train(n):
    # Anchor to the ABSOLUTE campaign worktree path, not the relative ".worktrees/
    # slot-N". Co-tenant campaigns share one .git (separate worktrees haco-<A>/ and
    # haco-<B>/), so a relative pattern matches the OTHER campaign's slot-N train and
    # a finished slot looks forever-live -> never finalized/redispatched. The trailing
    # slash still anchors the slot dir (slot-1/ != slot-10/). The real cmdline is
    # <REPO>/.worktrees/slot-N/runs/.../python train.py, an exact per-campaign boundary.
    return subprocess.run(["pgrep", "-f", f"{os.path.join(REPO, wt_of(n))}/.*train.py"],
                          capture_output=True).returncode == 0


# --- subagent invocation ------------------------------------------------------
def parse_agent(role):
    """Reconstruct (system_prompt_body, allowed_tools) from .claude/agents/<role>.md.
    Frontmatter is the YAML between the 1st and 2nd `---` lines; body follows."""
    with open(os.path.join(AGENTS, f"{role}.md")) as f:
        lines = f.read().splitlines()
    seps = [i for i, ln in enumerate(lines) if ln.strip() == "---"]
    fm = lines[seps[0] + 1:seps[1]]
    body = "\n".join(lines[seps[1] + 1:]).strip()
    tools = ""
    for ln in fm:
        if ln.startswith("tools:"):
            tools = ln.split(":", 1)[1].replace(" ", "")
            break
    return body, tools


def call_agent(role, cwd, spec):
    """Run a `-p` session AS <role>: append its body as system prompt, restrict
    to its declared tools. No --bare (that would skip the guard.py PreToolUse
    hook); --dangerously-skip-permissions keeps it prompt-free while the guard
    still hard-blocks the sealed surface."""
    body, tools = parse_agent(role)
    cmd = ["claude", "-p", spec,
           "--append-system-prompt", body,
           "--allowedTools", tools,
           "--permission-mode", "acceptEdits",
           "--dangerously-skip-permissions"]
    timeout = AGENT_TIMEOUTS.get(role, 1200)
    try:
        r = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True,
                           timeout=timeout)
    except subprocess.TimeoutExpired as e:
        sys.stderr.write(f"[orchestrator] {role} TIMEOUT after {timeout}s "
                         f"(cwd={cwd}) — killed, treated as no output\n")
        return e.stdout or ""
    if r.returncode != 0:
        sys.stderr.write(f"[orchestrator] {role} exit={r.returncode}: "
                         f"{r.stderr.strip()[:400]}\n")
    return r.stdout


def select_one(n):
    """Self-allocating select for ONE idle slot — option A. Each freed slot runs
    its own select reading live git (tree_view), so two selects never contend for
    the same slot and there is no global barrier. Returns (op, ref_or_None) or
    None. The exploration floor is best-effort: concurrent selects read the same
    `# counts:` header, so draft >= improve/3 holds in expectation, not strictly.
    A line whose op is not draft/improve/debug, or that (for improve/debug) lacks
    a ref, is dropped with a stderr warning rather than dispatched."""
    spec = (f"Task spec: {{run_tag: {run_tag}, idle_slots: [{n}]}}. Emit the plan.")
    for ln in call_agent("select", REPO, spec).splitlines():
        ln = ln.strip()
        m = PLAN_RE.match(ln)
        if m and int(m.group(1)) == n and m.group(2) in OPS and \
                (m.group(2) == "draft" or m.group(3)):
            return m.group(2), m.group(3)
        if ln.startswith("slot="):  # meant to be a plan line, but isn't valid
            sys.stderr.write(f"[orchestrator] slot={n} dropped bad plan line: {ln!r}\n")
    return None


# --- node bookkeeping ---------------------------------------------------------
def next_index():
    """Unique <i> for agent/<run_tag>/n<i>-<op>. Called ONLY under GIT_LOCK (from
    dispatch_slot), so concurrent workers never mint the same index."""
    refs = out("git", "for-each-ref", "--format=%(refname:short)",
               f"refs/heads/agent/{run_tag}/")
    idx = [int(m.group(1)) for m in
           (re.search(r"/n(\d+)-", r) for r in refs.splitlines()) if m]
    return (max(idx) + 1) if idx else 1


def recover_op_parent(n):
    """op/parent_sha from the slot's [RUNNING] commit (durable record), read
    BEFORE finalize amends it."""
    subj = out("git", "-C", wt_of(n), "log", "-1", "--format=%s")
    op = subj.split(":", 1)[0].strip()
    body = out("git", "-C", wt_of(n), "log", "-1", "--format=%b")
    psha = ""
    for ln in body.splitlines():
        if ln.startswith("parent:"):
            psha = ln.split(":", 1)[1].strip()
    return op, psha


# --- per-slot steps -----------------------------------------------------------
def run_or_bug(n, wall_minutes):
    """Source of truth is the artifact on disk, not the author's exit code. A
    usable train.py runs (detached). If the author produced NO train.py, that is a
    transient infra failure (LLM API 429/529, agent timeout) — NOT a research
    result — so the node is DISCARDED (worktree + branch removed), never finalized
    as a [BUGGY] node. Finalizing it would pollute the tree with a codeless,
    method-less node that `select` mis-routes debug/improve onto (re-drafting a
    duplicate and bypassing novelty falsification) and that skews the exploration
    stats. The next idle sweep re-dispatches a fresh draft (~SWEEP_EVERY backoff).
    [BUGGY] is thus reserved for its true meaning: a node whose train.py ran and
    scored nan/crashed. After launching a real run we wait until pgrep sees it
    (bounded) so the idle sweep can't mistake a just-launched run for a dead slot
    and dispatch over it."""
    if has_train(n):
        sh("scripts/slot_run.sh", str(n), gpu_for(n), py_of(n),
           run_tag, str(wall_minutes), str(cfg().get("cpu_threads", 0)))
        deadline = time.monotonic() + RUN_VISIBLE_TIMEOUT
        while time.monotonic() < deadline and not live_train(n):
            time.sleep(0.1)
    else:
        discard_node(n)


def discard_node(n):
    """Tear down a node whose author produced no train.py: remove the worktree and
    delete its branch so no phantom node persists in the tree. Mutates the shared
    .git, so it runs under GIT_LOCK. The slot then goes idle and the poller's sweep
    re-dispatches a fresh draft."""
    branch = out("git", "-C", wt_of(n), "rev-parse", "--abbrev-ref", "HEAD")
    with GIT_LOCK:
        sh("git", "worktree", "remove", "--force", wt_of(n))
        if branch and branch != "HEAD":
            subprocess.run(["git", "branch", "-D", branch],
                           text=True, capture_output=True)
    sys.stderr.write(f"[orchestrator] slot={n} author produced no train.py — "
                     f"discarded {branch or 'node'}; re-dispatch on next sweep\n")


def analyze_one(n):
    """Judge the run. Reads/writes only the slot's own worktree
    (runs/staging/finding) and touches no shared .git, so it runs unlocked. No-op
    when nothing ran (no train.py)."""
    if has_train(n):
        spec = f"Task spec: {{cwd: {wt_of(n)}, score_noise: {cfg()['score_noise']}}}"
        call_agent("analyze", os.path.join(REPO, wt_of(n)), spec)


def finalize_one(n, op, psha):
    """Amend the [RUNNING] placeholder into the final node and remove the
    worktree. `git worktree remove` mutates the shared .git, so EVERY caller holds
    GIT_LOCK (steady state: complete_slot; startup: recover, single-threaded)."""
    args = ["scripts/slot_finalize.sh", str(n), run_tag, op] + \
           ([psha] if psha else [])
    sh(*args)


def complete_slot(n):
    """Judge, freeze, then finalize the slot's just-finished node. analyze and the
    venv freeze are per-worktree (unlocked); only finalize mutates shared .git, so
    just that runs under GIT_LOCK. Recover op/parent from the [RUNNING] commit
    BEFORE finalize amends it. No-op if the worktree is gone (slot already idle)."""
    if not os.path.isdir(wt_of(n)):
        return
    op, psha = recover_op_parent(n)
    analyze_one(n)
    sh("scripts/slot_freeze.sh", str(n))  # uv pip freeze — unlocked, before the lock
    with GIT_LOCK:
        finalize_one(n, op, psha)


def dispatch_slot(n):
    """Idle slot -> self-select -> setup -> author -> launch run (detached).
    slot_add (worktree add + next_index + [RUNNING] commit) is the only
    shared-.git mutation, taken under GIT_LOCK; the venv build, the author LLM
    call, and the run are per-slot isolated and run unlocked, in parallel with
    other slots. No plan this round -> return; the sweep retries."""
    sel = select_one(n)
    if not sel:
        return
    op, ref = sel
    parent_ref, psha = ("HEAD", "") if op == "draft" else (ref, ref)
    with GIT_LOCK:
        branch = f"agent/{run_tag}/n{next_index()}-{op}"
        sh("scripts/slot_add.sh", str(n), parent_ref, branch, op,
           *([psha] if psha else []))
    # unlocked from here — per-slot isolated
    sh("scripts/slot_setup.sh", str(n), run_tag, *([psha] if psha else []))
    cwd, py = wt_of(n), py_of(n)
    if op == "draft":
        spec = f"Task spec: {{run_tag: {run_tag}, cwd: {cwd}, python: {py}}}"
    elif op == "improve":
        spec = (f"Task spec: {{run_tag: {run_tag}, parent_sha: {psha}, "
                f"cwd: {cwd}, python: {py}}}")
    else:  # debug
        spec = (f"Task spec: {{run_tag: {run_tag}, target_sha: {psha}, "
                f"cwd: {cwd}, python: {py}}}")
    call_agent(op, os.path.join(REPO, cwd), spec)
    run_or_bug(n, cfg()["wall_minutes"])


def service_slot(n):
    """One slot's full cycle, independent of every other slot. Skipped if the run
    is still live (a sweep fired on a busy slot); otherwise complete the finished
    node then dispatch the next. Per-slot errors are isolated — a bad slot logs
    and frees its WORKING flag so the sweep retries it, never killing the loop."""
    try:
        if live_train(n):
            return
        complete_slot(n)
        dispatch_slot(n)
    except Exception as e:
        sys.stderr.write(f"[orchestrator] slot={n} worker failed: {e}\n")
    finally:
        with WORKING_LOCK:
            WORKING.discard(n)


def submit(n):
    """Start a worker for slot n iff one isn't already active. The event tail and
    the idle sweep can both see the same free slot; the check-and-set guarantees
    exactly one worker per slot at a time. Returns True iff THIS call started the
    worker, so the sweep can stagger only real new starts."""
    with WORKING_LOCK:
        if n in WORKING:
            return False
        WORKING.add(n)
    try:
        POOL.submit(service_slot, n)
        return True
    except Exception as e:  # pool broken/shutdown — release the flag so we retry
        with WORKING_LOCK:
            WORKING.discard(n)
        sys.stderr.write(f"[orchestrator] submit slot={n} failed: {e}\n")
        return False


# --- startup recovery ---------------------------------------------------------
def recover():
    """Reconcile declared vs real state, single-threaded (runs before any worker,
    so it needs no GIT_LOCK). Fixes the slot_reconcile.sh gap: a run that
    completed during downtime (worktree present, train.py not live, score written,
    still [RUNNING]) must be finalized BEFORE reconcile, or reconcile would
    discard it as 'stalled'. Does NOT dispatch — the poller's first sweep hands
    every idle slot to a worker."""
    n_slots = cfg()["n_slots"]
    for n in range(n_slots):
        if not os.path.isdir(wt_of(n)) or live_train(n):
            continue
        score = f"{wt_of(n)}/runs/staging/score"
        subj = out("git", "-C", wt_of(n), "log", "-1", "--format=%s")
        # A written score means the run COMPLETED — route it to finalize so it is
        # never discarded by reconcile (which would `git branch -D` the node away).
        # [RUNNING]: completed during downtime, still needs judging + amend.
        # else: finalize itself crashed AFTER amending — already judged, so just
        # complete the idempotent cleanup; do NOT re-analyze.
        if os.path.isfile(score):
            if "[RUNNING]" in subj:
                op, psha = recover_op_parent(n)
                analyze_one(n)
                sh("scripts/slot_freeze.sh", str(n))
                finalize_one(n, op, psha)
            else:
                sh("scripts/slot_freeze.sh", str(n))
                finalize_one(n, *recover_op_parent(n))
    # Reconcile cleans the genuinely-stalled slots; running slots keep their
    # detached run (its event arrives via the tail). Idle slots are left for the
    # sweep to dispatch.
    sh("scripts/slot_reconcile.sh", run_tag, str(n_slots))


# --- poller (single consumer) -------------------------------------------------
def poller(offset, n_slots):
    """The only consumer thread: it dispatches work but never performs it, so it
    is never blocked by a long author/analyze/finalize. Two wake sources:
      - events.log tail: a `slot=N exit=…` line hands slot N to a worker.
      - periodic sweep: any slot with no live run and no active worker is handed
        to a worker — this covers startup idle slots and a worker that died
        before launching its run (so no slot can stall forever)."""
    last_sweep = 0.0
    while True:
        with open(EVENTS) as f:
            f.seek(offset)
            while True:
                line = f.readline()
                if not line:
                    break
                if not line.endswith("\n"):
                    break  # partial line; retry next poll from same offset
                offset = f.tell()
                m = EVENT_RE.match(line)
                if m:
                    submit(int(m.group(1)))
        now = time.monotonic()
        if now - last_sweep >= SWEEP_EVERY:
            last_sweep = now
            stagger = cfg().get("dispatch_stagger", DISPATCH_STAGGER)
            for n in range(n_slots):
                # submit() returns False (no-op) if the slot already has a worker;
                # service_slot re-checks live_train. Stagger only REAL new starts so
                # a fleet of drafts doesn't storm the LLM API at t=0.
                if not live_train(n) and submit(n) and stagger:
                    time.sleep(stagger)
        time.sleep(1.0)


def main():
    global POOL
    open(EVENTS, "a").close()  # driver legitimately owns events.log
    start_offset = os.path.getsize(EVENTS)  # ignore historical events
    n_slots = cfg()["n_slots"]
    POOL = ThreadPoolExecutor(max_workers=n_slots)
    recover()
    poller(start_offset, n_slots)


if __name__ == "__main__":
    main()
