#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/example-repo"
VAULT="$TMP/vault"
mkdir -p "$REPO/src" "$VAULT/Altamira"

cat >"$REPO/src/bridge.py" <<'PY'
def smooth_phase_boundaries():
    return "ok"


# comment_only_symbol moved; this comment must not count as a definition.
PY

cat >"$REPO/src/moved.py" <<'PY'
def relocated_symbol():
    return "moved"


def comment_only_symbol():
    return "definition"
PY

cat >"$VAULT/Altamira/source-note.md" <<'MD'
# Source Note
MD
cat >"$TMP/outside.md" <<'MD'
# Outside Vault
MD

cat >"$TMP/glossary.md" <<'MD'
### Smooth phase boundaries

**Domain:** Altamira
**Citation:** `smooth_phase_boundaries` in `example-repo:src/bridge.py`
**Last verified:** 2026-05-08

Definition.

### Source note

**Domain:** Altamira
**Citation:** [[Altamira/source-note]]
**Last verified:** 2026-05-08

Definition.

### Path citation

**Domain:** Altamira
**Citation:** `example-repo:src/bridge.py:1`
**Last verified:** 2026-05-08

Definition.

### Relocated symbol

**Domain:** Altamira
**Citation:** `relocated_symbol` in `example-repo:src/old.py`
**Last verified:** 2026-05-08

Definition.

### Comment-only old hit

**Domain:** Altamira
**Citation:** `comment_only_symbol` in `example-repo:src/bridge.py`
**Last verified:** 2026-05-08

Definition.

### Traversal note

**Domain:** Altamira
**Citation:** [[../outside]]
**Last verified:** 2026-05-08

Definition.

### Missing symbol

**Domain:** Altamira
**Citation:** `missing_symbol` in `example-repo:src/bridge.py`
**Last verified:** 2026-05-08

Definition.
MD

OUTPUT="$(
  "$ROOT/skills/domain-glossary/scripts/drift-check.sh" \
    --vault "$VAULT" \
    --repo "example-repo=$REPO" \
    "$TMP/glossary.md"
)"

grep -q "RESOLVED.*Smooth phase boundaries.*symbol" <<<"$OUTPUT"
grep -q "RESOLVED.*Source note.*note" <<<"$OUTPUT"
grep -q "RESOLVED.*Path citation.*path" <<<"$OUTPUT"
grep -q "RELOCATED.*Relocated symbol.*relocated_symbol" <<<"$OUTPUT"
grep -q "RELOCATED.*Comment-only old hit.*comment_only_symbol" <<<"$OUTPUT"
grep -q "UNRESOLVED.*Traversal note.*note escapes vault" <<<"$OUTPUT"
grep -q "UNRESOLVED.*Missing symbol.*missing_symbol" <<<"$OUTPUT"

JSON_OUTPUT="$(
  "$ROOT/skills/domain-glossary/scripts/drift-check.sh" \
    --json \
    --vault "$VAULT" \
    --repo "example-repo=$REPO" \
    "$TMP/glossary.md"
)"

grep -q '"status":"RESOLVED"' <<<"$JSON_OUTPUT"
grep -q '"status":"RELOCATED"' <<<"$JSON_OUTPUT"
grep -q '"status":"UNRESOLVED"' <<<"$JSON_OUTPUT"

echo "drift-check fixtures passed"
