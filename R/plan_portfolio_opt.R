# Portfolio optimisation with PSO for strategy combination (#32)
#
# Finds optimal weights across 4+ strategies using Particle Swarm
# Optimisation (PSO). Constraints: weights sum to 1, max single
# strategy weight, optional long-short.
#
# Reference: https://rtichoke.netlify.app/posts/portfolio_optimisation_pso.html
#
# Key principle: optimise on TRAINING data only. Evaluate on TESTING.
# Validate once on VALIDATION (sealed envelope).

plan_portfolio_opt <- function() {
  list(
    # ── Portfolio optimisation parameters ──────────────────────────
    targets::tar_target(port_params, {
      list(
        max_weight = 0.5,      # no single strategy > 50%
        min_weight = 0.0,      # no shorting strategies
        target = "sharpe",     # optimise for Sharpe ratio
        n_particles = 50L,     # PSO particles
        max_iter = 200L        # PSO iterations
      )
    }),

    # ── Combine all strategy returns into one matrix ──────────────
    #
    # #641: this used to be a 4-way inner_join chain, so any `ym` missing
    # from ANY ONE of the four constituents silently deleted that month for
    # ALL FOUR -- 128 of an expected ~190+ rows, including every March
    # (`stk_drif_portfolio` had no March rows at all; the upstream root
    # cause is tracked and fixed separately in R/plan_stock_backtest.R,
    # not here).
    #
    # The spine is now an explicit CALENDAR-COMPLETE monthly sequence
    # bounded by the OVERLAP of the two stock-level series' own date ranges
    # (`max(min(s1$ym), min(s2$ym))` .. `min(max(s1$ym), max(s2$ym))`), not
    # a plain union of whatever rows happen to exist. This matters because:
    #   - Using `seq()` to build the spine (rather than the literal ym
    #     values present in s1/s2) is what actually fixes #641 -- a month
    #     entirely absent from a constituent (e.g. every March in
    #     stk_drif_portfolio) still gets a spine row, with that constituent
    #     left NA rather than the row never existing.
    #   - Bounding to the stock-level OVERLAP (not the union) keeps the
    #     span close to the historical inner_join's implicit intersection.
    #     fac_max / fac_drif (data from 1964-/1968- onward) run six decades
    #     longer than stk_max / stk_drif (2005-/2010- onward); a plain
    #     `full_join` across all four would silently expand `port_returns`,
    #     and every "Full Period" metric/plot downstream, to include
    #     decades where no stock-level strategy exists -- a different,
    #     much bigger analysis than the 4-strategy stock+factor combination
    #     this target is for. It would also introduce a large block of NA
    #     into `stk_drif` (or `stk_max`, whichever starts later) for every
    #     pre-overlap month, which downstream consumers that read
    #     `port_returns` directly and do a *plain* `ret_matrix %*% w` (not
    #     the NA-aware `.port_weighted_return()` below) -- e.g.
    #     R/plan_regime.R's `regime_vol`/`regime_portfolio` -- are not
    #     written to expect.
    # Factor-level series are LEFT-joined onto that stock-bounded spine:
    # they cover the whole overlap window so this introduces no new NAs in
    # practice, but a genuine internal gap in either of them, or the normal
    # live-edge lag between stock-level and factor-level data feeds (the
    # most recent 1-2 months at the time of writing), now surfaces as an
    # honest NA in that column instead of silently deleting the row.
    #
    # A missing constituent is therefore an explicit NA in its own column,
    # never a deleted row. See `.port_weighted_return()` below for how
    # `port_combined` turns a row with one or more NA constituents into a
    # single portfolio return, and `check_portfolio_join_coverage()`
    # (R/plan_qa_gates.R) for the pipeline assertion guarding against a
    # calendar-month gap reappearing.
    targets::tar_target(port_returns, {
      library(dplyr)

      # Collect all strategy monthly returns
      s1 <- stk_max_portfolio |> select(ym, stk_max = port_ret)
      s2 <- stk_drif_portfolio |> select(ym, stk_drif = port_ret)
      s3 <- fm_portfolio |> select(ym, fac_max = portfolio_ret)
      s4 <- drif_portfolio |> select(ym, fac_drif = portfolio_ret)

      # Calendar-complete monthly spine bounded to the stock-level overlap
      # window (see comment above) -- NOT the literal set of ym values
      # present in s1/s2, which is exactly what would silently re-drop a
      # month like March if stk_drif_portfolio ever loses it again.
      spine_start <- max(min(s1$ym), min(s2$ym))
      spine_end   <- min(max(s1$ym), max(s2$ym))
      spine <- tibble::tibble(
        ym = format(
          seq(as.Date(paste0(spine_start, "-01")),
              as.Date(paste0(spine_end, "-01")),
              by = "month"),
          "%Y-%m"
        )
      )

      combined <- spine |>
        left_join(s1, by = "ym") |>
        left_join(s2, by = "ym") |>
        left_join(s3, by = "ym") |>
        left_join(s4, by = "ym")

      # Add risk-free
      combined |>
        left_join(stk_rf, by = "ym") |>
        mutate(date = as.Date(paste0(ym, "-15"))) |>
        arrange(date)
    }),

    # ── PSO optimisation on training data ─────────────────────────
    targets::tar_target(port_optimal_weights, {
      library(dplyr)

      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
      train <- port_returns |> filter(date <= stk_params$is_end)

      if (nrow(train) < 24) {
        cli::cli_warn("Not enough training data for portfolio optimisation")
        return(setNames(rep(0.25, 4), strat_cols))
      }

      ret_matrix <- as.matrix(train[, strat_cols])
      rf_vec <- train$rf_ret
      # Remove rows with NA
      complete <- complete.cases(ret_matrix, rf_vec)
      ret_matrix <- ret_matrix[complete, , drop = FALSE]
      rf_vec <- rf_vec[complete]

      # Objective: maximise Sharpe ratio
      neg_sharpe <- function(w) {
        w <- w / sum(w)  # normalise to sum=1
        port_ret <- as.numeric(ret_matrix %*% w)
        n <- length(port_ret)
        ann_ret <- prod(1 + port_ret)^(12/n) - 1
        ann_vol <- sd(port_ret) * sqrt(12)
        rf_ann <- mean(rf_vec, na.rm = TRUE) * 12
        if (ann_vol < 1e-8) return(1e6)
        -((ann_ret - rf_ann) / ann_vol)
      }

      # PSO or grid search (PSO needs pso package, fallback to grid)
      if (requireNamespace("pso", quietly = TRUE)) {
        result <- pso::psoptim(
          par = rep(0.25, 4),
          fn = neg_sharpe,
          lower = rep(port_params$min_weight, 4),
          upper = rep(port_params$max_weight, 4),
          control = list(
            maxit = port_params$max_iter,
            s = port_params$n_particles,
            trace = FALSE
          )
        )
        weights <- result$par / sum(result$par)
      } else {
        # Grid search fallback (coarse but correct)
        cli::cli_inform("pso not installed — using grid search")
        grid <- expand.grid(
          w1 = seq(0, 0.5, 0.1),
          w2 = seq(0, 0.5, 0.1),
          w3 = seq(0, 0.5, 0.1),
          w4 = seq(0, 0.5, 0.1)
        )
        grid <- grid[abs(rowSums(grid) - 1) < 0.05, ]  # allow small tolerance
        if (nrow(grid) == 0) {
          # Fallback: equal weight
          weights <- rep(0.25, 4)
        } else {
          sharpes <- apply(grid, 1, function(w) {
            w <- w / sum(w)
            -neg_sharpe(w)
          })
          best <- grid[which.max(sharpes), ]
          weights <- as.numeric(best) / sum(as.numeric(best))
        }
      }

      setNames(weights, strat_cols)
    }),

    # ── HRP weights on training data (Lopez de Prado 2016) ────────
    targets::tar_target(port_hrp_weights, {
      library(dplyr)

      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
      train <- port_returns |> filter(date <= stk_params$is_end)

      if (nrow(train) < 24) {
        cli::cli_warn("Not enough training data for HRP")
        return(setNames(rep(0.25, 4), strat_cols))
      }

      ret_matrix <- as.matrix(train[, strat_cols])
      ret_matrix <- ret_matrix[complete.cases(ret_matrix), , drop = FALSE]

      if (!requireNamespace("HierPortfolios", quietly = TRUE)) {
        cli::cli_warn("HierPortfolios not installed - falling back to equal weight")
        return(setNames(rep(0.25, 4), strat_cols))
      }

      # ret_matrix is already complete-cased on the line above; no NA warning fires (#498).
      cov_mat <- hd_cov_estimate(ret_matrix, method = COV_METHOD, lw_target = COV_LW_TARGET)
      # HRP_Portfolio returns a data.frame with a 'weights' column,
      # rownames match colnames of cov_mat.
      hrp_result <- HierPortfolios::HRP_Portfolio(cov_mat)
      w <- hrp_result$weights
      names(w) <- strat_cols
      w / sum(w)
    }),

    # ── Portfolio returns with optimal weights ────────────────────
    #
    # #641: port_returns can now carry an explicit NA for a constituent
    # that is missing that month (see the port_returns target above). A
    # plain `ret_matrix %*% w` would turn any such NA into an NA for the
    # WHOLE portfolio return that month -- and because cumprod() propagates
    # NA forward to every subsequent element, one missing constituent would
    # silently NA out the rest of optimal_cum/hrp_cum/equalwt_cum too.
    # `.port_weighted_return()` instead renormalises the target weight
    # vector over the strategies actually present that month (a missing
    # strategy contributes zero and present strategies are rescaled to sum
    # to 1) with a floor of 2 strategies required -- see its roxygen doc
    # below for the full rationale and the guard against a 1-strategy month
    # masquerading as a diversified portfolio. `port_metrics`'s
    # `calc_port_metrics()` below drops any remaining NA before computing
    # cagr/vol/sharpe/max_dd so a handful of live-edge NA months cannot
    # poison the whole-sample metrics.
    targets::tar_target(port_combined, {
      library(dplyr)

      strat_cols <- c("stk_max", "stk_drif", "fac_max", "fac_drif")
      w_pso <- port_optimal_weights
      w_hrp <- port_hrp_weights
      w_eq  <- stats::setNames(rep(1 / length(strat_cols), length(strat_cols)), strat_cols)

      ret_matrix <- as.matrix(port_returns[, strat_cols])
      pso_ret <- .port_weighted_return(ret_matrix, w_pso)
      hrp_ret <- .port_weighted_return(ret_matrix, w_hrp)
      eq_ret  <- .port_weighted_return(ret_matrix, w_eq)

      port_returns |>
        mutate(
          optimal_ret = pso_ret,
          hrp_ret     = hrp_ret,
          equalwt_ret = eq_ret,
          optimal_cum = cumprod(1 + optimal_ret),
          hrp_cum     = cumprod(1 + hrp_ret),
          equalwt_cum = cumprod(1 + equalwt_ret)
        )
    }),

    # ── Portfolio metrics ─────────────────────────────────────────
    targets::tar_target(port_metrics, {
      library(dplyr)

      # #641: optimal_ret/hrp_ret/equalwt_ret can now contain NA for months
      # where fewer than 2 of the 4 constituent strategies reported a value
      # (see .port_weighted_return() used by the port_combined target
      # above). cumprod() propagates NA forward to every SUBSEQUENT
      # element, so computing cagr/vol/sharpe/max_dd on the raw column
      # would silently NA-poison the whole metric from the first gap
      # onward. Each helper below drops NA returns for its own column
      # before computing, and annualises using that column's own non-NA
      # month count (not the shared `n`) -- `months` stays nrow(df), the
      # calendar span of the period, for readability.
      cagr_of <- function(r) {
        r <- r[!is.na(r)]
        if (length(r) < 1) return(NA_real_)
        prod(1 + r)^(12 / length(r)) - 1
      }
      vol_of <- function(r) {
        r <- r[!is.na(r)]
        if (length(r) < 2) return(NA_real_)
        sd(r) * sqrt(12)
      }
      sharpe_of <- function(r, rf_ann) {
        r <- r[!is.na(r)]
        if (length(r) < 2) return(NA_real_)
        ann <- prod(1 + r)^(12 / length(r)) - 1
        v <- sd(r) * sqrt(12)
        if (v < 1e-8) NA_real_ else (ann - rf_ann) / v
      }
      maxdd_of <- function(r) {
        r <- r[!is.na(r)]
        if (length(r) < 1) return(NA_real_)
        cum <- cumprod(1 + r)
        min(cum / cummax(cum) - 1)
      }
      calc_port_metrics <- function(df, label) {
        n <- nrow(df)
        if (n < 12) return(NULL)
        rf_ann <- mean(df$rf_ret, na.rm = TRUE) * 12
        tibble(
          period = label, months = n,
          opt_cagr   = cagr_of(df$optimal_ret),
          opt_vol    = vol_of(df$optimal_ret),
          opt_sharpe = sharpe_of(df$optimal_ret, rf_ann),
          opt_maxdd  = maxdd_of(df$optimal_ret),
          hrp_cagr   = cagr_of(df$hrp_ret),
          hrp_sharpe = sharpe_of(df$hrp_ret, rf_ann),
          hrp_maxdd  = maxdd_of(df$hrp_ret),
          eq_cagr    = cagr_of(df$equalwt_ret),
          eq_sharpe  = sharpe_of(df$equalwt_ret, rf_ann),
          eq_maxdd   = maxdd_of(df$equalwt_ret),
          # ann_rf published alongside opt_sharpe (#677 slice 4). All three
          # sharpe_of() calls above share this SAME rf_ann (one risk-free
          # rate per period, not per weighting scheme), so a single ann_rf
          # column is correct here -- it is specifically the rate behind
          # opt_sharpe, which is the only one of the three that reaches the
          # leaderboard as "PSO Optimal" (R/plan_leaderboard.R port_row).
          # FRACTION convention (port_metrics is never *100 -- see
          # R/plan_leaderboard.R port_row, which uses opt_cagr/opt_vol/
          # opt_sharpe/opt_maxdd unconverted) -- QA gate S17
          # (check_leaderboard_sharpe_coherence(), R/plan_qa_gates.R) asserts
          # sharpe == (cagr - ann_rf) / vol for every leaderboard row.
          ann_rf     = rf_ann
        )
      }

      # #666: Holdout (2024-01-01..2026-04-30, observed but not sealed) --
      # so the "PSO Optimal" Holdout base row (R/plan_leaderboard.R's
      # `port_row`) exists to match the pso_cost Holdout row emitted by
      # slice_portfolio() and survives the left_join instead of being
      # silently dropped (the #660 KNOWN GAP).
      bind_rows(
        calc_port_metrics(port_combined |> filter(date <= stk_params$is_end), "Training"),
        calc_port_metrics(port_combined |> filter(date >= stk_params$test_start, date <= stk_params$test_end), "Testing"),
        calc_port_metrics(port_combined |> filter(date >= stk_params$holdout_start, date <= stk_params$holdout_end), "Holdout"),
        calc_port_metrics(port_combined |> filter(date >= stk_params$val_start), "Validation"),
        calc_port_metrics(port_combined, "Full Period")
      )
    }),

    # ── Comparison plot ───────────────────────────────────────────
    targets::tar_target(port_comparison_plot, {
      library(ggplot2)
      library(dplyr)
      library(scales)

      w_pso <- port_optimal_weights
      w_hrp <- port_hrp_weights
      w_label <- paste0(
        "PSO: ", paste(names(w_pso), paste0(round(w_pso * 100), "%"), sep = "=", collapse = ", "),
        "  |  HRP: ", paste(names(w_hrp), paste0(round(w_hrp * 100), "%"), sep = "=", collapse = ", ")
      )

      plot_data <- port_combined |>
        select(date,
               `PSO Optimal` = optimal_cum,
               HRP           = hrp_cum,
               `Equal Weight` = equalwt_cum) |>
        tidyr::pivot_longer(-date, names_to = "portfolio", values_to = "growth")

      ggplot(plot_data, aes(date, growth, colour = portfolio)) +
        geom_line(linewidth = 0.6) +
        geom_vline(xintercept = stk_params$test_start, linetype = "dashed",
                   colour = "grey50", linewidth = 0.4) +
        scale_y_log10(labels = dollar) +
        scale_colour_manual(values = hd_palette(3)) +
        labs(x = NULL, y = "Growth of $1 (log scale)", colour = NULL,
             title = "Portfolio: PSO vs HRP vs Equal Weight",
             subtitle = w_label) +
        hd_theme()
    }),

    # ── Registry sentinel (#442 Tier 3) ──────────────────────────────────────
    # Upserts bt.strategy row for "pso_optimal", records one bt.run + bt.metric
    # rows (Full Period PSO-optimal columns from port_metrics).
    # Returns tibble(strategy_id, run_uuid).
    # Guard: returns empty tibble if DBI / duckdb are unavailable.
    # Note: port_metrics columns opt_cagr/opt_vol/opt_maxdd are decimal fractions
    # (canonical unit convention). Benchmark/HRP columns are excluded; only the
    # PSO optimal series columns are stored.
    targets::tar_target(pso_optimal_register_runs, {
      .pso_optimal_register_runs(
        strategy_names = strategy_names,
        port_metrics   = port_metrics,
        port_combined  = port_combined
      )
    }),

    # ── Monthly returns heatmap table ─────────────────────────────
    targets::tar_target(port_monthly_returns, {
      library(dplyr)
      library(tidyr)

      port_combined |>
        mutate(
          year = lubridate::year(date),
          month = lubridate::month(date),
          return_pct = optimal_ret * 100
        ) |>
        select(year, month, return_pct) |>
        tidyr::complete(year, month = 1:12) |>
        pivot_wider(
          names_from = month,
          values_from = return_pct,
          names_sort = TRUE
        ) |>
        arrange(year) |>
        mutate(across(-year, ~if_else(is.na(.), NA_real_, .))) |>
        # Calculate annual return
        rowwise() |>
        mutate(
          Annual = (prod(1 + c_across(-year) / 100, na.rm = TRUE) - 1) * 100
        ) |>
        ungroup() |>
        # Rename month columns to month abbreviations
        rename(
          Year = year,
          Jan = `1`, Feb = `2`, Mar = `3`, Apr = `4`,
          May = `5`, Jun = `6`, Jul = `7`, Aug = `8`,
          Sep = `9`, Oct = `10`, Nov = `11`, Dec = `12`
        ) |>
        # Format all numeric columns to 1 decimal place
        mutate(across(-Year, ~format(round(., 1), nsmall = 1))) |>
        as_tibble()
    })
  )
}


