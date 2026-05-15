#' Project-wide disclosure strings
#'
#' Single source of truth for caveats that appear on multiple pages.
#' When a strategy adds/removes the survivorship caveat, change here, not
#' at every site. See issue #150.
#' @export
disclosure_survivorship <- function() {
  n <- tryCatch(
    length(targets::tar_read(stk_top_tickers)),
    error = function(e) NA_integer_
  )
  size_phrase <- if (is.na(n)) "top-N" else paste0("top-", n)
  paste0(
    "**⚠ Survivorship-biased universe.** `stk_universe` now restricts to the ",
    size_phrase, " tickers by *current* market cap (#150 Option C) ",
    "to limit forward survivorship exposure. Historical backtest results ",
    "remain survivorship-biased — delisted firms (Lehman, Bear Stearns, ",
    "Enron, WorldCom, old GM, etc.) were never in the dataset and cannot ",
    "be reconstructed without point-in-time membership data. ",
    "Literature estimates residual bias at +1 to +3 pp/year for long-only ",
    "US equity. See [issue #150](https://github.com/JohnGavin/historical/issues/150) ",
    "for remediation status (Option A — point-in-time data — remains open)."
  )
}

#' Strategies whose results are affected by survivorship bias
#' @export
strategies_survivorship_biased <- function() {
  c(
    "stk_max",         # Stock MAX
    "stk_drif",        # Stock DRIF
    "mean_reversion",  # plan_mean_reversion.R
    "etf_replication", # uses stk_universe data
    "avoid_worst",     # via fals_avoid_worst_input
    "rsc"              # via fals_rsc_input
  )
}
