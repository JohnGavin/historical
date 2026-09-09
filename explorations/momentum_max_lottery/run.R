# Momentum x Lottery-Skewness (MAX) Double Sort
#
# Tests: Reihaneh Haghighi Zadeh (2026), as summarised by Joachim Klement,
#   "The price momentum of lottery tickets"
#   https://klementoninvesting.substack.com/p/the-price-momentum-of-lottery-tickets
#   (accessed 2026-09-09).
#
# PROVENANCE LIMIT: only Klement's summary of the paper was read here -- the
# underlying Zadeh (2026) paper was NOT read directly. Every "vs Zadeh" number
# below is a comparison against a third party's SUMMARY of the paper, not the
# paper itself. Treat any mismatch or match with that caveat in mind.
#
# Zadeh's reported US-equity results (1962-2023, annualised, per Klement):
#   Traditional momentum winners (high 12-2)   : 16.5%
#   Traditional momentum losers  (low  12-2)   :  0.1%
#   Lottery-like winners (high 12-2, high MAX) : 15.0%
#   Lottery-like losers  (low  12-2, high MAX) : -14.8%
# The claimed structure: the LONG leg is roughly unchanged by the lottery
# filter (15.0 vs 16.5); the SHORT leg is transformed (-14.8 vs 0.1). The
# entire claimed enhancement is supposed to live in the short leg.
#
# ---------------------------------------------------------------------------
# SIGNAL DEFINITIONS (exact, as specified in the exploration brief; a
# deliberate, documented interpretation of the brief's literal wording where
# it was ambiguous -- see the "month t is unused" note below)
# ---------------------------------------------------------------------------
# midx = year(date)*12 + month(date): a strictly increasing integer month
# index, one per calendar month, shared across all tickers.
#
# For a candidate FORMATION month t:
#   momentum_t = cumulative return over months [t-12, t-2] inclusive (11
#                monthly returns) -- i.e. explicitly SKIPPING month t-1 (the
#                standard short-term-reversal skip).
#   MAX_t      = the maximum single daily return within month t-1.
#   holding return for a "t-portfolio"  = the realised monthly return of
#                month t+1.
#
# LOOK-AHEAD GUARD (enforced below, see the `sig <-` block in section 2):
# momentum's most recent input is month t-2; MAX's only input is month t-1.
# Neither signal ever reads a return dated t or later. `hold_ret` (month
# t+1's return, i.e. the thing being predicted) is computed via
# `dplyr::lead(monthly_ret, 1)` in the SAME mutate() call as the signals but
# is never fed back into `mom_12_2` or `max_lag1` -- those are built purely
# from `dplyr::lag()` on earlier positions. As a side effect of following
# the brief literally, month t's OWN return is not used by either signal
# either (the momentum window stops at t-2, and MAX is drawn from t-1, not
# t) -- this is MORE conservative than the minimum required to avoid
# look-ahead bias (there is an unused buffer month between the newest signal
# input and the formation date), but it removes any ambiguity about
# leakage: nothing later than t-1 is ever read to build a signal used to
# rank at t.
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all("packages/historicaldata", quiet = TRUE))
suppressMessages({
  library(dplyr)
  library(tidyr)
})

RESULTS_DIR <- "explorations/momentum_max_lottery/results"
dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

# ── Assumptions (documented per fail-loud-not-null / provisional-constants) ──
# MANUAL: no source -- matches ltr_params$cost_per_trade (R/plan_ltr_momentum.R),
# a round-number assumption, not a sourced trading-cost figure.
ROUND_TRIP_COST <- 0.0010
# MANUAL: no source -- matches ltr_params$borrow_rate_annual (R/plan_ltr_momentum.R),
# a round-number assumption, not a sourced borrow-rate series.
BORROW_RATE_ANNUAL <- 0.03
# Mirrors ltr_params$min_stocks_per_month (R/plan_ltr_momentum.R) -- the
# minimum cross-section needed for a stable 3-way tercile sort (roughly
# 10 names/bucket at the margin).
MIN_STOCKS_PER_MONTH <- 30L
# Mirrors ltr_universe's minimum trading-history prefilter (R/plan_ltr_momentum.R).
MIN_HISTORY_DAYS <- 252L

