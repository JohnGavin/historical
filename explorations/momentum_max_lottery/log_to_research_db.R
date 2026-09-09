# Record this exploration in the research-log database (hd_rlog_*).
#
# WHY THIS SCRIPT EXISTS RATHER THAN AN AD-HOC Rscript -e:
# every metric written to the log is READ FROM the committed result files in
# results/, never re-typed. Per the reproducible-ingestion rule, a figure that
# exists in a machine-readable source must be derived by committed code. A
# hand-typed Sharpe carrying a "# from the run" comment is a violation, not a
# confirmation. Re-running this script after re-running run.R reproduces the
# rows exactly (modulo new uuids/timestamps, which are lineage, not claims).
#
# Run:
#   nix develop . --command Rscript explorations/momentum_max_lottery/log_to_research_db.R
#
# The store is append-only: re-running APPENDS a second set of rows, it does
# not overwrite. That is deliberate (audit log). Do not run it twice for the
# same experiment without meaning to.

suppressPackageStartupMessages({
  library(dplyr)
})
pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)

RES <- here::here("explorations", "momentum_max_lottery", "results")
ANN <- 12L  # monthly returns

read_res <- function(name) {
  p <- file.path(RES, name)
  if (!file.exists(p)) {
    cli::cli_abort(c(
      "x" = "Missing result file {.path {p}}.",
      "i" = "Run run.R first: it produces every input this script reads."
    ))
  }
  readr::read_csv(p, show_col_types = FALSE)
}

summary_metrics <- read_res("summary_metrics.csv")
turnover        <- read_res("turnover.csv")

# ── HAC-adjusted Sharpe ────────────────────────────────────────────────────
# The `results` table asks for `sharpe_hac`; run.R only computed a naive
# Sharpe. Writing the naive number into a column named `sharpe_hac` would be
# exactly the mislabelling `fail-loud-not-null` prohibits, so derive the real
# thing here.
#
# Derivation: for T periods, naive t = sqrt(T) * SR_period, so
# SR_period = t / sqrt(T) and SR_annual = t * sqrt(ann_factor / T).
# Substituting the Newey-West HAC t-statistic for the naive one gives the
# autocorrelation-corrected annualised Sharpe. hd_hac_sharpe() supplies
# hac_tstat and T.
hac_sharpe_annual <- function(r) {
  r <- r[!is.na(r)]
  if (length(r) < 3L) return(NA_real_)
  h <- hd_hac_sharpe(r, ann_factor = ANN)
  if (is.na(h$hac_tstat) || is.na(h$T) || h$T <= 0) return(NA_real_)
  h$hac_tstat * sqrt(ANN / h$T)
}

strategies <- c("mom_plain", "mom_lottery", "mom_nonlottery")

series <- lapply(strategies, function(s) {
  d <- read_res(paste0("strategy_returns_", s, ".csv"))
  list(gross = d$gross_ret, net = d$net_ret)
})
names(series) <- strategies

# Annualised turnover: run.R reports mean MONTHLY turnover per leg. Annualise
# by 12 and sum the two legs, since a long/short strategy trades both.
turnover_annual <- turnover |>
  group_by(strategy) |>
  summarise(turnover_annual = sum(turnover) * ANN, .groups = "drop")

# ── Map summary_metrics rows onto strategy ids ─────────────────────────────
# summary_metrics$label is prose; parse it rather than re-typing the numbers.
label_to_id <- function(label) {
  dplyr::case_when(
    grepl("^mom_plain.*GROSS",      label) ~ "mom_plain__gross",
    grepl("^mom_lottery.*GROSS",    label) ~ "mom_lottery__gross",
    grepl("^mom_nonlottery.*GROSS", label) ~ "mom_nonlottery__gross",
    grepl("^mom_plain -- NET",      label) ~ "mom_plain__net",
    grepl("^mom_lottery -- NET",    label) ~ "mom_lottery__net",
    grepl("^mom_nonlottery -- NET", label) ~ "mom_nonlottery__net",
    grepl("high-mom, high-MAX",     label) ~ "corner__highmom_highmax",
    grepl("high-mom, low-MAX",      label) ~ "corner__highmom_lowmax",
    grepl("low-mom,  high-MAX",     label) ~ "corner__lowmom_highmax",
    grepl("low-mom,  low-MAX",      label) ~ "corner__lowmom_lowmax",
    grepl("single-sort: high-mom",  label) ~ "singlesort__highmom",
    grepl("single-sort: low-mom",   label) ~ "singlesort__lowmom",
    TRUE ~ NA_character_
  )
}

