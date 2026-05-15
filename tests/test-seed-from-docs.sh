#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/domain-glossary/scripts/seed-from-docs.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/example-repo"
mkdir -p "$REPO/docs" "$REPO/scripts/foo"
git -c init.defaultBranch=main -C "$TMP" init example-repo >/dev/null
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name "Test User"

cat >"$REPO/README.md" <<'MD'
# Example

The DTW Threshold Artifact governs cross-channel alignment.

Refer to `apply_channel` when wiring the pipeline. Also see the `phase/bridge` module and the `kebab-flag` option.

**Smooth phase boundaries**: how a contiguous phase is reconstructed.

Project uses GPU acceleration; the MTF metric is the headline.

However Smooth Boundaries fail under sparse phase data; Pull Requests welcome.

## Installation

Run pip install.

```
secret_only_in_code_block_token
```
MD

cat >"$REPO/docs/glossary.md" <<'MD'
# Glossary

## Calibrated trust decision

A decision gated by the trust scalar.

## Usage

Some usage info.

## dtw threshold artifact

The dtw threshold artifact also appears in lowercase prose.

## Fixes Workflow

Section that should be rejected by the project-meta filter.
MD

cat >"$REPO/scripts/foo/README.md" <<'MD'
# Foo

## Channel canonicalization

Normalizes channel ordering across pipelines.
MD

cat >"$REPO/sample.py" <<'PY'
"""Computes the perturbation sweep gate."""


class BoundaryContinuity:
    """Bridges Smooth phase boundaries across windows."""
    pass
PY

cat >"$REPO/raw_doc.py" <<'PY'
r"""Raw docstring describing the Quintic Bridge."""


class RawClass:
    f"""Format-string docstring for the Token Vault."""
    pass
PY

git -C "$REPO" add .
git -C "$REPO" commit -m "Seed fixture repo" >/dev/null

OUTPUT="$(
  "$SCRIPT" \
    --repo "$REPO" \
    --repo-name example-repo \
    --limit 200
)"

assert_in() {
  if ! grep -qF "$1" <<<"$OUTPUT"; then
    echo "FAIL: expected to find '$1' in output" >&2
    echo "--- output ---" >&2
    echo "$OUTPUT" >&2
    exit 1
  fi
}

assert_not_in() {
  if grep -qF "$1" <<<"$OUTPUT"; then
    echo "FAIL: did not expect '$1' in output" >&2
    echo "--- output ---" >&2
    echo "$OUTPUT" >&2
    exit 1
  fi
}

# Capitalized phrases
assert_in "DTW Threshold Artifact"

# Backticked symbols
assert_in "apply_channel"

# Backticked path-shape and kebab-flag (widened TICK regex)
assert_in "phase/bridge"
assert_in "kebab-flag"

# Bolded glossary terms
assert_in "Smooth phase boundaries"

# Headings as candidate terms
assert_in "Calibrated trust decision"
assert_in "Channel canonicalization"

# Acronym extraction in prose
assert_in "GPU"
assert_in "MTF"

# Python class identifiers as glossary candidates
assert_in "BoundaryContinuity"
assert_in "RawClass"

# Python docstring extraction (Title-cased phrases)
assert_in "Bridges Smooth"

# Raw/format-prefixed docstrings
assert_in "Quintic Bridge"
assert_in "Token Vault"

# Code-block contents excluded
assert_not_in "secret_only_in_code_block_token"

# Tab-bracketed meta drops (single-token stoplist)
assert_not_in "	Installation	"
assert_not_in "	Usage	"
assert_not_in "	License	"

# Plural meta phrase rejection (PHRASE-level stoplist)
assert_not_in "Pull Requests"

# Sentence-start connector rejection
assert_not_in "However Smooth Boundaries"

# Project-meta tokens rejected via POSIX-portable is_meta (no \<...\> word
# boundaries — those are gawk-only and would silently no-op on macOS BWK awk).
assert_not_in "Fixes Workflow"

