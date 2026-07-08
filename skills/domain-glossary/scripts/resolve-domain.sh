#!/usr/bin/env bash
# resolve-domain.sh
#
# Read domain-glossary.local.md, match the current working directory against
# the `repos:` list under each domain (longest-prefix wins), and emit:
#
#   <domain>\t<glossary-absolute-path>
#
# on stdout. Empty stdout = no match; stderr explains why.
#
# Usage:
#   resolve-domain.sh                # uses $PWD
#   resolve-domain.sh /abs/cwd       # explicit cwd (testing)
#   resolve-domain.sh --config <p>   # override config path
#
# Exit 0 in all "expected" cases (no config, no match, etc.); reserve non-zero
# for actual script errors so the caller can rely on stdout content to make
# decisions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Plugin root is two levels up from skills/domain-glossary/scripts/.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
# Config resolution: prefer the plugin-root copy (legacy/explicit setups), but
# fall back to a version-independent XDG location. A plugin update recreates the
# cache dir and would otherwise silently wipe the plugin-root config.
XDG_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/domain-glossary/domain-glossary.local.md"
if [[ -f "$PLUGIN_ROOT/domain-glossary.local.md" ]]; then
  CONFIG="$PLUGIN_ROOT/domain-glossary.local.md"
else
  CONFIG="$XDG_CONFIG"
fi
CWD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config)
      [[ $# -ge 2 ]] || { echo "Missing value for --config" >&2; exit 2; }
      CONFIG="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,/^$/p' "$0" | sed 's|^# \{0,1\}||'
      exit 0
      ;;
    *)
      CWD="$1"
      shift
      ;;
  esac
done

CWD="${CWD:-$PWD}"

if [[ ! -f "$CONFIG" ]]; then
  echo "Config not found: $CONFIG" >&2
  echo "Copy domain-glossary.local.md.example to domain-glossary.local.md and edit." >&2
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 required but not on PATH" >&2
  exit 2
fi

python3 - "$CONFIG" "$CWD" <<'PY'
import os
import re
import subprocess
import sys

config_path = sys.argv[1]
cwd = os.path.realpath(os.path.expanduser(sys.argv[2]))


def canonical_repo(path):
    """If `path` is inside a git worktree, return the main checkout's path."""
    try:
        result = subprocess.run(
            ["git", "-C", path, "rev-parse", "--git-common-dir"],
            capture_output=True,
            text=True,
            timeout=2,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    git_dir = result.stdout.strip()
    if not git_dir:
        return None
    if not os.path.isabs(git_dir):
        git_dir = os.path.realpath(os.path.join(path, git_dir))
    # The main repo is the directory containing the .git dir.
    return os.path.dirname(os.path.realpath(git_dir))

with open(config_path) as f:
    raw = f.read()

match = re.search(r"^---\s*\n(.*?)\n---\s*$", raw, re.MULTILINE | re.DOTALL)
if not match:
    print(f"No YAML frontmatter in {config_path}", file=sys.stderr)
    sys.exit(0)

fm = match.group(1)

domains = []
current = None
for line in fm.splitlines():
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    if re.match(r"^domains\s*:\s*$", line):
        continue
    # Domain item start: "  - name: Foo"
    m = re.match(r"^\s*-\s*name\s*:\s*(.+?)\s*$", line)
    if m:
        if current is not None:
            domains.append(current)
        current = {"name": m.group(1), "glossary": None, "repos": []}
        continue
    # glossary: <path>
    m = re.match(r"^\s*glossary\s*:\s*(.+?)\s*$", line)
    if m and current is not None:
        current["glossary"] = os.path.expanduser(m.group(1))
        continue
    # repos: header
    if re.match(r"^\s*repos\s*:\s*$", line):
        continue
    # Repo entry: "      - /path"
    m = re.match(r"^\s*-\s*(.+?)\s*$", line)
    if m and current is not None and current.get("glossary"):
        current["repos"].append(os.path.expanduser(m.group(1)))

if current is not None:
    domains.append(current)

def match(probe: str):
    found = None
    for dom in domains:
        if not dom.get("glossary"):
            continue
        for repo in dom["repos"]:
            try:
                repo_abs = os.path.realpath(repo)
            except OSError:
                continue
            if probe == repo_abs or probe.startswith(repo_abs + os.sep):
                if found is None or len(repo_abs) > len(found["repo"]):
                    found = {
                        "name": dom["name"],
                        "glossary": dom["glossary"],
                        "repo": repo_abs,
                    }
    return found


best = match(cwd)

# If a direct cwd match failed and we're inside a git worktree, retry against
# the canonical (main) checkout so sibling worktrees auto-resolve to the
# registered repo.
if best is None:
    main = canonical_repo(cwd)
    if main and main != cwd:
        best = match(main)

if best is None:
    print(f"cwd '{cwd}' does not match any registered domain", file=sys.stderr)
    sys.exit(0)

print(f"{best['name']}\t{best['glossary']}")
PY