# ETF tickers to exclude from a stock-level double sort (scripts/fetch_equity.py
# DEFAULT_TICKERS, the ETF portion -- a double sort on stocks must not contain
# index/factor funds).
ETF_EXCLUDE <- c(
  "SPY", "QQQ", "IWM", "DIA", "VIXY", "TLT", "GLD", "DBC", "UUP", "IEF",
  "SHY", "TIP", "IAU", "PDBC", "BIL", "AGG", "EFA", "EEM", "VLUE",
  "MTUM", "QUAL", "USMV", "SIZE", "VTV", "VUG", "IWD", "IWF"
)

cat("========================================================\n")
cat("Momentum x MAX (lottery) double sort -- exploration run\n")
cat("========================================================\n\n")

# ── 1. Load & filter the equity panel ────────────────────────────────────────
cat("=== 1. Load equity panel ===\n")
ds <- hd_datasets()[["equity_daily"]]
cat("dataset url:", ds$url, "\n")
cat("registry note:", ds$description, "\n")
cat("survivorship_biased:", ds$survivorship_biased,
    " known_delistings:", ds$known_delistings, "\n\n")

lf <- duckplyr::read_parquet_duckdb(ds$url)
lf_cols <- names(lf)
cat("columns available on remote parquet:", paste(lf_cols, collapse = ", "), "\n")

raw <- lf |>
  filter(!grepl("\\.", ticker)) |>
  collect()

# Column-alias handling: some cached parquets expose `adjusted`, the
# canonical name is `adjusted_close`. Check which we actually got.
if (!("adjusted_close" %in% names(raw)) && ("adjusted" %in% names(raw))) {
  cat("price column found: 'adjusted' -- renaming to 'adjusted_close'\n")
  raw <- raw |> rename(adjusted_close = adjusted)
} else if ("adjusted_close" %in% names(raw)) {
  cat("price column found: 'adjusted_close'\n")
} else {
  cli::cli_abort(c(
    "x" = "Neither {.field adjusted_close} nor {.field adjusted} present in equity_daily.",
    "i" = "Columns seen: {.val {names(raw)}}"
  ))
}

raw <- raw |> mutate(date = as.Date(date))

n_before_etf <- n_distinct(raw$ticker)
raw <- raw |> filter(!(ticker %in% ETF_EXCLUDE))
n_after_etf <- n_distinct(raw$ticker)
cat(sprintf(
  "non-dotted tickers before ETF exclusion: %d, after excluding %d known ETFs: %d\n",
  n_before_etf, length(ETF_EXCLUDE), n_after_etf
))

hist_stats <- raw |>
  group_by(ticker) |>
  summarise(
    n_days = n(),
    first_date = min(date),
    last_date = max(date),
    .groups = "drop"
  )
keep_tickers <- hist_stats |> filter(n_days >= MIN_HISTORY_DAYS) |> pull(ticker)
raw <- raw |> filter(ticker %in% keep_tickers)
cat(sprintf(
  "tickers with >= %d trading days: %d (of %d)\n\n",
  MIN_HISTORY_DAYS, length(keep_tickers), n_after_etf
))

# ── Survivorship check (first-class finding, not a footnote) ────────────────
cat("=== Survivorship check ===\n")
panel_end <- max(raw$date)
cat(sprintf("panel end date: %s\n", format(panel_end)))
early_end <- hist_stats |>
  filter(ticker %in% keep_tickers, last_date < (panel_end - 365))
cat(sprintf(
  "tickers whose series ends >1 year before panel end (candidate delistings): %d\n",
  nrow(early_end)
))
if (nrow(early_end) > 0) {
  print(as.data.frame(early_end |> arrange(last_date)))
}
readr_ok <- requireNamespace("readr", quietly = TRUE)
if (readr_ok) {
  readr::write_csv(hist_stats, file.path(RESULTS_DIR, "ticker_history_stats.csv"))
} else {
  write.csv(hist_stats, file.path(RESULTS_DIR, "ticker_history_stats.csv"), row.names = FALSE)
}
cat("\n")

