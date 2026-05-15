---
name: domain-glossary
description: Source-grounded project glossary lookup and curation. **Invoke whenever you encounter an unfamiliar acronym, project-specific term, code-symbol name, or domain noun in a known project repo — do not guess at expansions.** Auto-resolves the right glossary for the current cwd. Also handles `seed` (build candidate terms from claude-mem / commits / GitNexus / docs) and `drift-check` (verify every citation still resolves).
version: 0.2.0
author: nhangen
---

# domain-glossary

A skill with three operations, but the most common is the **first**: looking up a term the agent doesn't already know.

## Operation 1 — Look up a term (default)

When the user mentions a term you can't ground in current context (acronyms like `GAMG`, `MMAE`, `LCR`; project-specific class names; ambiguous nouns), invoke this skill **before answering**. Do not guess at expansions. Steps:

1. **Resolve the current domain** from the active cwd:
   - Read `${CLAUDE_PLUGIN_ROOT}/domain-glossary.local.md` (frontmatter YAML).
   - For each entry under `domains:`, longest-prefix-match the current working directory against the entry's `repos:` list.
   - The matching entry's `name` is the domain; its `glossary:` is the file to read.
   - If no entry matches: the user's repo is not registered; report that and ask whether to add it to `domain-glossary.local.md` (`${CLAUDE_PLUGIN_ROOT}/domain-glossary.local.md.example` is the template).
2. **Read the glossary** with the Read tool. Glossary files use `### Term name` headings; entries carry `**Citation:**` lines pointing at code symbols, doc paths, or Obsidian notes.
3. **Answer grounded** in entries found there. If the term is in the glossary, cite the entry's citation back to the user (e.g. *"GAMG is G-Force Magnitude, the superior discrimination channel in the 42-channel analysis (`mtf-builder:docs/reports/.../PHASE1_COMPLETE_42CHANNEL_REPORT.md`)"*).
4. **If the term isn't there:** say so explicitly. Do not invent an expansion. Offer to run `seed` on the matching repo or ask the user to clarify. Trust-grounding is the whole point of the skill — a fabricated definition is worse than "I don't know."

This is the default invocation. Slash-commands `seed` and `drift-check` (below) are for curation, not lookup.

## Operation 2 — Seed new candidate terms

`/domain-glossary seed <domain>` — discover candidate terms for a domain by running all four seeders against its registered repos and presenting a ranked, deduped candidate list for user confirmation before writing.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/seed-from-claude-mem.sh --project <project> --query <domain>
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/seed-from-commits.sh --repo <repo>
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/seed-from-gitnexus.sh --repo <repo> --repo-name <name>
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/seed-from-docs.sh --repo <repo> --repo-name <name>
```

Merge the tab-separated rows using the protocol in `references/seed-protocol.md`. There is no standalone merge script; the agent does the merge. Do not write entries until term, definition, and citation are confirmed with the user.

## Operation 3 — Drift-check

`/domain-glossary drift-check <glossary.md>` — walk every citation in a glossary, verify the symbol or path still exists, and report `RESOLVED` / `RELOCATED` / `UNRESOLVED`.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/drift-check.sh <glossary.md>
```

Add `--repo name=/absolute/path` when a glossary uses repo aliases that are not registered in GitNexus.

## Setup (one-time, per machine)

```bash
cp ${CLAUDE_PLUGIN_ROOT}/domain-glossary.local.md.example \
   ${CLAUDE_PLUGIN_ROOT}/domain-glossary.local.md
# edit domain-glossary.local.md to register your domains + repo paths
```

`*.local.md` is gitignored. No CLAUDE.md edits, no per-repo install — registering a new domain is one entry in this file and works automatically across every Claude Code session afterward.

## Hard Rules

- Do not write uncited glossary entries.
- Do not invent acronym expansions or term definitions. If the glossary doesn't have it, say so.
- Treat Obsidian as the canonical glossary store.
- Keep glossaries per-domain rather than per-repository — multiple repos can share one glossary via the `repos:` list.
- Prefer symbol-name citations; fall back to file paths only when no stable symbol exists.
