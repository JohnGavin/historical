# Overnight / Intraday Return Split (issue #914 Gap 1)
#
# Source idea (read for ideas only -- nothing copied): "The overnight gain is
# real, no trade keeps it, the rule that chases it buys wrecks" -- Serhat
# Girgin, QuanterLab, 2026-09-13.
# https://quanterlab.com/research/the-overnight-gain-is-real-no-trade-keeps-it-the-rule-that-chases-it-buys-wrecks
#
# (a) SPY overnight vs intraday cumulative growth, 1993-present -- a SANITY
#     CHECK against the article's claimed direction (overnight >> daytime),
#     NOT a strategy target. Not logged to the research-log DB
#     (research-log-honesty.md): this reproduces a third party's published
#     finding on our own data, it is not a pre-registered hypothesis of ours
#     to be sealed before the fact.
#
# (b) Per-strategy attribution: for every daily-frequency equity/index
#     strategy whose exposure schedule is visible in the docs/_targets store
#     as a return applied to a SINGLE underlying asset (not per-ticker
#     cross-sectional weights), split its own realised return into the
#     overnight and intraday contribution using hd_return_legs() on that
#     underlying asset. Strategies whose per-ticker daily holdings are NOT
#     persisted in the store at that granularity are listed INDETERMINATE
#     with the specific reason -- see results/indeterminate_strategies.csv.
#     (Gap 2, break-even cost per trade, is explicitly OUT OF SCOPE here --
#     it depends on realised turnover, tracked separately in #567/#663.)
#
# READ-ONLY: this script reads the MAIN CHECKOUT's built targets store
# (docs/_targets) via tar_read_raw() -- it never calls tar_make() and never
# writes to that store, per this worktree's isolation contract.

suppressMessages(pkgload::load_all("packages/historicaldata", quiet = TRUE))
suppressMessages({
  library(dplyr)
})

RESULTS_DIR <- "explorations/overnight_intraday_split/results"
dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

MAIN_STORE <- "/Users/johngavin/docs_gh/proj/finance/data/historical/docs/_targets"

cat("========================================================\n")
cat("Overnight / Intraday Return Split -- exploration (issue #914 Gap 1)\n")
cat("========================================================\n\n")

# ── (a) SPY overnight vs intraday, 1993-present ────────────────────────────
cat("=== (a) SPY overnight vs intraday cumulative growth ===\n")
spy_raw <- hd_ohlcv("SPY", collect = TRUE) |>
  arrange(date) |>
  select(date, ticker, open, close, adjusted_close)
cat(
  "SPY rows:", nrow(spy_raw), " date range:", as.character(min(spy_raw$date)),
  "to", as.character(max(spy_raw$date)), "\n"
)

spy_legs <- hd_return_legs(spy_raw, quiet = FALSE) |>
  arrange(date) |>
  mutate(
    cum_overnight_only = cumprod(1 + overnight),
    cum_intraday_only  = cumprod(1 + intraday),
    cum_close_to_close = cumprod(1 + close_to_close)
  )

spy_summary <- tibble::tibble(
  metric = c("overnight_only", "intraday_only", "close_to_close"),
  dollar_1_grows_to = c(
    utils::tail(spy_legs$cum_overnight_only, 1),
    utils::tail(spy_legs$cum_intraday_only, 1),
    utils::tail(spy_legs$cum_close_to_close, 1)
  ),
  n_days = nrow(spy_legs),
  start_date = min(spy_legs$date),
  end_date = max(spy_legs$date)
)
print(spy_summary)
readr::write_csv(spy_summary, file.path(RESULTS_DIR, "spy_overnight_intraday_summary.csv"))
readr::write_csv(
  spy_legs |>
    select(
      date, overnight, intraday, close_to_close, corp_action_adjusted,
      cum_overnight_only, cum_intraday_only, cum_close_to_close
    ),
  file.path(RESULTS_DIR, "spy_overnight_intraday_daily.csv")
)

cat("\nDirection check vs the article's claim (SPY 1993-2026, overnight >> daytime):\n")
cat("  overnight-only $1 ->", round(utils::tail(spy_legs$cum_overnight_only, 1), 2), "\n")
cat("  intraday-only  $1 ->", round(utils::tail(spy_legs$cum_intraday_only, 1), 2), "\n")
cat(
  "  matches claimed direction:",
  utils::tail(spy_legs$cum_overnight_only, 1) > utils::tail(spy_legs$cum_intraday_only, 1),
  "\n\n"
)

