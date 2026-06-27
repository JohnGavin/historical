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
    #
    # IMPORTANT: Only plan files that are source()d in docs/_targets.R belong here.
    # Plan files that exist on disk but are NOT sourced (e.g. plan_te_ir.R,
    # plan_integration.R) are excluded — their targets never enter the live pipeline.
    #
    # To enumerate manually (most accurate — uses the same AST extractor as the test):
    #   Rscript -e '
    #     targets_r <- readLines("docs/_targets.R")
    #     sourced <- regmatches(targets_r, regexpr("R/plan_[^\"]+\\.R", targets_r))
    #     plan_files <- file.path(here::here(), sourced)
    #     plan_files <- plan_files[file.exists(plan_files)]
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
        olmar_metrics,
        persistence_metrics,
        port_metrics,
        rafi_metrics,
        regime_metrics,
        rsc_metrics,
        stk_drif_metrics,
        stk_max_metrics,
        tom_metrics,
        xgb_drif_metrics
      ))

      # Validate QA sub-targets.  Each returns a list with at minimum an
      # $n_issues or $issues field.  Collect any failures and abort once so
      # the developer sees all problems in one run.
      qa_failures <- character(0)

      if (isTRUE(qa_metadata_sync$issues > 0)) {
        qa_failures <- c(qa_failures,
          sprintf("qa_metadata_sync: %d dataset issue(s)", qa_metadata_sync$issues))
      }
      if (isTRUE(qa_volume_sanity$flagged > 0)) {
        qa_failures <- c(qa_failures,
          sprintf("qa_volume_sanity: %d ticker(s) with suspicious volume", qa_volume_sanity$flagged))
      }
      if (isTRUE(qa_html_quality$n_issues > 0)) {
        qa_failures <- c(qa_failures,
          sprintf("qa_html_quality: %d HTML issue(s) across %d file(s)",
                  qa_html_quality$n_issues, qa_html_quality$n_files))
      }

      if (length(qa_failures) > 0L) {
        cli::cli_abort(c(
          "x" = "QA summary: {length(qa_failures)} QA target(s) reported failures:",
          setNames(qa_failures, rep("i", length(qa_failures)))
        ))
      }

      cli::cli_inform(c("v" = "QA: all metric targets succeeded ({format(Sys.time(), '%H:%M:%S')})"))
      invisible(NULL)
    }, cue = targets::tar_cue(mode = "always")),

    # QA 2: Dataset-metadata consistency (#19)
    # Checks that every ticker in OHLCV parquets has a metadata row.
    # MISSING (OHLCV ticker without metadata) is a hard failure: downstream
    # joins on metadata silently drop those tickers.
    # ORPHANS (metadata row with no OHLCV) are informational only: they are
    # stale metadata for tickers whose OHLCV fetch has not yet run or was
    # de-listed. They do NOT increment the gate's issues count (#489).
    targets::tar_target(qa_metadata_sync, {
      library(dplyr)

      # Note: duckplyr/glmnet/xgboost/slider/RcppRoll are provided by the dev shell.
      # Earlier versions of this file globbed /nix/store as a fallback — removed in PR #219
      # since it re-introduced ABI-incompatible /nix/store paths (issue #211).

      datasets <- c("equity_daily", "crypto_daily")
      meta_ds <- hd_datasets()[["metadata"]]
      issues <- list()
      n_missing_issues <- 0L  # only missing counts toward gate failure
      n_orphan_issues  <- 0L  # informational only

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
          cli::cli_warn(c(
            "!" = "{ds_name}: {length(missing)} tickers in OHLCV but not metadata",
            "i" = "Missing: {paste(head(missing, 10), collapse = ', ')}{if (length(missing) > 10) '...' else ''}",
            ">" = "Run: python scripts/fetch_metadata.py (after adding tickers to the script's lists)"
          ))
          issues[[paste0(ds_name, "_missing")]] <- missing
          n_missing_issues <- n_missing_issues + 1L
        }
        if (length(orphans) > 0) {
          # Orphans are informational: stale metadata rows with no OHLCV.
          # They do NOT break downstream joins and are NOT counted in issues.
          cli::cli_inform(c(
            "i" = "{ds_name}: {length(orphans)} orphan metadata entries (no OHLCV data)",
            " " = "Orphans are stale metadata (pending-fetch or de-listed tickers) — not a gate failure."
          ))
          issues[[paste0(ds_name, "_orphans")]] <- orphans
          n_orphan_issues <- n_orphan_issues + 1L
        }
      }

      if (n_missing_issues == 0L && n_orphan_issues == 0L) {
        cli::cli_inform(c("v" = "QA metadata sync: all datasets consistent"))
      } else if (n_missing_issues == 0L) {
        cli::cli_inform(c("v" = "QA metadata sync: no missing metadata ({n_orphan_issues} orphan dataset(s) — informational only)"))
      }

      list(
        checked   = length(datasets),
        issues    = n_missing_issues,   # gate-breaking: OHLCV tickers without metadata
        n_orphans = n_orphan_issues,    # informational: metadata rows with no OHLCV
        details   = lapply(issues, length),
        timestamp = Sys.time()
      )
    }, cue = targets::tar_cue(mode = "always")),

    # QA 3: Volume sanity check (#21)
    # yfinance reports incorrect volume for non-US markets (London, XETRA, etc.).
    # Fix: null non-US avg_dollar_vol AFTER the DuckDB summarisation so the heavy
    # per-row computation stays in DuckDB. Then filter to only reliable-volume
    # (non-NA) tickers before flagging.
    # Calibration (#489): drop the >$5B/day absolute threshold — it false-flagged
    # US mega-caps (SPY $17B, TSLA $10B, QQQ $7B) whose ratio-to-US-median is
    # well under 50x. The ratio check alone (>50x within-exchange) is sufficient
    # once all non-US corrupt volume is excluded. Expected flagged count ≈ 0 on
    # current data.
    targets::tar_target(qa_volume_sanity, {
      library(dplyr)

      ds <- hd_datasets()[["equity_daily"]]

      # Step 1: per-ticker average dollar volume — computed in DuckDB (efficient).
      # Volume for non-US tickers is corrupt in yfinance but we don't null here;
      # we null AFTER collect so the regex helper runs in R.
      ticker_stats <- duckplyr::read_parquet_duckdb(ds$url) |>
        mutate(dollar_vol = close * volume) |>
        summarise(avg_dollar_vol = mean(dollar_vol, na.rm = TRUE), .by = ticker) |>
        collect() |>
        mutate(
          # #21: null non-US avg_dollar_vol after collect (raw parquet preserved).
          # hd_unreliable_volume_ticker() must be loaded via pkgload before this target runs.
          avg_dollar_vol = dplyr::if_else(
            hd_unreliable_volume_ticker(ticker),
            NA_real_,
            avg_dollar_vol
          ),
          exchange = case_when(
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
          )
        ) |>
        # Exclude tickers with no reliable volume (non-US, all NA after nulling)
        filter(!is.na(avg_dollar_vol))

      # Step 2: per-exchange median (now only reliable-volume tickers remain)
      exchange_stats <- ticker_stats |>
        summarise(median_vol = median(avg_dollar_vol, na.rm = TRUE),
                  n_tickers = n(), .by = exchange)

      # Step 3: flag outliers — only ratio check; absolute dollar threshold dropped
      # (#489: removed >$5B/day which false-flagged SPY/QQQ/TSLA).
      # Ratio >50x within-exchange is sufficient: US mega-cap ETFs are 5-20x median,
      # not 50x, so they pass cleanly.
      stats <- ticker_stats |>
        left_join(exchange_stats, by = "exchange") |>
        mutate(ratio_to_median = avg_dollar_vol / pmax(median_vol, 1)) |>
        filter(ratio_to_median > 50) |>
        arrange(desc(ratio_to_median))

      if (nrow(stats) > 0) {
        cli::cli_warn(c(
          "!" = "QA volume: {nrow(stats)} ticker(s) with suspicious dollar volume (>50x exchange median)",
          "i" = "Only reliable-volume tickers are evaluated (non-US volume is nulled per #21).",
          "i" = paste(head(stats$ticker, 10), collapse = ", ")
        ))
      } else {
        cli::cli_inform(c("v" = "QA volume: no outliers detected (non-US volume excluded per #21)"))
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
