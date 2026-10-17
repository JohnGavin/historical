# Backfill 11 past strategy results into the research-log ledger (Refs #962).
#
# These are FINISHED tests whose outcome was known before they were logged.
# Per .claude/rules/research-log-honesty.md every row is therefore written
# UNSEALED (never hd_rlog_seal()), with preregistered = FALSE and a
# seal_omitted_reason saying so, and with a status from hd_rlog_statuses()
# (never "tested"). Priority is NA: a finished test has no queue position.
#
# Every outcome below was re-read from its cited source on 2026-10-17 (issue
# bodies/comments via `gh issue view`, files in the repo). `outcome_quote` is a
# short verbatim quote (< 15 words) from that source; numbers in `economic_claim`
# / `caveats` are the source's own. Where a source did not support the status a
# survey had proposed, the status here is the one the source supports (rows 2
# and 6) and `status_basis` says why.
#
# Idempotent: a row whose name already exists in the ledger is skipped. The
# research log is append-only, so a skipped row is never edited.
#
# Run (repo root):
#   nix develop . --command Rscript scripts/seed_past_strategy_results.R
#
# Optional first argument: a base_dir override (tests/dry runs); default is the
# tracked inst/extdata/research_log/.

pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

args <- commandArgs(trailingOnly = TRUE)
base_dir <- if (length(args) >= 1L) args[[1]] else NULL

SEAL_REASON <- paste0(
  "backfilled after the outcome was known; ",
  "sealing post-hoc commits to nothing"
)
GH <- "JohnGavin/historical"

res <- function(name, claim, asset_class, source, issue, status, outcome_source,
                outcome_quote, status_basis, caveats) {
  list(name = name, claim = claim, asset_class = asset_class, source = source,
       issue = issue, status = status, outcome_source = outcome_source,
       outcome_quote = outcome_quote, status_basis = status_basis,
       caveats = caveats)
}

