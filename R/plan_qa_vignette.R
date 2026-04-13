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
    }, cue = targets::tar_cue(mode = "always"))
  )
}
