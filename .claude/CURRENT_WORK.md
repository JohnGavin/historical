# Current Work — rf return-basis programme (2026-10-12)

Tracking issue [#937](https://github.com/JohnGavin/historical/issues/937).
Every step is approved turn-by-turn by an explicit user verb.

## State

Merged: [#949](https://github.com/JohnGavin/historical/pull/949) to
[#954](https://github.com/JohnGavin/historical/pull/954),
[#955](https://github.com/JohnGavin/historical/pull/955) (re-render),
[#956](https://github.com/JohnGavin/historical/pull/956) (top5pct revert),
[#957](https://github.com/JohnGavin/historical/pull/957) (re-render),
[#958](https://github.com/JohnGavin/historical/pull/958) (funnel V units, #933).
Closed: PR #932, issues #943, #929.

## Next, in order

1. Funnel counts: `scripts/build.sh` from the MAIN checkout, read the DRIF and
   Avoid Worst rows of `qa_search_funnel`, re-render if pages change.
2. File an issue: `hd_deflated_sharpe()` divides its hurdle by `sqrt(T)` while
   treating V as dispersion (mismatch with the #958 convention).
3. #937 phase 3: static test for unrouted `sharpe_ratio_rf(` calls; registry
   vocabulary for benchmarks; INDETERMINATE sites `plan_mean_reversion.R:214`,
   `plan_shadow_trades.R:75-79`, `capacity.R:286`,
   `strategy_value_gate.R:54-66`; hoist duplicated rf wiring.
4. `macro-defense-rotation` stale re-render (uncommitted in the main checkout,
   diff is mostly embedded asset data, unrelated to #937).

## Gotchas

- Store lives only in the main checkout; one build at a time (`pgrep` first).
- `verify.sh` can exceed 600 s: run in the background, wait for the notice.
- No CI on root `R/`, `tests/`, `docs/`; `verify.sh` is the only gate.
- Step 2c reports VACUOUS-PASS (0 targets); coverage rests on
  `tar_option_set(imports = "historicaldata")`.
- Main checkout: leave `.claude/CURRENT_WORK.md` and untracked files alone.