rows <- list(
  res(
    "momentum_decomposition_equities_commodities",
    paste0("Decomposing 12-month momentum into persistent components ",
           "(style/industry vs beta/stock-specific, SSRN 5716502) improves ",
           "net Sharpe over total-return momentum in US equities and commodities"),
    "equity/commodity",
    paste0(GH, "#134 comment 2026-05-11; ",
           "knowledge/wiki/momentum-decomposition-cross-asset.md"),
    134L, "refuted",
    paste0(GH, "#134 (commodities: baseline net Sharpe -0.85, decomposed -0.89 ",
           "to -0.91); equities (529 stocks, 2000-2026, decomposed net Sharpe ",
           "-0.34 to -0.39 vs baseline +0.05) from knowledge/wiki/",
           "momentum-decomposition-cross-asset.md"),
    "All decomposed variants: Net Sharpe -0.89 to -0.91 (WORSE than baseline)",
    paste0("Source reports a completed negative test in two asset classes on ",
           "multi-decade samples and does not call either sample too small; ",
           "power not re-checked in source"),
    c(paste0("Equity figures appear only in the wiki page; issues #121 and ",
             "#123 as currently fetched hold no result text (plan only, no ",
             "comments). #134's body states the equity decomposition failed ",
             "(all Sharpe < 0)."),
      paste0("Commodity baseline momentum is itself negative (gross -0.75), ",
             "so that leg tests momentum, not only the decomposition."),
      paste0("The commodities universe (37 series) is the one #751 later ",
             "found to include non-investable IMF indexes and ETF/futures ",
             "twins; not re-examined for the momentum code."),
      "Crypto leg (#135) reported no quantitative result and is not covered.",
      paste0("The wiki marks the cross-asset generalisation as AI-inferred."))
  ),
  res(
    "commodity_mean_reversion",
    paste0("Cross-sectional 1m/3m/6m mean reversion (long recent losers, ",
           "short recent winners) earns a positive Sharpe in commodities"),
    "commodity",
    paste0(GH, "#138 comment 2026-05-29; ", GH, "#751 comments 2026-08-24 to ",
           "2026-08-26; ", GH, "#717, #738"),
    751L, "inconclusive-underpowered",
    paste0(GH, "#751 comment 2026-08-26 (after fixes: Sharpe 0.142, deflated ",
           "Sharpe -0.019, detection needs 307 years vs about 26 available)"),
    "CMR cannot be distinguished from zero",
    paste0("Re-statused from the proposed 'refuted': the original negative ",
           "result (#138, Sharpe -0.883/-0.666/-0.524) was measured on a ",
           "construction #717, #738 and #751 later showed to be defective, ",
           "and the sign flipped to +0.140 after the calendar-lookback fix. ",
           "The latest source reports the strategy as not detectable from ",
           "zero, which is the underpowered state; not re-measured since #808"),
    c(paste0("Original #138 test (2026-05-29): Sharpe -0.883 (1m), -0.666 ",
             "(3m), -0.524 (6m). Its magnitudes AND sign are affected by the ",
             "defects below, so it is not a clean refutation."),
      paste0("#717: daily data annualised as monthly (ann_factor 12); after ",
             "the fix Full-period Sharpe went -0.544 to -0.747."),
      paste0("#738: series monthly before 2000, daily after, declared daily ",
             "throughout."),
      paste0("#751: pre-2000 positions were non-investable IMF indexes, the ",
             "same commodity ranked against itself, and '3m' lookbacks were ",
             "3 days for 96% of the data. After #752/#755/#758/#762 the ",
             "reported state is Sharpe 0.142, deflated Sharpe -0.019."),
      paste0("307 years is not reachable with more data of the same kind; ",
             "the status records the source's own power statement.")
    )
  ),
  res(
    "commodity_12m_momentum",
    "12-month cross-sectional momentum earns a positive net Sharpe in commodities",
    "commodity",
    paste0(GH, "#134 comment 2026-05-11"),
    134L, "refuted",
    paste0(GH, "#134 (baseline net Sharpe -0.85, gross -0.75; 37 series, ",
           "1992-2026, monthly); same -0.853 shown in ", GH, "#138 comment"),
    "Baseline momentum itself doesn't work in commodities",
    paste0("Source reports a completed negative test (even gross Sharpe is ",
           "negative) on a 1992-2026 sample it does not call too small; ",
           "power not re-checked in source"),
    c(paste0("Same 37-series universe that #751 later found to contain ",
             "non-investable IMF indexes and ETF/futures twins; the momentum ",
             "code was not re-examined after #751, and the sibling mean-",
             "reversion result changed sign once its universe was fixed."),
      paste0("The wiki page gives only medium (70-80%) confidence that ",
             "baseline momentum is weak cross-asset."))
  ),
  res(
    "mean_reversion_skew_cvar_filters",
    paste0("Buying large single-day drops (relative to own volatility), ",
           "filtered by skewness, semivariance ratio and CVaR 5%, earns a ",
           "positive return on ETFs/large caps"),
    "equity",
    paste0(GH, "#50 comment 2026-04-28"),
    50L, "refuted",
    paste0(GH, "#50 comment (CAGR -5.9%, Sharpe -0.22, MaxDD -78%)"),
    "Mean reversion on ETFs/large caps fails",
    paste0("Source reports a completed negative backtest and does not call ",
           "the sample too small; sample length, cost model and power are not ",
           "stated in the source, so power not re-checked"),
    c(paste0("The source says momentum dominates reversion 'at daily ",
             "frequency with these parameters', so the finding is ",
             "parameter-specific."),
      paste0("Three filters were applied together with no complement control ",
             "or per-filter ablation; the result cannot say which filter, if ",
             "any, did anything."))
  ),
  res(
    "european_vix_risk_overlay",
    paste0("The US VIX-regime risk overlay (RSC), applied as a proxy to ",
           "European equity ETFs, improves risk-adjusted return versus ",
           "buy-and-hold"),
    "equity",
    paste0(GH, "#58 comment 2026-04-30"),
    58L, "refuted",
    paste0(GH, "#58 comment (OOS 2020 onward; overlay Sharpe below buy-and-",
           "hold for all five ETFs, e.g. FEZ 0.56 to 0.44)"),
    "Verdict: Negative result — same conclusion as US SPY overlay.",
    paste0("Source reports a completed negative OOS test and does not call ",
           "the window too small; the window is 2020 onward and power was ",
           "not re-checked in source"),
    c(paste0("Approach B only (US VIX regime as proxy); approach A (VSTOXX ",
             "term structure) was not tested because the data is unavailable."),
      paste0("Out-of-sample window is 2020 onward (about six years)."),
      paste0("FF5+Mom alpha: FEZ -4.70% (t -1.70), VGK -5.14% (t -2.06), ",
             "EWG -4.14% (t -1.47), EWQ -4.19% (t -1.59), EXSA.DE +4.04% ",
             "(t +1.38, R2 15%)."))
  ),
  res(
    "avoid_worst_days_rsc_overlay",
    paste0("VIX-triggered protection (Avoid Worst Days) and the RSC regime ",
           "overlay add alpha beyond market beta"),
    "equity",
    paste0(GH, "#57 comment 2026-04-28; ", GH, "#46 comment 2026-04-22; ",
           GH, "#813 comment 2026-09-29"),
    57L, "inconclusive-underpowered",
    paste0(GH, "#813 comment 2026-09-29 (corrected leaderboard row Sharpe ",
           "0.25, CAGR 5.3%, max DD -51.6%, vol 11.9%, 'underpowered (needs ",
           "99 years)'); ", GH, "#57 body table (Avoid Worst FF alpha t -0.80, ",
           "R2 41%; RSC t -1.60, R2 88%)"),
    "underpowered (needs 99 years)",
    paste0("Re-statused from the proposed 'refuted': the only source with a ",
           "power statement for the corrected strategy says underpowered. ",
           "#57 reports null alpha t-statistics without a power check and #46 ",
           "gives no statistics"),
    c(paste0("#813: the leaderboard row was wired to SPY buy-and-hold; its ",
             "body says the falsification framework used the strategy series ",
             "(aw_practical_backtest$ret_strategy), so #57's t-statistics are ",
             "not affected by the wiring bug. The corrected leaderboard row ",
             "was published after the fix (#921, #924)."),
      paste0("#46: walk-forward mean OOS CAGR 15.6% vs 18.4% hindsight; its ",
             "comment calls this moot because 't+1 execution shows strategy ",
             "fails regardless of threshold' (no statistics given)."),
      "#45 records no outcome.",
      paste0("One row covers two mechanisms the sources treat separately; ",
             "the RSC part is described as 'pure market beta' in #57."))
  ),
  res(
    "stock_drif_after_costs",
    paste0("Stock-level DRIF decile long/short earns a positive net Sharpe ",
           "after realistic costs (0.5%/trade, 3%/yr borrow)"),
    "equity",
    paste0(GH, "#424 comment 2026-06-05; ", GH, "#425; ", GH, "#449"),
    424L, "refuted",
    paste0(GH, "#424 comment 2026-06-05 (129 months; Full net Sharpe -1.13, ",
           "CAGR -17.9%, max DD -91.8%; Training -1.96, Testing -0.04, ",
           "Validation -0.01)"),
    "Net Sharpe is negative at every partition.",
    paste0("Source reports a completed negative test over 129 months and ",
           "calls the finding conclusive for the current universe; it does ",
           "not call the sample too small; power not re-checked in source"),
    c(paste0("Universe is the survivorship-biased top-100 (#150, #278); the ",
             "source defers a broader-universe re-test to #278."),
      paste0("An earlier #424 body table (Validation net Sharpe +0.67) came ",
             "from a prototype and is superseded by the production target."),
      paste0("#425 fixed zero cost deduction in factor-level DRIF only; it ",
             "did not change stock-level DRIF."),
      paste0("#449: the XGBoost variant is also negative (Full Sharpe ",
             "-1.494); separate model, corroborating only."))
  ),
  res(
    "news_sentiment_macro_signal",
    paste0("Newspaper keyword frequency or body-text sentiment (NYT, ",
           "Guardian) predicts next-month S&P 500 returns"),
    "equity index",
    paste0(GH, "#89 comments 2026-05-07; ", GH, "#82 comment 2026-05-04; ",
           "knowledge/wiki/priced-in-signals.md"),
    89L, "refuted",
    paste0(GH, "#89 (Guardian keywords: 6 terms, 76 months 2020-01 to ",
           "2026-04, next-month Spearman r from -0.090 to +0.144; sentimentr: ",
           "3 terms, 60 months, next-month |r| <= 0.077)"),
    "No predictive signal found",
    paste0("Source reports completed negative tests and does not call the ",
           "samples too small; with 60-76 months power was not re-checked in ",
           "source"),
    c(paste0("Same-month sentiment correlation is moderate (r +0.277 ",
             "inflation, +0.272 stock market): contemporaneous only."),
      paste0("NYT leg (#82) was entity-level annual data, not keywords; #82 ",
             "records no result, and the near-zero NYT figure appears only ",
             "second-hand in #89 and the wiki."),
      "About nine correlations, no multiple-testing adjustment reported.",
      "sentimentr scored 50 articles per month on the first 2000 characters.",
      "FinBERT was judged unnecessary, not tested.")
  ),
  res(
    "spx_rsi2_filter_vs_vix_rsi2",
    paste0("SPX RSI(2) <= 20 is a better oversold filter than VIX RSI(2) <= ",
           "20 for next-day SPX return and VIX change (aligrithm claim A)"),
    "equity index/volatility",
    "explorations/vix_spx_leadlag/SUMMARY.md (issue #611)",
    611L, "supported",
    paste0("explorations/vix_spx_leadlag/SUMMARY.md and results/run_output.txt ",
           "(8,351 days 1993-02-01 to 2026-04-10; SPX RSI(2)<=20 n=2324 next-",
           "day SPX +0.1086% win 55.6%; VIX RSI(2)<=20 n=2978 +0.0408% win ",
           "54.4%; unconditional +0.0465% win 54.0%)"),
    "the practical claim replicates, the causal claim does not",
    paste0("Source says claim A replicates (ordering matches the article). ",
           "No test statistic or power calculation is reported for it; power ",
           "not re-checked in source"),
    c("Entirely in-sample, no train/test split (stated in the source).",
      paste0("Gap is smaller than the article's: 1.2pp vs 2.15pp win rate; ",
             "different sample (1993-2026 vs 2007-2023) and simple-MA RSI."),
      paste0("The article's headline short-VX-futures backtest cannot be ",
             "replicated: only VIX spot is held."))
  ),
  res(
    "spx_leads_vix_causal_claim",
    paste0("SPX leads VIX, so VIX should not be used to time SPX (aligrithm ",
           "claim B)"),
    "equity index/volatility",
    "explorations/vix_spx_leadlag/SUMMARY.md (issue #611)",
    611L, "refuted",
    paste0("explorations/vix_spx_leadlag/SUMMARY.md and results/run_output.txt ",
           "(8,351 days; SPX_t to VIX_t+1 beta -0.289, t -0.11, p 0.911; ",
           "VIX_t to SPX_t+1 t +3.15, p 0.00162)"),
    "SPX has no incremental power over tomorrow's VIX change.",
    paste0("'No power' in the source means no incremental predictive ",
           "coefficient, not a low-power test: the source reports a null ",
           "SPX-to-VIX result on 8,351 days with the reverse direction ",
           "detected, labels the claim 'not supported; mildly reversed', and ",
           "does not call the sample too small. No formal power calculation ",
           "appears in the source"),
    c("In-sample, no train/test split.",
      paste0("At the daily close VIX is computed from SPX options quoted at ",
             "the same instant, so contemporaneity is structural; intraday ",
             "causality is untestable here."),
      "Regressors are 79% correlated (VIF about 2.7), so coefficients are not precisely identified.",
      paste0("A Levy-area measure does show SPX leading VIX in a path-",
             "geometry sense; the source judges that probably not tradeable ",
             "and this row does not refute it."))
  ),
  res(
    "momentum_12_2_vs_osap_underpowered",
    paste0("Our own 12-2 cross-sectional momentum long/short built from ",
           "equity_daily has a Sharpe distinguishable from zero"),
    "equity",
    "explorations/osap_survivorship_gap/SUMMARY.md (issues #816, #862, PR #900)",
    816L, "inconclusive-underpowered",
    paste0("explorations/osap_survivorship_gap/results/summary_metrics.csv ",
           "(overlap window n=618 months: Sharpe +0.187, needs 176.0 years; ",
           "full sample n=634: Sharpe +0.205, needs 147.8 years; about 52 ",
           "years available)"),
    "not detectably different from a zero Sharpe at any sample length",
    paste0("Source labels the series UNDERPOWERED, needing 147.8 to 176.0 ",
           "years against roughly 52 available; distinct from the #857 ",
           "momentum-by-MAX hypotheses (different claim and predictor)"),
    c(paste0("Survivorship-biased universe (known_delistings 0); the source ",
             "says it is INDETERMINATE how much of the gap to OSAP Mom12m is ",
             "survivorship vs universe vs construction."),
      paste0("OSAP Mom12m over the same window is adequately powered (Sharpe ",
             "+0.418); correlation with our series +0.578 after correcting an ",
             "earn-month misalignment."),
      "Not the same claim as the existing #857 rows (momentum x MAX filter).")
  )
)

