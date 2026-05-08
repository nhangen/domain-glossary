# Drift-Check Protocol

For every glossary entry, parse the `Citation:` line and resolve it without
mutating the glossary.

## Resolution

- Symbol citations resolve against the expected repo path first. If the symbol
  is missing at that path, drift-check searches the resolved repo. A single
  match becomes `RELOCATED`; zero or multiple matches become `UNRESOLVED`.
- Obsidian citations resolve by checking that the linked note exists under the
  configured vault root.
- Path citations resolve by checking that the file exists. If a line number is
  present, the line must be inside the file.

## Statuses

- `RESOLVED` — the cited artifact still exists.
- `RELOCATED` — the symbol was not at the old path but was found once elsewhere
  in the same repo; the output includes a suggested replacement citation.
- `UNRESOLVED` — manual review is required.

## Source Systems

GitNexus remains the preferred source of truth when the target repo is indexed,
but shell scripts cannot call Claude MCP tools directly. The local drift-checker
therefore uses explicit repo mappings, current git state, and GitNexus registry
paths as local fallbacks. Agent-side orchestration may still call GitNexus MCP
before or after the script when available.

`Last verified` should be updated only after a human or agent accepts the
drift-check result. The Phase 1 script reports drift; it does not rewrite
glossary files automatically.
