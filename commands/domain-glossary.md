---
name: domain-glossary
description: Build and maintain source-grounded domain glossaries. Usage: /domain-glossary [seed|drift-check] ...
---

Use the domain-glossary skill at `${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/SKILL.md`.

For drift checks, run:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/domain-glossary/scripts/drift-check.sh <glossary.md>
```

Examples:
- `/domain-glossary`
- `/domain-glossary seed Altamira`
- `/domain-glossary drift-check /Users/nhangen/Documents/Obsidian/Altamira/glossary.md`