# ── Value-weighting check (per brief: skip and say so if not readily available) ──
cat("=== Value-weighting availability check ===\n")
md_schema <- hd_datasets()[["metadata"]]$schema
has_market_cap_field <- "market_cap" %in% md_schema
has_date_dim <- "date" %in% md_schema
cat(sprintf(
  "metadata dataset has market_cap field: %s; has a date/time dimension: %s\n",
  has_market_cap_field, has_date_dim
))
cat(paste0(
  "metadata's own registry entry states frequency = \"static\" -- a single ",
  "current snapshot per ticker, not a point-in-time series. Applying today's ",
  "market cap to weight portfolios formed in, say, 1975 would itself be a ",
  "look-ahead violation (and would misrepresent relative sizes at the time). ",
  "Per the brief (\"if it is not readily available, say so and skip it rather ",
  "than approximating\"), VALUE-WEIGHTING IS SKIPPED. Only equal-weighted ",
  "results are reported below.\n\n"
))

# ── 2. Daily returns -> monthly signals, with an explicit month-contiguity guard ──
cat("=== 2. Daily returns -> monthly panel ===\n")
raw <- raw |>
  arrange(ticker, date) |>
  group_by(ticker) |>
  mutate(
    daily_ret = adjusted_close / dplyr::lag(adjusted_close) - 1,
    midx = as.integer(format(date, "%Y")) * 12L + as.integer(format(date, "%m"))
  ) |>
  ungroup()

monthly <- raw |>
  filter(!is.na(daily_ret)) |>
  group_by(ticker, midx) |>
  summarise(
    monthly_ret = prod(1 + daily_ret) - 1,
    max_ret = max(daily_ret),
    n_days_month = dplyr::n(),
    .groups = "drop"
  )

# Drop each ticker's very first calendar month: its monthly_ret is computed
# from daily_ret with the FIRST trading day of that ticker's history removed
# (no lag() available for it), so it is not a genuine full-month compounded
# return -- reporting it would silently understate that month's true return.
first_midx <- monthly |> group_by(ticker) |> summarise(first_midx = min(midx), .groups = "drop")
n_before_firstmonth_drop <- nrow(monthly)
monthly <- monthly |>
  left_join(first_midx, by = "ticker") |>
  filter(midx > first_midx) |>
  select(-first_midx)
cat(sprintf(
  "dropped %d ticker-first-months (incomplete compounding, no prior close)\n",
  n_before_firstmonth_drop - nrow(monthly)
))

# Month-contiguity guard: build a COMPLETE calendar-month grid per ticker
# (first observed month .. last observed month), left-joining actual data.
# Any calendar month a ticker did NOT trade becomes an explicit NA row
# rather than being silently skipped -- this makes plain positional
# lag()/lead()/slide_dbl() safe to use afterwards (row position now equals
# calendar-month position for every ticker), and NA propagates through
# cumprod()/lag() rather than silently misaligning a window across a gap.
full_grid <- monthly |>
  group_by(ticker) |>
  summarise(min_midx = min(midx), max_midx = max(midx), .groups = "drop") |>
  rowwise() |>
  mutate(midx = list(seq.int(min_midx, max_midx))) |>
  ungroup() |>
  select(ticker, midx) |>
  unnest(midx)

monthly_full <- full_grid |>
  left_join(monthly, by = c("ticker", "midx")) |>
  arrange(ticker, midx)

n_gap_months <- sum(is.na(monthly_full$monthly_ret))
cat(sprintf(
  "calendar ticker-month slots reconstructed: %d; of which %d were genuine gaps (ticker did not trade that month -- NA, not silently filled)\n\n",
  nrow(monthly_full), n_gap_months
))

# ── 3. Build the two signals with the look-ahead guard ───────────────────────
cat("=== 3. Signal construction ===\n")
sig_all <- monthly_full |>
  group_by(ticker) |>
  arrange(midx, .by_group = TRUE) |>
  mutate(
    # value at row t = month (t-2)'s monthly return
    shifted2 = dplyr::lag(monthly_ret, 2L),
    # cumulative return over the 11 months ending at (t-2), i.e. months [t-12, t-2]
    mom_12_2 = slider::slide_dbl(shifted2, ~ prod(1 + .x) - 1, .before = 10L, .complete = TRUE),
    # MAX drawn from month (t-1) only
    max_lag1 = dplyr::lag(max_ret, 1L),
    # holding return: month (t+1)'s realised return -- computed here for
    # convenience but NEVER read by mom_12_2 or max_lag1 above (those are
    # built from lag() on earlier positions only)
    hold_ret = dplyr::lead(monthly_ret, 1L)
  ) |>
  ungroup()