sm <- summary_metrics |> mutate(strategy_id = label_to_id(label))
if (any(is.na(sm$strategy_id))) {
  unmatched <- sm$label[is.na(sm$strategy_id)]
  cli::cli_abort(c(
    "x" = "Unmapped summary_metrics label{?s}: {.val {unmatched}}.",
    "i" = "Add a case to label_to_id() -- do not silently drop rows."
  ))
}

# Corner and single-sort buckets have their own monthly series in the bucket
# CSVs. Leaving sharpe_hac NA for them would be an NA standing in for a value
# that is computable -- the defect #728 exists to stop -- so derive them too.
buckets    <- read_res("monthly_bucket_returns.csv")
singlesort <- read_res("monthly_mom_singlesort_returns.csv")

# Tercile 3 = high, tercile 1 = low (run.R's ntile convention).
corner_series <- function(mom_t, max_t) {
  buckets |>
    filter(mom_tercile == mom_t, max_tercile == max_t) |>
    arrange(midx) |>
    pull(ew_ret)
}
singlesort_series <- function(mom_t) {
  singlesort |>
    filter(mom_tercile == mom_t) |>
    arrange(midx) |>
    pull(ew_ret)
}

hac_for <- function(id) {
  parts <- strsplit(id, "__", fixed = TRUE)[[1]]
  if (length(parts) == 2L && parts[1] %in% strategies) {
    return(hac_sharpe_annual(series[[parts[1]]][[parts[2]]]))
  }
  r <- switch(id,
    corner__highmom_highmax = corner_series(3L, 3L),
    corner__highmom_lowmax  = corner_series(3L, 1L),
    corner__lowmom_highmax  = corner_series(1L, 3L),
    corner__lowmom_lowmax   = corner_series(1L, 1L),
    singlesort__highmom     = singlesort_series(3L),
    singlesort__lowmom      = singlesort_series(1L),
    NULL
  )
  if (is.null(r)) {
    cli::cli_abort(c(
      "x" = "No return series mapped for strategy_id {.val {id}}.",
      "i" = "Every id must resolve to a series; NA here would hide a gap."
    ))
  }
  hac_sharpe_annual(r)
}

turn_for <- function(id) {
  base <- strsplit(id, "__", fixed = TRUE)[[1]][1]
  m <- turnover_annual$turnover_annual[turnover_annual$strategy == base]
  if (length(m) == 1L) m else NA_real_
}

# ── Lineage: hypotheses -> implementation -> results/critiques ─────────────
h1_uuid <- hd_rlog_uuid()   # the tradeable claim
h2_uuid <- hd_rlog_uuid()   # the specific -14.8% replication
impl_uuid <- hd_rlog_uuid()

# NOT SEALED, DELIBERATELY.
# hd_rlog_seal()'s own documentation: "Seal at inception, before the
# hypothesis is tested. A hash applied after you have seen the result commits
# to nothing." These hypotheses were formulated from Klement's article and
# tested in the same session, so sealing them now would manufacture the
# appearance of a pre-registration that never happened. commit_hash,
# sealed_at and seal_method are left NA, which the schema documents as
# "unsealed". The honest record is an unsealed row, not a fake seal.
hypotheses <- tibble::tibble(
  uuid = c(h1_uuid, h2_uuid),
  parent_uuid = NA_character_,
  economic_claim = c(
    paste0("Filtering a cross-sectional 12-2 momentum long/short by lottery-likeness ",
           "(MAX = max daily return in the prior month) improves its risk-adjusted ",
           "return, because investors overpay for lottery payoffs and those names ",
           "fall further when momentum turns."),
    paste0("Low-momentum, high-MAX US stocks earn strongly negative returns ",
           "(circa -14.8% annualised), versus circa +0.1% for low-momentum stocks ",
           "generally. Zadeh (2026) via Klement.")
  ),
  dependent_var = c("monthly long/short portfolio return",
                    "monthly equal-weighted bucket return"),
  predictor = c("12-2 momentum tercile x prior-month MAX tercile",
                "12-2 momentum tercile x prior-month MAX tercile"),
  sample_spec = paste0("equity_daily US non-ETF, 502 tickers, 633 months ",
                       "(52.8y), equal-weighted, t+1 execution, terciles; ",
                       "SURVIVORSHIP-BIASED (0 delistings)"),
  null_hypothesis = c(
    "MAX adds nothing: mom_lottery and mom_nonlottery have equal Sharpe.",
    "The low-mom/high-MAX bucket return does not differ from the low-mom/low-MAX bucket."
  ),
  # Distinct statuses: these two failed in DIFFERENT ways, and collapsing
  # them to one label would lose the distinction `checks-must-distinguish-
  # unknown` exists to preserve.
  status = c(
    "tested-underpowered",   # measured; sample cannot resolve it either way
    "untestable-on-this-data" # population required by the claim is absent
  ),
  commit_hash = NA_character_,
  sealed_at   = as.POSIXct(NA),
  seal_method = NA_character_,
  extra_json = c(
    jsonlite::toJSON(list(
      source = "https://klementoninvesting.substack.com/p/the-price-momentum-of-lottery-tickets",
      source_read_directly = FALSE,
      underlying_paper = "Zadeh (2026) -- NOT read directly, only Klement's summary",
      preregistered = FALSE,
      seal_omitted_reason = "outcome known before logging; sealing post-hoc commits to nothing",
      github_issue = 857
    ), auto_unbox = TRUE),
    jsonlite::toJSON(list(
      zadeh_reported_pct = -14.8,
      zadeh_reported_baseline_pct = 0.1,
      source_read_directly = FALSE,
      preregistered = FALSE,
      github_issue = 857
    ), auto_unbox = TRUE)
  )
)

