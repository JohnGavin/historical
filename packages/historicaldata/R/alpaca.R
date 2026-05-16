#' Snapshot the Alpaca assets universe to parquet
#'
#' Calls the Alpaca Markets `v2/assets` endpoint and writes the response as
#' parquet. Captures the 18 fields documented in the Alpaca API: identifiers
#' (`id`, `class`, `exchange`, `symbol`, `name`), tradability flags (`status`,
#' `tradable`, `marginable`, `shortable`, `easy_to_borrow`, `fractionable`),
#' margin requirements, attributes (e.g. `has_options`, `etp`,
#' `ptp_no_exception`), and order-sizing constraints (`min_order_size`,
#' `min_trade_increment`, `price_increment`).
#'
#' This is a thin direct-API wrapper — the upstream `{alpacar}` package
#' (datawookie/alpacar) is GitHub-only and therefore not in our nix pin, so we
#' call `httr2` directly. Functionally equivalent to `alpacar::assets_list()`
#' for the 18 documented fields.
#'
#' @section Credentials:
#' Reads keys from environment variables:
#' \itemize{
#'   \item `ALPACA_KEY` — Alpaca API key ID
#'   \item `ALPACA_SECRET` — Alpaca API secret
#' }
#' Add these to `~/.Renviron` (NOT to project files). The Alpaca canonical
#' SDK variable names are `APCA_API_KEY_ID` / `APCA_API_SECRET_KEY`; if you
#' use those instead, pass them explicitly via `key` / `secret`. Aborts early
#' if either is missing — does not silently fall through.
#'
#' @section Account type:
#' Paper-trading and live accounts return identical assets metadata (same
#' universe, same fields, same conids). Default `paper = TRUE` is correct
#' for all metadata-only work; switch only if you genuinely need the
#' live-data tier.
#'
#' @section Survivorship:
#' Pass `status = "inactive"` (or `"both"`) to retrieve delisted symbols.
#' The default `"active"` gives the currently-tradeable universe only — same
#' survivorship trap as a yfinance snapshot. Pair with periodic snapshots
#' to build a point-in-time universe (see issue #150).
#'
#' @param out_dir Directory for the parquet. Created if missing.
#' @param asset_class One of `"us_equity"`, `"crypto"`, or `NULL` for all.
#' @param status One of `"active"`, `"inactive"`, or `"both"`. Default `"active"`.
#' @param date Snapshot date (defaults to today); embedded in the filename.
#' @param paper If `TRUE` (default), hits `paper-api.alpaca.markets`; else
#'   `api.alpaca.markets`. Assets metadata is identical between tiers.
#' @param key,secret Optional explicit credentials. If `NULL` (default),
#'   reads from `ALPACA_KEY` / `ALPACA_SECRET` env vars.
#' @param min_rows Soft floor — warn if the response held fewer rows than this.
#' @return Path to the written parquet (invisibly).
#' @family discovery
#' @export
hd_alpaca_assets_snapshot <- function(out_dir,
                                      asset_class = NULL,
                                      status = c("active", "inactive", "both"),
                                      date = Sys.Date(),
                                      paper = TRUE,
                                      key = NULL,
                                      secret = NULL,
                                      min_rows = 100L) {
  rlang::check_installed(c("httr2", "jsonlite", "arrow"))
  status <- match.arg(status)

  key <- key %||% Sys.getenv("ALPACA_KEY", unset = NA_character_)
  secret <- secret %||% Sys.getenv("ALPACA_SECRET", unset = NA_character_)
  if (is.na(key) || !nzchar(key) || is.na(secret) || !nzchar(secret)) {
    cli::cli_abort(c(
      "Alpaca credentials missing.",
      "i" = "Set {.envvar ALPACA_KEY} and {.envvar ALPACA_SECRET} in {.file ~/.Renviron} (then restart R), or pass {.arg key}/{.arg secret} explicitly."
    ))
  }

  base_url <- if (isTRUE(paper)) "https://paper-api.alpaca.markets" else "https://api.alpaca.markets"

  fetch_one <- function(api_status) {
    req <- httr2::request(base_url) |>
      httr2::req_url_path_append("v2", "assets") |>
      httr2::req_headers(
        `APCA-API-KEY-ID` = key,
        `APCA-API-SECRET-KEY` = secret
      ) |>
      httr2::req_url_query(status = api_status) |>
      httr2::req_retry(max_tries = 3L) |>
      httr2::req_throttle(rate = 200 / 60)  # 200 req/min free tier
    if (!is.null(asset_class)) {
      req <- httr2::req_url_query(req, asset_class = asset_class)
    }
    resp <- httr2::req_perform(req)
    body <- httr2::resp_body_string(resp)
    rows <- jsonlite::fromJSON(body, flatten = TRUE, simplifyDataFrame = TRUE)
    if (!is.data.frame(rows) || nrow(rows) == 0L) {
      cli::cli_abort("Alpaca returned 0 rows for status = {.val {api_status}}.")
    }
    tibble::as_tibble(rows)
  }

  out <- switch(status,
    active   = fetch_one("active"),
    inactive = fetch_one("inactive"),
    both     = dplyr::bind_rows(fetch_one("active"), fetch_one("inactive"))
  )

  if (nrow(out) < min_rows) {
    cli::cli_warn("Alpaca returned {nrow(out)} rows (< min_rows = {min_rows}). Confirm asset_class / status filters.")
  }

  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  class_tag <- if (is.null(asset_class)) "all" else asset_class
  filename <- sprintf("alpaca_assets_%s_%s_%s.parquet",
                      class_tag, status, format(date, "%Y%m%d"))
  out_path <- file.path(out_dir, filename)
  arrow::write_parquet(out, out_path)

  cli::cli_alert_success("Wrote {nrow(out)} rows to {.path {out_path}}")
  invisible(out_path)
}
