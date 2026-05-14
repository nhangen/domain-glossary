#!/usr/bin/env bash
set -euo pipefail

REPO="."
REPO_NAME=""
LIMIT=50

usage() {
  cat <<'USAGE'
Usage:
  seed-from-docs.sh [options]

Options:
  --repo <path>       Repository path to scan. Defaults to current directory.
  --repo-name <name>  Repo alias for output citations. Defaults to repo basename.
  --limit <n>         Maximum rows. Default: 50.
  -h, --help          Show this help.

Output columns:
  candidate<TAB>count<TAB>source<TAB>citation

Surfaces scanned:
  README.md, AGENTS.md, CLAUDE.md, CONTEXT.md at repo root
  docs/**/*.md (depth <= 4)
  */**/README.md outside docs/
  Python module + class docstrings
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

collect_files() {
  cd "$REPO"
  for f in README.md AGENTS.md CLAUDE.md CONTEXT.md; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
  if [[ -d docs ]]; then
    find docs -maxdepth 4 -type f -name '*.md' 2>/dev/null
  fi
  find . -mindepth 2 -maxdepth 5 -type f -name 'README.md' \
    -not -path './docs/*' \
    -not -path './.git/*' \
    -not -path './node_modules/*' \
    -not -path './.venv/*' \
    -not -path './__pycache__/*' 2>/dev/null |
    sed 's|^\./||'
  find . -mindepth 1 -maxdepth 6 -type f -name '*.py' \
    -not -path './.git/*' \
    -not -path './node_modules/*' \
    -not -path './.venv/*' \
    -not -path './__pycache__/*' 2>/dev/null |
    sed 's|^\./||'
}

FILES_TMP="$(mktemp)"
trap 'rm -f "$FILES_TMP"' EXIT
collect_files | awk '!seen[$0]++' >"$FILES_TMP"

if [[ ! -s "$FILES_TMP" ]]; then
  exit 0
fi

extract() {
  local file="$1"
  local rel="$file"
  case "$file" in
    *.md)
      awk -v file="$rel" '
        BEGIN { in_code = 0 }
        /^[[:space:]]*```/ { in_code = !in_code; next }
        in_code { next }
        {
          line = $0
          # Headings: "## Term name"
          if (match(line, /^#{1,6}[[:space:]]+/)) {
            heading = substr(line, RLENGTH + 1)
            sub(/[[:space:]]+$/, "", heading)
            print "HEADING\t" heading "\t" file
          }
          # Bolded glossary terms: "**Term**:"
          s = line
          while (match(s, /\*\*[^*]+\*\*[[:space:]]*:/)) {
            chunk = substr(s, RSTART, RLENGTH)
            term = chunk
            sub(/^\*\*/, "", term)
            sub(/\*\*[[:space:]]*:$/, "", term)
            print "BOLD\t" term "\t" file
            s = substr(s, RSTART + RLENGTH)
          }
          # Backticked symbols
          s = line
          while (match(s, /`[A-Za-z_][A-Za-z0-9_.]*`/)) {
            chunk = substr(s, RSTART + 1, RLENGTH - 2)
            print "TICK\t" chunk "\t" file
            s = substr(s, RSTART + RLENGTH)
          }
          # Capitalized noun phrases (2+ Title Case tokens) in prose
          if (line !~ /^#/) {
            s = line
            while (match(s, /[A-Z][A-Za-z0-9]+([[:space:]]+[A-Z][A-Za-z0-9]+)+/)) {
              phrase = substr(s, RSTART, RLENGTH)
              print "PHRASE\t" phrase "\t" file
              s = substr(s, RSTART + RLENGTH)
            }
          }
        }
      ' "$REPO/$file"
      ;;
    *.py)
      awk -v file="$rel" '
        BEGIN { in_doc = 0; buf = "" }
        function flush() {
          if (buf != "") {
            gsub(/[[:space:]]+/, " ", buf)
            sub(/^ /, "", buf); sub(/ $/, "", buf)
            # First sentence
            sentence = buf
            if (match(sentence, /\./)) sentence = substr(sentence, 1, RSTART - 1)
            # Capitalized phrases in the docstring
            s = sentence
            while (match(s, /[A-Z][A-Za-z0-9]+([[:space:]]+[A-Za-z][A-Za-z0-9]+)+/)) {
              phrase = substr(s, RSTART, RLENGTH)
              print "PHRASE\t" phrase "\t" file
              s = substr(s, RSTART + RLENGTH)
            }
            # Backticked items
            s = sentence
            while (match(s, /`[A-Za-z_][A-Za-z0-9_.]*`/)) {
              chunk = substr(s, RSTART + 1, RLENGTH - 2)
              print "TICK\t" chunk "\t" file
              s = substr(s, RSTART + RLENGTH)
            }
            buf = ""
          }
        }
        {
          line = $0
          if (in_doc) {
            if (line ~ /"""/) {
              sub(/""".*$/, "", line)
              buf = buf " " line
              in_doc = 0
              flush()
            } else {
              buf = buf " " line
            }
            next
          }
          # Module-level docstring (no leading indent) or class-level (indented)
          if (line ~ /^[[:space:]]*"""/) {
            content = line
            sub(/^[[:space:]]*"""/, "", content)
            if (content ~ /"""/) {
              sub(/""".*$/, "", content)
              buf = content
              flush()
            } else {
              buf = content
              in_doc = 1
            }
          }
        }
      ' "$REPO/$file"
      ;;
  esac
}

STOPLIST="^(The|This|That|These|Those|And|But|For|From|With|Into|About|After|Before|When|While|Where|There|Their|They|Them|Then|Than|Will|Would|Should|Could|Have|Has|Been|Being|Note|Notes|Usage|Example|Examples|Installation|Install|Configuration|Config|License|Overview|Introduction|Getting Started|Quick Start|Description|Summary|Status|TODO|FIXME|Why|How|What|See Also|References|Setup|Requirements|Dependencies|Changelog|Contributing|Authors|Credits|Acknowledgments|PR|Commit|Branch|Merge|Fix|Feat|Chore|Docs|Test|Tests|Pull Request)$"

{
  while IFS= read -r f; do
    extract "$f"
  done <"$FILES_TMP"
} |
  awk -F '\t' -v name="$REPO_NAME" -v stoplist="$STOPLIST" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    function is_meta(t) {
      return t ~ ("\\<" "(PR|commit|branch|merge|fix|feat|chore|docs|test|Closes|Fixes|Resolves)" "\\>")
    }
    {
      kind = $1
      term = trim($2)
      file = $3
      if (term == "") next
      if (length(term) < 3) next
      # Single-word common-English drop list (anchored)
      if (term ~ stoplist) next
      # Project-meta phrases
      if (is_meta(term)) next
      # Headings: only keep if term-shaped (not section-y)
      if (kind == "HEADING") {
        if (tolower(term) ~ /^(installation|usage|license|example|examples|overview|introduction|getting started|quick start|description|summary|status|todo|why|how|what|see also|references|setup|requirements|dependencies|changelog|contributing|authors|credits|acknowledgments|configuration|config|notes|note|api|cli|scripts|commands|tests|tests passing|hard rules|known limitations|evaluation status|current status|citation forms|examples)$/) next
        if (term ~ /\?$/) next
      }
      # Backticked: require identifier shape, length >= 3
      if (kind == "TICK") {
        if (term !~ /^[A-Za-z_][A-Za-z0-9_.]*$/) next
        if (length(term) < 3) next
      }
      # PHRASE: at least 2 tokens, each starts uppercase
      if (kind == "PHRASE") {
        if (term !~ /^[A-Z]/) next
        n = split(term, toks, " ")
        if (n < 2) next
      }
      key = term
      count[key]++
      if (!(key in citation)) citation[key] = name ":" file
    }
    END {
      for (k in count) {
        printf "%s\t%d\tdocs\t%s\n", k, count[k], citation[k]
      }
    }
  ' |
  sort -t $'\t' -k2,2nr -k1,1 |
  awk -v limit="$LIMIT" 'NR <= limit'
