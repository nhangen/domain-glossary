#!/usr/bin/env bash
# drift-check-on-commit.sh
#
# Fire a drift check asynchronously after a git commit. This script returns
# within milliseconds so it never measurably slows the commit-capture flow.
# The actual work runs in a detached subshell under a hard timeout.
#
# State-file semantics (per ~/.claude/rules/ceo-automated-writers-are-playbooks):
#   - On detected drift (RELOCATED, UNRESOLVED, or missing glossary):
#     OVERWRITE $CEO_VAULT/CEO/alerts/glossary-drift.md with status=firing.
#   - On clean check (all RESOLVED): OVERWRITE with status=clear.
#   - On error or timeout: stderr only. State file is left untouched so a
#     transient failure does not silently clear an active alert (mirrors the
#     `measurement_failed` invariant in ceo-disk-monitor.sh).
#
# Environment:
#   CEO_VAULT                 — Obsidian vault root. Default: $HOME/Documents/Obsidian
#   DOMAIN_GLOSSARY_CONFIG    — Override domain-glossary.local.md path.
#   DRIFT_CHECK_TIMEOUT_SECS  — Override the 30s timeout (testing only).
#   DRIFT_CHECK_FOREGROUND    — If set to 1, run synchronously (testing only).
#
# Usage:
#   drift-check-on-commit.sh        # detach + return immediately
#
# Exit status: 0 always (we don't block the parent). Failures land in stderr.

set -uo pipefail

: "${HOME:?HOME must be set before drift-check-on-commit}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DRIFT_CHECK_ALL="$SCRIPT_DIR/drift-check-all.sh"
CEO_VAULT="${CEO_VAULT:-$HOME/Documents/Obsidian}"
ALERT_FILE="$CEO_VAULT/CEO/alerts/glossary-drift.md"
TIMEOUT_SECS="${DRIFT_CHECK_TIMEOUT_SECS:-30}"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
CONFIG="${DOMAIN_GLOSSARY_CONFIG:-$PLUGIN_ROOT/domain-glossary.local.md}"

# Skip entirely if the user hasn't configured a glossary.
if [[ ! -f "$CONFIG" ]]; then
  exit 0
fi

# Find a timeout command. On macOS without coreutils, `timeout` may be absent
# but `gtimeout` from homebrew coreutils is available. If neither exists, we
# still fire-and-forget, but we cap runtime via a watchdog subshell.
TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi

run_check() {
  # python3 is used twice (summary parse + drift-line formatting). Without it,
  # the first call's output would be empty (caught by the [[ -z $counts ]]
  # guard, state preserved) but the second call would silently produce an
  # empty bullet list while still writing status=firing — losing actionable
  # detail with no signal. Bail at the entry point to preserve state intact.
  if ! command -v python3 >/dev/null 2>&1; then
    echo "glossary-drift: python3 unavailable; skipping drift check" >&2
    return 0
  fi

  local stderr_file stdout_file rc lockdir
  stderr_file="$(mktemp -t glossary-drift.err.XXXXXX)"
  stdout_file="$(mktemp -t glossary-drift.out.XXXXXX)"

  # Serialize concurrent runs (N commits in a rebase, parallel hooks). Without
  # this, two children read the same prior state and the second can clobber
  # the first's firing→since timestamp, or overwrite firing with stale clear.
  # mkdir is portable atomic-create across macOS/Linux without depending on
  # flock(1) (not in macOS base).
  lockdir="$ALERT_FILE.lock.d"
  mkdir -p "$(dirname "$lockdir")"
  if ! mkdir "$lockdir" 2>/dev/null; then
    # Stale-lock detection: if the holder's PID is gone, reclaim.
    local holder_pid=""
    if [[ -f "$lockdir/pid" ]]; then
      holder_pid="$(cat "$lockdir/pid" 2>/dev/null)"
    fi
    if [[ -n "$holder_pid" ]] && ! kill -0 "$holder_pid" 2>/dev/null; then
      rm -rf "$lockdir"
      if ! mkdir "$lockdir" 2>/dev/null; then
        echo "glossary-drift: lock contention after reclaim attempt; skipping" >&2
        rm -f "$stderr_file" "$stdout_file"
        return 0
      fi
    else
      # Active holder; skip this run. The held run will write fresh state.
      rm -f "$stderr_file" "$stdout_file"
      return 0
    fi
  fi
  echo $$ >"$lockdir/pid"

  # shellcheck disable=SC2064
  trap "rm -rf '$lockdir'; rm -f '$stderr_file' '$stdout_file'" EXIT

  if [[ -n "$TIMEOUT_BIN" ]]; then
    "$TIMEOUT_BIN" --signal=KILL "${TIMEOUT_SECS}" \
      "$DRIFT_CHECK_ALL" --config "$CONFIG" --json \
      >"$stdout_file" 2>"$stderr_file"
    rc=$?
    if [[ "$rc" -eq 137 || "$rc" -eq 124 ]]; then
      echo "glossary-drift: drift-check-all timed out after ${TIMEOUT_SECS}s" >&2
      [[ -s "$stderr_file" ]] && cat "$stderr_file" >&2
      return 0
    fi
  else
    # Fallback watchdog: launch drift-check-all, kill the whole process tree
    # on timeout. `kill -9 $child` alone leaves python3 descendants alive
    # (they reparent to init and keep writing). pkill -P sweeps direct
    # children; we do that before killing the wrapper so the tree is gone.
    "$DRIFT_CHECK_ALL" --config "$CONFIG" --json \
      >"$stdout_file" 2>"$stderr_file" &
    local child=$!
    (
      sleep "$TIMEOUT_SECS"
      pkill -9 -P "$child" 2>/dev/null
      kill -9 "$child" 2>/dev/null
    ) &
    local watchdog=$!
    wait "$child" 2>/dev/null
    rc=$?
    # Silence "Terminated" job-control message when killing the watchdog.
    { kill "$watchdog" 2>/dev/null && wait "$watchdog" 2>/dev/null; } || true
    if [[ "$rc" -eq 137 || "$rc" -eq 143 ]]; then
      echo "glossary-drift: drift-check-all timed out after ${TIMEOUT_SECS}s" >&2
      return 0
    fi
  fi

  # rc from drift-check-all is the count of non-RESOLVED citations (0-255).
  # Stderr at this stage means the script itself errored (config missing,
  # python failure, etc.) — bail without touching the state file.
  if [[ ! -s "$stdout_file" && -s "$stderr_file" ]]; then
    echo "glossary-drift: drift-check-all error:" >&2
    cat "$stderr_file" >&2
    return 0
  fi

  # Parse the final summary line: {"summary":true,...}
  local summary
  summary="$(grep '"summary":true' "$stdout_file" | tail -n 1)"
  if [[ -z "$summary" ]]; then
    echo "glossary-drift: drift-check-all produced no summary line" >&2
    [[ -s "$stderr_file" ]] && cat "$stderr_file" >&2
    return 0
  fi

  # Extract counts with a tiny python helper (no jq dependency).
  # NOTE: bash 3.2 mis-parses $(python3 - <<'PY' ... PY) when the body
  # contains certain quote shapes; pass the summary as stdin instead.
  local counts
  counts="$(printf '%s' "$summary" | python3 -c '
import json, sys
try:
    s = json.loads(sys.stdin.read())
except Exception:
    print("PARSE_ERROR", file=sys.stderr)
    sys.exit(0)
required = ("resolved", "relocated", "unresolved", "glossaries_missing")
missing = [k for k in required if k not in s]
if missing:
    print("MISSING_KEYS: " + ",".join(missing), file=sys.stderr)
    sys.exit(0)
print("{0}\t{1}\t{2}\t{3}\t{4}".format(s["resolved"], s["relocated"], s["unresolved"], s["glossaries_missing"], s.get("check_failed", 0)))
')"
  if [[ -z "$counts" ]]; then
    echo "glossary-drift: failed to parse summary: $summary" >&2
    return 0
  fi
  IFS=$'\t' read -r resolved relocated unresolved missing check_failed <<<"$counts"
  : "${check_failed:=0}"

  local drift=$((relocated + unresolved + missing + check_failed))
  local status timestamp since prior_status prior_since
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "$drift" -gt 0 ]]; then
    status="firing"
  else
    status="clear"
  fi

  # Preserve `since` across runs in the same status. If the prior file exists
  # but lacks a parseable `status:` frontmatter field, treat it as corruption
  # and preserve `prior_since` rather than resetting — mirrors the disk-monitor
  # measurement_failed invariant (transient corruption shouldn't reset the
  # firing-start timestamp).
  prior_status=""
  prior_since=""
  if [[ -f "$ALERT_FILE" ]]; then
    prior_status="$(sed -n 's/^status:[[:space:]]*//p' "$ALERT_FILE" | head -n 1)"
    prior_since="$(sed -n 's/^since:[[:space:]]*//p' "$ALERT_FILE" | head -n 1)"
  fi
  if [[ -f "$ALERT_FILE" && -z "$prior_status" ]]; then
    # Corrupt prior file: status field missing/unreadable. Preserve since if we
    # could still parse it; otherwise fall through to current timestamp.
    if [[ -n "$prior_since" ]]; then
      since="$prior_since"
    else
      since="$timestamp"
    fi
    echo "glossary-drift: prior alert file lacks parseable status; preserving since" >&2
  elif [[ "$status" == "$prior_status" && -n "$prior_since" ]]; then
    since="$prior_since"
  else
    since="$timestamp"
  fi

  # Build the drifted-citation list (top 25 — bounded so the alert stays scannable).
  local drift_lines=""
  if [[ "$drift" -gt 0 ]]; then
    drift_lines="$(grep -E '"status":"(RELOCATED|UNRESOLVED)"' "$stdout_file" \
      | head -n 25 \
      | python3 -c '
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except Exception:
        continue
    domain = d.get("domain","?")
    status = d.get("status","?")
    term = d.get("term","?")
    detail = d.get("detail","")
    suggestion = d.get("suggestion","")
    suffix = " -> " + suggestion if suggestion else ""
    print("- **" + domain + "** | `" + term + "` | " + status + " - " + detail + suffix)
