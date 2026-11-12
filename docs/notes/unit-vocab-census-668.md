> Point-in-time note, written 2026-11-01; figures may be stale — re-verify against current targets.

# Unit and vocabulary census (issue #668, Phase 1)

Read-only groundwork for [#668](https://github.com/JohnGavin/historical/issues/668).
No code is changed by this document. It lists every place found that
normalises, labels or converts a metric's unit or vocabulary, so that the
migration steps (Phase 2 and 3, section 4) can be sized and ordered.

- Snapshot: commit `9bc72928c395d4f7689f3a45516dc0c639c54eaa` (origin/main at
  the time of writing). Line numbers below are for that commit and will drift.
- Method: static reading only. No `tar_make()`, no store, no `tar_read()` was
  run. Every row cites a line that was read. Where a verdict depends on a
  built target, it says INDETERMINATE and names the command the owner would
  run (section 3).
- Prior state (verified): the glossary, registry and property-based all-NA gate
  landed in PR #806, and the all-NA gate over the metrics-registry targets in
  PR #898 (`gh pr list --search 668 --state all`). `git log --all --grep 668`
  and a file search found no earlier census document.
- Homes, not copies: this document does not re-type the period vocabulary or
  the unit vocabulary. Their homes are `data/glossary.yaml` (`period_label`
  entity, lines 24-44) and `hd_metric_units()`
  (`packages/historicaldata/R/registry_metrics.R:37`).

Verdict key: MIGRATE (should move onto a central mechanism), ALREADY-CENTRAL
(is, or already derives from, a single home), LEAVE (reason given),
INDETERMINATE (reason given).

## 1. Sites that normalise, label or convert

### 1a. Central mechanisms and their mirrors

| # | file:line | Function / target | Input vocabulary | Output vocabulary | Via `resolve_entity()`? | Verdict |
|---|---|---|---|---|---|---|
| 1 | `R/glossary.R:132` | `resolve_entity()` | observed value, entity name, alias map | canonical value (alias replaced, NA and unknown pass through) | is the mechanism | ALREADY-CENTRAL. Zero production callers: the only references outside comments are `tests/testthat/test-glossary.R` (grep `resolve_entity` over `R/`, `packages/`, `scripts/`, `data/`, `docs/_targets.R`) |
| 2 | `R/glossary.R:73`, `R/plan_partitions.R:135` | `load_glossary()` feeding `PERIOD_LABELS_ALLOWED` | `data/glossary.yaml` | period-label set | n/a (consumer of the glossary) | ALREADY-CENTRAL |
| 3 | `R/glossary.R:98`, `data/entity_resolution.yaml:18-20` | `load_entity_resolution()` | alias YAML | alias to canonical tibble per entity | feeds #1 | ALREADY-CENTRAL. Registers one alias only (the full-sample spelling) |
| 4 | `packages/historicaldata/R/registry_metrics.R:37` | `hd_metric_units()` | none | the unit vocabulary | no | ALREADY-CENTRAL (the real home; the glossary mirrors it) |
| 5 | `packages/historicaldata/R/registry_metrics.R:41` | `.hd_validate_metric_units()` | metric name, unit | abort on NA or unknown unit | no | ALREADY-CENTRAL |
| 6 | `packages/historicaldata/R/registry_metrics.R:195` (called at `:267-268`) | `.hd_canonicalise_unit()` in `hd_leaderboard_from_registry()` | stored value and unit tag | percent divided by 100 and re-tagged; all other units pass through | no. It converts scale, which `resolve_entity()` (alias map only) cannot | ALREADY-CENTRAL for the registry read path |
| 7 | `data/glossary.yaml:46-71` | `metric_unit` entity | unit set | same set, documentation mirror | no | ALREADY-CENTRAL. Kept in sync with #4 by `tests/testthat/test-glossary.R:134-139` |
| 8 | `packages/historicaldata/R/hd_return_basis.R:16`, `:74` | `.HD_RETURN_BASIS_VOCAB`, `hd_return_basis()` | strategy label | total / excess / blend / indeterminate | no | ALREADY-CENTRAL (own home with file:line evidence per row). Not registered in the glossary; a glossary copy would be a second home, so leave it |
| 9 | `R/plan_leaderboard.R:96`, `:252` | `.strategy_obs_ann_factor_source`, `STRATEGY_OBS_ANN_FACTOR` | `hd_strategy_names_tbl()` | per-strategy observations-per-year | no | ALREADY-CENTRAL (derived from `strategy_names`; abort on a missing citation, `:224-250`) |
| 10 | `packages/historicaldata/R/registry_metrics.R:453` | `.normalise_metric_long()` | long or wide metrics tibble plus `units` | `metric_name`, `metric_value`, `metric_unit`, validated | no | ALREADY-CENTRAL |
| 11 | `packages/historicaldata/R/registry_metrics.R:228` | `hd_leaderboard_from_registry()` | `bt.metric` rows | canonical value and unit, with `value_stored` / `unit_stored` kept | no | ALREADY-CENTRAL |

### 1b. Leaderboard boundary helpers (inside the `leaderboard` target, `R/plan_leaderboard.R`)

Two separate operations happen in these closures: a period-label rename and a
percent-to-fraction scale conversion. They are listed as separate rows
because only the first is something `resolve_entity()` can express.

| # | file:line | Function | Input vocabulary | Output vocabulary | Via `resolve_entity()`? | Verdict |
|---|---|---|---|---|---|---|
| 12 | `R/plan_leaderboard.R:609` | `.norm_mf()` period rename | source period label | canonical full-sample label (`ifelse(period == "Full", ...)`) | no | MIGRATE. This is the alias already registered at `data/entity_resolution.yaml:18-20` |
| 13 | `R/plan_leaderboard.R:632` | `.norm_value()` period rename | source period label | canonical full-sample label | no | MIGRATE (same alias as #12) |
| 14 | `R/plan_leaderboard.R:434-439` | `.norm_ltr()` | cagr, vol, max_dd, ann_rf in percent | fraction | no | LEAVE for Phase 2. `resolve_entity()` maps labels, not scales; replacing a scale divide needs the unit-declaration design in section 4 (P3-2) |
| 15 | `R/plan_leaderboard.R:444-450` | `.norm_olmar()` | percent; `days` column | fraction; `months` column | no | LEAVE (as #14). Also renames an observation-count column, see section 2 concept D |
| 16 | `R/plan_leaderboard.R:458-469` | `.norm_tom()` | `cagr_tom` etc. in percent; `n_days` | fraction; `months` | no | LEAVE (as #14) |
| 17 | `R/plan_leaderboard.R:530-538` | `.norm_rsc()` | percent; `n_obs` | fraction; `months` | no | LEAVE (as #14) |
| 18 | `R/plan_leaderboard.R:546-559` | `.norm_mom_sibling()` | percent; `n_months`; no period column | fraction; synthesised full-sample label (literal at `:551`) | no | LEAVE (as #14). The literal label is a typed copy of the glossary's `canonical_full_sample_value` (`data/glossary.yaml:41`); fold into P2-1 |
| 19 | `R/plan_leaderboard.R:578-584` | `.norm_aw()` | percent; `n_days` | fraction; `months` | no | LEAVE (as #14) |
| 20 | `R/plan_leaderboard.R:610-611` | `.norm_mf()` scale | percent | fraction | no | LEAVE (as #14) |
| 21 | `R/plan_leaderboard.R:633-634` | `.norm_value()` scale | percent | fraction | no | LEAVE (as #14) |
| 22 | `R/plan_leaderboard.R:483-497` | `.norm_cmr()` | already fraction (comment `:478-482`); `n_days`; no period column | passes through; `months`; synthesised full-sample label (literal at `:488`) | no | LEAVE. Label literal handled with #18 in P2-1 |
| 23 | `R/plan_leaderboard.R:510-513` | `.norm_cmr_conditioned()` | wraps `.norm_cmr()` | same as #22 | no | LEAVE |
| 24 | `R/plan_leaderboard.R:639-648` | five direct `add_meta()` calls (Factor MAX, Factor DRIF, Stock MAX, Stock DRIF, XGB DRIF) | already fraction (agrees with `fm_units` / `drif_units` / `stk_units` / `xgb_units` in 1c) | passes through | no | LEAVE |
| 25 | `R/plan_leaderboard.R:700-709` | PSO Optimal `port_row` transmute | fraction (`pso_units` in 1c) | passes through | no | LEAVE |
| 26 | `R/plan_leaderboard.R:735` | `filter(period != "Validation")` | period | period | no | LEAVE (uses a vocabulary word as a filter; the sealing rule, not a normaliser) |
| 27 | `R/plan_leaderboard.R:749-769` | `calc_cost_metrics()` | monthly return vector; hard-coded `12 / n` at `:761` | `net_cagr`, `cum_pnl`, `cvar_95` as fractions | no | INDETERMINATE. The 12 assumes monthly input (comment `:750`); which strategies feed it, and whether any daily series does, is in the `cost_rows` and extension blocks after `:781`, which were not read |

### 1c. Registry-writer unit maps (one hand-typed column to unit map per metrics target)

Found with `grep -rnE "units *<- *c\(" R/ packages/historicaldata/R/`, which
returned 15 maps under `R/` plus `stability_units` in the package (16 rows
below). Only maps assigned to a variable matching that pattern are covered;
registry writers that name their map differently would be missed (section 5).
The "cagr unit" column is what the map declares for the cagr-like column.

| # | file:line | Map | cagr-like unit | Covered by `test-registry-unit-map-coverage.R`? | Verdict |
|---|---|---|---|---|---|
| 28 | `R/plan_factormax.R:523` | `fm_units` | fraction | yes | LEAVE |
| 29 | `R/plan_drif.R:656` | `drif_units` | fraction | yes | LEAVE |
| 30 | `R/plan_stock_backtest.R:1686` | `stk_units` | fraction | yes | LEAVE |
| 31 | `R/plan_xgb_signal.R:344` | `xgb_units` | fraction | yes | LEAVE |
| 32 | `R/plan_portfolio_opt.R:581` | `pso_units` (`opt_cagr`) | fraction | yes | LEAVE |
| 33 | `R/plan_commodities_mean_reversion.R:1624` | `cmr_units` | fraction | yes | LEAVE |
| 34 | `R/plan_ltr_momentum.R:557` | `ltr_units` | percent | yes | LEAVE |
| 35 | `R/plan_avoid_worst.R:1482` | `aw_units` | percent | yes | LEAVE |
| 36 | `R/plan_turn_of_month.R:450` | `tom_units` (`cagr_tom`) | percent | yes | LEAVE |
| 37 | `R/plan_risk_state.R:943` | `rsc_units` | percent | yes | LEAVE |
| 38 | `R/plan_mom_prepeak.R:610` | `mom_prepeak_units` | percent | yes (hand-declared case plus a percent assertion) | LEAVE |
| 39 | `R/plan_olmar.R:662` | `olmar_units` | percent | no | LEAVE (but outside the coverage test, see section 5) |
| 40 | `R/plan_ev_ebit.R:389` | `ev_units` | percent | no | LEAVE (as #39) |
| 41 | `R/plan_managed_futures.R:581` | `mf_units` | percent | no | LEAVE (as #39) |
| 42 | `R/plan_mom_prepeak_gauntlet.R:663` | `gauntlet_units` | no cagr; ratios, fractions, `days` | no | LEAVE (as #39) |
| 43 | `packages/historicaldata/R/registry_metrics.R:361` | `stability_units` | no cagr; ratio, count, fraction | not applicable (package) | LEAVE |

Why LEAVE: each map is the registry-side unit declaration for its target, and
the registry already validates and canonicalises from it (#4, #5, #6). They
are not wrong. The census issue is that for the percent-unit targets the same
fact (this column is percent) is stated a second time in the matching
`.norm_*` closure (rows 14-21). The pairing is Phase 3 material.

The coverage test checks that every numeric column has an entry in the map.
It does not check that the unit value is right (the one exception is the
percent assertion for `mom_prepeak_units`, `test-registry-unit-map-coverage.R:428-441`).

### 1d. QA gates that embed a unit or vocabulary assumption

| # | file:line | Gate | Assumption | Via `resolve_entity()`? | Verdict |
|---|---|---|---|---|---|
| 44 | `R/plan_qa_gates.R:400` (target at `:5012`) | S9 `check_leaderboard_metric_ranges()` | hand-typed plausible-fraction bounds for cagr, vol, max_dd (`:410-414`); catches a missed divide by 100 by magnitude | no | LEAVE until a declaration-driven gate exists (section 4, P3-1, P3-3) |
| 45 | `R/plan_qa_gates.R:481` (target at `:5026`) | S10 `check_leaderboard_period_vocab()` | assertion 1: every strategy has a full-sample row (`:492-513`); assertion 2: periods are in `PERIOD_LABELS_ALLOWED` (`:516-536`) | no (set comes from the glossary via #2) | LEAVE. Assertion 2 is the vocabulary check; assertion 1 is a coverage check and must survive any retirement |
| 46 | `R/plan_qa_gates.R:722` | S11 `check_metric_window_bounds()` `exempt_periods` | hand-typed list including both the alias spelling and the canonical spelling of the full-sample label | no | MIGRATE. A typed copy of vocabulary that has a home (P2-2) |
| 47 | `R/plan_qa_gates.R:1505` (target at `:5209`) | S17 `check_leaderboard_sharpe_coherence()` | `sharpe == (cagr - ann_rf) / vol` within `tol`, which assumes `ann_rf` is in the same unit as `cagr` | no | LEAVE (it is the check that `ann_rf` was converted in lockstep) |
| 48 | `R/plan_qa_gates.R:2504`, `:2713` | S26 and S36 all-NA gates | see section 3 | no | INDETERMINATE (the gates exist and are property-based; whether they pass without exemptions on a real build needs the section 3 commands) |

### 1e. Display, prose and separate glossaries

| # | file:line | What | Verdict |
|---|---|---|---|
| 49 | `docs/leaderboard.qmd:465-478`, `:507`, `:801-802`, `:992-996`, `:1552-1555`, and others | display-time `x 100` and `"%"` formatting of fraction columns. `grep -c "\* *100\|/ *100" docs/leaderboard.qmd` returned 27 matching lines, which includes non-metric uses (borrow-rate labels at `:1099-1104`, Kelly at `:1574-1577`) | LEAVE. The module comment at `R/plan_leaderboard.R:31-32` states display formatting belongs to the consumer |
| 50 | `R/leaderboard_caption.R:148-150` | prose defining Top5% Share as a fraction | LEAVE (prose; its unit statement agrees with `top_share = "fraction"` at `registry_metrics.R:367`) |
| 51 | `data/column_glossary.yaml` (header lines 1-17), `R/column_popover.R:24` | separate reader-facing column glossary; its header says it is kept separate from `data/glossary.yaml` on purpose and that reconciliation under #788 is deferred | LEAVE (owner decision on #788, not part of #668) |

### 1f. Sharpe, return basis and other vocabularies

| # | file:line | What | Verdict |
|---|---|---|---|
| 52 | `R/utils_metrics.R:137` | `sharpe_ratio_rf()`: (geometric `ann_ret` minus arithmetic `ann_rf`) over `ann_vol` | ALREADY-CENTRAL for the leaderboard Sharpe (per its own roxygen, `:95-106`) |
| 53 | `R/utils_metrics.R:44` | `annualise_returns()`: `sharpe = cagr / vol`, no risk-free deduction (`:76`) | INDETERMINATE. Its roxygen names `plan_managed_futures.R` and `plan_ev_ebit.R` as the "no-rf family" (`utils_metrics.R:100-105`), but `.norm_mf()` / `.norm_value()` require and convert `ann_rf` and S17 requires non-NA `ann_rf`. Whether that text is stale was not established from the lines read |
| 54 | `R/plan_leaderboard.R:146-158`, `:177-187` | `.prob_sharpe_input_sharpe()`, `.prob_sharpe_input_n()` choose geometric vs arithmetic Sharpe per row | LEAVE (explicit, tested selection, #919/#937) |
| 55 | `R/plan_fip_screen.R:222-224`, `:247` | `fip_comparison` uses `"Full"`, `"Training"`, `"OOS"`; its caption filters on `"Full"`. `fip_comparison` is an S11 registry target (`R/plan_qa_gates.R:669`) | INDETERMINATE. Whether any published surface expects the canonical spelling for this target was not read |
| 56 | `R/plan_european_overlay.R:182-183`, `R/plan_rafi.R:239`, `R/plan_jst_trend.R:142-224`, `R/plan_causal_graph.R:383` | other research tables labelled with the alias spelling (matched lines only; surrounding code not read) | INDETERMINATE (same question as #55) |
| 57 | `R/plan_ev_ebit.R:384`, `R/plan_managed_futures.R:576` (also `:251`, `:327`, `:411`) | registry writers and captions that filter the source target on the alias spelling | LEAVE. Coupled to why #12 and #13 must keep renaming at the leaderboard boundary: renaming at the source would break these filters |

Verdict counts are not typed here. Reproduce them with
`sed -n '/^## 1\./,/^## 2\./p' docs/notes/unit-vocab-census-668.md` and then
`grep -c "^| [0-9]* |.*| MIGRATE"` on that output (likewise ALREADY-CENTRAL,
LEAVE, INDETERMINATE; a verdict is the first word of a row's last cell). The PR body records the numbers obtained at commit time.

## 2. Vocabularies and units in use, by concept

A concept is flagged COMPETING when more than one representation is in use.

### A. Scale of cagr, vol, max_dd, ann_rf: COMPETING (fraction vs percent)

- Fraction at source: rows 28-33 (Factor MAX, Factor DRIF, Stock MAX/DRIF,
  XGB DRIF, PSO Optimal, CMR).
- Percent at source: rows 34-41 (LTR, Avoid Worst, TOM, Risk State, the three
  momentum siblings, OLMAR-1, Value (HML), Managed Futures).
- Two independent conversion mechanisms exist: the per-closure `/ 100` in rows
  14-21 (leaderboard path) and the unit tag read by `.hd_canonicalise_unit()`
  (registry path, row 6). For the eight percent sources the closure and the
  units map agree (both read). Neither is generated from the other.
- Display: fraction to `"x%"` in `docs/leaderboard.qmd` (row 49).

### B. Period label: COMPETING

- Canonical set: `data/glossary.yaml:34-40`; the full-sample spelling
  difference is registered at `data/entity_resolution.yaml:18-20`.
- Alias spelling still produced at source by Managed Futures and Value (HML)
  (renamed at rows 12-13), and used by `fip_comparison` and the research
  tables in rows 55-56.
- Out-of-sample label: the strategy-local OOS window and the canonical bounded
  Testing window are deliberately separate (`R/plan_partitions.R:50-68`), so
  that pair is two vocabulary entries, not a defect. Do not alias them.
- Typed copies of vocabulary outside the glossary: rows 18, 22 (literals) and
  46 (`exempt_periods`).

### C. Sharpe: COMPETING (by design, documented)

- Leaderboard `sharpe`: geometric return minus risk-free over volatility
  (row 52).
- No-rf `cagr / vol` helper (row 53), status unclear.
- Arithmetic excess Sharpe on the deflated-Sharpe path, selected per row in
  rows 54 (`.prob_sharpe_input_sharpe`).
- Separate statistic `hac_sharpe` carried beside `sharpe` (`ltr_units`,
  `rsc_units`).
- Return basis (total / excess / blend / indeterminate) decides whether the
  risk-free rate is deducted (row 8).
- Observation-per-year assumption: monthly strategies use 12, daily ones 252
  (row 9); `calc_cost_metrics()` hard-codes 12 (row 27).

### D. Observation-count column: COMPETING

The leaderboard column `months` holds a count of months for monthly
strategies and a count of days for daily ones. Source names seen: `days`
(row 15), `n_days` (rows 16, 19, 22), `n_obs` (row 17), `n_months` (row 18,
rows 12-13 source). The mislabel is documented as compensated by
`STRATEGY_OBS_ANN_FACTOR` (`R/plan_leaderboard.R:58-80`). The registry maps
tag all of them `count`.

### E. Drawdown duration: COMPETING

`cmr_units` tags `avg_dd_duration` / `max_dd_duration` as `count`, with a
comment explaining why not `days` (`R/plan_commodities_mean_reversion.R:1608-1617`).
`mom_prepeak_units` and `gauntlet_units` tag `avg_dd_days` / `max_dd_days` as
`days` (`R/plan_mom_prepeak.R:610-616`, `R/plan_mom_prepeak_gauntlet.R:663-671`).
Same concept (length of a drawdown), two unit tags. The CMR comment states the
reason (the tag measures periods of the series, which are days there), so this
is a declared convention clash, not an accident, but the registry cannot tell
the two apart downstream.

### F. Metric unit tag: single representation

The unit set has one home (row 4) with one validator (row 5), one mirror
(row 7) and a sync test. Not competing.

### G. Fraction-valued shares and probabilities: single representation

`top_share` is `fraction` (`registry_metrics.R:367`); the leaderboard shows it
as a percent only at display time (row 49). Not competing.

## 3. `LEADERBOARD_ALL_NA_EXEMPT` and its sibling

### Current entries

| Constant | file:line | Value | Entries |
|---|---|---|---|
| `LEADERBOARD_ALL_NA_EXEMPT` | `R/plan_qa_gates.R:2549` | `character(0)` | none |
| `METRICS_REGISTRY_ALL_NA_EXEMPT` | `R/plan_qa_gates.R:2662` | `list()` | none |

Both are empty by design (roxygen `:2540-2548` and `:2649-2661`).

### Is each exemption still justified?

There are no entries, so there is no exemption to justify or retire from
code alone. The open question is the opposite one: does the gate pass without
any exemption on a real build? That depends on built targets, so:

| Question | Verdict | Command the owner runs (from the repo root, main checkout) |
|---|---|---|
| Did `qa_leaderboard_no_all_na_metric` (S26, target at `:5399`) pass on the last build, i.e. is the empty list correct? | INDETERMINATE | `targets::tar_meta(names = c("qa_leaderboard_no_all_na_metric", "qa_metrics_registry_no_all_na"), fields = c("time", "error", "warnings"), store = "docs/_targets")`, then `targets::tar_read(qa_leaderboard_no_all_na_metric, store = "docs/_targets")` |
| Is any numeric leaderboard column close to all-NA (a candidate exemption)? | INDETERMINATE | `lb <- targets::tar_read(leaderboard, store = "docs/_targets"); vapply(Filter(is.numeric, lb), function(x) sum(!is.na(x)), integer(1))` and look for small or zero values |
| Did S36 actually check every target in its union, or skip some? | INDETERMINATE | See the structural note below; check which of the union exist with `targets::tar_exist_objects(<names>, store = "docs/_targets")` where the names are `names(S11_METRICS_REGISTRY)` (`R/plan_qa_gates.R:662`) plus `discover_subperiod_targets()` (`:2599`) |

### Structural observation (read, not run)

`check_metrics_registry_no_all_na()` skips a target that cannot be read from
the store, with only an informational message (`R/plan_qa_gates.R:2733-2745`).
Together with the empty-table early return in `check_no_all_na_numeric_columns()`
(`:2505-2507`), a build where several registry targets are missing or empty
can report S36 as passed having checked fewer targets than the success message
lists (`:5645-5649` prints the full union, not the checked subset). This is a
possible three-outcome gap (checked, failed, not checked collapse to "passed").
Whether it has happened is INDETERMINATE; the `tar_exist_objects` command
above answers it for the current store.

## 4. Proposed Phase 2 and Phase 3 (one PR each)

"Needs build.sh" follows the project rule in `.claude/CLAUDE.md`: a change to
a target body or to `packages/*/R/` needs `scripts/build.sh` in the main
checkout, not only `scripts/verify.sh`. Order is by risk and dependency.

### Phase 2 (small, evidence-bearing, no new design)

| Step | Change | Needs build.sh? | Evidence required before merge |
|---|---|---|---|
| P2-0 | No PR. Owner runs the three section 3 commands | n/a | Output pasted into #668, settling the INDETERMINATE rows |
| P2-1 | Rows 12, 13, 18, 22: replace the inline period rename in `.norm_mf()` / `.norm_value()` with `resolve_entity()`, and the synthesised full-sample literals with the glossary's canonical value. Ensure the resolution map is loaded where the target runs (the loaders walk up from the working directory, `R/glossary.R:42-62`) | Yes (edits the `leaderboard` target body) | `tar_read(leaderboard)` before and after is identical (`waldo::compare`); S10 and S11 still pass; a falsification run with the alias removed from `entity_resolution.yaml` makes S10 fail for the two strategies |
| P2-2 | Row 46: derive `exempt_periods` from the glossary instead of typing it | Yes (edits a QA gate used by a target) | Unit test for `check_metric_window_bounds()` unchanged and green; `qa_metric_window_bounds` target passes on a real build |

### Phase 3 (needs an owner decision on shape first)

| Step | Change | Needs build.sh? | Evidence required |
|---|---|---|---|
| P3-1 | Add a declaration of unit per published leaderboard column (a new glossary entity or a column in the registry units) and a gate that checks the built `leaderboard` against it. Name it with the next unused gate number: the highest in `R/plan_qa_gates.R` at this commit is S44, so S45 if still free (`grep -noE "\(S[0-9]+[,)]"`). The existing S16 is `check_borrow_status_registry()` (`R/plan_qa_gates.R:1281`), unrelated to units; the new gate must not reuse that number | Yes | The gate fails when a x100 error is injected into each of the eight percent sources one at a time (falsification), and passes on the real leaderboard |
| P3-2 | Pilot: generate one `.norm_*` scale conversion from its sibling registry units map, using Managed Futures and Value (HML) (rows 20-21, 40-41) because P2-1 already touches them. Then one PR per further pair of strategies | Yes. Moving a map into `packages/historicaldata/R/` would also need `tar_invalidate()` first because package source is not tracked as a target dependency (project memory, #753) | Leaderboard values identical before and after; `test-registry-unit-map-coverage.R` extended to cover rows 39-42 |
| P3-3 | Retire S10 assertion 2 (row 45) once a declaration-driven vocabulary check covers `period`. Keep assertion 1 (every strategy has a full-sample row) | Yes | The replacement gate demonstrably fails on a non-canonical label (falsification), and S10's own tests are moved, not deleted |
| P3-4 | Retire S9 (row 44) only after P3-1 has run on at least one full build and has been seen to fail on injected errors. S9's magnitude bounds are the only existing detector of a missed divide by 100, so it stays until then | Yes | Same falsification as P3-1, plus a note of any real case S9 caught that P3-1 would not |
| P3-5 | Decide concept D (`months` holds days) and concept E (drawdown duration tags): rename, declare, or document | Yes for any rename (registry rows already written with the old names need regenerating, `hd_leaderboard_from_registry` roxygen `:213-218`) | Owner decision recorded first |

Not proposed: reconciling `data/column_glossary.yaml` (row 51) or the
no-rf Sharpe helper (row 53); both need an owner decision outside #668.

## 5. What this census could not establish

- Nothing was run. No target was built or read, so every statement about
  built values is INDETERMINATE (section 3 lists the commands).
- Source units are taken from two agreeing statements per target (the
  `.norm_*` comment and the registry unit map), not from reading each source
  calculation function. For the eight percent sources the two agree. No gate
  I read checks a unit map's value against the source computation (only
  presence, plus one percent assertion for `mom_prepeak_units`).
- The units-map list is a grep on the name pattern `units <- c(`. Registry
  writers for `mr_metrics`, `rafi_metrics`, `aw_metrics`, `fip_comparison`,
  `eur_results`, `eur_comparison` and `eur_ciss_results` (all in
  `S11_METRICS_REGISTRY`, `R/plan_qa_gates.R:662-673`) produced no match, so
  either they have no registry writer, or their map uses another name. Not
  established which.
- Four of the 15 maps under `R/` (rows 39-42) are not in the coverage test's
  case list (`tests/testthat/test-registry-unit-map-coverage.R:306-390`);
  whether another test covers them was not searched beyond a grep for
  `units`.
- `calc_cost_metrics()` callers and the `cost_rows` extension block
  (`R/plan_leaderboard.R` after line 781) were not read, so row 27 stays
  INDETERMINATE.
- Consumers of the alias spelling in `fip_comparison` and the research tables
  (rows 55-56) were seen only as matched lines.
- The `qa_legacy_leaderboard_sentinel` target (`R/plan_artefact_registry.R`)
  that compares the legacy leaderboard with the registry-backed one was not
  read; a grep of that file for unit and period words found nothing relevant,
  which is not proof it applies no conversion.
- Files outside `R/`, `packages/historicaldata/R/`, `data/`, `docs/leaderboard.qmd`
  and the named tests were not searched (for example `scripts/`, other
  `docs/*.qmd`, `explorations/`). `scripts/compute_ltr_model.R` is cited by
  `hd_return_basis.R:96` but was not read.
- Line numbers are for commit `9bc7292`. They will drift; re-grep before use.
