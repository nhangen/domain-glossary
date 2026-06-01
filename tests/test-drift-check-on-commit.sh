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

# --- Test 4a: timeout via watchdog fallback (no `timeout`/`gtimeout` on PATH) ---
# The previous test takes the TIMEOUT_BIN branch when coreutils is installed.
# This one forces the fallback path (pkill -P + kill -9 wrapper) by scrubbing
# PATH down to dirs that don't contain timeout/gtimeout.
SCRUB_PATH=""
for d in /usr/bin /bin /usr/sbin /sbin; do
  if [[ ! -x "$d/timeout" && ! -x "$d/gtimeout" ]]; then
    SCRUB_PATH="${SCRUB_PATH:+$SCRUB_PATH:}$d"
  fi
done
if [[ -z "$SCRUB_PATH" ]] || command -v timeout >/dev/null 2>&1 && PATH="$SCRUB_PATH" command -v timeout >/dev/null 2>&1; then
  echo "SKIP: cannot build a PATH without timeout/gtimeout on this host"
else
  rm -f "$ALERT"
  # Re-seed prior state so we can detect a regression that clears it.
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
  cat >"$STUB_DIR/drift-check-all.sh" <<'STUB'
#!/usr/bin/env bash
sleep 60
STUB
  chmod +x "$STUB_DIR/drift-check-all.sh"
  START=$(date +%s)
  PATH="$SCRUB_PATH" \
  DRIFT_CHECK_FOREGROUND=1 \
    DRIFT_CHECK_TIMEOUT_SECS=2 \
    CEO_VAULT="$CEO_VAULT" \
    DOMAIN_GLOSSARY_CONFIG="$CONFIG" \
    "$HOOK_COPY" 2>"$TMP/stderr4a.log"
  END=$(date +%s)
  ELAPSED=$((END - START))
  [[ "$ELAPSED" -lt 10 ]] || { echo "FAIL: watchdog fallback didn't enforce timeout (${ELAPSED}s)"; exit 1; }
  grep -q "timed out" "$TMP/stderr4a.log" || { echo "FAIL: no timeout stderr from watchdog fallback"; cat "$TMP/stderr4a.log"; exit 1; }
  AFTER_HASH="$(shasum "$ALERT" | awk '{print $1}')"
  [[ "$BEFORE_HASH" == "$AFTER_HASH" ]] || { echo "FAIL: watchdog fallback mutated state on timeout"; exit 1; }
  echo "PASS: watchdog fallback enforces timeout; state preserved"
fi

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

# --- Test 4c: lock prevents concurrent state-file clobber ---
# Pre-fix, two near-simultaneous foreground runs read the same prior state and
# the second clobbered the first. With the lock, the second run sees the dir
# held and skips, leaving the first run's state untouched.
cat >"$STUB_DIR/drift-check-all.sh" <<'STUB'
#!/usr/bin/env bash
# Stub that takes 1 second so two parallel runs overlap.
sleep 1
echo '{"summary":true,"resolved":0,"relocated":1,"unresolved":0,"glossaries_missing":0}'
STUB
chmod +x "$STUB_DIR/drift-check-all.sh"
rm -f "$ALERT"
# Run A in background (longer-lived), Run B foreground while A holds the lock.
DRIFT_CHECK_FOREGROUND=1 \
  DRIFT_CHECK_TIMEOUT_SECS=10 \
  CEO_VAULT="$CEO_VAULT" \
  DOMAIN_GLOSSARY_CONFIG="$CONFIG" \
  "$HOOK_COPY" &
A_PID=$!
sleep 0.2
SKIP_STDERR="$TMP/skip-stderr.log"
DRIFT_CHECK_FOREGROUND=1 \
  DRIFT_CHECK_TIMEOUT_SECS=10 \
  CEO_VAULT="$CEO_VAULT" \
  DOMAIN_GLOSSARY_CONFIG="$CONFIG" \
  "$HOOK_COPY" 2>"$SKIP_STDERR"
B_RC=$?
wait "$A_PID"
[[ "$B_RC" -eq 0 ]] || { echo "FAIL: lock-skipped run should still return 0"; exit 1; }
[[ -f "$ALERT" ]] || { echo "FAIL: A should have written the alert"; exit 1; }
grep -q "^relocated: 1" "$ALERT" || { echo "FAIL: A's content missing"; cat "$ALERT"; exit 1; }
echo "PASS: concurrent run skipped while lock held"

# --- Test 5: detached mode actually detaches ---
# The previous version only timed wallclock, which would have passed even if
# the hook ran the (fast) real fixture synchronously. Use a sleeping stub so a
# foreground regression would block the parent for the sleep duration. Then
# assert (a) hook returns quickly and (b) the background worker is still alive
# while the parent has already returned.
DETACH_DIR="$TMP/detach"
mkdir -p "$DETACH_DIR"
cat >"$DETACH_DIR/drift-check-all.sh" <<'STUB'
#!/usr/bin/env bash
# Touch a marker on entry, sleep, touch a second marker on exit. The test
# uses these to verify the worker actually ran asynchronously.
touch "${DRIFT_DETACH_MARKER_DIR:?DRIFT_DETACH_MARKER_DIR must be set}/started"
sleep 4
touch "$DRIFT_DETACH_MARKER_DIR/finished"
echo '{"summary":true,"resolved":0,"relocated":0,"unresolved":0,"glossaries_missing":0}'
STUB
chmod +x "$DETACH_DIR/drift-check-all.sh"
DETACH_HOOK="$DETACH_DIR/drift-check-on-commit.sh"
cp "$HOOK" "$DETACH_HOOK"
MARKER_DIR="$TMP/detach-markers"
mkdir -p "$MARKER_DIR"

# Use a fresh CEO_VAULT so we don't collide with the lockdir from earlier tests.
DETACH_VAULT="$TMP/detach-vault"
mkdir -p "$DETACH_VAULT/CEO/alerts"

ELAPSED_MS=$(
  DRIFT_CHECK_TIMEOUT_SECS=30 \
  CEO_VAULT="$DETACH_VAULT" \
  DOMAIN_GLOSSARY_CONFIG="$CONFIG" \
  DRIFT_DETACH_MARKER_DIR="$MARKER_DIR" \
  python3 -c '
import os, sys, time, subprocess
start = time.time()
subprocess.run([sys.argv[1]], check=True)
print(int((time.time() - start) * 1000))
' "$DETACH_HOOK"
)

if [[ "$ELAPSED_MS" -ge 2000 ]]; then
  echo "FAIL: hook did not detach (took ${ELAPSED_MS}ms with a 4s stub)"
  exit 1
fi

# The worker must still be running — `finished` marker absent, `started` present.
sleep 0.5
[[ -f "$MARKER_DIR/started" ]] || { echo "FAIL: stub never started — detach didn't fire the worker"; exit 1; }
[[ ! -f "$MARKER_DIR/finished" ]] || { echo "FAIL: stub finished before parent returned — not actually async"; exit 1; }

# Wait for the worker to finish so the alert appears.
for _ in $(seq 1 50); do
  [[ -f "$MARKER_DIR/finished" ]] && break
  sleep 0.2
done
[[ -f "$MARKER_DIR/finished" ]] || { echo "FAIL: stub never finished"; exit 1; }
[[ -f "$DETACH_VAULT/CEO/alerts/glossary-drift.md" ]] || { echo "FAIL: alert never written"; exit 1; }
echo "PASS: detached mode runs worker async (hook returned in ${ELAPSED_MS}ms)"

# Wait briefly to give background child a chance to finish writing the alert
# so it doesn't outlive the test directory.
sleep 2

echo "ALL PASS"
