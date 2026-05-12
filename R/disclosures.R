#' Project-wide disclosure strings
#'
#' Single source of truth for caveats that appear on multiple pages.
#' When a strategy adds/removes the survivorship caveat, change here, not
#' at every site. See issue #150.
#' @export
disclosure_survivorship <- function() {
  paste0(
    "**⚠ Survivorship-biased universe.** The 672-ticker `stk_universe` ",
    "(S&P 500 + STOXX 600) contains only currently-listed members with ",
    "history backfilled — delisted firms (Lehman, Bear Stearns, Enron, ",
    "WorldCom, old GM, etc.) are absent. Stock-level Sharpe / CAGR / DD ",
    "shown here overstates achievable returns; literature estimates the ",
    "bias at +1 to +3 pp/year for long-only US equity. ",
    "See [issue #150](https://github.com/JohnGavin/historical/issues/150) ",
    "for remediation status."
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
