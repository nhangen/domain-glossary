#!/usr/bin/env bash
set -euo pipefail

VAULT_PATH="${OBSIDIAN_VAULT_PATH:-$HOME/Documents/Obsidian}"
JSON=0
GLOSSARY=""
REPO_NAMES=()
REPO_PATHS=()

usage() {
  cat <<'USAGE'
Usage:
  drift-check.sh [options] <glossary.md>

Options:
  --vault <path>          Obsidian vault root. Defaults to $OBSIDIAN_VAULT_PATH
                          or ~/Documents/Obsidian.
  --repo <name=path>      Register a repo alias for citations such as
                          `symbol` in `repo:path`. May be passed multiple times.
  --json                  Emit JSON lines instead of text.
  -h, --help              Show this help.

Citation forms:
  **Citation:** `symbol_name` in `repo:path/to/file.py`
  **Citation:** [[Altamira/some-note]]
  **Citation:** `repo:path/to/file.py:42`

Statuses:
  RESOLVED    The cited artifact still exists.
  RELOCATED   The cited symbol was not at the old path but was found elsewhere
              in the same resolved repo.
  UNRESOLVED  Manual review is needed.
USAGE
}

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  printf '%s' "$s"
}

emit() {
  local status="$1"
  local term="$2"
  local kind="$3"
  local citation="$4"
  local detail="$5"
  local suggestion="${6:-}"

  if [[ "$JSON" == 1 ]]; then
    printf '{"status":"%s","term":"%s","kind":"%s","citation":"%s","detail":"%s","suggestion":"%s"}\n' \
      "$(json_escape "$status")" \
      "$(json_escape "$term")" \
      "$(json_escape "$kind")" \
      "$(json_escape "$citation")" \
      "$(json_escape "$detail")" \
      "$(json_escape "$suggestion")"
  else
    if [[ -n "$suggestion" ]]; then
      printf '%-10s %-24s %-8s %s -> %s\n' \
        "$status" "$term" "$kind" "$detail" "$suggestion"
    else
      printf '%-10s %-24s %-8s %s\n' "$status" "$term" "$kind" "$detail"
    fi
  fi
}

strip_backticks() {
  local s="$1"
  s="${s#\`}"
  s="${s%\`}"
  printf '%s' "$s"
}

resolve_repo_root() {
  local repo="$1"
  local i

  if [[ -d "$repo" ]]; then
    cd "$repo" && pwd
    return 0
  fi

  for i in "${!REPO_NAMES[@]}"; do
    if [[ "${REPO_NAMES[$i]}" == "$repo" ]]; then
      cd "${REPO_PATHS[$i]}" && pwd
      return 0
    fi
  done

  if [[ -n "${DOMAIN_GLOSSARY_REPO_ROOT:-}" ]] &&
     [[ -d "$DOMAIN_GLOSSARY_REPO_ROOT" ]] &&
     [[ "$(basename "$DOMAIN_GLOSSARY_REPO_ROOT")" == "$repo" ]]; then
    cd "$DOMAIN_GLOSSARY_REPO_ROOT" && pwd
    return 0
  fi

  if git_root="$(git rev-parse --show-toplevel 2>/dev/null)" &&
     [[ "$(basename "$git_root")" == "$repo" ]]; then
    printf '%s\n' "$git_root"
    return 0
  fi

  if command -v jq >/dev/null 2>&1 && [[ -f "$HOME/.gitnexus/registry.json" ]]; then
    local match
    match="$(
      jq -r --arg repo "$repo" '
        .[]
        | select(.name == $repo or (.path | split("/")[-1]) == $repo)
        | .path
      ' "$HOME/.gitnexus/registry.json" 2>/dev/null | head -n 1
    )"
    if [[ -n "$match" && -d "$match" ]]; then
      printf '%s\n' "$match"
      return 0
    fi
  fi

  return 1
}

