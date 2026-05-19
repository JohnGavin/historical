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
    # Depends on all metric/leaderboard/strategy targets so tar_make() only
    # reaches this target after every upstream computation succeeds.
    # If any listed target errored, this target is skipped (not a false "QA passed").
    #
    # CANONICAL LIST — keep in sync with every tar_target(*_metrics) in R/.
    # Automated check: tests/testthat/test-qa-summary-deps.R asserts both sets match.
    # To enumerate manually (most accurate — uses the same AST extractor as the test):
    #   Rscript -e '
    #     plan_files <- list.files("R", pattern="^plan_.*\\.R$", full.names=TRUE)
    #     out <- character(0)
    #     walk <- function(e) {
    #       if (is.call(e)) {
    #         h <- e[[1L]]
    #         is_tar <- (is.symbol(h) && identical(as.character(h), "tar_target")) ||
    #           (is.call(h) && length(h)==3L && identical(h[[1L]], as.symbol("::")) &&
    #            identical(h[[2L]], as.symbol("targets")) && identical(h[[3L]], as.symbol("tar_target")))
    #         if (is_tar && length(e)>=2L && is.symbol(e[[2L]]) && grepl("_metrics$", as.character(e[[2L]])))
    #           out[[length(out)+1L]] <<- as.character(e[[2L]])
    #         for (i in seq_along(e)) walk(e[[i]])
    #       }
    #     }
    #     for (f in plan_files) { ex <- parse(file=f, keep.source=FALSE); for (e in ex) walk(e) }
    #     cat(paste(sort(unique(out)), collapse="\n"), "\n")
    #   '
    # DO NOT add a new *_metrics target without also updating this list (roborev #2788).
    targets::tar_target(qa_summary, {
      invisible(list(
        leaderboard,
        strategy_names, strategy_correlation,
        # All *_metrics targets (alphabetical — add new ones here):
        aw_metrics,
        boot_metrics,
        bt_metrics_is,
        bt_replication_metrics,
        decay_metrics,
        drif_metrics,
        etf_a_metrics,
        etf_b_metrics,
        fm_metrics,
        kelly_metrics,
        ltr_metrics,
        mr_metrics,
        ms_metrics,
        persistence_metrics,
        port_metrics,
        rafi_metrics,
        regime_metrics,
        rsc_metrics,
        stk_drif_metrics,
        stk_max_metrics,
        te_ir_metrics,
        xgb_drif_metrics
      ))
      cli::cli_inform(c("v" = "QA: all metric targets succeeded ({format(Sys.time(), '%H:%M:%S')})"))
      invisible(NULL)
    }, cue = targets::tar_cue(mode = "always")),

    # QA 2: Dataset-metadata consistency (#19)
    # Checks that every ticker in OHLCV parquets has a metadata row
    targets::tar_target(qa_metadata_sync, {
      library(dplyr)

      # Note: duckplyr/glmnet/xgboost/slider/RcppRoll are provided by the dev shell.
      # Earlier versions of this file globbed /nix/store as a fallback — removed in PR #219
      # since it re-introduced ABI-incompatible /nix/store paths (issue #211).

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
      library(dplyr)

      ds <- hd_datasets()[["equity_daily"]]
      # Note: duckplyr/glmnet/xgboost/slider/RcppRoll are provided by the dev shell.
      # Earlier versions of this file globbed /nix/store as a fallback — removed in PR #219
      # since it re-introduced ABI-incompatible /nix/store paths (issue #211).

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
        raw_tibble   = 'class="dataframe"',
        syntax_error = "Syntax error|Parse error|mermaid version",
        broken_image = "broken-image|img-error"
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
