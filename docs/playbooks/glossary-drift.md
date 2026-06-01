---
name: glossary-drift
description: Async post-commit drift check for domain glossaries; writes state to alerts/glossary-drift.md, never blocks commits
trigger: post-commit
schedule: ""
preflight: none
tier: low-stakes write
status: active
runner: script
script: drift-check-on-commit.sh
out_pattern: CEO/alerts/glossary-drift.md
---

# Glossary Drift

Shell-only playbook. Fires after every successful `git commit` (via the obsidian
commit-capture flow) and verifies that every glossary citation in
`domain-glossary.local.md` still resolves to a live symbol or file.

Runs detached from the parent shell — the commit hook returns in ~10–70 ms;
the actual check (about 1 s on a 49-citation glossary against the
`mtf-builder` repo) finishes in the background under a 30 s hard timeout.

## Origin

Issue [nhangen/domain-glossary#6](https://github.com/nhangen/domain-glossary/issues/6).

An earlier draft of this work proposed wiring drift-check into commit-capture
synchronously. Pre-implementation audit flagged the risk of stalling commits,
and pointed at the
[`ceo-automated-writers-are-playbooks`](https://github.com/nhangen/llm-tools/blob/main/home/.claude/rules/ceo-automated-writers-are-playbooks.md)
rule (state file, not signal generator). This playbook is the audit-corrected
version.

## Outputs

| File | Mode | When |
|---|---|---|
| `CEO/alerts/glossary-drift.md` | overwrite | Every successful run. One state file with frontmatter (`status: firing\|clear`, `since:`, `last_check:`, per-status counts, `writer: domain-glossary`). |

The state file is **never appended**. On detected drift it lists up to the
first 25 drifted citations in the body; if all glossaries resolve cleanly the
body is replaced with `All citations resolve cleanly.`.

### Failure invariant

On any of: `drift-check-all.sh` non-recoverable error, timeout, malformed
summary line — stderr is the only output. The state file is left untouched so
a transient failure cannot silently clear an active alert. Mirrors the
`measurement_failed` invariant in `ceo-disk-monitor.sh`.

The hook is fire-and-forget from the parent's perspective. Errors that occur
in the background subshell are logged to `${TMPDIR:-/tmp}/glossary-drift.log`
for forensic inspection.

## Install

Two pieces:

1. **In this repo** — the `drift-check-on-commit.sh` script is already in
   `skills/domain-glossary/scripts/`.
2. **In `claude-ceo`** — add a registry entry pointing at this playbook so
   `ceo playbook scan` picks it up:

   ```json
   {
     "name": "glossary-drift",
     "description": "Async post-commit glossary citation drift check; state file at alerts/glossary-drift.md",
     "trigger": "post-commit",
     "schedule": "",
     "tier": "low-stakes write",
     "status": "active",
     "runner": "script",
     "script": "<path-to>/skills/domain-glossary/scripts/drift-check-on-commit.sh",
     "out_pattern": "CEO/alerts/glossary-drift.md"
   }
   ```

   Trigger is `post-commit`, not `cron` — invocation is driven by the obsidian
   commit-capture hook (see "Wiring into commit-capture" below), not a clock.

3. **In the obsidian plugin's `commit-capture.sh`** (or any equivalent
   post-commit hook) — call this script after the commit-detection branch:

   ```bash
   if command -v drift-check-on-commit >/dev/null 2>&1 || \
      [ -x "$DOMAIN_GLOSSARY_HOOK" ]; then
     "${DOMAIN_GLOSSARY_HOOK:-$HOME/.../skills/domain-glossary/scripts/drift-check-on-commit.sh}" || true
   fi
   ```

   The `|| true` is belt-and-suspenders — the script always exits 0 — but
   guarantees no commit-capture regression even on a misconfigured environment.

## Documented gaps

- **30 s hard timeout.** Tuned for glossaries up to ~500 citations. Larger
  glossaries should split into multiple domain entries (`domain-glossary` is
  already designed around per-domain files) rather than raising the cap.
- **No partial-state output on timeout.** If the check is killed mid-run, the
  prior state file is preserved. No "we got 17 of 49 before being killed"
  output exists; the next commit re-runs from scratch.
- **No transition-to-inbox escalation.** The disk-monitor playbook escalates
  to `CEO/inbox/<host>.md` when state stays firing across runs; this playbook
  intentionally does not. Glossary drift is a curation backlog item, not an
  operational alert — the maintainer reads the state file when they want to
  curate, not when paged.
- **Repo aliases derived from basename only.** A registered repo with a path
  ending `/mtf-builder` becomes the alias `mtf-builder`. Two registered repos
  with the same basename collide. If that becomes a problem, add an explicit
  `alias:` field to `domain-glossary.local.md` rather than fixing it here.

## Disable

To disable, remove the call from `commit-capture.sh`. The script itself stays
installed so manual `drift-check-on-commit.sh` invocations still work.
