#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

SOURCE="$TMP/glossary.md"
DEST="$TMP/repo/docs/glossary.md"

cat >"$SOURCE" <<'MD'
---
date: 2026-05-08
domain: Altamira
---

# Glossary

Keep this paragraph.

---

Keep this horizontal-rule section.
MD

"$ROOT/skills/domain-glossary/scripts/render-repo-mirror.sh" \
  --source "$SOURCE" \
  --dest "$DEST" >/dev/null

grep -q "Generated mirror" "$DEST"
grep -q "Keep this paragraph" "$DEST"
grep -q "Keep this horizontal-rule section" "$DEST"
! grep -q "domain: Altamira" "$DEST"

BEFORE="$(sha256sum "$SOURCE" 2>/dev/null || shasum -a 256 "$SOURCE")"
if "$ROOT/skills/domain-glossary/scripts/render-repo-mirror.sh" \
  --source "$SOURCE" \
  --dest "$SOURCE" >/dev/null 2>&1; then
  echo "same-file render unexpectedly succeeded" >&2
  exit 1
fi
AFTER="$(sha256sum "$SOURCE" 2>/dev/null || shasum -a 256 "$SOURCE")"
[[ "$BEFORE" == "$AFTER" ]]

echo "render mirror fixtures passed"