# ── Internal helper: NA-aware weighted portfolio return (#641) ────────────────

#' Combine strategy returns into a single weighted portfolio return, one row
#' at a time, treating any NA constituent as absent rather than propagating
#' the NA to the whole row
#'
#' `port_returns` (#641) left-joins its four constituent strategies onto a
#' calendar-complete month spine bounded to the stock-level overlap window,
#' so a constituent missing that month is an explicit `NA` in its own
#' column rather than a deleted row. Plain matrix
#' multiplication (`ret_matrix %*% w`) would turn any such `NA` into `NA` for
#' the whole row regardless of that constituent's weight, and because
#' `cumprod()` propagates `NA` forward to every subsequent element, a single
#' missing constituent early in the series would silently `NA` out the rest
#' of the cumulative growth series too.
#'
#' Instead, for each row, the target weight vector `w` is renormalised over
#' the strategies actually present that month: a missing strategy
#' contributes zero and the present strategies' weights are rescaled to sum
#' to 1 (i.e. their *relative* weights are preserved, just no longer diluted
#' by a strategy that reported nothing). This is a deliberate modelling
#' choice, not an artefact of the join -- treating a missing value as a zero
#' return instead would understate the drawdown/CAGR contribution the
#' missing strategy is actually making that month (unknown, not zero).
#'
#' Guard: a month where FEWER THAN 2 of the (currently 4) strategies report
#' a value is NOT renormalised into a portfolio observation -- that would
#' silently turn into a 100%-single-strategy bet dressed up as "PSO
#' Optimal"/"HRP"/"Equal Weight". Such rows return `NA`. In the data as of
#' #641 this affects only the most recent 1-2 months, where the
#' factor-level return series (`fac_max`/`fac_drif`) lag the stock-level
#' series (`stk_max`/`stk_drif`) at the live edge -- an expected, benign
#' data-feed lag, not a defect. `calc_port_metrics()` (used by the
#' `port_metrics` target) drops any remaining NA per-column before computing
#' cagr/vol/sharpe/max_dd, so this cannot poison whole-sample metrics; the
#' `port_comparison_plot` growth chart will show a break at that row, which
#' honestly reflects "we don't know this month's return" rather than
#' inventing one.
#'
#' @param ret_matrix Numeric matrix, one column per strategy (colnames
#'   matching the names of `w`), one row per period. May contain `NA`.
#' @param w Named numeric weight vector, same names/order as
#'   `colnames(ret_matrix)`, non-negative, summing to 1 over the full set.
#' @return Numeric vector, one weighted return per row of `ret_matrix`
#'   (`NA` where fewer than 2 columns are non-NA that row, or where the
#'   available strategies' weights sum to (numerically) zero).
#' @noRd
.port_weighted_return <- function(ret_matrix, w) {
  apply(ret_matrix, 1L, function(row) {
    avail <- !is.na(row)
    if (sum(avail) < 2L) return(NA_real_)
    w_avail <- w[avail]
    w_sum <- sum(w_avail)
    if (w_sum < 1e-8) return(NA_real_)
    sum(row[avail] * w_avail) / w_sum
  })
}


