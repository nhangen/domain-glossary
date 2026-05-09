# Phase 4 A/B Trial — Altamira Glossary

Date: 2026-05-08

## Scope

This is the Phase 4 trial for the source-grounded domain glossary skill. The
trial used two real `mtf-builder` bug fixtures from prior review notes:

1. MR !29: `physics_quintic` comparison harness used a different kinematics
   anchor than production `smooth_phase_boundaries`.
2. MR !45 / MTF-35: `run_sweep` rejected a threshold artifact for DTW even
   though DTW could consume the same artifact for calibrated trust decisions.

The trial compared a bare subagent prompt against a glossary-loaded subagent
prompt for each fixture.

## Measurement Caveat

`token-scope --context --json` was not available in the local shell during this
run, so the planned token measurement could not be produced. The trial records
self-reported retrospective proxy measurements instead:

- first-correct-hypothesis step, where the step is the numbered reasoning
  step at which the subagent named the root cause;
- whether the final PR description preserved domain vocabulary;
- whether the session needed extra context to name the root cause;
- reviewer judgment on whether the result would need editing before reuse.

This makes the result useful as a workflow signal, but not strong evidence for
token reduction.

The fixture wording came from prior review notes, so it likely included
root-cause cues and compressed the discovery work. This under-tests whether a
glossary helps on a fresh investigation.

## Results

| Fixture | Session | Glossary context | First correct hypothesis | Domain-language PR description | Notes |
| --- | --- | --- | --- | --- | --- |
| MR !29 kinematics-anchor mismatch | A | no | 3 (saturated — see caveat) | partial | Found the root cause, but described it in looser implementation terms. |
| MR !29 kinematics-anchor mismatch | B | yes | 3 (saturated — see caveat) | strong | Used "smooth phase boundaries" and "kinematics anchor" directly and described the production-vs-harness mismatch more cleanly. |
| MTF-35 DTW threshold-artifact guard | A | no | 3 (saturated — see caveat) | partial | Found the stale guard and proposed the correct allowlist-style fix. |
| MTF-35 DTW threshold-artifact guard | B | yes | 3 (saturated — see caveat) | strong | Preserved the calibrated trust semantics and fallback vocabulary in the PR description. |

## Decision

Outcome: no measured token/speed signal; small reviewer-observed language
preference.

The glossary did not reduce time-to-first-correct-hypothesis in this proxy
trial. All four sessions reached the root cause by step 3 because the fixtures
were already well specified. The glossary-loaded sessions produced PR
descriptions that, by reviewer judgment, kept the Altamira terms and validation
semantics intact with less editing.

Phase 5 is the publish/readiness decision gate. The Phase 4/5 decision is to
keep the repository public as personal v0.1 tooling, but not claim token savings
or treat it as marketplace-ready. The next real validation should be
prospective: load the glossary before the next fresh Altamira debugging/review
session and capture `token-scope` metrics from the start.

## PR Description Rubric

The reviewer preference used this lightweight rubric:

- terminology accuracy;
- source-grounded root-cause language;
- preservation of validation semantics;
- edits needed before reuse in a PR.

## Follow-Ups

- Install or expose `token-scope` in the shell used for future trials.
- Run a prospective trial on the next fresh `mtf-builder` bug rather than a
  retrospective fixture.
- Add an optional repo mirror only after the Obsidian glossary stabilizes.
