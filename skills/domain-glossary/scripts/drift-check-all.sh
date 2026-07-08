#!/usr/bin/env bash
# drift-check-all.sh
#
# Walk every domain in domain-glossary.local.md and run drift-check.sh on each
# glossary. Aggregate counts (RESOLVED / RELOCATED / UNRESOLVED) per domain and
# overall. Exit status is the count of non-RESOLVED citations (capped at 255),
# so callers can branch on "is there drift" without parsing output.
#
# Usage:
#   drift-check-all.sh                   # text report on stdout
#   drift-check-all.sh --json            # JSON Lines (one per domain) + summary
#   drift-check-all.sh --config <path>   # override domain-glossary.local.md
#
# Repo aliases for each domain's glossary are derived from the registered
# `repos:` entries: the basename of each repo path becomes the alias, mapped to
# the absolute path. This matches how `seed-from-gitnexus.sh` and friends are
# invoked.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
# Prefer plugin-root config, fall back to a version-independent XDG location so
# a plugin update (which recreates the cache dir) can't silently wipe it.
XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/domain-glossary/domain-glossary.local.md"
if [[ -f "$PLUGIN_ROOT/domain-glossary.local.md" ]]; then
  CONFIG="$PLUGIN_ROOT/domain-glossary.local.md"
else
  CONFIG="$XDG_CONFIG"
fi
JSON=0

usage() {
  cat <<'USAGE'
Usage: drift-check-all.sh [options]

Options:
  --config <path>   Override domain-glossary.local.md path.
  --json            Emit JSON Lines instead of human-readable text.
  -h, --help        Show this help.

Exit status equals the number of non-RESOLVED citations (capped at 255).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config) CONFIG="$2"; shift 2 ;;
    --json) JSON=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -f "$CONFIG" ]]; then
  echo "Config not found: $CONFIG" >&2
  exit 2
fi

# Emit domains as TSV: name\tglossary\trepos(comma-joined)
# (Bash 3.2 compatible — no mapfile.)
DOMAINS_TSV="$(python3 - "$CONFIG" <<'PY'
import os
import re
import sys

with open(sys.argv[1]) as f:
    raw = f.read()

m = re.search(r"^---\s*\n(.*?)\n---\s*$", raw, re.MULTILINE | re.DOTALL)
if not m:
    sys.exit(0)

current = None
domains = []
for line in m.group(1).splitlines():
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    if re.match(r"^domains\s*:\s*$", line):
        continue
    mm = re.match(r"^\s*-\s*name\s*:\s*(.+?)\s*$", line)
    if mm:
        if current is not None:
            domains.append(current)
        current = {"name": mm.group(1), "glossary": None, "repos": []}
        continue
    mm = re.match(r"^\s*glossary\s*:\s*(.+?)\s*$", line)
    if mm and current is not None:
        current["glossary"] = os.path.expanduser(mm.group(1))
        continue
    if re.match(r"^\s*repos\s*:\s*$", line):
        continue
    mm = re.match(r"^\s*-\s*(.+?)\s*$", line)
    if mm and current is not None and current.get("glossary"):
        current["repos"].append(os.path.expanduser(mm.group(1)))

if current is not None:
    domains.append(current)

for d in domains:
    if not d.get("glossary"):
        continue
    repos = ",".join(d["repos"])
    print(f"{d['name']}\t{d['glossary']}\t{repos}")
PY
)"

if [[ -z "$DOMAINS_TSV" ]]; then
  echo "No domains with glossary paths found in $CONFIG" >&2
  exit 2
fi

DRIFT_CHECK="$SCRIPT_DIR/drift-check.sh"
if [[ ! -x "$DRIFT_CHECK" ]]; then
  echo "drift-check.sh not executable at $DRIFT_CHECK" >&2
  exit 2
fi

# Totals
TOTAL_RESOLVED=0
TOTAL_RELOCATED=0
TOTAL_UNRESOLVED=0
TOTAL_MISSING=0  # glossary files referenced in config that don't exist on disk
TOTAL_FAILED=0   # drift-check.sh invocations that errored (rc != 0 with empty stdout)

