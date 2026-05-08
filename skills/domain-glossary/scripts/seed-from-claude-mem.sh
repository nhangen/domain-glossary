#!/usr/bin/env bash
set -euo pipefail

DB="${CLAUDE_MEM_DB:-$HOME/.claude-mem/claude-mem.db}"
PROJECT=""
QUERY=""
MIN_COUNT=3
LIMIT=50

usage() {
  cat <<'USAGE'
Usage:
  seed-from-claude-mem.sh [options]

Options:
  --db <path>         claude-mem SQLite DB. Defaults to ~/.claude-mem/claude-mem.db.
  --project <name>    Restrict to observations whose project matches this value.
  --query <text>      Restrict to observations containing this text.
  --min-count <n>     Minimum phrase frequency. Default: 3.
  --limit <n>         Maximum rows. Default: 50.
  -h, --help          Show this help.

Output columns:
  candidate<TAB>count<TAB>source<TAB>example_observation_ids
USAGE
}

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)
      DB="$2"
      shift 2
      ;;
    --project)
      PROJECT="$2"
      shift 2
      ;;
    --query)
      QUERY="$2"
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

if [[ ! -f "$DB" ]]; then
  echo "claude-mem DB not found: $DB" >&2
  exit 2
fi

where="1=1"
if [[ -n "$PROJECT" ]]; then
  qp="$(sql_quote "$PROJECT")"
  where="$where AND project LIKE '%$qp%'"
fi
if [[ -n "$QUERY" ]]; then
  qq="$(sql_quote "$QUERY")"
  where="$where AND (title LIKE '%$qq%' OR subtitle LIKE '%$qq%' OR narrative LIKE '%$qq%' OR text LIKE '%$qq%' OR concepts LIKE '%$qq%')"
fi

sqlite3 -tabs "$DB" "
  SELECT
    id,
    coalesce(title, '') || ' ' ||
    coalesce(subtitle, '') || ' ' ||
    coalesce(narrative, '') || ' ' ||
    coalesce(text, '') || ' ' ||
    coalesce(concepts, '')
  FROM observations
  WHERE $where
  ORDER BY created_at_epoch DESC
  LIMIT 500;
" |
  awk -F '\t' -v min="$MIN_COUNT" -v limit="$LIMIT" '
    BEGIN {
      split("about across after agent all also and are because been branch bug build but can code commit could data docs documentation does done during each for from gitlab has have into just merge more most mrs need note obsidian only other path pattern plan project repo repository review run same should source status still test than that the their them then there these they this through using was what-changed when where which while with work would", sw, " ")
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
    function add(term, id) {
      count[term]++
      if (ids[term] == "") ids[term] = id
      else if (ids[term] !~ "(^|,)" id "(,|$)") ids[term] = ids[term] "," id
    }
    {
      id = $1
      text = clean($2)
      n = split(text, words, " ")
      for (i = 1; i <= n; i++) {
        if (keep(words[i])) add(words[i], id)
        if (i < n && keep(words[i]) && keep(words[i+1])) {
          add(words[i] " " words[i+1], id)
        }
        if (i + 1 < n && keep(words[i]) && keep(words[i+1]) && keep(words[i+2])) {
          add(words[i] " " words[i+1] " " words[i+2], id)
        }
      }
    }
    END {
      for (term in count) {
        if (count[term] >= min) {
          printf "%s\t%d\tclaude-mem\t%s\n", term, count[term], ids[term]
        }
      }
    }
  ' |
  sort -t $'\t' -k2,2nr -k1,1 |
  awk -v limit="$LIMIT" 'NR <= limit'