n_candidate_rows <- nrow(sig_all)
sig <- sig_all |> filter(!is.na(mom_12_2), !is.na(max_lag1), !is.na(hold_ret))
n_dropped_incomplete <- n_candidate_rows - nrow(sig)
cat(sprintf(
  "ticker-month rows: %d total calendar slots; %d dropped for an incomplete window (insufficient history at the start/end of a ticker's life, or a gap inside the required [t-12,t+1] span); %d usable formation rows\n",
  n_candidate_rows, n_dropped_incomplete, nrow(sig)
))

# ── Cross-sectional thinness guard: drop calendar months too thin for a stable tercile sort ──
month_counts <- sig |> group_by(midx) |> summarise(n_stocks = dplyr::n(), .groups = "drop")
few_months <- month_counts |> filter(n_stocks < MIN_STOCKS_PER_MONTH)
cat(sprintf(
  "calendar months with < %d stocks carrying a valid signal: %d of %d candidate months -- these are DROPPED (not silently averaged over a thin/unstable cross-section)\n",
  MIN_STOCKS_PER_MONTH, nrow(few_months), nrow(month_counts)
))
if (nrow(few_months) > 0) {
  ym_of <- function(m) sprintf("%04d-%02d", (m - ((m - 1) %% 12L + 1L)) %/% 12L, (m - 1) %% 12L + 1L)
  few_disp <- few_months |> mutate(ym = ym_of(midx)) |> arrange(midx)
  cat("dropped-month sample (first 10, oldest):\n")
  print(as.data.frame(head(few_disp[, c("ym", "midx", "n_stocks")], 10)))
  if (nrow(few_disp) > 10) {
    cat(sprintf("... and %d more (see results/dropped_thin_months.csv)\n", nrow(few_disp) - 10))
  }
  if (readr_ok) {
    readr::write_csv(few_disp, file.path(RESULTS_DIR, "dropped_thin_months.csv"))
  } else {
    write.csv(few_disp, file.path(RESULTS_DIR, "dropped_thin_months.csv"), row.names = FALSE)
  }
}
good_months <- month_counts |> filter(n_stocks >= MIN_STOCKS_PER_MONTH)
sig <- sig |> semi_join(good_months, by = "midx")
cat(sprintf(
  "formation rows after dropping thin months: %d, spanning %d calendar months\n",
  nrow(sig), n_distinct(sig$midx)
))
avg_n_per_month <- mean(good_months$n_stocks)
cat(sprintf("average stocks per formation month (after thinness filter): %.1f\n\n", avg_n_per_month))

# ── 4. Independent double sort (terciles) ────────────────────────────────────
cat("=== 4. Double sort (independent terciles on momentum and MAX) ===\n")
sig <- sig |>
  group_by(midx) |>
  mutate(
    mom_tercile = dplyr::ntile(mom_12_2, 3L),  # 1 = low, 3 = high
    max_tercile = dplyr::ntile(max_lag1, 3L)   # 1 = low, 3 = high
  ) |>
  ungroup()

cell_counts <- sig |>
  group_by(mom_tercile, max_tercile) |>
  summarise(avg_n_per_month = round(dplyr::n() / n_distinct(sig$midx), 1), .groups = "drop") |>
  arrange(mom_tercile, max_tercile)
cat("average stocks per (mom_tercile x max_tercile) cell per month:\n")
print(as.data.frame(cell_counts))
cat("\n")

# Persist the full stock-month signal table (this is the "monthly leg
# returns" input; see also monthly_bucket_returns.csv below for the
# aggregated version). ~200k rows -- written as parquet, not CSV, to keep
# the exploration's committed footprint reasonable (CSV of this table is
# ~23MB; parquet is roughly an order of magnitude smaller).
sig_out <- sig |> select(ticker, midx, monthly_ret, max_ret, mom_12_2, max_lag1,
                          hold_ret, mom_tercile, max_tercile)