# Case-folded dedup: the README PHRASE "DTW Threshold Artifact" and the
# glossary HEADING "dtw threshold artifact" share a lowercase key. The
# output must have exactly one row, carrying the Title-Cased display
# variant and count >= 2.
dtw_rows="$(grep -ciE '^dtw threshold artifact	' <<<"$OUTPUT" || true)"
if [[ "$dtw_rows" -ne 1 ]]; then
  echo "FAIL: expected exactly 1 row for the DTW Threshold Artifact key, got $dtw_rows" >&2
  echo "--- output ---" >&2
  echo "$OUTPUT" >&2
  exit 1
fi
dtw_display="$(grep -iE '^dtw threshold artifact	' <<<"$OUTPUT" | awk -F'\t' 'NR==1{print $1}')"
if [[ "$dtw_display" != "DTW Threshold Artifact" ]]; then
  echo "FAIL: expected display 'DTW Threshold Artifact', got '$dtw_display'" >&2
  exit 1
fi
dtw_count="$(grep -iE '^dtw threshold artifact	' <<<"$OUTPUT" | awk -F'\t' 'NR==1{print $2}')"
if [[ "$dtw_count" -lt 2 ]]; then
  echo "FAIL: expected count >= 2 for DTW Threshold Artifact, got $dtw_count" >&2
  exit 1
fi

# Citation file existence
while IFS=$'\t' read -r candidate count source citation; do
  rel="${citation#example-repo:}"
  if [[ ! -f "$REPO/$rel" ]]; then
    echo "FAIL: citation '$citation' does not point at a real file (looked at $REPO/$rel)" >&2
    exit 1
  fi
done <<<"$OUTPUT"

# Repo alias plumbing
ALIAS_OUTPUT="$(
  "$SCRIPT" \
    --repo "$REPO" \
    --repo-name custom-name \
    --limit 200
)"
while IFS=$'\t' read -r candidate count source citation; do
  if [[ "$citation" != custom-name:* ]]; then
    echo "FAIL: citation '$citation' does not start with 'custom-name:'" >&2
    exit 1
  fi
done <<<"$ALIAS_OUTPUT"

# Reject non-repo dirs
mkdir -p "$TMP/not-a-repo"
echo "# x" > "$TMP/not-a-repo/README.md"
if "$SCRIPT" --repo "$TMP/not-a-repo" --repo-name not-a-repo >/dev/null 2>&1; then
  echo "FAIL: seed-from-docs accepted a non-repository directory" >&2
  exit 1
fi

# --limit non-numeric must error
if "$SCRIPT" --repo "$REPO" --repo-name example-repo --limit foo >/dev/null 2>&1; then
  echo "FAIL: --limit foo was accepted; expected error" >&2
  exit 1
fi

# Missing argument value must error (not crash under set -u)
if "$SCRIPT" --repo "$REPO" --repo-name example-repo --limit >/dev/null 2>&1; then
  echo "FAIL: --limit with no value was accepted; expected error" >&2
  exit 1
fi

# --limit honored as a positive bound
LIMITED="$("$SCRIPT" --repo "$REPO" --repo-name example-repo --limit 3)"
limited_count="$(printf '%s\n' "$LIMITED" | wc -l | tr -d ' ')"
if [[ "$limited_count" -gt 3 ]]; then
  echo "FAIL: --limit 3 produced $limited_count rows" >&2
  exit 1
fi

# Empty repo: zero rows, exit 0
EMPTY_REPO="$TMP/empty-repo"
mkdir -p "$EMPTY_REPO"
git -c init.defaultBranch=main -C "$TMP" init empty-repo >/dev/null
git -C "$EMPTY_REPO" config user.email test@example.com
git -C "$EMPTY_REPO" config user.name "Test User"
git -C "$EMPTY_REPO" commit --allow-empty -m "init" >/dev/null
EMPTY_OUT="$("$SCRIPT" --repo "$EMPTY_REPO" --repo-name empty-repo)"
if [[ -n "$EMPTY_OUT" ]]; then
  echo "FAIL: empty repo produced output: $EMPTY_OUT" >&2
  exit 1
fi

echo "seed-from-docs fixtures passed"
