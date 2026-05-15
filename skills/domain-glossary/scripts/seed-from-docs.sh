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
  --limit <n>         Maximum rows (non-negative integer). Default: 50.
  -h, --help          Show this help.

Output columns:
  candidate<TAB>count<TAB>source<TAB>citation

Surfaces scanned:
  README.md, AGENTS.md, CLAUDE.md, CONTEXT.md at repo root
  docs/**/*.md (depth <= 4)
  */**/README.md outside docs/
  Python module + class docstrings (plain """, r""", b""", f""", u""")
USAGE
}

require_value() {
  if [[ $# -lt 2 ]]; then
    echo "Missing value for $1" >&2
    usage >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      require_value "$@"
      REPO="$2"
      shift 2
      ;;
    --repo-name)
      require_value "$@"
      REPO_NAME="$2"
      shift 2
      ;;
    --limit)
      require_value "$@"
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

if [[ ! "$LIMIT" =~ ^[0-9]+$ ]]; then
  echo "Invalid --limit: $LIMIT (must be a non-negative integer)" >&2
  exit 2
fi

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
          # Backticked symbols (widened to permit /, -)
          s = line
          while (match(s, /`[A-Za-z_][-A-Za-z0-9_.\/]*`/)) {
            chunk = substr(s, RSTART + 1, RLENGTH - 2)
            print "TICK\t" chunk "\t" file
            s = substr(s, RSTART + RLENGTH)
          }
          # Prose-only patterns (skip heading lines)
          if (line !~ /^#/) {
            # Capitalized noun phrases (2+ Title Case tokens)
            s = line
            while (match(s, /[A-Z][A-Za-z0-9]+([[:space:]]+[A-Z][A-Za-z0-9]+)+/)) {
              phrase = substr(s, RSTART, RLENGTH)
              print "PHRASE\t" phrase "\t" file
              s = substr(s, RSTART + RLENGTH)
            }
            # Acronyms (>=2 uppercase letters/digits, leading alpha)
            s = line
            while (match(s, /(^|[^A-Za-z0-9])[A-Z][A-Z0-9]+([^A-Za-z0-9]|$)/)) {
              chunk = substr(s, RSTART, RLENGTH)
              # Strip leading/trailing non-alnum captured by the boundary
              sub(/^[^A-Za-z0-9]+/, "", chunk)
              sub(/[^A-Za-z0-9]+$/, "", chunk)
              if (length(chunk) >= 2) print "ACRONYM\t" chunk "\t" file
              s = substr(s, RSTART + RLENGTH)
            }
          }
        }
      ' "$REPO/$file"
      ;;
    *.py)
      awk -v file="$rel" '
        BEGIN { in_doc = 0; quote = ""; buf = "" }
        function flush() {
          if (buf != "") {
            gsub(/[[:space:]]+/, " ", buf)
            sub(/^ /, "", buf); sub(/ $/, "", buf)
            sentence = buf
            if (match(sentence, /\./)) sentence = substr(sentence, 1, RSTART - 1)
            s = sentence
            while (match(s, /[A-Z][A-Za-z0-9]+([[:space:]]+[A-Z][A-Za-z0-9]+)+/)) {
              phrase = substr(s, RSTART, RLENGTH)
              print "PHRASE\t" phrase "\t" file
              s = substr(s, RSTART + RLENGTH)
            }
            s = sentence
            while (match(s, /`[A-Za-z_][-A-Za-z0-9_.\/]*`/)) {
              chunk = substr(s, RSTART + 1, RLENGTH - 2)
              print "TICK\t" chunk "\t" file
              s = substr(s, RSTART + RLENGTH)
            }
            s = sentence
            while (match(s, /(^|[^A-Za-z0-9])[A-Z][A-Z0-9]+([^A-Za-z0-9]|$)/)) {
              chunk = substr(s, RSTART, RLENGTH)
              sub(/^[^A-Za-z0-9]+/, "", chunk)
              sub(/[^A-Za-z0-9]+$/, "", chunk)
              if (length(chunk) >= 2) print "ACRONYM\t" chunk "\t" file
              s = substr(s, RSTART + RLENGTH)
            }
            buf = ""
          }
        }
        {
          line = $0
          # Class identifiers are first-class glossary candidates.
          if (match(line, /^[[:space:]]*class[[:space:]]+[A-Z][A-Za-z0-9_]+/)) {
            classline = substr(line, RSTART, RLENGTH)
            sub(/^[[:space:]]*class[[:space:]]+/, "", classline)
            print "TICK\t" classline "\t" file
          }
          if (in_doc) {
            close_re = (quote == "'\''" ? "'\'''\'''\''" : "\"\"\"")
            if (index(line, close_re) > 0) {
              tail_pos = index(line, close_re)
              prefix = substr(line, 1, tail_pos - 1)
              buf = buf " " prefix
              in_doc = 0
              quote = ""
              flush()
            } else {
              buf = buf " " line
            }
            next
          }
          # Module/class/function docstring: """ or '\'''\'''\'' with optional r/b/f/u prefix.
          if (match(line, /^[[:space:]]*[rRbBuUfF]?"""/) || match(line, /^[[:space:]]*[rRbBuUfF]?'\'''\'''\''/)) {
            opener_end = RSTART + RLENGTH - 1
            # Detect which quote sequence opened.
            seg = substr(line, RSTART, RLENGTH)
            if (index(seg, "\"\"\"") > 0) quote = "\""
            else quote = "'\''"
            close_re = (quote == "'\''" ? "'\'''\'''\''" : "\"\"\"")
            content = substr(line, opener_end + 1)
            tail_pos = index(content, close_re)
            if (tail_pos > 0) {
              buf = substr(content, 1, tail_pos - 1)
              in_doc = 0
              quote = ""
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

STOPLIST="^(The|This|That|These|Those|And|But|For|From|With|Into|About|After|Before|When|While|Where|There|Their|They|Them|Then|Than|Will|Would|Should|Could|Have|Has|Been|Being|Note|Notes|Usage|Example|Examples|Installation|Install|Configuration|Config|License|Overview|Introduction|Getting Started|Quick Start|Description|Summary|Status|TODO|FIXME|Why|How|What|See Also|References|Setup|Requirements|Dependencies|Changelog|Contributing|Authors|Credits|Acknowledgments|PR|Commit|Branch|Merge|Fix|Feat|Chore|Docs|Test|Tests|Pull Request|Pull Requests)$"

# Connector tokens that should never be the first or last word of a meaningful phrase.
CONNECTORS="^(Of|And|The|For|From|With|Into|About|On|By|To|A|An|In|At|As|Is|Are|Be|Or|But|However|Therefore|Also|Thus|Then|So|Yet)$"

# Multi-word phrase stoplist (full-phrase rejects).
PHRASE_STOPLIST="^(Pull Request|Pull Requests|MIT License|Apache License|GNU License|GitHub Actions|GitHub Pages|Table Of Contents|Code Of Conduct|Quick Start|Getting Started|Open Source|Read Me|Read The|See Also|Best Practices|Hello World)$"

{
  while IFS= read -r f; do
    extract "$f"
  done <"$FILES_TMP"
} |
  awk -F '\t' \
      -v name="$REPO_NAME" \
      -v stoplist="$STOPLIST" \
      -v connectors="$CONNECTORS" \
      -v phrase_stoplist="$PHRASE_STOPLIST" '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    function is_meta(t) {
      return tolower(t) ~ /(^|[^a-z0-9])(pr|commit|branch|merge|fix|feat|chore|docs|test|closes|fixes|resolves)([^a-z0-9]|$)/
    }
    function uc_count(s,    i, n, c) {
      n = 0
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c >= "A" && c <= "Z") n++
      }
      return n
    }
    {
      kind = $1
      term = trim($2)
      file = $3
      if (term == "") next
      if (length(term) < 3 && kind != "ACRONYM") next
      if (term ~ stoplist) next
      if (is_meta(term)) next
      if (term ~ phrase_stoplist) next
      if (kind == "HEADING") {
        if (tolower(term) ~ /^(installation|usage|license|example|examples|overview|introduction|getting started|quick start|description|summary|status|todo|why|how|what|see also|references|setup|requirements|dependencies|changelog|contributing|authors|credits|acknowledgments|configuration|config|notes|note|api|cli|scripts|commands|tests|tests passing|hard rules|known limitations|evaluation status|current status|citation forms|examples)$/) next
        if (term ~ /\?$/) next
      }
      if (kind == "TICK") {
        if (term !~ /^[A-Za-z_][-A-Za-z0-9_.\/]*$/) next
        if (length(term) < 3) next
        # Reject trivial bare paths (./, ../) and lone separators.
        if (term ~ /^[\.\/-]+$/) next
      }
      if (kind == "PHRASE") {
        if (term !~ /^[A-Z]/) next
        n = split(term, toks, " ")
        if (n < 2) next
        # Strip leading/trailing connector tokens (e.g. "The", "However", "Of").
        first = 1
        last = n
        while (first <= last && toks[first] ~ connectors) first++
        while (last >= first && toks[last] ~ connectors) last--
        if (last - first + 1 < 2) next
        if (first != 1 || last != n) {
          stripped = toks[first]
          for (i = first + 1; i <= last; i++) stripped = stripped " " toks[i]
          term = stripped
          if (term !~ /^[A-Z]/) next
        }
      }
      if (kind == "ACRONYM") {
        if (term !~ /^[A-Z][A-Z0-9]+$/) next
        if (length(term) < 2) next
        # Reject doc section-name acronyms commonly typed as SHOUT-CASE.
        if (term ~ /^(README|USAGE|INSTALL|INSTALLATION|LICENSE|CHANGELOG|NOTES|TODO|FIXME|CONTRIBUTING|AUTHORS|CREDITS|ACKNOWLEDGMENTS|OVERVIEW|INTRODUCTION|SETUP|REQUIREMENTS|DEPENDENCIES|REFERENCES|SUMMARY|DESCRIPTION|STATUS|ARCHITECTURE|ROADMAP|HOWTO|FAQ|NOTE|WARNING|CAUTION|IMPORTANT|TIP|TBD|TBA|N\/A|NA|OK)$/) next
      }
      key = tolower(term)
      count[key]++
      if (!(key in display) || uc_count(term) > uc_count(display[key])) {
        display[key] = term
      }
      if (!(key in citation)) citation[key] = name ":" file
    }
    END {
      for (k in count) {
        printf "%s\t%d\tdocs\t%s\n", display[k], count[k], citation[k]
      }
    }
  ' |
  sort -t $'\t' -k2,2nr -k1,1 |
  awk -v limit="$LIMIT" 'NR <= limit'
