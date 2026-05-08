#!/usr/bin/env bash
set -euo pipefail

REPO="."
REPO_NAME=""
LIMIT=50

usage() {
  cat <<'USAGE'
Usage:
  seed-from-gitnexus.sh [options]

Options:
  --repo <path>       Repository path to inspect. Defaults to current directory.
  --repo-name <name>  Repo alias for output citations. Defaults to repo basename.
  --limit <n>         Maximum rows. Default: 50.
  -h, --help          Show this help.

Output columns:
  candidate<TAB>count<TAB>source<TAB>citation

Note:
  GitNexus does not expose a "top symbols" CLI in the installed version. This
  script checks GitNexus CLI availability, then uses local symbol definitions as
  a scriptable fallback. Agent-side orchestration can still call GitNexus MCP/CLI
  for richer context on selected candidates.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --repo-name)
      REPO_NAME="$2"
      shift 2
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$REPO" ]]; then
  echo "Repo not found: $REPO" >&2
  exit 2
fi

REPO="$(cd "$REPO" && pwd)"
if [[ -z "$REPO_NAME" ]]; then
  REPO_NAME="$(basename "$REPO")"
fi

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository: $REPO" >&2
  exit 2
fi

if command -v gitnexus >/dev/null 2>&1; then
  if ! gitnexus -h >/dev/null 2>&1; then
    echo "gitnexus CLI is installed but not responding cleanly" >&2
  fi
else
  echo "gitnexus CLI not found; using local symbol fallback" >&2
fi

(
  cd "$REPO"
  rg -n '^[[:space:]]*(def|class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*|^[[:space:]]*[A-Z][A-Z0-9_]{2,}[[:space:]]*=' . \
    -g '*.py' \
    -g '!**/.git/**' \
    -g '!**/.venv/**' \
    -g '!**/__pycache__/**' 2>/dev/null
) |
  awk -v name="$REPO_NAME" '
    {
      first = index($0, ":")
      rest = substr($0, first + 1)
      second = index(rest, ":")
      file = substr($0, 1, first - 1)
      line = substr(rest, 1, second - 1)
      text = substr(rest, second + 1)
      symbol = ""
      if (text ~ /^[[:space:]]*(def|class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/) {
        symbol = text
        sub(/^[[:space:]]*(def|class)[[:space:]]+/, "", symbol)
        sub(/[^A-Za-z0-9_].*$/, "", symbol)
      } else if (text ~ /^[[:space:]]*[A-Z][A-Z0-9_][A-Z0-9_]+[[:space:]]*=/) {
        symbol = text
        sub(/^[[:space:]]*/, "", symbol)
        sub(/[[:space:]]*=.*$/, "", symbol)
      }
      if (symbol != "") {
        rel = file
        sub(/^\.\//, "", rel)
        count[symbol]++
        citation[symbol] = "`" symbol "` in `" name ":" rel "`"
      }
    }
    END {
      for (symbol in count) {
        printf "%s\t%d\tgitnexus-fallback\t%s\n", symbol, count[symbol], citation[symbol]
      }
    }
  ' |
  sort -t $'\t' -k2,2nr -k1,1 |
  awk -v limit="$LIMIT" 'NR <= limit'
