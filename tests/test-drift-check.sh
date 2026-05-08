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
LOCAL_ONLY = "module"


def relocated_symbol():
    return "moved"


def comment_only_symbol():
    local_assignment = "not stable"
    return "definition"
PY

cat >"$VAULT/Altamira/source-note.md" <<'MD'
# Source Note
MD
cat >"$TMP/outside.md" <<'MD'
# Outside Vault
MD
cat >"$TMP/outside.py" <<'PY'
# Outside repo
PY

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

### Escaping path

**Domain:** Altamira
**Citation:** `example-repo:../outside.py:1`
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

### Local assignment

**Domain:** Altamira
**Citation:** `local_assignment` in `example-repo:src/moved.py`
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
grep -q "UNRESOLVED.*Escaping path.*path escapes repo" <<<"$OUTPUT"
grep -q "RELOCATED.*Relocated symbol.*relocated_symbol" <<<"$OUTPUT"
grep -q "RELOCATED.*Comment-only old hit.*comment_only_symbol" <<<"$OUTPUT"
grep -q "UNRESOLVED.*Traversal note.*note escapes vault" <<<"$OUTPUT"
grep -q "UNRESOLVED.*Local assignment.*local_assignment" <<<"$OUTPUT"
grep -q "UNRESOLVED.*Missing symbol.*missing_symbol" <<<"$OUTPUT"

JSON_OUTPUT="$(
  "$ROOT/skills/domain-glossary/scripts/drift-check.sh" \
    --json \
    --vault "$VAULT" \
    --repo "example-repo=$REPO" \
    "$TMP/glossary.md"
)"

python3 - <<'PY' <<<"$JSON_OUTPUT"
import json
import sys

rows = [json.loads(line) for line in sys.stdin if line.strip()]
by_term = {row["term"]: row for row in rows}

assert by_term["Smooth phase boundaries"]["status"] == "RESOLVED"
assert by_term["Smooth phase boundaries"]["kind"] == "symbol"

relocated = by_term["Comment-only old hit"]
assert relocated["status"] == "RELOCATED"
assert relocated["kind"] == "symbol"
assert relocated["suggestion"] == "`comment_only_symbol` in `example-repo:src/moved.py`"

escaping = by_term["Escaping path"]
assert escaping["status"] == "UNRESOLVED"
assert escaping["kind"] == "path"
assert "path escapes repo" in escaping["detail"]

local_assignment = by_term["Local assignment"]
assert local_assignment["status"] == "UNRESOLVED"
assert local_assignment["kind"] == "symbol"

traversal = by_term["Traversal note"]
assert traversal["status"] == "UNRESOLVED"
assert traversal["kind"] == "note"
assert "note escapes vault" in traversal["detail"]
PY

echo "drift-check fixtures passed"
