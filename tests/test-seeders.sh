#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/example-repo"
mkdir -p "$REPO/src"
git -c init.defaultBranch=main -C "$TMP" init example-repo >/dev/null
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name "Test User"

cat >"$REPO/src/bridge.py" <<'PY'
def smooth_phase_boundaries():
    return "ok"


class BoundaryContinuity:
    pass
PY

git -C "$REPO" add .
git -C "$REPO" commit -m "Add smooth phase boundary validation" >/dev/null
git -C "$REPO" commit --allow-empty -m "Document smooth phase boundary validation" >/dev/null
git -C "$REPO" worktree add -b fixture-worktree "$TMP/example-worktree" >/dev/null 2>&1

COMMIT_OUTPUT="$(
  "$ROOT/skills/domain-glossary/scripts/seed-from-commits.sh" \
    --repo "$REPO" \
    --min-count 2 \
    --limit 20
)"
grep -q "smooth phase" <<<"$COMMIT_OUTPUT"

WORKTREE_OUTPUT="$(
  "$ROOT/skills/domain-glossary/scripts/seed-from-commits.sh" \
    --repo "$TMP/example-worktree" \
    --min-count 2 \
    --limit 20
)"
grep -q "smooth phase" <<<"$WORKTREE_OUTPUT"

DB="$TMP/claude-mem.db"
sqlite3 "$DB" <<'SQL'
CREATE TABLE observations (
  id INTEGER PRIMARY KEY,
  project TEXT NOT NULL,
  title TEXT,
  subtitle TEXT,
  narrative TEXT,
  text TEXT,
  concepts TEXT,
  created_at_epoch INTEGER NOT NULL
);
INSERT INTO observations VALUES
  (1, 'mtf-builder', 'Smooth phase boundary validation', '', 'smooth phase boundary validation protects continuity', '', 'smooth phase boundary', 3),
  (2, 'mtf-builder', 'Smooth phase boundary fix', '', 'smooth phase boundary drift check', '', 'smooth phase boundary', 2),
  (3, 'mtf-builder', 'Smooth phase boundary report', '', 'smooth phase boundary metrics', '', 'smooth phase boundary', 1);
SQL

MEM_OUTPUT="$(
  "$ROOT/skills/domain-glossary/scripts/seed-from-claude-mem.sh" \
    --db "$DB" \
    --project mtf-builder \
    --query smooth \
    --min-count 3 \
    --limit 20
)"
grep -q "smooth phase" <<<"$MEM_OUTPUT"
grep -q "1,2,3\\|3,2,1" <<<"$MEM_OUTPUT"

SYMBOL_OUTPUT="$(
  "$ROOT/skills/domain-glossary/scripts/seed-from-gitnexus.sh" \
    --repo "$REPO" \
    --repo-name example-repo \
    --limit 20
)"
grep -q 'smooth_phase_boundaries' <<<"$SYMBOL_OUTPUT"
grep -q '`smooth_phase_boundaries` in `example-repo:src/bridge.py`' <<<"$SYMBOL_OUTPUT"

echo "seeder fixtures passed"