arrow::write_parquet(sig_out, file.path(RESULTS_DIR, "stock_month_signals.parquet"))

# ── 5. Bucket / strategy returns (equal-weighted) ────────────────────────────
cat("=== 5. Bucket and strategy returns ===\n")

bucket_ret <- sig |>
  group_by(midx, mom_tercile, max_tercile) |>
  summarise(ew_ret = mean(hold_ret), n = dplyr::n(), .groups = "drop")

mom_bucket_ret <- sig |>
  group_by(midx, mom_tercile) |>
  summarise(ew_ret = mean(hold_ret), n = dplyr::n(), .groups = "drop")

if (readr_ok) {
  readr::write_csv(bucket_ret, file.path(RESULTS_DIR, "monthly_bucket_returns.csv"))
  readr::write_csv(mom_bucket_ret, file.path(RESULTS_DIR, "monthly_mom_singlesort_returns.csv"))
} else {
  write.csv(bucket_ret, file.path(RESULTS_DIR, "monthly_bucket_returns.csv"), row.names = FALSE)
  write.csv(mom_bucket_ret, file.path(RESULTS_DIR, "monthly_mom_singlesort_returns.csv"), row.names = FALSE)
}

corner_hh <- bucket_ret |> filter(mom_tercile == 3, max_tercile == 3) |> arrange(midx)  # high mom, high MAX
corner_hl <- bucket_ret |> filter(mom_tercile == 3, max_tercile == 1) |> arrange(midx)  # high mom, low MAX
corner_lh <- bucket_ret |> filter(mom_tercile == 1, max_tercile == 3) |> arrange(midx)  # low mom, high MAX
corner_ll <- bucket_ret |> filter(mom_tercile == 1, max_tercile == 1) |> arrange(midx)  # low mom, low MAX

plain_long <- mom_bucket_ret |> filter(mom_tercile == 3) |> arrange(midx)
plain_short <- mom_bucket_ret |> filter(mom_tercile == 1) |> arrange(midx)

strat_pair <- function(long_df, short_df) {
  inner_join(
    long_df |> select(midx, long_ret = ew_ret),
    short_df |> select(midx, short_ret = ew_ret),
    by = "midx"
  ) |>
    arrange(midx) |>
    mutate(gross_ret = long_ret - short_ret)
}

mom_plain_strat <- strat_pair(plain_long, plain_short)
mom_lottery_strat <- strat_pair(corner_hh, corner_lh)
mom_nonlottery_strat <- strat_pair(corner_hl, corner_ll)

cat(sprintf(
  "mom_plain      : %d overlapping months\n", nrow(mom_plain_strat)
))
cat(sprintf(
  "mom_lottery    : %d overlapping months\n", nrow(mom_lottery_strat)
))
cat(sprintf(
  "mom_nonlottery : %d overlapping months\n\n", nrow(mom_nonlottery_strat)
))

# ── 6. Turnover ───────────────────────────────────────────────────────────
cat("=== 6. Turnover (fraction of names replaced at each rebalance) ===\n")
turnover_from_membership <- function(df) {
  df <- df |> distinct(midx, ticker) |> arrange(midx)
  months <- sort(unique(df$midx))
  if (length(months) < 2) return(NA_real_)
  turns <- vapply(seq_along(months)[-1], function(i) {
    prev <- df$ticker[df$midx == months[i - 1L]]
    cur  <- df$ticker[df$midx == months[i]]
    if (length(prev) == 0) return(NA_real_)
    1 - length(intersect(prev, cur)) / length(prev)
  }, numeric(1))
  mean(turns, na.rm = TRUE)
}

mem_plain_long <- sig |> filter(mom_tercile == 3)
mem_plain_short <- sig |> filter(mom_tercile == 1)
mem_hh <- sig |> filter(mom_tercile == 3, max_tercile == 3)
mem_lh <- sig |> filter(mom_tercile == 1, max_tercile == 3)
mem_hl <- sig |> filter(mom_tercile == 3, max_tercile == 1)
mem_ll <- sig |> filter(mom_tercile == 1, max_tercile == 1)

