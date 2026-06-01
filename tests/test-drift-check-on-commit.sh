#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

HOOK="$ROOT/skills/domain-glossary/scripts/drift-check-on-commit.sh"

# --- Fixture: one repo, one glossary, one drift case ---
REPO="$TMP/repo"
mkdir -p "$REPO/src/new_home"
cat >"$REPO/src/new_home/lib.py" <<'PY'
def relocated_thing():
    return "moved"
PY

VAULT="$TMP/vault"
mkdir -p "$VAULT/Test"
cat >"$VAULT/Test/glossary.md" <<'MD'
### Relocated thing

**Citation:** `relocated_thing` in `repo:src/old/lib.py`

Definition.
MD

CONFIG="$TMP/domain-glossary.local.md"
cat >"$CONFIG" <<MD
---
domains:
  - name: Test
    glossary: $VAULT/Test/glossary.md
    repos:
      - $REPO
---
MD

CEO_VAULT="$TMP/ceo-vault"

# --- Test 1: foreground mode produces firing state file with drift ---
DRIFT_CHECK_FOREGROUND=1 \
  CEO_VAULT="$CEO_VAULT" \
  DOMAIN_GLOSSARY_CONFIG="$CONFIG" \
  "$HOOK"

ALERT="$CEO_VAULT/CEO/alerts/glossary-drift.md"
[[ -f "$ALERT" ]] || { echo "FAIL: alert file not written"; exit 1; }
grep -q "^status: firing" "$ALERT" || { echo "FAIL: not firing"; cat "$ALERT"; exit 1; }
grep -q "^relocated: 1" "$ALERT" || { echo "FAIL: relocated count wrong"; cat "$ALERT"; exit 1; }
grep -q "Relocated thing" "$ALERT" || { echo "FAIL: missing drift term"; cat "$ALERT"; exit 1; }
echo "PASS: drift detected, state file overwritten with firing"

# --- Test 2: clean glossary writes a clear state file ---
cat >"$VAULT/Test/glossary.md" <<'MD'
### Relocated thing

**Citation:** `relocated_thing` in `repo:src/new_home/lib.py`

Definition.
MD

FIRST_SINCE="$(grep '^since:' "$ALERT" | awk '{print $2}')"
sleep 1

DRIFT_CHECK_FOREGROUND=1 \
  CEO_VAULT="$CEO_VAULT" \
  DOMAIN_GLOSSARY_CONFIG="$CONFIG" \
  "$HOOK"

grep -q "^status: clear" "$ALERT" || { echo "FAIL: did not transition to clear"; cat "$ALERT"; exit 1; }
NEW_SINCE="$(grep '^since:' "$ALERT" | awk '{print $2}')"
[[ "$NEW_SINCE" != "$FIRST_SINCE" ]] || { echo "FAIL: since should update on status change"; exit 1; }
echo "PASS: state transitions firing -> clear (since updated)"

# --- Test 3: re-running while clean preserves since timestamp ---
SECOND_SINCE="$NEW_SINCE"
sleep 1
DRIFT_CHECK_FOREGROUND=1 \
  CEO_VAULT="$CEO_VAULT" \
  DOMAIN_GLOSSARY_CONFIG="$CONFIG" \
  "$HOOK"
THIRD_SINCE="$(grep '^since:' "$ALERT" | awk '{print $2}')"
[[ "$THIRD_SINCE" == "$SECOND_SINCE" ]] || { echo "FAIL: since should be preserved when status unchanged"; exit 1; }
echo "PASS: since preserved on same-status reruns"

# --- Test 4: timeout enforced, alert untouched on overrun ---
# Replace the underlying drift-check-all with a sleeping stub.
STUB_DIR="$TMP/stub"
mkdir -p "$STUB_DIR"
cat >"$STUB_DIR/drift-check-all.sh" <<'STUB'
#!/usr/bin/env bash
sleep 60
echo '{"summary":true,"resolved":0,"relocated":0,"unresolved":0,"glossaries_missing":0}'
STUB
chmod +x "$STUB_DIR/drift-check-all.sh"