# ── Internal helper ────────────────────────────────────────────────────────────
# Prefixed .pso_optimal_* (private; not exported from the package).
# Mirrors .drif_register_runs() from plan_drif.R.

#' Register PSO Optimal portfolio backtest run in the strategy registry
#'
#' @param strategy_names Tibble from the `strategy_names` target.
#' @param port_metrics Tibble from the `port_metrics` target. Full-period
#'   PSO-optimal columns (`opt_cagr`, `opt_vol`, `opt_sharpe`, `opt_maxdd`)
#'   are used for the bt.metric insert. Values are decimal fractions.
#' @param port_combined Tibble from the `port_combined` target; used to
#'   extract `optimal_ret` (monthly) for SSR/top5pct stability metrics.
#'
#' @return Tibble with columns: strategy_id, run_uuid.
#' @noRd
.pso_optimal_register_runs <- function(strategy_names, port_metrics,
                                       port_combined) {
  if (!requireNamespace("DBI", quietly = TRUE) ||
      !requireNamespace("duckdb", quietly = TRUE)) {
    return(tibble::tibble(
      strategy_id = character(),
      run_uuid    = character()
    ))
  }

  path <- historicaldata::hd_registry_path()
  historicaldata::hd_registry_init(path)
  con <- historicaldata::hd_registry_open(path, read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  strat_row <- strategy_names |>
    dplyr::filter(.data$code_name == "pso_optimal") |>
    dplyr::transmute(
      strategy_id        = .data$code_name,
      short_name         = .data$short_name,
      long_name          = .data$long_name,
      asset_class        = .data$asset_class,
      frequency          = .data$frequency,
      ann_factor         = as.integer(.data$ann_factor),
      directionality     = as.character(.data$directionality),
      liquidity_tier     = as.character(.data$liquidity_tier),
      time_horizon_days  = as.integer(.data$time_horizon_days_avg),
      trades_per_year    = as.numeric(.data$trades_per_year_avg),
      turnover_pct       = as.numeric(.data$turnover_pct_per_period_avg),
      tags               = .data$tags,
      research_paper_doi = .data$research_paper_doi
    )

  historicaldata::hd_strategy_upsert(con, strat_row)

  uu <- historicaldata::hd_run_upsert(
    con,
    strategy_id      = "pso_optimal",
    partition        = "phase1",
    pipeline_version = "phase1"
  )

  # Record Full Period PSO-optimal metrics (decimal fractions; canonical units).
  # Only store PSO columns; HRP/equal-weight columns belong to separate strategies
  # if they are ever registered.
  # Units (#640): opt_cagr/opt_vol/opt_maxdd are decimal fractions (per the
  # comment above), opt_sharpe is a scale-free ratio, months is a count.
  # ann_rf (#677 slice 4) was added to port_metrics as a decimal fraction
  # (calc_port_metrics() above, never *100) but is NOT currently selected by
  # `pso_cols` below -- unlike the other ten registry writers in this repo,
  # this one uses an explicit intersect() allow-list rather than a
  # setdiff()-based exclusion, so new columns on port_metrics do not
  # automatically flow into hd_metric_record() here. `ann_rf` is declared in
  # `pso_units` for forward-compatibility/consistency with the leaderboard's
  # unit convention, but this target does not currently attempt to write
  # ann_rf and was therefore not among the writers erroring under #691.
  full_row <- port_metrics[port_metrics$period == "Full Period", , drop = FALSE]
  if (nrow(full_row) == 1L) {
    pso_cols <- intersect(
      c("months", "opt_cagr", "opt_vol", "opt_sharpe", "opt_maxdd"),
      names(full_row)
    )
    pso_units <- c(
      months = "count", opt_cagr = "fraction", opt_vol = "fraction",
      opt_sharpe = "ratio", opt_maxdd = "fraction", ann_rf = "fraction"
    )
    if (length(pso_cols) > 0L) {
      historicaldata::hd_metric_record(
        con, uu, full_row[, pso_cols, drop = FALSE],
        units = pso_units[pso_cols]
      )
    }
  }

  # Record SSR + top5pct stability metrics (#400). Monthly: w=36, ann_factor=12.
  rets <- port_combined$optimal_ret
  rets <- rets[!is.na(rets)]
  if (length(rets) > 0L) {
    historicaldata::hd_record_stability_metrics(
      con        = con,
      run_uuid   = uu,
      returns    = rets,
      w          = 36L,
      ann_factor = 12L
    )
  }

  tibble::tibble(strategy_id = "pso_optimal", run_uuid = uu)
}
