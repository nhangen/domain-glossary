---
name: domain-glossary
description: Build and maintain source-grounded domain glossaries in Obsidian, seeded from claude-mem, GitNexus, commits, and notes, with citation drift checks.
version: 0.1.0
author: nhangen
---

# domain-glossary

Status: Phase 1 drift-check and Phase 2 seed scripts are available. The first
Altamira glossary seed exists in Obsidian.

## Current Behavior

When invoked without a subcommand, identify the target domain and report the
available commands.

For `drift-check`, run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/drift-check.sh <glossary.md>
```

Add `--repo name=/absolute/path` when a glossary uses repo aliases that are not
registered in GitNexus.

For `seed`, run the three seed scripts and merge their tab-separated output in
the agent workflow:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/seed-from-claude-mem.sh --project <project> --query <domain>
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/seed-from-commits.sh --repo <repo>
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/seed-from-gitnexus.sh --repo <repo> --repo-name <name>
```

Treat the seed output as a candidate list. There is not yet a standalone merge
script; the agent should merge and rank rows using `references/seed-protocol.md`.
Do not write entries until the term, definition, and citation are confirmed.

## Intended Workflow

1. Identify the domain from the user prompt, current repository, or configured
   repo-to-domain map.
2. Seed candidate terms from claude-mem observations, git commit messages, and
   GitNexus symbol data.
3. Ask the user to confirm or reject candidate terms.
4. Resolve every citation before writing an entry.
5. Write accepted entries to the Obsidian domain glossary.
6. Run drift-check and report resolved, relocated, and unresolved citations.

## Altamira Defaults

Initial domain: `Altamira`

Initial repo alias:

```text
mtf-builder=/Users/nhangen/Library/Mobile Documents/com~apple~CloudDocs/Documents/WSU/Altamira/MTF/mtf-builder
```

Canonical glossary:

```text
/Users/nhangen/Documents/Obsidian/Altamira/glossary.md
```

## Hard Rules

- Do not write uncited glossary entries.
- Treat Obsidian as the canonical glossary store.
- Keep glossaries per-domain rather than per-repository.
- Prefer symbol-name citations; fall back to file paths only when no stable
  symbol exists.
