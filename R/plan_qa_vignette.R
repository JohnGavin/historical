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
      library(dplyr)

      duckplyr_path <- Sys.glob("/nix/store/*-r-duckplyr-*/library")
      duckplyr_path <- duckplyr_path[file.exists(file.path(duckplyr_path, "duckplyr"))]
      if (length(duckplyr_path) > 0) .libPaths(c(.libPaths(), duckplyr_path[[1]]))

      datasets <- c("equity_daily", "crypto_daily")
      meta_ds <- hd_datasets()[["metadata"]]
      issues <- list()

      for (ds_name in datasets) {
        ds <- hd_datasets()[[ds_name]]
        if (is.null(ds)) next

        ohlcv_tickers <- duckplyr::read_parquet_duckdb(ds$url) |>
          distinct(ticker) |> collect() |> pull(ticker)
        meta_tickers <- duckplyr::read_parquet_duckdb(meta_ds$url) |>
          filter(dataset == ds_name) |>
          distinct(ticker) |> collect() |> pull(ticker)

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
      library(dplyr)

      ds <- hd_datasets()[["equity_daily"]]
      duckplyr_path <- Sys.glob("/nix/store/*-r-duckplyr-*/library")
      duckplyr_path <- duckplyr_path[file.exists(file.path(duckplyr_path, "duckplyr"))]
      if (length(duckplyr_path) > 0) .libPaths(c(.libPaths(), duckplyr_path[[1]]))

      # Per-ticker dollar volume
      ticker_stats <- duckplyr::read_parquet_duckdb(ds$url) |>
        mutate(dollar_vol = close * volume) |>
        summarise(avg_dollar_vol = mean(dollar_vol, na.rm = TRUE), .by = ticker) |>
        collect() |>
        mutate(exchange = case_when(
          grepl("\\.DE$", ticker) ~ "DE",
          grepl("\\.PA$", ticker) ~ "PA",
          grepl("\\.AS$", ticker) ~ "AS",
          grepl("\\.SW$", ticker) ~ "SW",
          grepl("\\.MC$", ticker) ~ "MC",
          grepl("\\.MI$", ticker) ~ "MI",
          grepl("\\.ST$", ticker) ~ "ST",
          grepl("\\.CO$", ticker) ~ "CO",
          grepl("\\.L$",  ticker) ~ "L",
          TRUE ~ "US"
        ))

      # Per-exchange median
      exchange_stats <- ticker_stats |>
        summarise(median_vol = median(avg_dollar_vol, na.rm = TRUE),
                  n_tickers = n(), .by = exchange)

      # Flag outliers: >50x exchange median or >$5B/day
      stats <- ticker_stats |>
        left_join(exchange_stats, by = "exchange") |>
        mutate(ratio_to_median = avg_dollar_vol / pmax(median_vol, 1)) |>
        filter(ratio_to_median > 50 | avg_dollar_vol > 5e9) |>
        arrange(desc(ratio_to_median))

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
    }, cue = targets::tar_cue(mode = "always")),

    # QA 4: HTML quality check — scan rendered HTML for common defects
    # Runs after quarto render; catches leaked code, empty tables, errors
    targets::tar_target(qa_html_quality, {
      html_dir <- here::here("docs")
      html_files <- list.files(html_dir, pattern = "\\.html$", full.names = TRUE)

      if (length(html_files) == 0) {
        cli::cli_inform(c("i" = "QA HTML: no rendered HTML files found in docs/"))
        return(list(n_files = 0L, issues = NULL, timestamp = Sys.time()))
      }

      # Patterns that should NEVER appear in deployed HTML
      error_patterns <- c(
        leaked_code  = "#\\| label|#\\| echo|#\\| results",
        raw_tar_read = "safe_tar_read|tar_read\\(",
        not_available = "not yet built|not available|MISSING EVIDENCE",
        r_error      = "Error in |Error:",
        null_output  = ">NULL<|> NULL<",
        raw_tibble   = 'class="dataframe"'
      )

      results <- lapply(html_files, function(f) {
        content <- readLines(f, warn = FALSE)
        text <- paste(content, collapse = "\n")
        counts <- vapply(error_patterns, function(pat) {
          sum(grepl(pat, content, ignore.case = FALSE))
        }, integer(1))
        tibble::tibble(
          file = basename(f),
          total_issues = sum(counts),
          leaked_code = counts[["leaked_code"]],
          raw_tar_read = counts[["raw_tar_read"]],
          not_available = counts[["not_available"]],
          r_error = counts[["r_error"]],
          null_output = counts[["null_output"]],
          raw_tibble = counts[["raw_tibble"]]
        )
      })

      report <- dplyr::bind_rows(results)
      n_issues <- sum(report$total_issues)

      if (n_issues > 0) {
        bad <- report |> dplyr::filter(total_issues > 0)
        cli::cli_warn(c(
          "!" = "QA HTML: {n_issues} issue(s) across {nrow(bad)} file(s)",
          "i" = "Files: {paste(bad$file, collapse = ', ')}"
        ))
      } else {
        cli::cli_inform(c("v" = "QA HTML: {nrow(report)} files, 0 issues"))
      }

      list(
        n_files = nrow(report),
        n_issues = n_issues,
        report = report,
        timestamp = Sys.time()
      )
    }, cue = targets::tar_cue(mode = "always"))
  )
}
