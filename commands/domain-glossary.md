---
name: domain-glossary
description: Build and maintain source-grounded domain glossaries. Usage: /domain-glossary [seed|drift-check] ...
---

Use the domain-glossary skill at `${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/SKILL.md`.

User arguments: `$ARGUMENTS`

Pass the full user arguments through to the skill. Interpret the first argument
as the requested subcommand when present:

- `lookup <term>` (default if first arg looks like a term, not a subcommand)
- `seed`
- `drift-check`

For `lookup`, the skill auto-resolves the active repo's domain via
`${CLAUDE_PLUGIN_ROOT}/domain-glossary.local.md` and reads the matching
glossary file. This is also the operation the skill performs when invoked
without a slash-command — whenever the agent encounters an unfamiliar term in
a registered repo.

For drift checks, run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/drift-check.sh <glossary.md>
```

Examples:
- `/domain-glossary`
- `/domain-glossary seed Altamira`
- `/domain-glossary drift-check /Users/nhangen/Documents/Obsidian/Altamira/glossary.md`