turnover_tbl <- tibble::tibble(
  strategy = c("mom_plain", "mom_plain", "mom_lottery", "mom_lottery", "mom_nonlottery", "mom_nonlottery"),
  leg = c("long", "short", "long", "short", "long", "short"),
  turnover = c(
    turnover_from_membership(mem_plain_long), turnover_from_membership(mem_plain_short),
    turnover_from_membership(mem_hh), turnover_from_membership(mem_lh),
    turnover_from_membership(mem_hl), turnover_from_membership(mem_ll)
  )
)
print(as.data.frame(turnover_tbl))
cat("\n")

# ── 7. Cost- and borrow-adjustment ────────────────────────────────────────
cat("=== 7. Cost and borrow adjustment ===\n")
cat(sprintf(
  "assumed round-trip trading cost: %.2f%% per name replaced (MANUAL: matches ltr_params$cost_per_trade, not independently sourced)\n",
  100 * ROUND_TRIP_COST
))
cat(sprintf(
  "assumed short-borrow cost: %.1f%%/yr, applied every month the short leg is held (MANUAL: matches ltr_params$borrow_rate_annual, not independently sourced)\n\n",
  100 * BORROW_RATE_ANNUAL
))
monthly_borrow <- BORROW_RATE_ANNUAL / 12

net_adjust <- function(strat_df, long_to, short_to) {
  strat_df |>
    mutate(
      long_cost = long_to * ROUND_TRIP_COST,
      short_cost = short_to * ROUND_TRIP_COST,
      net_ret = (long_ret - long_cost) - (short_ret + short_cost) - monthly_borrow
    )
}

mom_plain_strat <- net_adjust(
  mom_plain_strat,
  turnover_tbl$turnover[turnover_tbl$strategy == "mom_plain" & turnover_tbl$leg == "long"],
  turnover_tbl$turnover[turnover_tbl$strategy == "mom_plain" & turnover_tbl$leg == "short"]
)
mom_lottery_strat <- net_adjust(
  mom_lottery_strat,
  turnover_tbl$turnover[turnover_tbl$strategy == "mom_lottery" & turnover_tbl$leg == "long"],
  turnover_tbl$turnover[turnover_tbl$strategy == "mom_lottery" & turnover_tbl$leg == "short"]
)
mom_nonlottery_strat <- net_adjust(
  mom_nonlottery_strat,
  turnover_tbl$turnover[turnover_tbl$strategy == "mom_nonlottery" & turnover_tbl$leg == "long"],
  turnover_tbl$turnover[turnover_tbl$strategy == "mom_nonlottery" & turnover_tbl$leg == "short"]
)

if (readr_ok) {
  readr::write_csv(mom_plain_strat, file.path(RESULTS_DIR, "strategy_returns_mom_plain.csv"))
  readr::write_csv(mom_lottery_strat, file.path(RESULTS_DIR, "strategy_returns_mom_lottery.csv"))
  readr::write_csv(mom_nonlottery_strat, file.path(RESULTS_DIR, "strategy_returns_mom_nonlottery.csv"))
} else {
  write.csv(mom_plain_strat, file.path(RESULTS_DIR, "strategy_returns_mom_plain.csv"), row.names = FALSE)
  write.csv(mom_lottery_strat, file.path(RESULTS_DIR, "strategy_returns_mom_lottery.csv"), row.names = FALSE)
  write.csv(mom_nonlottery_strat, file.path(RESULTS_DIR, "strategy_returns_mom_nonlottery.csv"), row.names = FALSE)
}

# ── 8. Performance metrics + detection power ─────────────────────────────
cat("=== 8. Performance metrics (annualised) + detection power ===\n\n")

skewness_sample <- function(r) {
  r <- r[!is.na(r)]
  m <- mean(r)
  s <- stats::sd(r)
  if (s == 0 || length(r) < 3) return(NA_real_)
  mean((r - m)^3) / s^3
}

max_drawdown <- function(r) {
  r <- r[!is.na(r)]
  cum <- cumprod(1 + r)
  peak <- cummax(cum)
  min(cum / peak - 1)
}