# ── (b) Per-strategy attribution ───────────────────────────────────────────
cat("=== (b) Per-strategy overnight/intraday attribution ===\n")

read_main_store <- function(name) {
  tryCatch(
    targets::tar_read_raw(name, store = MAIN_STORE),
    error = function(e) {
      cli::cli_warn("Could not read {name} from main store: {conditionMessage(e)}")
      NULL
    }
  )
}

spy_legs_join <- spy_legs |> select(date, overnight, intraday)

attribution_rows <- list()

## Avoid Worst (Days) -- VIX Protection, SPY-only, binary in/out.
## Signal is decided from the PRIOR day's close (R/plan_avoid_worst.R
## aw_practical_backtest: shocked/vix_elevated computed off d$ret[i-1] /
## d$vix[i-1]), so in_market[t] is already known before day t's overnight
## leg begins -- both legs of day t are captured together when in market,
## neither when out. No leg is unreachable by this execution.
aw <- read_main_store("aw_practical_backtest")
if (!is.null(aw)) {
  aw2 <- aw |>
    select(date, in_market, ret_market, ret_strategy) |>
    inner_join(spy_legs_join, by = "date") |>
    mutate(
      overnight_contrib = ifelse(in_market, overnight, 0),
      intraday_contrib  = ifelse(in_market, intraday, 0),
      recompound        = (1 + overnight_contrib) * (1 + intraday_contrib) - 1
    )
  # Consistency check: on in-market days, recompounding the two legs must
  # reproduce the strategy's own recorded ret_strategy exactly.
  mism <- aw2 |>
    filter(in_market) |>
    mutate(diff = abs(recompound - ret_strategy)) |>
    filter(diff > 1e-6)
  cat(
    "Avoid Worst: in-market days =", sum(aw2$in_market), "of", nrow(aw2),
    " | recompound mismatches (tol 1e-6):", nrow(mism), "\n"
  )

  cum_overnight <- prod(1 + aw2$overnight_contrib)
  cum_intraday  <- prod(1 + aw2$intraday_contrib)
  cum_actual    <- utils::tail(aw$cum_strategy, 1)
  attribution_rows[["Avoid Worst (Days)"]] <- tibble::tibble(
    strategy   = "Avoid Worst (Days) / VIX Protection",
    underlying = "SPY",
    execution_note = paste0(
      "Full-day in/out switch decided from prior-day close info; both legs ",
      "captured together when in market, neither when out -- no leg is ",
      "unreachable by this execution."
    ),
    n_days                          = nrow(aw2),
    n_days_in_market                = sum(aw2$in_market),
    dollar_grows_overnight_leg_only = cum_overnight,
    dollar_grows_intraday_leg_only  = cum_intraday,
    dollar_grows_actual_strategy    = cum_actual,
    n_recompound_mismatches         = nrow(mism)
  )
  readr::write_csv(aw2, file.path(RESULTS_DIR, "avoid_worst_attribution_daily.csv"))
} else {
  cat("Avoid Worst: aw_practical_backtest not readable from main store -- skipped.\n")
}

