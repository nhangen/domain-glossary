#!/usr/bin/env bash
set -euo pipefail

SOURCE=""
DEST=""

usage() {
  cat <<'USAGE'
Usage:
  render-repo-mirror.sh --source <vault-glossary.md> --dest <repo/docs/glossary.md>

Copies the Obsidian-first glossary to a repo mirror with a short provenance
header. The vault file remains canonical.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE="$2"
      shift 2
      ;;
    --dest)
      DEST="$2"
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

if [[ -z "$SOURCE" || -z "$DEST" ]]; then
  usage >&2
  exit 2
fi
if [[ ! -f "$SOURCE" ]]; then
  echo "Source glossary not found: $SOURCE" >&2
  exit 2
fi

SOURCE_REAL="$(cd "$(dirname "$SOURCE")" && pwd -P)/$(basename "$SOURCE")"
DEST_DIR="$(dirname "$DEST")"
mkdir -p "$(dirname "$DEST")"
DEST_REAL="$(cd "$DEST_DIR" && pwd -P)/$(basename "$DEST")"

if [[ "$SOURCE_REAL" == "$DEST_REAL" ]]; then
  echo "Refusing to render mirror over canonical source: $SOURCE" >&2
  exit 2
fi

TMP_DEST="$(mktemp "$DEST_REAL.tmp.XXXXXX")"
trap 'rm -f "$TMP_DEST"' EXIT
{
  echo "<!-- Generated mirror. Canonical glossary: $SOURCE -->"
  echo
  awk '
    NR == 1 && $0 == "---" {
      in_frontmatter = 1
      next
    }
    in_frontmatter && $0 == "---" {
      in_frontmatter = 0
      next
    }
    !in_frontmatter { print }
  ' "$SOURCE"
} >"$TMP_DEST"

mv "$TMP_DEST" "$DEST_REAL"
trap - EXIT

echo "Rendered repo mirror: $DEST"
