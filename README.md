# domain-glossary

**Source-grounded domain glossaries in Obsidian — every entry cites a verifiable code symbol, and every citation is drift-checked.**

## Why

Static `CONTEXT.md` / `GLOSSARY.md` files rot. A term defined against `Foo::bar()` in 2024 becomes a lie once the symbol is renamed, moved, or deleted, and nobody notices until an agent quotes it back at you.

This plugin keeps glossary entries in Obsidian (per-domain, not per-repo), requires every entry to cite a stable artifact (symbol name first, file path fallback), and provides a `drift-check` pass that classifies every citation as `RESOLVED`, `RELOCATED`, or `UNRESOLVED`.

## How it works

1. **Seed** candidate terms from three sources: claude-mem observations, git commit message corpora, and local symbol definitions (GitNexus CLI when available, grep fallback otherwise).
2. **Confirm** each candidate with the user before writing — the agent never writes uncited entries.
3. **Store** accepted entries in an Obsidian domain glossary (`<vault>/<Domain>/glossary.md`).
4. **Drift-check** on demand: walk every citation, resolve it against the cited repo, report status.
5. **Mirror** (optional) the canonical vault file to a repo `docs/glossary.md` with a provenance header.

## Current Status

- Storage: Obsidian-first, with optional repo mirror.
- Scope: per-domain glossary files.
- First target: Altamira / `mtf-builder`.
- Exposure: public personal v0.1 tooling; not marketplace-ready.
- Citation key: symbol-name primary, file-path fallback.

## Evaluation Status

Phase 4/5 produced retrospective proxy evidence only: no measured token savings, no proxy time-to-root-cause improvement, and a small reviewer-observed preference for glossary-loaded PR language.

Because `token-scope` was not available in the trial shell, this repository does not claim measured token savings yet. See `docs/evaluations/2026-05-08-phase4-ab-trial.md` for the caveats and next validation step.

## Commands

| Command | What it does |
|---|---|
| `/domain-glossary` | Identify the current domain and list available subcommands. |
| `/domain-glossary seed <domain>` | Run the three seed scripts and merge candidates for review. |
| `/domain-glossary drift-check <glossary.md>` | Resolve every citation in the glossary and report drift. |

## Scripts

All scripts live under `skills/domain-glossary/scripts/` and can be run directly without invoking the slash command.

| Script | Purpose |
|---|---|
| `drift-check.sh [--repo name=path] [--json] <glossary.md>` | Resolve citations, emit `RESOLVED` / `RELOCATED` / `UNRESOLVED`. |
| `seed-from-claude-mem.sh --project <p> --query <q>` | Candidate terms from claude-mem SQLite (`~/.claude-mem/claude-mem.db`). |
| `seed-from-commits.sh --repo <path> [--since <date>]` | Candidate terms by phrase frequency in git log. |
| `seed-from-gitnexus.sh --repo <path> --repo-name <alias>` | Candidate terms from symbol definitions (GitNexus when present, grep fallback). |
| `render-repo-mirror.sh --source <vault.md> --dest <repo/docs/glossary.md>` | Copy vault glossary to a repo mirror with provenance header. |

## Citation forms

Drift-check accepts three citation shapes inside a glossary entry:

```text
**Citation:** `symbol_name` in `repo:path/to/file.py`
**Citation:** `repo:path/to/file.py:42`
**Citation:** [[Altamira/some-note]]
```

`repo:` is an alias registered via `--repo name=/absolute/path` or via GitNexus.

## Examples

Drift-check a domain glossary against a registered repo:

```bash
skills/domain-glossary/scripts/drift-check.sh \
  --repo "mtf-builder=/path/to/mtf-builder" \
  /path/to/glossary.md
```

Seed candidates for a domain glossary:

```bash
skills/domain-glossary/scripts/seed-from-claude-mem.sh --project mtf-builder --query Altamira
skills/domain-glossary/scripts/seed-from-commits.sh    --repo /path/to/mtf-builder
skills/domain-glossary/scripts/seed-from-gitnexus.sh   --repo /path/to/mtf-builder --repo-name mtf-builder
```

Each seed script emits tab-separated rows (`candidate<TAB>count<TAB>source<TAB>citation`). The agent merges and ranks them per `references/seed-protocol.md`.

## Install

Personal plugin (source-tree development model):

```bash
# Source lives in ~/ML-AI/claude/domain-glossary
# Symlink into the Claude Code plugin cache to use it live:
ln -s ~/ML-AI/claude/domain-glossary \
      ~/.claude/plugins/cache/nhangen/domain-glossary/0.1.0
```

Then restart Claude Code. The `/domain-glossary` command and skill become available.

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `OBSIDIAN_VAULT_PATH` | `~/Documents/Obsidian` | Vault root for citation resolution and `[[wikilink]]` lookups. |
| `CLAUDE_MEM_DB` | `~/.claude-mem/claude-mem.db` | claude-mem SQLite database for seeding. |

## Development

```bash
./tests/test-drift-check.sh
./tests/test-seeders.sh
./tests/test-render-repo-mirror.sh
```

The tests are pure bash + fixtures; no network, no real vault.

## Hard rules

- No uncited glossary entries — ever.
- Obsidian is the canonical store. Repo mirrors are read-only renders.
- Glossaries are per-domain, not per-repository (one domain can span multiple repos).
- Prefer symbol-name citations; fall back to file paths only when no stable symbol exists.

## Known limitations

- GitNexus seed path is a grep-based fallback when the installed GitNexus CLI does not expose a "top symbols" subcommand. Symbol ranking is approximate.
- There is no automatic merge of seed output. The agent merges and ranks rows interactively.
- Drift-check does not rewrite glossary files. Resolution suggestions are advisory.

## License

MIT