while IFS=$'\t' read -r name glossary repos_csv; do
  [[ -z "$name" ]] && continue

  if [[ ! -f "$glossary" ]]; then
    if [[ "$JSON" == 1 ]]; then
      printf '{"domain":"%s","status":"glossary_missing","path":"%s"}\n' \
        "$name" "$glossary"
    else
      echo "DOMAIN $name: glossary missing ($glossary)"
    fi
    TOTAL_MISSING=$((TOTAL_MISSING + 1))
    continue
  fi

  # Build --repo args. Warn on basename collisions so a config with two repos
  # that share a directory name doesn't silently shadow one of them.
  REPO_ARGS=()
  SEEN_BASENAMES=""
  IFS=',' read -ra REPOS <<<"$repos_csv"
  for r in "${REPOS[@]}"; do
    [[ -z "$r" ]] && continue
    [[ ! -d "$r" ]] && continue
    bn="$(basename "$r")"
    if [[ ",$SEEN_BASENAMES," == *",$bn,"* ]]; then
      echo "drift-check-all: WARNING domain '$name' has two repos with basename '$bn' — second overrides first" >&2
    fi
    SEEN_BASENAMES="$SEEN_BASENAMES,$bn"
    REPO_ARGS+=(--repo "$bn=$r")
  done

  # Run drift-check, parse counts. Always JSON internally for parsing. Capture
  # stderr to a tmpfile so a per-domain check failure surfaces as a distinct
  # status (rather than emitting zeros that look indistinguishable from a
  # clean glossary).
  DC_STDERR="$(mktemp -t drift-check-all-stderr.XXXXXX)"
  RAW_OUTPUT="$("$DRIFT_CHECK" "${REPO_ARGS[@]}" --json "$glossary" 2>"$DC_STDERR")"
  DC_RC=$?
  if [[ -z "$RAW_OUTPUT" && "$DC_RC" -ne 0 ]]; then
    # drift-check.sh died without producing any citation lines. Treat as a
    # check failure for this domain so the upstream wrapper doesn't clear an
    # active firing alert when a check itself errors.
    TOTAL_FAILED=$((TOTAL_FAILED + 1))
    if [[ "$JSON" == 1 ]]; then
      err_msg="$(head -c 200 "$DC_STDERR" | tr '\n"\\' '   ')"
      printf '{"domain":"%s","status":"check_failed","exit":%d,"error":"%s"}\n' \
        "$name" "$DC_RC" "$err_msg"
    else
      echo "DOMAIN $name: check_failed exit=$DC_RC"
      head -n 3 "$DC_STDERR" | sed 's/^/    /'
    fi
    rm -f "$DC_STDERR"
    continue
  fi
  rm -f "$DC_STDERR"

  RESOLVED=$(printf '%s\n' "$RAW_OUTPUT" | grep -c '"status":"RESOLVED"' || true)
  RELOCATED=$(printf '%s\n' "$RAW_OUTPUT" | grep -c '"status":"RELOCATED"' || true)
  UNRESOLVED=$(printf '%s\n' "$RAW_OUTPUT" | grep -c '"status":"UNRESOLVED"' || true)

  TOTAL_RESOLVED=$((TOTAL_RESOLVED + RESOLVED))
  TOTAL_RELOCATED=$((TOTAL_RELOCATED + RELOCATED))
  TOTAL_UNRESOLVED=$((TOTAL_UNRESOLVED + UNRESOLVED))

  if [[ "$JSON" == 1 ]]; then
    # Per-domain summary line, then forward each citation row as a JSON line
    # decorated with the domain name so callers don't have to re-correlate.
    printf '{"domain":"%s","status":"checked","resolved":%d,"relocated":%d,"unresolved":%d,"glossary":"%s"}\n' \
      "$name" "$RESOLVED" "$RELOCATED" "$UNRESOLVED" "$glossary"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      # Strip leading {, prepend domain field.
      printf '{"domain":"%s",%s\n' "$name" "${line#\{}"
    done <<<"$RAW_OUTPUT"
  else
    echo "DOMAIN $name ($glossary)"
    printf '  RESOLVED=%d  RELOCATED=%d  UNRESOLVED=%d\n' \
      "$RESOLVED" "$RELOCATED" "$UNRESOLVED"
    # Show only the drifted entries, not the noise.
    printf '%s\n' "$RAW_OUTPUT" | grep -v '"status":"RESOLVED"' | while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "    $line"
    done
  fi
done <<<"$DOMAINS_TSV"

if [[ "$JSON" == 1 ]]; then
  printf '{"summary":true,"resolved":%d,"relocated":%d,"unresolved":%d,"glossaries_missing":%d,"check_failed":%d}\n' \
    "$TOTAL_RESOLVED" "$TOTAL_RELOCATED" "$TOTAL_UNRESOLVED" "$TOTAL_MISSING" "$TOTAL_FAILED"
else
  echo
  echo "SUMMARY  RESOLVED=$TOTAL_RESOLVED  RELOCATED=$TOTAL_RELOCATED  UNRESOLVED=$TOTAL_UNRESOLVED  MISSING_GLOSSARIES=$TOTAL_MISSING  CHECK_FAILED=$TOTAL_FAILED"
fi

DRIFT=$((TOTAL_RELOCATED + TOTAL_UNRESOLVED + TOTAL_MISSING + TOTAL_FAILED))
[[ "$DRIFT" -gt 255 ]] && DRIFT=255
exit "$DRIFT"
