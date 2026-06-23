#!/usr/bin/env bash
# scripts/tree_view.sh <run_tag> [keep]
# Bounded tree view for the agents: union of the most-recent <keep> and top-<keep>
# scored nodes, deduped, newest-first, in the `%h %s%n%b` format they read. Keeps
# routing context O(keep) as the DAG grows.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
run_tag="$1"; keep="${2:-100}"
glob="agent/${run_tag}/*"

recent=$(git log --branches="$glob" --format='%H' -n "$keep" 2>/dev/null || true)
top=$(git log --branches="$glob" --format='%H%x09%s' 2>/dev/null \
  | sed -nE 's/^([0-9a-f]+)\t.*\[score=(-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?)\].*/\2 \1/p' \
  | sort -rn -k1,1 | head -n "$keep" | awk '{print $2}')

union=$(printf '%s\n%s\n' "$recent" "$top" | awk 'NF && !seen[$0]++')
[ -n "$union" ] || exit 0                      # no nodes yet -> empty (never walk HEAD)

# Full-DAG op tally (drives select's exploration floor, which must see every node).
echo "# counts: $(git log --branches="$glob" --format=%s 2>/dev/null \
  | grep -oE '^(draft|improve|debug):' | sort | uniq -c | tr '\n' ' ')"
git log --no-walk=sorted --format='%h %s%n%b' $union