## Risk State (VIX Overlay) -- SPY-only, fractional exposure applied
## uniformly to the whole day's SPY return (R/plan_risk_state.R
## rsc_portfolio: gross_ret_strategy = exposure * spy_ret + ...). Both legs
## are partially captured every day in proportion to exposure -- no leg is
## unreachable.
rsc <- read_main_store("rsc_portfolio")
if (!is.null(rsc)) {
  rsc2 <- rsc |>
    select(date, exposure, spy_ret, ret_strategy) |>
    inner_join(spy_legs_join, by = "date") |>
    mutate(
      overnight_contrib = exposure * overnight,
      intraday_contrib  = exposure * intraday
    )
  cum_overnight <- prod(1 + rsc2$overnight_contrib)
  cum_intraday  <- prod(1 + rsc2$intraday_contrib)
  cum_actual    <- utils::tail(rsc$cum_strategy, 1)
  cat(
    "Risk State: mean exposure =", round(mean(rsc2$exposure, na.rm = TRUE), 3),
    " days =", nrow(rsc2), "\n"
  )
  attribution_rows[["Risk State (VIX Overlay)"]] <- tibble::tibble(
    strategy   = "Risk State (VIX Overlay)",
    underlying = "SPY",
    execution_note = paste0(
      "Fractional daily exposure (0.10-1.00) applied uniformly to the ",
      "whole day's SPY return; both legs partially captured every day in ",
      "proportion to exposure -- no leg is unreachable."
    ),
    n_days                          = nrow(rsc2),
    n_days_in_market                = NA_integer_,
    dollar_grows_overnight_leg_only = cum_overnight,
    dollar_grows_intraday_leg_only  = cum_intraday,
    dollar_grows_actual_strategy    = cum_actual,
    n_recompound_mismatches         = NA_integer_
  )
  readr::write_csv(rsc2, file.path(RESULTS_DIR, "risk_state_attribution_daily.csv"))
} else {
  cat("Risk State: rsc_portfolio not readable from main store -- skipped.\n")
}

attribution_tbl <- dplyr::bind_rows(attribution_rows)
cat("\nPer-strategy attribution (reproducible from the store):\n")
print(attribution_tbl)
readr::write_csv(attribution_tbl, file.path(RESULTS_DIR, "per_strategy_attribution.csv"))

# ── (c) Strategies where attribution is NOT reproducible from the store ────
# Each reason below was checked directly against the named target/function
# body during this exploration (see SUMMARY.md for the file:line evidence);
# none is a guess.
indeterminate <- tibble::tribble(
  ~strategy, ~targets_checked, ~reason,
  "LTR", "ltr_portfolio (R/plan_ltr_momentum.R)",
  paste0(
    "ltr_portfolio persists only a monthly aggregate long-short return ",
    "(ls_ret_net) per (date, ym) -- no per-ticker daily holdings/weights ",
    "are persisted anywhere in the store. A daily overnight/intraday split ",
    "would require re-deriving unpersisted intermediate position state."
  ),
  "OLMAR-1", "olmar_portfolio (R/plan_olmar.R); olmar_backtest() (packages/historicaldata/R/olmar.R)",
  paste0(
    "olmar_backtest() returns only date/gross_ret/net_ret/turnover -- the ",
    "per-ticker weight vector formed each day (b_new) is computed ",
    "internally but never returned or persisted. Its realised return is ",
    "already defined as adjusted_close_{t+1}/adjusted_close_t - 1 (trade ",
    "at close, hold the full next day), so even a per-ticker split would ",
    "need the unpersisted weight history."
  ),
  "Factor DRIF", "stk_drif_portfolio (R/plan_stock_backtest.R)",
  paste0(
    "Monthly-rebalanced decile long-short portfolio; the decile membership ",
    "per ticker/month exists only as an intermediate variable (`deciled`) ",
    "inside the stk_drif_portfolio target body, never persisted as its own ",
    "target. Re-deriving it would mean replaying the ADV-filter/decile-",
    "assignment pipeline outside the store."
  ),
  "Value (HML)", "hd_factors() / factors dataset (Fama-French, Ken French library)",
  paste0(
    "A pre-computed long-short FACTOR RETURN series, not a set of ",
    "tradable ticker-level positions we hold -- there is no equity_daily ",
    "open/close for 'the HML portfolio' as a single priced asset to split ",
    "into legs."
  ),
  "Managed Futures", "commodities/futures plan files (not equity_daily)",
  paste0(
    "Trades futures/commodity series, not equity_daily. Out of scope for ",
    "this gap, which is bounded to SPY-scale equity opens/closes; a ",
    "futures overnight/intraday split would need each contract's own ",
    "session open/close convention, not addressed here."
  ),
  "Mom Pre-Peak", "mom_prepeak_portfolio (R/plan_mom_prepeak.R)",
  paste0(
    "Same shape as Factor DRIF: a monthly quantile-sorted long-short ",
    "portfolio built from stk_monthly$monthly_ret; per-ticker daily ",
    "holdings are not persisted in the store."
  )
)
print(indeterminate)
readr::write_csv(indeterminate, file.path(RESULTS_DIR, "indeterminate_strategies.csv"))

cat("\nDone. Results written to", RESULTS_DIR, "\n")
