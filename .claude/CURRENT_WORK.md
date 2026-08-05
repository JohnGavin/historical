# Current Work — session 23 end (2026-08-05, ENDED)

## State: all work merged + pushed

`main` at `4268094`, working tree clean. 11 PRs merged (#627, #628, #630,
#632, #633, #634, #636, #638, #639, #642, #644) plus three render commits.
`scripts/verify.sh` PASS on merged main; `tar_make()` completes; leaderboard
re-rendered and deployed.

## What this session was

Started as "how do we handle liquidity, leverage and concentration?" — an
audit. Became a data-integrity cascade: measuring leverage meant dividing
`vol` by gross exposure, which put two unit scales side by side and exposed
that the published leaderboard had been showing **1720% volatility**.

The through-line: the `.norm_*` helpers in `plan_leaderboard.R` rename columns
but normalise nothing. That produced the unit bug (#637), the period-vocabulary
bug (#643), and — via a `factor()` added while fixing the second — the
null-Period bug (#646). Same shape three times: **an unexpected value silently
coerced to a null-ish state instead of failing loudly.**

### Shipped
- Leverage measurement from zero: `hd_exposure_metrics()` + gross-convention
  registry + `Gross` column (#628). `hd_risk_contribution()` with the Euler
  identity as anchor and the ERC property asserted (#633).
- Unit scale normalised to fractions + S9 range gate (#639); period vocabulary
  + `PERIOD_LABELS_ALLOWED` + S10 gate (#644); leaderboard 15 → 17 strategies.
- Tri-state `not computed` labelling for `Credible`/`Redundant`/`Material` (#642).
- Kyle's lambda was byte-identical to Amihud; now a real price-impact slope (#627).
- Tail independence surfaced (#630); ADV-cap axis surfaced (#634); liquidity
  on `equity_daily` + non-US volume corruption-guard fix (#636).
- llm#903 acceptance test: footer KV metadata over `hf://` = **one 256 KB
  range request**, 0.19% of a 134.9 MB file. Slice 1 unblocked.

## Next task (highest value first)

1. **#645 — the validation seal is broken.** `Managed Futures` / `Value (HML)`
   compute `OOS` as `dates >= 2010-01-01` **unbounded**, spanning sealed
   Validation, automatically every run — and both now sit on the headline
   ranking, so it is more prominent than before. Bound at `test_end` (one
   line) as the stop-gap; re-cutting onto canonical partitions is the
   considered fix, but check DBC availability (live 2006) first.
2. **#641 — every March missing.** `stk_drif_portfolio` has no March rows;
   `port_returns` chains four `inner_join`s so one gap deletes the month for
   all four (128 rows vs ~156). Blocks the book-level anchor in #635.
3. **#646 — 2 null Period cells live on the page.** Build the factor levels
   from `PERIOD_LABELS_ALLOWED`; assert no `NA` survives the coercion.
4. **#635 — set the leverage level.** Per-strategy done (median vol/gross
   **8.92%**; at a 19% target implied gross ≈ 2.13× ≈ the 2.0× already run).
   Still needed: our own equity-universe vol (replaces the imported ~16%),
   a stress-period recompute, realised gross for the four `is_cap` rows, and
   #641 fixed before trusting any book-level figure.
5. **#640** — `bt.metric` records `metric_unit` but nothing validates it on
   write or converts on read; #639 fixed the dashboard path only, so
   leaderboard and registry now disagree.
6. Smaller: **#629** (OLMAR missing from `strategy_names`), **#631** (19 bare
   source URLs + the unbuilt `qa_no_bare_source_urls` gate).

## Decisions taken (do not relitigate)

- Leverage policy constrains **gross**, layered beneath a vol-normalised
  allocator. Net rejected (unreachable for a dollar-neutral book — scaling by
  any *k* leaves net 0); cash-borrowing rejected (never binds; neutral books
  borrow securities, not cash). #626.
- `OOS` is **not** remapped to `Testing` — different window, includes
  Validation. #645.
- Canonical metric unit is **fraction**; percent formatting belongs to the
  presentation layer. #639.

## Traps that cost time

- `audits/*.md` are point-in-time and never updated when the defects are
  fixed. The June cost audit was 2 months stale and produced false CRITICAL
  claims twice. Saved to project memory.
- Squash merges make `git merge-base --is-ancestor` report "unmerged"
  forever — worktree GC must use PR state, not ancestry (llm#902).
- DuckDB 1.5.1 removed `SET enable_http_logging`; use `CALL enable_logging('HTTP')`.
  And `count(*)` is answered from the parquet footer, so it is useless as a
  full-read control.
- `x[c(TRUE, NA, FALSE)]` inserts a literal `NA` — the source of the
  `WARNING: NA, NA, ...` caption.
- Only `leaderboard.qmd` was re-rendered; other dashboards remain stale.