resolve_path_parts() {
  local spec="$1"
  local repo="${spec%%:*}"
  local rest="${spec#*:}"
  local line=""
  local root

  if [[ "$spec" == /* ]]; then
    printf '%s\t%s\t%s\n' "" "$spec" ""
    return 0
  fi

  if [[ "$repo" == "$spec" ]]; then
    printf '%s\t%s\t%s\n' "" "$spec" ""
    return 0
  fi

  if [[ "$rest" =~ ^(.+):([0-9]+)$ ]]; then
    rest="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
  fi

  if ! root="$(resolve_repo_root "$repo")"; then
    return 1
  fi

  printf '%s\t%s\t%s\n' "$repo" "$root/$rest" "$line"
}

symbol_defined_in_file() {
  local file="$1"
  local symbol="$2"

  awk -v wanted="$symbol" '
    function trim_name(s) {
      sub(/^[[:space:]]*/, "", s)
      sub(/[[:space:]]*[:=].*$/, "", s)
      sub(/[^A-Za-z0-9_].*$/, "", s)
      return s
    }
    {
      name = ""
      if ($0 ~ /^[[:space:]]*(def|class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*/) {
        name = $0
        sub(/^[[:space:]]*(def|class)[[:space:]]+/, "", name)
        name = trim_name(name)
      } else if ($0 ~ /^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/) {
        name = $0
        name = trim_name(name)
      }
      if (name == wanted) {
        found = 1
        exit
      }
    }
    END { exit found ? 0 : 1 }
  ' "$file"
}

search_symbol() {
  local root="$1"
  local symbol="$2"

  (
    cd "$root"
    rg -l '^[[:space:]]*(def|class)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*|^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' . \
      -g '!**/.git/**' \
      -g '!**/.venv/**' \
      -g '!**/node_modules/**' \
      -g '!**/__pycache__/**' 2>/dev/null
  ) |
    while IFS= read -r rel; do
      rel="${rel#./}"
      if symbol_defined_in_file "$root/$rel" "$symbol"; then
        printf '%s\n' "$root/$rel"
      fi
    done |
    sort
}

check_note() {
  local term="$1"
  local citation="$2"
  local note="$citation"
  note="${note#*[[}"
  note="${note%%]]*}"
  note="${note%%|*}"
  note="${note%%#*}"

  if [[ "$note" == /* || "$note" == ".." || "$note" == ../* ||
        "$note" == */../* || "$note" == */.. ]]; then
    emit "UNRESOLVED" "$term" "note" "$citation" "note escapes vault: $note"
    return
  fi

  local target="$VAULT_PATH/$note"
  [[ "$target" == *.md ]] || target="$target.md"

  if [[ -f "$target" ]]; then
    local real_vault real_target
    real_vault="$(cd "$VAULT_PATH" && pwd -P)"
    real_target="$(cd "$(dirname "$target")" && pwd -P)/$(basename "$target")"
    if [[ "$real_target" != "$real_vault"/* ]]; then
      emit "UNRESOLVED" "$term" "note" "$citation" "note escapes vault: $note"
      return
    fi
    emit "RESOLVED" "$term" "note" "$citation" "$note"
  else
    emit "UNRESOLVED" "$term" "note" "$citation" "missing note: $note"
  fi
}

check_path() {
  local term="$1"
  local citation="$2"
  local spec
  local parts repo file line

  spec="$(strip_backticks "$citation")"
  if ! parts="$(resolve_path_parts "$spec")"; then
    emit "UNRESOLVED" "$term" "path" "$citation" "unknown repo in $spec"
    return
  fi

  IFS=$'\t' read -r repo file line <<<"$parts"
  if [[ -f "$file" ]]; then
    if [[ -n "$line" ]]; then
      local count
      count="$(wc -l <"$file" | tr -d ' ')"
      if (( line >= 1 && line <= count )); then
        emit "RESOLVED" "$term" "path" "$citation" "$spec"
      else
        emit "UNRESOLVED" "$term" "path" "$citation" "line $line outside file with $count lines"
      fi
    else
      emit "RESOLVED" "$term" "path" "$citation" "$spec"
    fi
  else
    emit "UNRESOLVED" "$term" "path" "$citation" "missing file: $spec"
  fi
}

check_symbol() {
  local term="$1"
  local symbol="$2"
  local location="$3"
  local citation="$4"
  local repo="${location%%:*}"
  local rel="${location#*:}"
  local root

  if ! root="$(resolve_repo_root "$repo")"; then
    emit "UNRESOLVED" "$term" "symbol" "$citation" "unknown repo: $repo"
    return
  fi

  local file="$root/$rel"
  if [[ -f "$file" ]] && symbol_defined_in_file "$file" "$symbol"; then
    emit "RESOLVED" "$term" "symbol" "$citation" "$symbol in $repo:$rel"
    return
  fi

  local matches count first rel_match
  matches="$(search_symbol "$root" "$symbol" || true)"
  count="$(printf '%s\n' "$matches" | sed '/^$/d' | wc -l | tr -d ' ')"

  if [[ "$count" == 1 ]]; then
    first="$(printf '%s\n' "$matches" | sed -n '1p')"
    rel_match="${first#$root/}"
    emit "RELOCATED" "$term" "symbol" "$citation" \
      "$symbol moved from $repo:$rel" \
      "\`$symbol\` in \`$repo:$rel_match\`"
  elif [[ "$count" == 0 ]]; then
    emit "UNRESOLVED" "$term" "symbol" "$citation" \
      "$symbol not found in $repo"
  else
    emit "UNRESOLVED" "$term" "symbol" "$citation" \
      "$symbol has $count possible matches in $repo"
  fi
}

parse_citation() {
  local term="$1"
  local line="$2"
  local body
  body="$(printf '%s\n' "$line" | sed 's/^.*\*\*Citation:\*\*[[:space:]]*//')"
  body="${body#"${body%%[![:space:]]*}"}"

  if [[ "$body" =~ \[\[([^]]+)\]\] ]]; then
    check_note "$term" "$body"
  elif [[ "$body" =~ ^\`([^\`]+)\`[[:space:]]+in[[:space:]]+\`([^\`]+)\` ]]; then
    check_symbol "$term" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$body"
  elif [[ "$body" =~ ^\`([^\`]+)\` ]]; then
    check_path "$term" "${BASH_REMATCH[0]}"
  else
    emit "UNRESOLVED" "$term" "unknown" "$body" "unrecognized citation format"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault)
      VAULT_PATH="$2"
      shift 2
      ;;
    --repo)
      IFS='=' read -r name path <<<"$2"
      if [[ -z "$name" || -z "$path" || ! -d "$path" ]]; then
        echo "Invalid --repo mapping: $2" >&2
        exit 2
      fi
      REPO_NAMES+=("$name")
      REPO_PATHS+=("$path")
      shift 2
      ;;
    --json)
      JSON=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      GLOSSARY="$1"
      shift
      ;;
  esac
done

if [[ -z "$GLOSSARY" ]]; then
  usage >&2
  exit 2
fi

if [[ ! -f "$GLOSSARY" ]]; then
  echo "Glossary file not found: $GLOSSARY" >&2
  exit 2
fi

term="(unknown)"
found=0
while IFS= read -r line; do
  if [[ "$line" =~ ^###[[:space:]]+(.+) ]]; then
    term="${BASH_REMATCH[1]}"
  elif [[ "$line" == *"**Citation:**"* ]]; then
    found=1
    parse_citation "$term" "$line"
  fi
done <"$GLOSSARY"

if [[ "$found" == 0 ]]; then
  echo "No Citation lines found in $GLOSSARY" >&2
  exit 1
fi