# Run the hook with the stubbed drift-check-all.
HOOK_COPY="$STUB_DIR/drift-check-on-commit.sh"
cp "$HOOK" "$HOOK_COPY"

# Capture alert before, time the call, capture alert after.
BEFORE_HASH="$(shasum "$ALERT" | awk '{print $1}')"
START=$(date +%s)
DRIFT_CHECK_FOREGROUND=1 \
  DRIFT_CHECK_TIMEOUT_SECS=2 \
  CEO_VAULT="$CEO_VAULT" \
  DOMAIN_GLOSSARY_CONFIG="$CONFIG" \
  "$HOOK_COPY" 2>"$TMP/stderr.log"
END=$(date +%s)
ELAPSED=$((END - START))

[[ "$ELAPSED" -lt 10 ]] || { echo "FAIL: timeout not enforced (took ${ELAPSED}s)"; exit 1; }
grep -q "timed out" "$TMP/stderr.log" || { echo "FAIL: no timeout stderr message"; cat "$TMP/stderr.log"; exit 1; }
AFTER_HASH="$(shasum "$ALERT" | awk '{print $1}')"
[[ "$BEFORE_HASH" == "$AFTER_HASH" ]] || { echo "FAIL: alert file mutated on timeout"; exit 1; }
echo "PASS: timeout enforced; state file preserved"

# --- Test 4b: malformed JSON summary preserves state (schema-strict parser) ---
cat >"$STUB_DIR/drift-check-all.sh" <<'STUB'
#!/usr/bin/env bash
# Emits a valid JSON object that's missing one of the four required count
# keys. Pre-fix, the parser defaulted missing keys to 0 and the firing alert
# would be silently overwritten with status=clear.
echo '{"summary":true,"resolved":0,"relocated":0,"unresolved":0}'
STUB
chmod +x "$STUB_DIR/drift-check-all.sh"

# Seed a firing alert so we can detect a regression that clears it.
mkdir -p "$CEO_VAULT/CEO/alerts"
cat >"$ALERT" <<'PRIOR'
---
status: firing
since: 2026-01-01T00:00:00Z
last_check: 2026-01-01T00:00:00Z
resolved: 0
relocated: 1
unresolved: 0
glossaries_missing: 0
writer: domain-glossary
---

# Glossary Drift

1 citation(s) need review.
PRIOR
BEFORE_HASH="$(shasum "$ALERT" | awk '{print $1}')"
DRIFT_CHECK_FOREGROUND=1 \
  DRIFT_CHECK_TIMEOUT_SECS=10 \
  CEO_VAULT="$CEO_VAULT" \
  DOMAIN_GLOSSARY_CONFIG="$CONFIG" \
  "$HOOK_COPY" 2>"$TMP/stderr4b.log"
AFTER_HASH="$(shasum "$ALERT" | awk '{print $1}')"
[[ "$BEFORE_HASH" == "$AFTER_HASH" ]] || { echo "FAIL: malformed JSON cleared firing state"; cat "$ALERT"; exit 1; }
echo "PASS: malformed JSON summary preserves prior state"

# --- Test 5: detached mode returns quickly (python-based timer for portability) ---
ELAPSED_MS=$(python3 -c '
import os, sys, time, subprocess
env = os.environ.copy()
env["DRIFT_CHECK_TIMEOUT_SECS"] = "10"
env["CEO_VAULT"] = sys.argv[2]
env["DOMAIN_GLOSSARY_CONFIG"] = sys.argv[3]
start = time.time()
subprocess.run([sys.argv[1]], env=env, check=True)
print(int((time.time() - start) * 1000))
' "$HOOK" "$CEO_VAULT" "$CONFIG")
if [[ "$ELAPSED_MS" -lt 2000 ]]; then
  echo "PASS: detached mode returns in ${ELAPSED_MS}ms"
else
  echo "FAIL: detached mode took ${ELAPSED_MS}ms"
  exit 1
fi

# Wait briefly to give background child a chance to finish writing the alert
# so it doesn't outlive the test directory.
sleep 2

echo "ALL PASS"