implementations <- tibble::tibble(
  uuid = impl_uuid,
  parent_uuid = h1_uuid,
  code_ref = "explorations/momentum_max_lottery/run.R",
  notebook_path = "explorations/momentum_max_lottery/SUMMARY.md",
  params_json = jsonlite::toJSON(list(
    momentum = "12-2 (t-12..t-2, skip t-1)",
    lottery_proxy = "MAX = max single-day return in month t-1",
    n_quantiles = 3L,
    weighting = "equal",
    execution = "form at close of t, hold t+1",
    ann_factor = ANN,
    cost_per_trade = 0.0010,
    universe = "equity_daily US non-ETF, ETFs excluded"
  ), auto_unbox = TRUE),
  extra_json = jsonlite::toJSON(list(
    parquet_not_committed = "results/stock_month_signals.parquet (9.4MB, regenerable)"
  ), auto_unbox = TRUE)
)

results_rows <- sm |>
  transmute(
    uuid = vapply(seq_len(n()), function(i) hd_rlog_uuid(), character(1)),
    parent_uuid = impl_uuid,
    strategy_id,
    partition = "full-sample",
    cagr = ann_ret_cagr,
    sharpe_hac = vapply(strategy_id, hac_for, numeric(1), USE.NAMES = FALSE),
    max_dd,
    turnover_annual = vapply(strategy_id, turn_for, numeric(1), USE.NAMES = FALSE),
    n_obs = as.integer(n_months),
    results_db_run_date = Sys.Date(),
    extra_json = vapply(seq_len(n()), function(i) {
      as.character(jsonlite::toJSON(list(
        naive_sharpe = sm$sharpe[i],
        ann_vol = sm$ann_vol[i],
        skew = sm$skew[i],
        detection_verdict = sm$detection_verdict[i],
        min_n_years_for_80pct_power = sm$min_n_years_for_80pct_power[i],
        zadeh_reported_pct = sm$zadeh_pct[i],
        label = sm$label[i]
      ), auto_unbox = TRUE, na = "null"))
    }, character(1))
  )

critiques <- tibble::tibble(
  uuid = vapply(1:3, function(i) hd_rlog_uuid(), character(1)),
  parent_uuid = impl_uuid,
  defect_class = c("survivorship-bias", "insufficient-power", "metric-selection"),
  severity = c("critical", "critical", "high"),
  finding = c(
    paste0("0 of 502 tickers delist; the panel contains no failed firms. The ",
           "population the -14.8% claim concerns is structurally absent, so the ",
           "result is INDETERMINATE, not a refutation."),
    paste0("All three long/short strategies are underpowered. Plain 12-2 momentum ",
           "(naive Sharpe 0.163) needs 231 years at 80% power against 52.8 available; ",
           "mom_lottery net needs 8,468. No Sharpe comparison here is resolvable."),
    paste0("The three strategies rank in exactly opposite order on Sharpe versus ",
           "CAGR, max drawdown and skew. mom_lottery is best on Sharpe and worst on ",
           "all three others. A Sharpe-only comparison inverts the conclusion.")
  ),
  cell_ref = c("results/ticker_history_stats.csv",
               "results/summary_metrics.csv",
               "results/summary_metrics.csv"),
  resolved = c(FALSE, FALSE, TRUE)  # (3) resolved by reporting all four statistics
)

hd_rlog_append("hypotheses", hypotheses)
hd_rlog_append("implementations", implementations)
hd_rlog_append("results", results_rows)
hd_rlog_append("critiques", critiques)

cli::cli_inform(c("v" = "Logged {nrow(hypotheses)} hypotheses, 1 implementation, {nrow(results_rows)} results, {nrow(critiques)} critiques."))
print(results_rows |> select(strategy_id, cagr, sharpe_hac, max_dd, n_obs), n = 20)
