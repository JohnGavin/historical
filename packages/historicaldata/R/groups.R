#' List all curated ticker groups
#'
#' Returns a tibble of named groups with their tickers and definitions.
#' Groups are editorial (curated), not computed from metadata.
#'
#' @return Tibble with columns: group, description, tickers (character vector in list-column)
#' @export
#' @examples
#' hd_ticker_groups()
#' hd_ticker_groups() |> dplyr::filter(group == "FAANG")
hd_ticker_groups <- function() {
  groups <- list(
    list("FAANG",
         "Meta (Facebook), Apple, Amazon, Netflix, Google (Alphabet)",
         c("META", "AAPL", "AMZN", "NFLX", "GOOGL")),
    list("Magnificent 7",
         "7 largest US tech companies by market cap",
         c("AAPL", "MSFT", "GOOGL", "AMZN", "NVDA", "META", "TSLA")),
    list("US Semiconductors",
         "Major US semiconductor companies",
         c("NVDA", "AMD", "INTC", "AVGO", "QCOM")),
    list("US Banks",
         "Major US financial institutions",
         c("JPM", "BAC", "GS", "MS", "V", "MA")),
    list("US Healthcare",
         "Major US healthcare and pharma",
         c("JNJ", "UNH", "PFE", "ABBV", "MRK")),
    list("US Energy",
         "Major US oil and gas",
         c("XOM", "CVX", "COP")),
    list("US Consumer",
         "Major US consumer staples and retail",
         c("WMT", "COST", "HD", "MCD", "KO", "PEP")),
    list("US Industrials",
         "Major US industrial companies",
         c("CAT", "BA", "GE", "HON", "UPS")),
    list("US Index ETFs",
         "Major US equity index ETFs",
         c("SPY", "QQQ", "IWM", "DIA")),
    list("Major Crypto",
         "Top 4 cryptocurrencies by market cap",
         c("BTC", "ETH", "SOL", "BNB")),
    list("Stablecoins",
         "USD-pegged cryptocurrency tokens",
         c("USDC", "USDT")),
    list("Solana DeFi",
         "Solana blockchain ecosystem tokens",
         c("SOL", "RAY", "HNT", "BONK", "PYTH")),
    list("DeFi Altcoins",
         "Alternative cryptocurrencies outside top 4",
         c("XRP", "ADA", "DOGE", "DOT"))
  )

  dplyr::tibble(
    group = vapply(groups, \(x) x[[1]], character(1)),
    description = vapply(groups, \(x) x[[2]], character(1)),
    tickers = lapply(groups, \(x) x[[3]])
  )
}

#' Get tickers for a named group
#'
#' @param name Group name (e.g. "FAANG", "Magnificent 7", "Stablecoins")
#' @return Character vector of ticker symbols
#' @export
#' @examples
#' hd_group("FAANG")
#' hd_group("Major Crypto")
hd_group <- function(name) {
  groups <- hd_ticker_groups()
  match <- groups[groups$group == name, ]
  if (nrow(match) == 0) {
    available <- paste(groups$group, collapse = ", ")
    cli::cli_abort(c(
      "Unknown group: {name}",
      "i" = "Available groups: {available}"
    ))
  }
  match$tickers[[1]]
}
