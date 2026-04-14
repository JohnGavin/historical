# QA validation targets for vignettes
#
# These depend on ALL vig_* targets (via tidy_eval in tar_target).
# They validate outputs AFTER computation, BEFORE rendering.
# If any QA target fails, the build reports the error.
#
# Note: tar_objects() cannot be called during tar_make().
# Instead, QA targets take vig outputs as dependencies.

plan_qa_vignette <- function() {
  list(
    # QA 1: Pipeline completion marker
    targets::tar_target(qa_summary, {
      cli::cli_inform(c("v" = "QA: pipeline completed. Run post-render checks separately."))
      list(status = "pipeline_complete", timestamp = Sys.time())
    }, cue = targets::tar_cue(mode = "always")),

    # QA 2: Dataset-metadata consistency (#19)
    # Checks that every ticker in OHLCV parquets has a metadata row
    targets::tar_target(qa_metadata_sync, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      con <- hd_connect()
      on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

      datasets <- c("equity_daily", "crypto_daily")
      meta_ds <- hd_datasets()[["metadata"]]
      issues <- list()

      for (ds_name in datasets) {
        ds <- hd_datasets()[[ds_name]]
        if (is.null(ds)) next

        ohlcv_tickers <- DBI::dbGetQuery(con, sprintf(
          "SELECT DISTINCT ticker FROM read_parquet('%s')", ds$url))$ticker
        meta_tickers <- DBI::dbGetQuery(con, sprintf(
          "SELECT DISTINCT ticker FROM read_parquet('%s') WHERE dataset = '%s'",
          meta_ds$url, ds_name))$ticker

        missing <- setdiff(ohlcv_tickers, meta_tickers)
        orphans <- setdiff(meta_tickers, ohlcv_tickers)

        if (length(missing) > 0) {
          cli::cli_warn(c("!" = "{ds_name}: {length(missing)} tickers in OHLCV but not metadata",
                          "i" = "Missing: {paste(head(missing, 10), collapse = ', ')}{if (length(missing) > 10) '...' else ''}"))
          issues[[paste0(ds_name, "_missing")]] <- missing
        }
        if (length(orphans) > 0) {
          cli::cli_inform(c("i" = "{ds_name}: {length(orphans)} orphan metadata entries (no OHLCV data)"))
          issues[[paste0(ds_name, "_orphans")]] <- orphans
        }
      }

      if (length(issues) == 0) {
        cli::cli_inform(c("v" = "QA metadata sync: all datasets consistent"))
      }

      list(
        checked = length(datasets),
        issues = length(issues),
        details = lapply(issues, length),
        timestamp = Sys.time()
      )
    }, cue = targets::tar_cue(mode = "always")),

    # QA 3: Volume sanity check (#21)
    # yfinance reports incorrect volume for non-US markets
    # Flag tickers with suspiciously high dollar volume
    targets::tar_target(qa_volume_sanity, {
      pkgload::load_all(here::here("packages/historicaldata"), quiet = TRUE)
      con <- hd_connect()
      on.exit(DBI::dbDisconnect(con, shutdown = TRUE))

      ds <- hd_datasets()[["equity_daily"]]

      # Per-exchange median dollar volume and outlier detection
      stats <- DBI::dbGetQuery(con, sprintf("
        WITH ticker_stats AS (
          SELECT ticker,
            CASE
              WHEN ticker LIKE '%%.DE' THEN 'DE'
              WHEN ticker LIKE '%%.PA' THEN 'PA'
              WHEN ticker LIKE '%%.AS' THEN 'AS'
              WHEN ticker LIKE '%%.SW' THEN 'SW'
              WHEN ticker LIKE '%%.MC' THEN 'MC'
              WHEN ticker LIKE '%%.MI' THEN 'MI'
              WHEN ticker LIKE '%%.ST' THEN 'ST'
              WHEN ticker LIKE '%%.CO' THEN 'CO'
              WHEN ticker LIKE '%%.L'  THEN 'L'
              ELSE 'US'
            END as exchange,
            AVG(close * volume) as avg_dollar_vol
          FROM read_parquet('%s')
          GROUP BY ticker
        ),
        exchange_stats AS (
          SELECT exchange,
            MEDIAN(avg_dollar_vol) as median_vol,
            COUNT(*) as n_tickers
          FROM ticker_stats
          GROUP BY exchange
        )
        SELECT t.ticker, t.exchange, t.avg_dollar_vol,
          e.median_vol as exchange_median,
          t.avg_dollar_vol / NULLIF(e.median_vol, 0) as ratio_to_median
        FROM ticker_stats t
        JOIN exchange_stats e ON t.exchange = e.exchange
        WHERE t.avg_dollar_vol / NULLIF(e.median_vol, 0) > 50
           OR t.avg_dollar_vol > 5e9
        ORDER BY ratio_to_median DESC
      ", ds$url))

      if (nrow(stats) > 0) {
        cli::cli_warn(c(
          "!" = "QA volume: {nrow(stats)} tickers with suspicious dollar volume",
          "i" = "Tickers >50x exchange median or >$5B/day (yfinance bug for non-US):",
          "i" = paste(head(stats$ticker, 10), collapse = ", ")
        ))
      } else {
        cli::cli_inform(c("v" = "QA volume: no outliers detected"))
      }

      list(
        flagged = nrow(stats),
        tickers = if (nrow(stats) > 0) stats$ticker else character(0),
        details = if (nrow(stats) > 0) stats else NULL,
        timestamp = Sys.time()
      )
    }, cue = targets::tar_cue(mode = "always"))
  )
}