stopifnot(length(rows) == 11L, !anyDuplicated(vapply(rows, `[[`, "", "name")))

existing <- suppressMessages(hd_strategy_ledger(base_dir = base_dir))
existing_names <- existing$name

written <- character()
skipped <- character()
for (r in rows) {
  if (r$name %in% existing_names) {
    skipped <- c(skipped, r$name)
    next
  }
  hd_strategy_idea_append(
    name                = r$name,
    economic_claim      = r$claim,
    source              = r$source,
    priority            = NA_character_,
    asset_class         = r$asset_class,
    issue               = r$issue,
    status              = r$status,
    seal_omitted_reason = SEAL_REASON,
    extra               = list(
      outcome_source = r$outcome_source,
      outcome_quote  = r$outcome_quote,
      status_basis   = r$status_basis,
      caveats        = I(r$caveats),
      backfill_issue = 962L
    ),
    base_dir            = base_dir
  )
  written <- c(written, r$name)
}

cat(sprintf("seed_past_strategy_results: written=%d skipped=%d\n",
            length(written), length(skipped)))
if (length(written) > 0L) cat("  written:", paste(written, collapse = ", "), "\n")
if (length(skipped) > 0L) cat("  skipped (already in ledger):", paste(skipped, collapse = ", "), "\n")
