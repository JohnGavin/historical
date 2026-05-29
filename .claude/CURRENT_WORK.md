# Current Work (Session 2026-05-28/29 #11 — robustness stack + Pillar 8 + bug sweep + roborev clear, ENDED)

**Last updated:** session end
**Previous sessions:** #10 (#288 CI gate, #160 deflated Sharpe, WFC digest, roborev clean-up), #9 (external-source digests), #8 (research-log DB, OLMAR-1), #7 (merge-queue drain)

## This session — 23 PRs merged

### Initial 10-PR triage wave (executed session-#10's 58-FAIL plan)
- **#302** wiki crypto outcome clarity (r4333)
- **#303** docs/stock-backtest NULL leak (r3828, r4296)
- **#304** pytest required-check stall (r4328/4331/4369/4476)
- **#305** ADD signal scaffold (closes #279 Angle B work) — `hd_compute_add` + 33 tests + plan
- **#306** WT-B strategy plans — 5 fixed (NA-safe is_spike, OLMAR test_end cap, join key `ym` not `date`, Sharpe-from-excess), 3 partials → follow-ups
- **#307** **(critical)** `apply_adv_cap` respects `w_max` (r2122 cap-violation bug)
- **#308** WT-A data layer — rlang `%||%` import, `hd_lazy` survivorship warn, non-HF guards
- **#309** WFC scaffold (#297 build piece) — `hd_wf_correlation()` + 25 tests + plan
- **#310** CPCV scaffold (#299 build piece) — purge + embargo + paths + PBO + 105 tests
- **#311** quiz-logic.js XSS hardening (r4366) — `safeUrl()` allowlist + DOM APIs

### P0 + design-driven follow-ups
- **#321 (#317)** `qa_summary` includes olmar_metrics + tom_metrics (silently failing test now passes)
- **#322 (#315)** `with_envvar` scope encloses `skip_if` in test-jst.R (other tests audited)
- **#323 (#314)** TOM wired into the full 8-test falsification gauntlet (mirrors LTR sibling pattern)
- **#324 (#316)** documented `adjusted_close` schema choice — surfaced a cross-dataset divergence (→ #325)
- **#327 (#313)** heap-based DFS in TRP with explicit comparator (deterministic tie-break)

### Robustness trio + Pillar 8 + hygiene
- **#326 (#319)** CPCV integration into plan_drif — `drif_path_sharpe` (15 paths, C(6,2)) + `drif_pbo`; factormax confirmed exempt
- **#328 (#318)** WFC extended to DRIF elastic-net + `wfc_all_summary` + leaderboard `wf_corr` + `wfc_verdict` columns
- **#330 (#269)** Pillar 8 risk architecture — `hd_dd_duration` + `hd_loss_clustering` + leaderboard columns
- **#331/#333** Pillar 8 capstone — surfaced `max_consecutive_losses` (was computed but hidden)
- **#332 (#325)** cross-dataset column normalisation — single canonical `adjusted_close` with read-time backward-compat alias

## Key technical events

### Three real latent bugs caught
- **r2122 ADV cap renorm** — `apply_adv_cap()` unconditionally divided by `w_total`, pushing weights above `w_max` when `sum(w_max) < 1`. Tests blessed the violation as "mathematical limit". Fix: conditional renorm + new regression test (4×0.20 = 80% invested + 20% cash).
- **r4366 quiz-logic.js XSS** — `innerHTML` string-concat with untrusted `r.real_url`. Fix: `safeUrl()` http/https allowlist + DOM APIs.
- **qa_summary gap** — `olmar_metrics` and `tom_metrics` missing since OLMAR (#276) and TOM (#289) shipped. test-qa-summary-deps.R was failing pre-#307 (surfaced during r2122 fix).

### Robustness layer now complete on the leaderboard
- **WFC** (Pearson + Spearman + 2×2 verdict) for Factor MAX + Factor DRIF
- **CPCV / PBO** for DRIF (15 paths)
- **Deflated Sharpe** via `K_eff_strat` (#296 prior session)
- **Pillar 8**: max DD + avg DD duration + max DD duration + loss clustering (runs test + lag-1 ACF) + max consecutive losses

### Roborev
58 FAIL reviews closed in bulk (17 session-#10 stale-closes done early; 41 cascade-on-merged-PR closures done at end). 1 residual: r4371 (DRIF Cakici rank-before-filter — deferred per user, tracked in #312).

### CI
Main is green. Transient failure on #330 post-merge (alphavantage_daily snapshot mismatch) was incidentally fixed by #332's `adjusted` → `adjusted_close` rename in `registry.R`.

## Follow-ups filed (12)

- **#312** DRIF Cakici rank-before-filter — **deferred per user** ("investigate first")
- **#313** TRP DFS sort — closed via #327
- **#314** TOM falsification wiring — closed via #323
- **#315** skip-guard timing — closed via #322
- **#316** adjusted_close design — closed via #324
- **#317** qa_summary gap — closed via #321
- **#318** WFC extension — closed via #328
- **#319** CPCV integration — closed via #326
- **#320** ADD URL + backtest + leaderboard — **blocked on Chen-Zimmermann data acquisition**
- **#325** cross-dataset normalisation — closed via #332
- **#329** XGB factor-level WFC — **architecture decision needed**
- **#331** surface max_cons_losses — closed via #333

## Last PR of session

- **#334 (#138)** — Commodities mean-reversion strategy + falsification wiring. Counterpart to #134's failed momentum (Sharpe -0.85). 36 tests pass. Numbers (does MR actually work in commodities?) determined at next `tar_make` — that is the actual research question.

## Next session candidates

- **#271** TOM acceptance gates — wiring is in (#323); needs `tar_make` run to produce numbers (heavy)
- **#138 verification** — read `cmr_vs_mom_compare` output once `tar_make` has run; either celebrate or honest-negative result
- **#278** OLMAR S&P 600 — blocked on #150 Option A (PIT data, deferred — paid source)
- **#329** XGB factor-level WFC — needs architecture decision (3 options outlined in issue body)
- **#157** specification-curve multiverse on plan_drif
- **#267** BeyondPassive EUR/USD hedge overlay
- **#280** Long-run commodity index 1871–2025

## Open issue counts (post-session)

~50 open. Robustness-stack work complete. Remaining open is research backlog (P3/P4) + the 5 blocked/deferred items above. See the priority groups posted in the session transcript for the full triage view.