')"
  fi

  mkdir -p "$(dirname "$ALERT_FILE")"
  local tmp="$ALERT_FILE.tmp.$$"
  {
    echo "---"
    echo "status: $status"
    echo "since: $since"
    echo "last_check: $timestamp"
    echo "resolved: $resolved"
    echo "relocated: $relocated"
    echo "unresolved: $unresolved"
    echo "glossaries_missing: $missing"
    echo "check_failed: $check_failed"
    echo "writer: domain-glossary"
    echo "---"
    echo
    echo "# Glossary Drift"
    echo
    if [[ "$status" == "firing" ]]; then
      echo "$drift citation(s) need review."
      echo
      echo "$drift_lines"
    else
      echo "All citations resolve cleanly."
    fi
  } >"$tmp"
  mv "$tmp" "$ALERT_FILE"
}

if [[ "${DRIFT_CHECK_FOREGROUND:-0}" == "1" ]]; then
  run_check
  exit 0
fi

# Detach so the commit hook returns immediately. Use nohup for SIGHUP resistance
# (setsid is not available on macOS). Re-exec self with --__bg-run so the
# detached child re-enters with the foreground codepath.
LOG="${TMPDIR:-/tmp}/glossary-drift.log"
if [[ "${1:-}" == "--__bg-run" ]]; then
  run_check
  exit 0
fi

DRIFT_CHECK_FOREGROUND=1 \
  CEO_VAULT="$CEO_VAULT" \
  DOMAIN_GLOSSARY_CONFIG="$CONFIG" \
  DRIFT_CHECK_TIMEOUT_SECS="$TIMEOUT_SECS" \
  nohup "$0" --__bg-run </dev/null >>"$LOG" 2>&1 &
disown 2>/dev/null || true
exit 0
