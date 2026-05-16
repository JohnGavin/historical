#' Snapshot a Yahoo Finance screener result to parquet
#'
#' Wraps the [yfscreen][yfscreen::yfscreen-package] API to capture a one-shot
#' universe snapshot for a `(region, sec_type)` pair (e.g. UK-listed ETFs).
#' Intended for periodic offline ingestion, not for live querying.
#'
#' yfscreen depends on undocumented Yahoo internals (crumb-cookie auth) and has
#' been broken upstream more than once. Schema-stability is checked at fetch
#' time and a warning is emitted if expected columns are missing.
#'
#' @param region Two-letter Yahoo region code (e.g. `"gb"`, `"us"`, `"de"`).
#' @param sec_type One of `"etf"`, `"equity"`, `"mutualfund"`, `"index"`, `"future"`.
#' @param out_dir Directory for the parquet. Created if missing.
#' @param date Snapshot date (defaults to today); embedded in the filename.
#' @param min_rows Soft floor — warn if the screener returned fewer than this.
#' @param max_total Upper bound on rows to retrieve. yfscreen's `size` argument
#'   is the TOTAL desired (not page size); the function chunks internally at
#'   250/request and stops early when a page returns empty. Default 10000 is
#'   enough to capture any single-region universe; lower it for quick smoke
#'   tests.
#' @return Path to the written parquet (invisibly).
#' @family discovery
#' @export
hd_yahoo_screen_snapshot <- function(region,
                                     sec_type = c("etf", "equity", "mutualfund", "index", "future"),
                                     out_dir,
                                     date = Sys.Date(),
                                     min_rows = 10L,
                                     max_total = 10000L) {
  rlang::check_installed(c("yfscreen", "arrow"))
  sec_type <- match.arg(sec_type)

  query <- yfscreen::create_query(list(list("eq", list("region", region))))
  payload <- yfscreen::create_payload(sec_type, query, size = max_total)
  rows <- yfscreen::get_data(payload)

  if (!is.data.frame(rows) || nrow(rows) == 0L) {
    cli::cli_abort("yfscreen returned no rows for region {.val {region}} / sec_type {.val {sec_type}}.")
  }
  if (nrow(rows) < min_rows) {
    cli::cli_warn("yfscreen returned {nrow(rows)} rows (< min_rows = {min_rows}). Yahoo schema may have changed.")
  }

  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  filename <- sprintf("%s_%s_universe_%s.parquet",
                      region, sec_type, format(date, "%Y%m%d"))
  out_path <- file.path(out_dir, filename)
  arrow::write_parquet(tibble::as_tibble(rows), out_path)

  cli::cli_alert_success("Wrote {nrow(rows)} rows to {.path {out_path}}")
  invisible(out_path)
}
