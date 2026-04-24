# Results database: canonical schema + append + query
#
# hd_results_schema()  — empty tibble with all 73 typed columns
# hd_results_append()  — write rows to dated parquet files
# hd_results_query()   — lazy frame over all results parquets
#
# Every strategy run should populate a subset of columns (NULLs are OK).

# ── 1. Canonical schema ────────────────────────────────────────────────────────

#' Canonical schema for the results database
#'
#' Returns an empty tibble with all columns correctly typed.  This is the
#' single source of truth for column names and types — every strategy must
#' populate these columns (NULLs are acceptable for missing metrics).
#'
#' @return Zero-row tibble with 73 typed columns.
#' @family results
#' @export
hd_results_schema <- function() {
  tibble::tibble(
    # Identity
    run_date               = as.Date(character()),
    strategy_id            = character(),
    asset_class            = character(),
    partition              = character(),
    benchmark              = character(),
    is_negative            = logical(),

    # Performance (strategy vs benchmark)
    start_date             = as.Date(character()),
    end_date               = as.Date(character()),
    duration_days          = integer(),
    exposure_time_pct      = double(),
    start_value            = double(),
    final_value            = double(),
    peak_value             = double(),
    total_return_pct       = double(),
    cagr                   = double(),
    vol                    = double(),
    sharpe_naive           = double(),
    sharpe_hac             = double(),
    hac_tstat              = double(),
    exposure_adj_return    = double(),
    correlation_benchmark  = double(),
    sortino                = double(),
    calmar                 = double(),

    # Drawdown
    max_dd                   = double(),
    avg_dd                   = double(),
    max_dd_duration_days     = integer(),
    avg_dd_duration_days     = integer(),
    n_drawdowns              = integer(),
    n_drawdowns_per_year     = double(),
    recovery_days            = integer(),

    # Risk
    cvar_5pct          = double(),
    skewness           = double(),
    kurtosis           = double(),
    beta_mkt           = double(),
    up_capture         = double(),
    down_capture       = double(),
    best_month         = double(),
    worst_month        = double(),
    hit_rate_months    = double(),
    turnover_annual    = double(),

    # Falsification
    ff_alpha_annual  = double(),
    ff_alpha_tstat   = double(),
    ff_r_squared     = double(),
    rej_rate_wn      = double(),
    rej_rate_rv      = double(),
    rej_rate_ma1     = double(),
    rej_rate_fn      = double(),
    rej_rate_garch   = double(),
    rej_rate_gjr     = double(),
    k_eff            = double(),
    delta_z          = double(),

    # Trade analysis
    n_trades                  = integer(),
    n_trades_per_year         = double(),
    n_wins                    = integer(),
    n_losses                  = integer(),
    win_rate                  = double(),
    avg_return_per_trade      = double(),
    best_trade                = double(),
    worst_trade               = double(),
    max_trade_duration_days   = integer(),
    avg_trade_duration_days   = integer(),
    profit_factor             = double(),
    win_loss_ratio            = double(),
    payoff_ratio              = double(),
    cpc_index                 = double(),
    expectancy                = double(),
    max_consecutive_wins      = integer(),
    max_consecutive_losses    = integer(),

    # Flex
    note_1     = character(),
    note_2     = character(),
    note_3     = character(),
    tag_1      = character(),
    tag_2      = character(),
    extra_json = character()
  )
}


# ── 2. Append ──────────────────────────────────────────────────────────────────

#' Append strategy results to the parquet log
#'
#' Writes one or more result rows to a date-stamped parquet file under
#' \code{results_dir}.  If a file already exists for today, existing rows are
#' read, the new rows appended, and the combined frame is deduplicated on
#' \code{(strategy_id, partition)} before writing.
#'
#' Missing schema columns are filled with \code{NA}; extra columns in
#' \code{new_rows} are silently dropped.  Types are coerced to match the
#' canonical schema.
#'
#' @param new_rows Tibble matching \code{hd_results_schema()} columns (extra
#'   columns ignored, missing columns filled with \code{NA}).
#' @param results_dir Directory for parquet files.  Defaults to
#'   \code{inst/extdata/results/} relative to the package root (via
#'   \code{here::here()}).
#' @return Invisible path to the written file.
#' @family results
#' @export
hd_results_append <- function(new_rows, results_dir = NULL) {
  if (is.null(results_dir)) {
    results_dir <- file.path(here::here(), "inst", "extdata", "results")
  }
  dir.create(results_dir, recursive = TRUE, showWarnings = FALSE)

  # Ensure schema conformance: add missing columns as NA, coerce types
  schema <- hd_results_schema()
  for (col in names(schema)) {
    if (!col %in% names(new_rows)) {
      new_rows[[col]] <- NA
    }
    target_class <- class(schema[[col]])[1]
    if (target_class == "Date" && !inherits(new_rows[[col]], "Date")) {
      new_rows[[col]] <- as.Date(new_rows[[col]])
    } else if (target_class == "integer" && !is.integer(new_rows[[col]])) {
      new_rows[[col]] <- as.integer(new_rows[[col]])
    } else if (target_class == "numeric" && !is.numeric(new_rows[[col]])) {
      new_rows[[col]] <- as.numeric(new_rows[[col]])
    } else if (target_class == "logical" && !is.logical(new_rows[[col]])) {
      new_rows[[col]] <- as.logical(new_rows[[col]])
    } else if (target_class == "character" && !is.character(new_rows[[col]])) {
      new_rows[[col]] <- as.character(new_rows[[col]])
    }
  }
  # Select only schema columns in schema order
  new_rows <- new_rows[, names(schema), drop = FALSE]

  out_path <- file.path(results_dir, paste0("results_", Sys.Date(), ".parquet"))

  # If file exists for today, read and append
  if (file.exists(out_path)) {
    existing <- arrow::read_parquet(out_path)
    # New rows first so distinct() keeps the latest version
    combined <- dplyr::bind_rows(new_rows, existing) |>
      dplyr::distinct(strategy_id, partition, .keep_all = TRUE)
    arrow::write_parquet(combined, out_path, compression = "zstd")
  } else {
    arrow::write_parquet(new_rows, out_path, compression = "zstd")
  }

  cli::cli_inform(c("v" = "Wrote {nrow(new_rows)} row(s) to {out_path}"))
  invisible(out_path)
}


# ── 3. Query ───────────────────────────────────────────────────────────────────

#' Query the results database (all historical runs)
#'
#' Reads all dated parquet files in \code{results_dir} and returns a single
#' tibble.  Use dplyr verbs to filter or summarise, then collect if needed.
#'
#' @param results_dir Directory containing results parquets.  Defaults to
#'   \code{inst/extdata/results/} relative to the package root.
#' @return Tibble of all results rows, or an empty schema tibble if no files
#'   are found.
#' @family results
#' @export
hd_results_query <- function(results_dir = NULL) {
  if (is.null(results_dir)) {
    results_dir <- file.path(here::here(), "inst", "extdata", "results")
  }
  files <- list.files(results_dir, pattern = "\\.parquet$", full.names = TRUE)
  if (length(files) == 0) {
    cli::cli_warn("No results files found in {results_dir}")
    return(hd_results_schema())
  }
  purrr::map_dfr(files, arrow::read_parquet)
}
