# Seed Protocol

Candidate terms come from existing artifacts, not from a blank interview.

Sources:

- claude-mem observations for recurring domain phrases.
- Git commit messages for repeated nouns and noun phrases.
- GitNexus-indexed repos when available, with local symbol definitions as the
  scriptable fallback.
- Obsidian notes for durable domain vocabulary already written down.

The user confirms candidates before the skill writes glossary entries.

## Script Output

Each seed script emits tab-separated rows:

```text
candidate<TAB>count<TAB>source<TAB>evidence
```

The evidence column is source-specific:

- `claude-mem`: comma-separated observation IDs.
- `commits`: first matching commit subject.
- `gitnexus-fallback`: a proposed symbol citation.

## Merge Logic

This merge is currently an agent-side procedure, not a standalone script.

1. Normalize candidate text to lowercase for merging.
2. Add counts across sources.
3. Boost candidates that appear in more than one source.
4. Prefer candidates with symbol citations when a glossary entry needs a code
   anchor.
5. Drop generic workflow terms unless the target domain itself uses them as
   vocabulary.

The scripts are candidate generators, not glossary writers. A candidate becomes
a glossary entry only after the user or orchestrating agent confirms the term,
definition, and citation.
