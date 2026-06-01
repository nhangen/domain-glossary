---
name: domain-glossary
description: Source-grounded project glossary lookup and curation. **Use when the user asks "what is X?", "what does <ACRONYM> mean?", "define X", "explain <term>", or references any project-specific acronym, code-symbol, or domain noun in a registered repo — do not guess at expansions.** Auto-resolves the right glossary for the current cwd via a resolver script. Also handles `seed` (build candidates from claude-mem / commits / GitNexus / docs) and `drift-check` (verify every citation still resolves).
version: 0.2.0
author: nhangen
---

# domain-glossary

A skill with three operations. The most common is the **first**: looking up a term the agent doesn't already know.

## Operation 1 — Look up a term (default)

When the user mentions a term you can't ground in current context (acronyms like `GAMG`, `MMAE`, `LCR`; project-specific class names; ambiguous nouns), invoke this skill **before answering**. Do not guess at expansions.

**Step 1.** Find the current working directory:

```bash
pwd
```

**Step 2.** Resolve which glossary applies to that cwd. Run the resolver:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/resolve-domain.sh" "$(pwd)"
```

Output is `<domain>\t<glossary-absolute-path>` on stdout, or empty if no match (stderr explains why).

The resolver handles all the parsing: YAML frontmatter in `domain-glossary.local.md`, longest-prefix matching, `~/`-expansion, and a git-worktree fallback (so a worktree sibling of a registered repo automatically resolves to the same domain). The agent does not need to parse YAML.

**Step 3.** If the resolver emitted a path, read it with the Read tool. Glossary files use `### Term name` headings; entries carry `**Citation:**` lines pointing at code symbols, doc paths, or Obsidian notes.

**Step 4.** Answer grounded in entries found there. If the term is in the glossary, cite the entry's citation back to the user (e.g. *"GAMG is G-Force Magnitude, the superior discrimination channel in the 42-channel analysis (`mtf-builder:docs/reports/.../PHASE1_COMPLETE_42CHANNEL_REPORT.md`)"*).

**Step 5.** Handle the failure cases:
- **Resolver emitted empty + stderr says "Config not found":** the user hasn't set up `domain-glossary.local.md` yet. Point them at `${CLAUDE_PLUGIN_ROOT}/domain-glossary.local.md.example` and stop.
- **Resolver emitted empty + stderr says "does not match any registered domain":** the current repo isn't in the config. Tell the user, offer to add an entry, and answer the original question from non-glossary knowledge with an explicit hedge.
- **Glossary was read but the term isn't in it:** say so explicitly. Do not invent an expansion. Offer to run `seed` on the matching repo to find candidates. Trust-grounding is the whole point of the skill — a fabricated definition is worse than "I don't know."

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

To check every configured domain at once:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/drift-check-all.sh
```

Repo aliases for `drift-check-all` are derived from the basename of each path in `domain-glossary.local.md`'s `repos:` list. Exit status is the count of drifted citations (capped at 255).

For automated post-commit invocation, see `drift-check-on-commit.sh` and `docs/playbooks/glossary-drift.md` — the hook detaches under a 30 s hard timeout and writes a state file to `$CEO_VAULT/CEO/alerts/glossary-drift.md`.

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
