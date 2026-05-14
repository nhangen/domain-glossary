#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

Refer to `apply_channel` when wiring the pipeline.

**Smooth phase boundaries**: how a contiguous phase is reconstructed.

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

git -C "$REPO" add .
git -C "$REPO" commit -m "Seed fixture repo" >/dev/null

OUTPUT="$(
  "$ROOT/skills/domain-glossary/scripts/seed-from-docs.sh" \
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

# test_extracts_capitalized_phrases
assert_in "DTW Threshold Artifact"

# test_extracts_backticked_symbols
assert_in "apply_channel"

# test_extracts_bolded_terms
assert_in "Smooth phase boundaries"

# test_extracts_heading_terms
assert_in "Calibrated trust decision"
assert_in "Channel canonicalization"

# test_skips_code_block_contents
assert_not_in "secret_only_in_code_block_token"

# test_skips_common_meta_terms
assert_not_in "	Installation	"
assert_not_in "	Usage	"
assert_not_in "	License	"

# test_citation_includes_source_file
while IFS=$'\t' read -r candidate count source citation; do
  rel="${citation#example-repo:}"
  if [[ ! -f "$REPO/$rel" ]]; then
    echo "FAIL: citation '$citation' does not point at a real file (looked at $REPO/$rel)" >&2
    exit 1
  fi
done <<<"$OUTPUT"

# test_repo_alias_in_citation
ALIAS_OUTPUT="$(
  "$ROOT/skills/domain-glossary/scripts/seed-from-docs.sh" \
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

# Reject non-repo dirs (mirror seed-from-gitnexus's contract)
mkdir -p "$TMP/not-a-repo"
echo "# x" > "$TMP/not-a-repo/README.md"
if "$ROOT/skills/domain-glossary/scripts/seed-from-docs.sh" \
  --repo "$TMP/not-a-repo" \
  --repo-name not-a-repo >/dev/null 2>&1; then
  echo "FAIL: seed-from-docs accepted a non-repository directory" >&2
  exit 1
fi

echo "seed-from-docs fixtures passed"
