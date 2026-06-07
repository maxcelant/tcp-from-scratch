#!/usr/bin/env bash
# Convenience wrapper for `make review`. Runs the current lesson's integration
# check if one exists. For the full review (file/symbol/test checks + progress
# advancement) use the `/review` skill in Claude Code instead.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

CUR="$(awk -F': *' '/^current:/{print $2; exit}' .progress 2>/dev/null || echo 00)"
echo "current lesson: ${CUR}"

# Always-on static checks.
if [ -f go.mod ]; then
  echo "==> go build ./..."
  go build ./... || { echo "build failed"; exit 1; }
  echo "==> go vet ./..."
  go vet ./... || true
  echo "==> go test ./..."
  go test ./... 2>/dev/null || true
fi

CHECK="scripts/check-L${CUR}.sh"
if [ -f "$CHECK" ]; then
  echo "==> ${CHECK}"
  exec bash "$CHECK"
else
  echo "No integration check for lesson ${CUR} (file/symbol/test checks only)."
  echo "Run /review in Claude Code for the full, progress-advancing review."
fi
