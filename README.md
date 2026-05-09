# domain-glossary

Personal Claude Code skill for maintaining source-grounded domain glossaries.

The goal is a homegrown replacement for static `CONTEXT.md`-style project
glossaries. Entries live in Obsidian by domain, cite verifiable source artifacts,
and are periodically checked for drift.

## Current Status

- Storage: Obsidian-first, with optional repo mirror later.
- Scope: per-domain glossary files.
- First target: Altamira / `mtf-builder`.
- Exposure: public personal v0.1 tooling; not marketplace-ready.
- Citation key: symbol-name primary, file-path fallback.

## Evaluation Status

Phase 4/5 produced retrospective proxy evidence only: no measured token savings,
no proxy time-to-root-cause improvement, and a small reviewer-observed preference
for glossary-loaded PR language.

Because `token-scope` was not available in the trial shell, this repository does
not claim measured token savings yet. See
`docs/evaluations/2026-05-08-phase4-ab-trial.md` for the caveats and next
validation step.

## Planned Usage

```text
/domain-glossary
/domain-glossary seed Altamira
/domain-glossary drift-check /path/to/glossary.md
```

## Drift Check

```bash
skills/domain-glossary/scripts/drift-check.sh \
  --repo "mtf-builder=/path/to/mtf-builder" \
  /path/to/glossary.md
```

The checker reports `RESOLVED`, `RELOCATED`, or `UNRESOLVED` for every citation.
It does not rewrite glossary files automatically.

## Tests

```bash
./tests/test-drift-check.sh
./tests/test-seeders.sh
./tests/test-render-repo-mirror.sh
```
