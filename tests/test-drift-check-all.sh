#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

VAULT="$TMP/vault"
mkdir -p "$VAULT/Altamira" "$VAULT/Foo"

# --- Repo Alpha: has the cited symbol ---
ALPHA="$TMP/alpha"
mkdir -p "$ALPHA/src"
cat >"$ALPHA/src/lib.py" <<'PY'
def alpha_symbol():
    return "ok"
PY

# --- Repo Beta: cited symbol was moved (so it should show RELOCATED) ---
BETA="$TMP/beta"
mkdir -p "$BETA/src/new_home"
cat >"$BETA/src/new_home/relocated.py" <<'PY'
def beta_symbol():
    return "moved"
PY

# Two glossaries.
cat >"$VAULT/Altamira/glossary.md" <<'MD'
### Alpha symbol

**Citation:** `alpha_symbol` in `alpha:src/lib.py`

Definition.
MD

cat >"$VAULT/Foo/glossary.md" <<'MD'
### Beta symbol

**Citation:** `beta_symbol` in `beta:src/old_home/relocated.py`

Definition.

### Gone symbol

**Citation:** `gone_symbol` in `beta:src/nowhere.py`

Definition.
MD

# domain-glossary.local.md
CONFIG="$TMP/domain-glossary.local.md"
cat >"$CONFIG" <<MD
---
domains:
  - name: Altamira
    glossary: $VAULT/Altamira/glossary.md
    repos:
      - $ALPHA
  - name: Foo
    glossary: $VAULT/Foo/glossary.md
    repos:
      - $BETA
---
MD

DRIFT_ALL="$ROOT/skills/domain-glossary/scripts/drift-check-all.sh"

# --- Test 1: text output runs and exits with drift count ---
set +e
OUT=$("$DRIFT_ALL" --config "$CONFIG" 2>&1)
RC=$?
set -e

# Expect: Alpha RESOLVED=1; Foo has 1 RELOCATED + 1 UNRESOLVED = drift=2.
if [[ "$RC" -ne 2 ]]; then
  echo "FAIL: expected exit 2, got $RC" >&2
  echo "$OUT" >&2
  exit 1
fi
echo "$OUT" | grep -q "DOMAIN Altamira" || { echo "FAIL: Altamira missing"; echo "$OUT"; exit 1; }
echo "$OUT" | grep -q "DOMAIN Foo" || { echo "FAIL: Foo missing"; echo "$OUT"; exit 1; }
echo "$OUT" | grep -q "RESOLVED=1  RELOCATED=0  UNRESOLVED=0" || { echo "FAIL: Alpha counts"; echo "$OUT"; exit 1; }
echo "$OUT" | grep -q "RESOLVED=0  RELOCATED=1  UNRESOLVED=1" || { echo "FAIL: Foo counts"; echo "$OUT"; exit 1; }
echo "$OUT" | grep -q "SUMMARY  RESOLVED=1  RELOCATED=1  UNRESOLVED=1" || { echo "FAIL: summary"; echo "$OUT"; exit 1; }
echo "PASS: text output and counts"

# --- Test 2: JSON output emits a summary line ---
set +e
JSON=$("$DRIFT_ALL" --config "$CONFIG" --json 2>&1)
RC=$?
set -e
[[ "$RC" -eq 2 ]] || { echo "FAIL: json exit $RC"; echo "$JSON"; exit 1; }
echo "$JSON" | grep -q '"summary":true' || { echo "FAIL: no summary line"; echo "$JSON"; exit 1; }
echo "$JSON" | grep -q '"relocated":1' || { echo "FAIL: relocated count"; echo "$JSON"; exit 1; }
echo "$JSON" | grep -q '"unresolved":1' || { echo "FAIL: unresolved count"; echo "$JSON"; exit 1; }
echo "$JSON" | grep -q '"domain":"Foo"' || { echo "FAIL: domain tagging"; echo "$JSON"; exit 1; }
echo "PASS: json output"

# --- Test 3: missing glossary file shows up ---
rm "$VAULT/Foo/glossary.md"
set +e
OUT2=$("$DRIFT_ALL" --config "$CONFIG" 2>&1)
RC=$?
set -e
echo "$OUT2" | grep -q "glossary missing" || { echo "FAIL: missing glossary not reported"; echo "$OUT2"; exit 1; }
echo "$OUT2" | grep -q "MISSING_GLOSSARIES=1" || { echo "FAIL: missing count"; echo "$OUT2"; exit 1; }
[[ "$RC" -ge 1 ]] || { echo "FAIL: missing glossary should produce non-zero exit"; exit 1; }
echo "PASS: missing-glossary handling"

# --- Test 4: clean glossary returns 0 ---
rm "$VAULT/Altamira/glossary.md"
cat >"$VAULT/Altamira/glossary.md" <<'MD'
### Alpha symbol

**Citation:** `alpha_symbol` in `alpha:src/lib.py`

Definition.
MD
cat >"$CONFIG" <<MD
---
domains:
  - name: Altamira
    glossary: $VAULT/Altamira/glossary.md
    repos:
      - $ALPHA
---
MD
set +e
"$DRIFT_ALL" --config "$CONFIG" >/dev/null 2>&1
RC=$?
set -e
[[ "$RC" -eq 0 ]] || { echo "FAIL: clean glossary expected exit 0, got $RC"; exit 1; }
echo "PASS: clean glossary exits 0"

echo "ALL PASS"
