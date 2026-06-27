#' Test whether a ticker's volume data is unreliable due to yfinance non-US bug
#'
#' yfinance reports incorrect (typically inflated) volume figures for tickers
#' traded on non-US exchanges. The volume field for these tickers is treated as
#' `NA` on read — the raw parquet is preserved unchanged
#' (`raw-folder-readonly` rule).
#'
#' The affected exchange suffixes are:
#' - `.L`  — London Stock Exchange
#' - `.DE` — XETRA (Frankfurt)
#' - `.PA` — Euronext Paris
#' - `.AS` — Euronext Amsterdam
#' - `.SW` — SIX Swiss Exchange
#' - `.MC` — BME (Madrid)
#' - `.MI` — Borsa Italiana
#' - `.ST` — Nasdaq Stockholm
#' - `.CO` — Nasdaq Copenhagen
#'
#' This list is derived from the `exchange` `case_when` in
#' `qa_volume_sanity` and from the exchange suffixes used in `R/groups.R`.
#' See GitHub issue #21 for the root cause and evidence.
#'
#' @param ticker Character vector of ticker symbols.
#' @return Logical vector, same length as `ticker`. `TRUE` where the ticker
#'   belongs to a non-US exchange whose volume is known to be unreliable in
#'   yfinance. `FALSE` for US tickers (no suffix) and any unknown suffixes.
#' @references GitHub issue #21
#' @family quality-audit
#' @export
#' @examples
#' hd_unreliable_volume_ticker(c("AAPL", "ISF.L", "SAP.DE", "AIR.PA",
#'                                "ASML.AS", "NESN.SW", "SAN.MC",
#'                                "ISP.MI", "VOLV-B.ST", "GN.CO", "SPY"))
#' # FALSE  TRUE  TRUE  TRUE  TRUE  TRUE  TRUE  TRUE  TRUE  TRUE  FALSE
hd_unreliable_volume_ticker <- function(ticker) {
  grepl(
    "\\.L$|\\.DE$|\\.PA$|\\.AS$|\\.SW$|\\.MC$|\\.MI$|\\.ST$|\\.CO$",
    ticker,
    perl = TRUE
  )
}
