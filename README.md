# domain-glossary

Personal Claude Code skill for maintaining source-grounded domain glossaries.

The goal is a homegrown replacement for static `CONTEXT.md`-style project
glossaries. Entries live in Obsidian by domain, cite verifiable source artifacts,
and are periodically checked for drift.

## Phase 0 Status

- Storage: Obsidian-first, with optional repo mirror later.
- Scope: per-domain glossary files.
- First target: Altamira / `mtf-builder`.
- Exposure: personal-only through the A/B trial.
- Citation key: symbol-name primary, file-path fallback.

## Planned Usage

```text
/domain-glossary
/domain-glossary seed Altamira
/domain-glossary drift-check /Users/nhangen/Documents/Obsidian/Altamira/glossary.md
```

## Drift Check

```bash
skills/domain-glossary/scripts/drift-check.sh \
  --repo "mtf-builder=/Users/nhangen/Library/Mobile Documents/com~apple~CloudDocs/Documents/WSU/Altamira/MTF/mtf-builder" \
  /Users/nhangen/Documents/Obsidian/Altamira/glossary.md
```

The checker reports `RESOLVED`, `RELOCATED`, or `UNRESOLVED` for every citation.
It does not rewrite glossary files automatically.

## Tests

```bash
./tests/test-drift-check.sh
./tests/test-seeders.sh
./tests/test-render-repo-mirror.sh
```
