#!/usr/bin/env Rscript
# Fetch Kalshi FOMC rate decision market data (#47)
#
# Source:
# - Kalshi public API (no auth): api.elections.kalshi.com/trade-api/v2/
# - Series: KXFED (Fed rate decision contracts)
#
# Each market represents a specific rate outcome (e.g., "4.25% or above")
# for a given FOMC meeting. last_price is in $0-$1 = implied probability.
#
# Usage: Rscript scripts/fetch_kalshi.R

suppressPackageStartupMessages({
  library(dplyr)
  library(arrow)
  library(cli)
})

cli_h1("Kalshi FOMC Market Data Fetch")

# ── Configuration ────────────────────────────────────────────────
API_BASE     <- "https://api.elections.kalshi.com/trade-api/v2"
SERIES_TICKER <- "KXFED"
OUT_PATH     <- here::here("data/raw/kalshi_fomc.parquet")

# ── Paginated market fetch ───────────────────────────────────────
fetch_kalshi_markets <- function(series_ticker, api_base, limit = 200) {
  all_markets <- list()
  cursor      <- NULL
  page        <- 1L

  repeat {
    url <- sprintf("%s/markets?series_ticker=%s&limit=%d",
                   api_base, series_ticker, limit)
    if (!is.null(cursor) && nchar(cursor) > 0) {
      url <- paste0(url, "&cursor=", utils::URLencode(cursor, reserved = TRUE))
    }

    cli_inform(c("i" = "Page {page}: {url}"))

    resp <- tryCatch(
      jsonlite::fromJSON(url, simplifyDataFrame = FALSE),
      error = function(e) {
        cli_abort("API request failed: {e$message}")
      }
    )

    markets <- resp$markets
    if (is.null(markets) || length(markets) == 0) break

    all_markets <- c(all_markets, markets)
    cli_inform(c("v" = "  Retrieved {length(markets)} markets (total: {length(all_markets)})"))

    # Pagination: follow cursor if present and non-empty
    cursor_next <- resp$cursor
    if (is.null(cursor_next) || length(cursor_next) == 0 || nchar(cursor_next) == 0) break
    if (!is.null(cursor) && identical(cursor_next, cursor)) break  # guard against infinite loop
    cursor <- cursor_next
    page   <- page + 1L

    Sys.sleep(1)  # rate limit: 1 second between paginated requests
  }

  all_markets
}

# ── Parse market list to tibble ──────────────────────────────────
parse_markets <- function(markets) {
  if (length(markets) == 0) {
    cli_warn("No markets returned from API")
    return(tibble(
      event_ticker   = character(),
      market_ticker  = character(),
      outcome_label  = character(),
      probability    = numeric(),
      yes_bid        = numeric(),
      yes_ask        = numeric(),
      volume         = integer(),
      open_interest  = integer(),
      close_time     = as.POSIXct(character()),
      status         = character(),
      fetched_at     = as.POSIXct(character())
    ))
  }

  safe_num  <- function(x) {
    if (is.null(x) || length(x) == 0) return(NA_real_)
    v <- suppressWarnings(as.numeric(x))
    if (is.na(v)) NA_real_ else v
  }
  safe_int  <- function(x) {
    if (is.null(x) || length(x) == 0) return(NA_integer_)
    v <- suppressWarnings(as.integer(x))
    if (is.na(v)) NA_integer_ else v
  }
  safe_chr  <- function(x) if (is.null(x) || length(x) == 0) NA_character_ else as.character(x[[1]])
  safe_time <- function(x) {
    if (is.null(x) || length(x) == 0 || is.na(x)) return(as.POSIXct(NA))
    tryCatch(as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
             error = function(e) as.POSIXct(NA))
  }

  rows <- lapply(markets, function(m) {
    # last_price is in dollars (0.01 to 0.99) = probability
    last_price_raw <- m$last_price_dollars %||% m$last_price %||% NA_real_
    probability    <- safe_num(last_price_raw)

    tibble(
      event_ticker   = safe_chr(m$event_ticker),
      market_ticker  = safe_chr(m$ticker),
      outcome_label  = safe_chr(m$subtitle %||% m$title),
      probability    = probability,
      yes_bid        = safe_num(m$yes_bid),
      yes_ask        = safe_num(m$yes_ask),
      volume         = safe_int(m$volume),
      open_interest  = safe_int(m$open_interest),
      close_time     = safe_time(m$close_time),
      status         = safe_chr(m$status)
    )
  })

  bind_rows(rows) |>
    mutate(fetched_at = Sys.time())
}

# ── Main ─────────────────────────────────────────────────────────
cli_inform(c("i" = "Fetching series: {SERIES_TICKER}"))

markets_raw <- fetch_kalshi_markets(SERIES_TICKER, API_BASE)
cli_inform(c("v" = "Total markets fetched: {length(markets_raw)}"))

markets_df <- parse_markets(markets_raw)
cli_inform(c(
  "i" = "Parsed {nrow(markets_df)} market rows",
  "i" = "Events: {n_distinct(markets_df$event_ticker)}",
  "i" = "Probability range: {round(min(markets_df$probability, na.rm=TRUE),3)} - {round(max(markets_df$probability, na.rm=TRUE),3)}"
))

# ── Write parquet ────────────────────────────────────────────────
dir.create(dirname(OUT_PATH), recursive = TRUE, showWarnings = FALSE)
arrow::write_parquet(markets_df, OUT_PATH, compression = "zstd")

cli_h2("Summary")
cli_inform(c(
  "v" = "{nrow(markets_df)} markets written",
  "i" = "File: {OUT_PATH} ({round(file.info(OUT_PATH)$size / 1024, 1)} KB)"
))

print(dplyr::select(markets_df, event_ticker, market_ticker, outcome_label,
                    probability, volume, status))
