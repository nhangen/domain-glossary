# Citation Format

Glossary entries support three citation families.

## Symbol Citation

```markdown
**Citation:** `smooth_phase_boundaries` in `mtf-builder:scripts/pipeline/dtw_pipeline/combine_phases.py`
```

Use this when a stable function, class, constant, or script-level symbol is the
best anchor. The symbol name is the primary key; the path is the expected current
location. If the path no longer contains the symbol, drift-check searches the
resolved repo and reports `RELOCATED` when it finds exactly one replacement.

## Obsidian Note Citation

```markdown
**Citation:** [[Altamira/2026-05-04-mtf-builder-mr29-review-fix]]
```

Use this when the source of truth is a session note, plan, analysis note, or
human-written interpretation. Aliases and heading anchors are allowed, but
drift-check resolves only the note file.

## Path Citation

```markdown
**Citation:** `mtf-builder:docs/ARCHITECTURE.md:210`
```

Use this as a fallback when no stable symbol exists. Line numbers are checked
for being inside the file, but line citations should be considered weaker than
symbols because they drift under ordinary edits.

## Repo Resolution

`drift-check.sh` resolves repo names in this order:

1. `--repo name=/absolute/path` options.
2. `DOMAIN_GLOSSARY_REPO_ROOT` when its basename matches the repo.
3. The current git repo when its basename matches the repo.
4. `~/.gitnexus/registry.json` when GitNexus has indexed the repo.

If a repo cannot be resolved, the citation is `UNRESOLVED`.
