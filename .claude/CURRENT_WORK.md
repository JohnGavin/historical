# Current Work — session 26 (2026-08-29 → 2026-08-31)

## State

`main` fast-forwarded to `3f3c10a`, this worktree's own branch has 0 unique
commits (this session's work landed via ~30 separately-dispatched PRs, merged
directly to `main`, not via this branch). Working tree clean.

## What this session was

Built a triage artifact — the Signal Board — classifying all 161 open issues
into 6 priority tiers by risk to data/decision integrity, then worked through
P0 (all 26) and roughly half of P1 (24) via parallel worktree-isolated
agents, plus a decision-menu-then-dispatch cycle on the leverage-policy
cluster (#624/#625/#626/#635/#719/#587). Full detail in `CHANGELOG.md`'s
"session 26" entry — this file is the short version for the next session to
orient from.

## Verification posture (read before trusting any number)

Everything merged today passed `scripts/verify.sh` (structural: parse +
`tar_validate()` + both testthat suites). **Nothing was verified against a
real `tar_make()`** — this worktree cannot run `scripts/build.sh` (main-
checkout only). Pipeline-body changes from today that need that confirmation
before being trusted for real sizing/decisions:

- The leverage allocator (#626/#833) — real gross-exposure numbers unconfirmed
- CMR conditioning-overlay wiring (#751/#808) — diagnostic targets built,
  not wired into `cmr_returns_*` yet
- XGBoost reseeding (#779/#802) — fix logic confirmed via debugging, not via
  a rebuilt store
- The stop-rule engine (#588/#820) — mechanism proven on synthetic data only,
  real Arm A/B/C numbers against live strategies still needed
- `#586`'s prop-constrained view — merged on a static target-name check, not
  a real `quarto render` (see CHANGELOG Known Limitations)

**First thing to do next session in the main checkout:** run
`scripts/build.sh --render` and read `scripts/check_pipeline_errors.R`'s
output. If anything above shows an errored target, that's expected work, not
a regression to panic about.

## Open decisions (not code — need a human)

- **Leverage backstop level (D1)**: `leverage_gross_backstop` currently
  defaults to 2.0x, override via `HD_LEVERAGE_GROSS_BACKSTOP`. Not finalized.
- **#586's fat-tail simulation fallback + finite-horizon conditioning**: out
  of scope this session.
- **#719 Layer 2** (full provenance checklist gating the allocator): only a
  narrow slice (detection-power gate, S31) is built. The rest is unscoped.

## Next session

**Signal Board tiers not yet touched:** P2-P5 (the bulk of the original
161-issue backlog — mostly exploratory research/strategy proposals, lower
urgency by construction). Re-derive the tier list from a fresh `gh issue
list` rather than trusting the original Signal Board artifact's snapshot —
today moved a lot of issues.

**Held back this session, still open, still worth a look:**

| Issue | Why held |
|---|---|
| [#553](https://github.com/JohnGavin/historical/issues/553)/[#554](https://github.com/JohnGavin/historical/issues/554)/[#555](https://github.com/JohnGavin/historical/issues/555) | Fundamentals pipeline built for a 10-ticker pilot only; the QA gates are correct-but-inert until a real fundamentals strategy calls `hd_fundamentals()` |
| [#585](https://github.com/JohnGavin/historical/issues/585) G1/G4 | Blocked on #587 Phase 2+ (`reference_narrative` field) and #463 (fat-tailed sim) respectively |
| [#490](https://github.com/JohnGavin/historical/issues/490) Gap 5 | pointblank pilot — low priority, never dispatched |
| [#813](https://github.com/JohnGavin/historical/issues/813) | avoid_worst leaderboard metrics wired to SPY buy-and-hold, not the real strategy |
| [#804](https://github.com/JohnGavin/historical/issues/804) | `pkgctx-freshness` CI flake — hit and merged past 4 times, never actually fixed |
| [#830](https://github.com/JohnGavin/historical/issues/830), [#831](https://github.com/JohnGavin/historical/issues/831) | Crypto microstructure + NautilusTrader — evaluation issues, not started |

**roborev:** 58 verdict failures / 35 addressed → 23 net unaddressed at
session end. 0 crashes, 0 quota, consistency check clean — expected backlog
volume given ~30 PRs merged in one session, not a health problem.