compute_metrics <- function(r, ann_factor = 12) {
  r <- r[!is.na(r)]
  n <- length(r)
  hac <- hd_hac_sharpe(r, ann_factor = ann_factor)
  cagr <- prod(1 + r)^(ann_factor / n) - 1
  list(
    n_months = n,
    ann_ret_cagr = cagr,
    ann_ret_arith = hac$annualised_mean,
    ann_vol = hac$annualised_vol,
    sharpe = hac$naive_sharpe,
    max_dd = max_drawdown(r),
    skew = skewness_sample(r)
  )
}

detection_verdict <- function(sharpe_annual, n_obs) {
  if (is.na(sharpe_annual) || sharpe_annual <= 0) {
    return(list(
      power = NA_real_, underpowered = NA, min_n_periods = NA_real_,
      min_n_years = NA_real_, verdict = "N/A (non-positive Sharpe: one-sided H1 has nothing positive to detect)"
    ))
  }
  d <- hd_detection_power(sharpe_annual = sharpe_annual, n_obs = n_obs, ann_factor = 12)
  d$verdict <- if (isTRUE(d$underpowered)) "UNDERPOWERED" else "adequately powered"
  d
}

report_row <- function(label, r, zadeh_pct = NA_real_) {
  m <- compute_metrics(r)
  dp <- detection_verdict(m$sharpe, m$n_months)
  cat(sprintf("--- %s ---\n", label))
  cat(sprintf(
    "  DETECTION POWER: %s (n=%d months=%.1fyr; sharpe=%.3f needs min_n_years=%.1f for 80%% power at alpha=0.05)\n",
    dp$verdict, m$n_months, m$n_months / 12, m$sharpe,
    if (is.na(dp$min_n_years)) NA_real_ else dp$min_n_years
  ))
  cat(sprintf(
    "  ann_ret(CAGR)=%+.2f%%  ann_ret(arith)=%+.2f%%  ann_vol=%.2f%%  sharpe=%+.3f  max_dd=%+.2f%%  skew=%+.3f  n=%d\n",
    100 * m$ann_ret_cagr, 100 * m$ann_ret_arith, 100 * m$ann_vol, m$sharpe,
    100 * m$max_dd, m$skew, m$n_months
  ))
  if (!is.na(zadeh_pct)) {
    cat(sprintf("  Zadeh (Klement summary) reports: %+.1f%%\n", zadeh_pct))
  }
  cat("\n")
  tibble::tibble(
    label = label, n_months = m$n_months, ann_ret_cagr = m$ann_ret_cagr,
    ann_ret_arith = m$ann_ret_arith, ann_vol = m$ann_vol, sharpe = m$sharpe,
    max_dd = m$max_dd, skew = m$skew, detection_verdict = dp$verdict,
    detection_power = dp$power, min_n_years_for_80pct_power = dp$min_n_years,
    zadeh_pct = zadeh_pct
  )
}

cat("### Four corner buckets (long-only, equal-weighted) vs Zadeh's table ###\n\n")
row_hh <- report_row("corner: high-mom, high-MAX (lottery winners)", corner_hh$ew_ret, 15.0)
row_hl <- report_row("corner: high-mom, low-MAX  (non-lottery winners, no Zadeh figure)", corner_hl$ew_ret, NA_real_)
row_lh <- report_row("corner: low-mom,  high-MAX (lottery losers)", corner_lh$ew_ret, -14.8)
row_ll <- report_row("corner: low-mom,  low-MAX  (non-lottery losers, no Zadeh figure)", corner_ll$ew_ret, NA_real_)

cat("### Traditional (single-sort) momentum legs vs Zadeh's table ###\n\n")
row_plain_long <- report_row("single-sort: high-mom (traditional winners)", plain_long$ew_ret, 16.5)
row_plain_short <- report_row("single-sort: low-mom (traditional losers)", plain_short$ew_ret, 0.1)

cat("### Three long/short strategies -- gross ###\n\n")
row_mp_gross <- report_row("mom_plain (long high-mom, short low-mom, MAX-blind) -- GROSS", mom_plain_strat$gross_ret)
row_ml_gross <- report_row("mom_lottery (Zadeh's construction) -- GROSS", mom_lottery_strat$gross_ret)
row_mnl_gross <- report_row("mom_nonlottery (the control) -- GROSS", mom_nonlottery_strat$gross_ret)

