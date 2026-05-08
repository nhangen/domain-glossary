#!/usr/bin/env bash
set -euo pipefail

REPO="."
SINCE=""
MIN_COUNT=2
LIMIT=50

usage() {
  cat <<'USAGE'
Usage:
  seed-from-commits.sh [options]

Options:
  --repo <path>       Git repository to scan. Defaults to current directory.
  --since <date>      Pass through to git log --since.
  --min-count <n>     Minimum phrase frequency. Default: 2.
  --limit <n>         Maximum rows. Default: 50.
  -h, --help          Show this help.

Output columns:
  candidate<TAB>count<TAB>source<TAB>example
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --since)
      SINCE="$2"
      shift 2
      ;;
    --min-count)
      MIN_COUNT="$2"
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

if ! git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository: $REPO" >&2
  exit 2
fi

git_args=(log --pretty=%s)
if [[ -n "$SINCE" ]]; then
  git_args+=(--since "$SINCE")
fi

git -C "$REPO" "${git_args[@]}" |
  awk -v min="$MIN_COUNT" -v limit="$LIMIT" '
    BEGIN {
      split("a add an and are as at be branch bug change chore closes cleanup commit dev docs feature fix for from in into is it merge mr of on or pr readme repo result results test tests the to update with without", sw, " ")
      for (i in sw) stop[sw[i]] = 1
    }
    function clean(s) {
      gsub(/[^A-Za-z0-9_+-]+/, " ", s)
      gsub(/[[:space:]]+/, " ", s)
      sub(/^ /, "", s)
      sub(/ $/, "", s)
      return tolower(s)
    }
    function keep(w) {
      return length(w) >= 3 && !(w in stop) && w !~ /^[0-9]+$/
    }
    {
      original = $0
      line = clean($0)
      n = split(line, words, " ")
      for (i = 1; i <= n; i++) {
        if (keep(words[i])) add(words[i], original)
        if (i < n && keep(words[i]) && keep(words[i+1])) {
          add(words[i] " " words[i+1], original)
        }
        if (i + 1 < n && keep(words[i]) && keep(words[i+1]) && keep(words[i+2])) {
          add(words[i] " " words[i+1] " " words[i+2], original)
        }
      }
    }
    function add(term, example) {
      count[term]++
      if (!(term in first)) first[term] = example
    }
    END {
      for (term in count) {
        if (count[term] >= min) {
          printf "%s\t%d\tcommits\t%s\n", term, count[term], first[term]
        }
      }
    }
  ' |
  sort -t $'\t' -k2,2nr -k1,1 |
  awk -v limit="$LIMIT" 'NR <= limit'
