# OLMAR Phase 4 — Bite-Sized Follow-Up Tasks

Each task ≤ 1 hour. These can be dispatched separately as worktree-isolated
agents once the user picks a primary data path in
[`olmar-phase4-scoping.md`](olmar-phase4-scoping.md).

Tasks are grouped by phase. **Do not start phase 2 tasks until phase 1
gates are green.**

---

## Phase 0 — Decisions and confirmations (user does these, not an agent)

- [ ] **0a. Pick primary path.** Read `olmar-phase4-scoping.md` § B and
      decide: CRSP / Norgate / Wayback+EODHD. Record decision in
      [`#278`](https://github.com/JohnGavin/historical/issues/278) comment.
- [ ] **0b. Confirm pricing.** For the chosen paid path, get a quote from
      the provider directly (web pricing pages were either 404 or
      sign-in-walled during scoping).
- [ ] **0c. Confirm WRDS access.** If picking CRSP: confirm current
      institutional affiliation and active WRDS login.
- [ ] **0d. Approve budget.** If picking a paid path: confirm budget for
      ~$20–50/mo and add to project cost tracker.

---

## Phase 1 — Data source verification (small, agent-dispatchable)

### Free / Wayback path

- [ ] **1a. Wayback-fetch S&P 600 historical lists** (30 min)
      Fetch Wikipedia "List of S&P 600 companies" revisions at
      2005-01-01, 2010-01-01, 2015-01-01, 2020-01-01, 2025-01-01
      via Wayback Machine. Save raw HTML under
      `data/raw/sp600_wayback/<date>.html`. Report ticker count per
      snapshot.
- [ ] **1b. Parse Wayback snapshots → long-format CSV** (45 min)
      Parse the 5 snapshots from 1a into one CSV with columns
      `(snapshot_date, ticker, company)`. Save to
      `data/raw/sp600_wayback/membership_snapshots.csv`.
- [ ] **1c. Verify EODHD has delisted tickers** (30 min)
      Pick 5 known small-cap delistings from 2008–2012 (e.g. CIT,
      DELL pre-buyout, Smithfield Foods, Solyndra equivalents) and
      query the EODHD free tier to confirm prices are available.
      Document the API call pattern.

### Paid Norgate path

- [ ] **1d. Verify Norgate Python API quickstart** (30 min)
      With a trial / paid subscription, query the Norgate Python API
      for S&P 600 membership on 2010-01-15 and 2020-01-15. Confirm
      ticker counts ~ 600 each. Document the API call pattern.
- [ ] **1e. Verify Norgate delisting fields** (30 min)
      Query Norgate for LEH, BSC, and a known S&P 600 delisting (e.g.
      Pier 1 Imports, JC Penney, Hertz pre-bankruptcy). Confirm
      `delisting_date`, `delisting_reason`, `delisting_price` fields
      are populated.

### Paid Sharadar path

- [ ] **1f. Verify Sharadar TICKERS dataset has S&P 600 history** (30 min)
      Via Nasdaq Data Link API or `nasdaqdatalink` Python pkg, query
      `SHARADAR/TICKERS` and inspect the `category` / `scalemarketcap`
      / `siccode` columns to verify a PIT S&P 600 reconstruction is
      possible. Document the join logic.

---

## Phase 2 — Data ingest (agent-dispatchable, isolation: worktree)

- [ ] **2a. Add `load_sp600_pit()` function to `scripts/fetch_equity.py`**
      (1 h)
      Mirror the pattern of `load_sp500_tickers()` but with a
      `as_of_date` parameter. Returns a long-format dataframe with
      `(ticker, date, in_universe_pit, index_name)`. Source depends
      on Phase 0 decision.
- [ ] **2b. Add `hd_sp600_pit(as_of_date)` to
      `packages/historicaldata/R/groups.R`** (1 h)
      R-side helper that reads the parquet emitted by 2a. NOT a
      `hd_ticker_groups()` row — this is a function of date. Add
      roxygen docs + unit test against a known snapshot date.
- [ ] **2c. Write `equity_universe_pit` parquet to HF dataset** (1 h)
      Mirror the existing `equity_daily` HF upload pattern. Document
      schema in `data/README.md`. Add to `hd_datasets()` registry.
- [ ] **2d. Add `survivorship_biased = FALSE` flag scaffold to
      `stk_drif_metrics` and `stk_max_metrics`** (15 min, 1-line
      change but GATED — only land once 2a-2c are green)
      Currently these targets hardcode `mutate(survivorship_biased = TRUE)`.
      Make this a parameter that defaults to TRUE on `stk_universe` and
      FALSE on `stk_universe_pit`. The PIT-using metrics target must
      pass FALSE.

---

## Phase 3 — Wiring + first run (agent-dispatchable, gated on Phase 2)

- [ ] **3a. Replace stub with real implementation in `R/plan_universe_pit.R`**
      (1 h)
      Swap the `cli::cli_abort()` body for the actual
      `duckplyr::read_parquet_duckdb(hd_datasets()[["equity_universe_pit"]]$url)`
      logic. Add validation: ticker count per year is plausible (~600
      for S&P 600).
- [ ] **3b. Register `plan_universe_pit()` in `_targets.R`** (10 min)
      One-line change. Must NOT happen until 3a passes its own
      validation.
- [ ] **3c. Add `olmar_params_sp600_pit` target in `R/plan_olmar.R`**
      (45 min)
      Parameters object with `cost_bps = 20L` (NOT 10 — see scoping doc
      § D), `leverage = 0.2`, plus a `sp600_pit_ticker_selector`
      function that picks the in-universe set per date.
- [ ] **3d. Add `olmar_prices_sp600_pit` and `olmar_portfolio_sp600_pit`
      targets** (1 h)
      Same shape as the existing `olmar_prices` / `olmar_portfolio` but
      per-date ticker membership. Each ticker's price series is
      zero-padded before listing and after delisting.
- [ ] **3e. Add `olmar_metrics_sp600_pit` + caption + research-log
      lineage** (1 h)
      New `hyp_id`/`impl_id`/`res_id` chain. Add a `critiques` row
      with `defect_class = "survivorship"` explicitly stating that
      this run uses the PIT universe.
- [ ] **3f. Run the side-by-side 10-bps / 20-bps / 30-bps cost
      sensitivity** (30 min compute + 30 min review)
      Three variants of `olmar_metrics_sp600_pit` at different
      `cost_bps`. Report side-by-side.

---

## Phase 4 — Bias quantification + writeup (agent-dispatchable)

- [ ] **4a. Compute survivorship-bias delta** (1 h)
      Build `olmar_metrics_sp600_biased` (no PIT filter, just
      currently-listed small-caps from `stk_universe` slice) AND
      `olmar_metrics_sp600_pit`. The CAGR / Sharpe / MaxDD delta is
      the bias estimate. Append to [#150](https://github.com/JohnGavin/historical/issues/150).
- [ ] **4b. Draft vignette skeleton** (1 h)
      `vignettes/olmar-phase4-sp600.qmd` — does NOT run targets
      directly, reads them via `safe_tar_read()`. Must include the
      mandatory `## Methodology` block per
      `narrative-evidence-block` rule. Add `survivorship_biased=FALSE`
      banner per #150 Option B.
- [ ] **4c. Add to leaderboard** (45 min)
      Wire OLMAR P4 SP600-PIT metrics into the leaderboard target.
      One row per cost-sensitivity variant.

---

## Phase 5 — Close-out

- [ ] **5a. Document the data-source decision in CHANGELOG** (15 min)
      One-paragraph entry under Phase 4 OLMAR. Record cost, latency,
      and what bias-correction the PIT data adds.
- [ ] **5b. Close [#278](https://github.com/JohnGavin/historical/issues/278)
      with the final cost-corrected CAGR** (15 min)
      Include the side-by-side comparison of author's claim vs our
      result. Note whether the gap is mostly cost-realism or mostly
      survivorship.
- [ ] **5c. File any follow-up issues for production hardening** (30
      min) — only if the result motivates it.

---

## Notes for whoever picks this up

- Phase 0 is user-only — do NOT dispatch agents on those tasks.
- Phase 1 tasks are read-only / data-acquisition — safe to
  dispatch with `isolation: "worktree"` and a tight prompt.
- Phase 2+ must NOT start until the user has explicitly approved the
  data-source decision. Even if Phase 1 reports a clean verification.
- Cost discipline: each cell in the metrics output gets a cost-bps
  label. Do not bury the 10-bps "comparison only" row as if it were
  the headline.
- Per `priced-in-prohibition` rule: small-cap mean-reversion is partly
  microstructure-driven, NOT just behavioural. The 106% claim may
  embed liquidity premium that disappears at non-trivial AUM. The
  cost sensitivity in 3f is doing double duty as capacity analysis.
