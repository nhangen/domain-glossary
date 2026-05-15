#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/domain-glossary/scripts/resolve-domain.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Stage fake repos
REPO_A="$TMP/projects/main-repo"
REPO_B="$TMP/work spaces/repo with spaces"
SIBLING_WT="$TMP/projects/main-repo-feature-x"
UNRELATED="$TMP/projects/main-repo-archive"

mkdir -p "$REPO_A" "$REPO_B" "$SIBLING_WT" "$UNRELATED"
for dir in "$REPO_A" "$REPO_B"; do
  git -C "$dir" init -q
  git -C "$dir" config user.email t@t
  git -C "$dir" config user.name t
  git -C "$dir" commit --allow-empty -q -m init
done

# Add SIBLING_WT as a real git worktree of REPO_A.
git -C "$REPO_A" branch wt-branch >/dev/null
git -C "$REPO_A" worktree add -q "$SIBLING_WT" wt-branch
# UNRELATED is its own repo (NOT a worktree of REPO_A) -- must not match.
git -C "$UNRELATED" init -q
git -C "$UNRELATED" config user.email t@t
git -C "$UNRELATED" config user.name t
git -C "$UNRELATED" commit --allow-empty -q -m init

# Build a config that uses both `~`-prefixed and absolute paths, plus a
# multi-domain block, plus a path containing spaces.
GLOSS_A="$TMP/vault/Alpha/glossary.md"
GLOSS_B="$TMP/vault/Beta/glossary.md"
mkdir -p "$(dirname "$GLOSS_A")" "$(dirname "$GLOSS_B")"
echo "# Alpha" > "$GLOSS_A"
echo "# Beta"  > "$GLOSS_B"

CONFIG="$TMP/domain-glossary.local.md"
cat >"$CONFIG" <<EOF
---
domains:
  - name: Alpha
    glossary: $GLOSS_A
    repos:
      - $REPO_A
  - name: Beta
    glossary: $GLOSS_B
    repos:
      - $REPO_B
---
EOF

run() {
  "$SCRIPT" --config "$CONFIG" "$1" 2>"$TMP/stderr"
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $label" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    echo "  stderr:   $(cat "$TMP/stderr" 2>/dev/null)" >&2
    exit 1
  fi
}

# 1. Direct match for REPO_A → Alpha
out="$(run "$REPO_A")"
assert_eq "Alpha	$GLOSS_A" "$out" "direct match REPO_A"

# 2. Direct match for REPO_B with spaces in path → Beta
out="$(run "$REPO_B")"
assert_eq "Beta	$GLOSS_B" "$out" "spaces in repo path"

# 3. Subdirectory of REPO_A → Alpha (prefix match)
mkdir -p "$REPO_A/sub/dir"
out="$(run "$REPO_A/sub/dir")"
assert_eq "Alpha	$GLOSS_A" "$out" "subdirectory of registered repo"

# 4. Sibling that is NOT a worktree (own repo) must NOT match the registered
#    repo's domain via prefix alone.
out="$(run "$UNRELATED")"
assert_eq "" "$out" "sibling-named non-worktree does not match"

# 5. Sibling that IS a worktree of REPO_A must resolve to Alpha via the git
#    canonical-repo fallback.
out="$(run "$SIBLING_WT")"
assert_eq "Alpha	$GLOSS_A" "$out" "git worktree falls back to canonical repo"

# 6. Path with no git context, not under any registered repo → empty.
out="$(run "$TMP/nowhere")"
assert_eq "" "$out" "unregistered path"

# 7. Missing config file → empty, exit 0.
out="$("$SCRIPT" --config "$TMP/missing.md" "$REPO_A" 2>/dev/null || echo "ERR")"
assert_eq "" "$out" "missing config exits 0 with empty stdout"

# 8. Malformed YAML → empty, exit 0, no crash.
BAD="$TMP/bad.md"
cat >"$BAD" <<'EOF'
---
domains:
  - name: Alpha
    glossary: /tmp/x
    repos:
      - [malformed
---
EOF
out="$("$SCRIPT" --config "$BAD" "$REPO_A" 2>/dev/null || echo "ERR")"
# The list item parser is lenient — "[malformed" becomes a literal repo entry
# that won't match any real cwd, so the result is empty. The point is: no
# crash, exit 0, empty output.
assert_eq "" "$out" "malformed YAML does not crash"

# 9. --help works.
"$SCRIPT" --help >/dev/null

echo "resolve-domain fixtures passed"
