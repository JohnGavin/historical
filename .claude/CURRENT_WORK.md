# Current Work — session 24 end (2026-08-08, ENDED)

## State: all work merged + pushed

`main` at `92b726f` (last code commit `bb02089`; the seven commits after it are
automated `data:` refreshes). Working tree clean. **9 PRs merged** — #647, #649,
#650, #651, #652, #658, #659, #661, #662, #666, #670.

Final `tar_make()`: **59 built, 703 skipped, 2m 35s, 0 errors**, all seven QA
gates (S9–S15) passing on real data.

## What this session was

Continued session 23's through-line — *an unexpected value silently coerced to a
null-ish state instead of failing loudly* — and found that it had a sibling:
**a guard whose scope is drawn around the known instances rather than the
property being guarded.**

Both failed the same way, twice each:

- The `backtest-partitions` rule's `paths:` glob matched only files that
  *compute* partitions, so the rule never loaded for the file that *published*
  them (#660). Fixed in PR #661.
- Gate S11's scope is a hardcoded pair (`mf_metrics`, `ev_metrics`), so it could
  not see the third and fourth targets with the identical defect (#667). Open.

That is the argument behind #668: replace per-instance gates with one
registry-driven gate.

### Shipped

- **Validation seal, four leaks** — unbounded `OOS` (#645/PR #649, gate S11);
  automatic `Validation` slice for 7 strategies (#648/PR #659, gate S14);
  published in vignette prose with a conclusion drawn from it (#660/PR #662,
  gate S15). The fourth (#655, committed digest parquet) is open.
- **Partition re-cut to four tiers** (#660/PR #666): Training ≤2019-12-31,
  Testing →2023-12-31, **Holdout** 2024-01-01→2026-04-30 (observed, never
  sealed), Validation 2026-05-01→ (untouched). Holdout surfaced on the
  leaderboard via all 7 source-metrics targets.
- **#641 March gap** — a 21-day lookback built from one calendar month; February
  never supplies 21 days, so `c20`/`c21` were `NA` and glmnet propagated `NA`
  across the row (PR #652). Plus the `inner_join` chain that spread one gap to
  all four constituents (PR #651, gates S12/S13).
- **#640 registry units** (PR #650), **#654 verify.sh now asserts skips**
  (PR #658), **#669 `adjusted_close` schema break across 12 files** (PR #670).
- **#635 decided:** σ_target 11.5%, gross backstop 3.5×, book vol 6.57%.
- **Two rules:** `fail-loud-not-null` (PR #647); `backtest-partitions` extended
  to storage/display/reasoning + `paths:` widened (PR #661/#666).

### Numbers

`stk_drif_portfolio` 129 → 195 rows (March 0 → 17) · `port_returns` 128 → 195 ·
PSO Optimal max_dd −0.099 → **−0.212** · registry NULL units ~256 → **0** ·
root tests 326 → 397 · QA gates **2 → 7**.

## Next session — start here

1. **#667 (highest value, smallest change).** Bound the two unbounded `Testing`
   windows — `R/plan_risk_state.R:301-304` and `R/plan_avoid_worst.R:459` — at
   `test_end` from `bt_partitions`, **and widen S11 beyond its hardcoded pair**.
   The regression test is cheap and already described on the issue: perturb
   `test_end`, assert every `Testing` window moves.
2. **#655** — find why `tar_make()` does not refresh the tracked digest
   snapshot. A tracked artefact a full run silently skips is worse than a stale
   one. It also carries Validation rows into git history.
3. **#665 / #664** — financing modelled on neither side consistently; three
   strategies' returns overstated by an unmodelled borrow cost.
4. **#668** — the glossary/entity-resolution registry, once the partition work
   has settled (user's sequencing decision).
5. **Re-derive σ = 11.5%** after #667 and #665 land — both change its inputs.

Also open: #656 (two live `inner_join` hazards), #657 (~20 unaudited join
sites), #663 (turnover / cost-drag bridge).

## Carried lessons

- **"Pipeline green" ≠ "pipeline works."** #669's targets were unbuildable for
  ~10 weeks while every run reported success, because caching hid them. A
  periodic full-rebuild check is not built.
- **A `tryCatch` that substitutes its own diagnosis is worse than no handler.**
  `olmar_prices` reported "check network access" for what was a schema error —
  and I repeated that misdiagnosis in #669 before it was traced.
- **Dispatch agents to run `scripts/verify.sh` in the foreground**
  (`timeout=600000`). Backgrounding it made three agents stall and report
  "waiting for the build" as a result. Recorded in memory.
- **Re-verify the remote after any agent completion report** — one agent
  believed it was done while nothing had been pushed.