cat("### Three long/short strategies -- net of costs and short borrow ###\n\n")
row_mp_net <- report_row("mom_plain -- NET", mom_plain_strat$net_ret)
row_ml_net <- report_row("mom_lottery -- NET", mom_lottery_strat$net_ret)
row_mnl_net <- report_row("mom_nonlottery -- NET", mom_nonlottery_strat$net_ret)

summary_tbl <- dplyr::bind_rows(
  row_hh, row_hl, row_lh, row_ll,
  row_plain_long, row_plain_short,
  row_mp_gross, row_ml_gross, row_mnl_gross,
  row_mp_net, row_ml_net, row_mnl_net
)
if (readr_ok) {
  readr::write_csv(summary_tbl, file.path(RESULTS_DIR, "summary_metrics.csv"))
  readr::write_csv(turnover_tbl, file.path(RESULTS_DIR, "turnover.csv"))
} else {
  write.csv(summary_tbl, file.path(RESULTS_DIR, "summary_metrics.csv"), row.names = FALSE)
  write.csv(turnover_tbl, file.path(RESULTS_DIR, "turnover.csv"), row.names = FALSE)
}

# ── 9. Head-to-head: does the MAX filter do anything? ────────────────────
cat("=== 9. mom_lottery vs mom_nonlottery (the control that matters) ===\n")
lottery_beats_control_gross <- row_ml_gross$sharpe > row_mnl_gross$sharpe
lottery_beats_control_net <- row_ml_net$sharpe > row_mnl_net$sharpe
cat(sprintf(
  "GROSS Sharpe: mom_lottery=%+.3f vs mom_nonlottery=%+.3f -> mom_lottery %s\n",
  row_ml_gross$sharpe, row_mnl_gross$sharpe,
  if (lottery_beats_control_gross) "BEATS the control" else "does NOT beat the control"
))
cat(sprintf(
  "NET   Sharpe: mom_lottery=%+.3f vs mom_nonlottery=%+.3f -> mom_lottery %s\n\n",
  row_ml_net$sharpe, row_mnl_net$sharpe,
  if (lottery_beats_control_net) "BEATS the control" else "does NOT beat the control"
))

# ── 10. Survivorship verdict for the -14.8% short-leg claim ──────────────
cat("=== 10. Survivorship verdict (PASS / FAIL / INDETERMINATE) ===\n")
cat(paste0(
  "The equity_daily dataset is documented survivorship_biased = TRUE with ",
  "known_delistings = 0L across its full ", format(min(raw$date), "%Y"), "-",
  format(panel_end, "%Y"), " span, and Enron/Lehman/Bear Stearns/WorldCom/WaMu ",
  "are absent from the universe. Zadeh's -14.8% headline is a claim SPECIFICALLY ",
  "about the return of stocks that go on to crash hardest (low prior momentum, ",
  "high lottery-skew) -- precisely the stocks a survivorship-biased panel ",
  "structurally cannot contain. Our short leg can only ever include names that ",
  "eventually recovered enough to still be listed today; the worst outcomes in ",
  "that population, by construction, are missing from our data. This is not a ",
  "question our data can answer either way -- a smaller (or larger) measured ",
  "effect here is NOT evidence for or against the -14.8% claim, because the ",
  "population being sampled is different in a way that specifically targets ",
  "the tail we are trying to measure.\n\n",
  "VERDICT: INDETERMINATE. Neither a match nor a mismatch with Zadeh's -14.8% ",
  "settles anything about the true magnitude, because our panel cannot ",
  "represent the stocks whose returns would matter most for that number. This ",
  "is a structural limit of the data source, not a small-sample or ",
  "detection-power issue (which is assessed separately in section 8/9) -- see ",
  "checks-must-distinguish-unknown.md: a check whose output cannot vary with ",
  "the thing being tested is not a check on that thing.\n"
))

cat("\n========================================================\n")
cat("Run complete. Outputs written to:", RESULTS_DIR, "\n")
cat("========================================================\n")
