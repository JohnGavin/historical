# Plan: Interval Coverage QA Gate (#597)
#
# Asks the question nobody had asked of our published intervals: do they
# contain outcomes at the rate they claim?
#
# R/plan_bootstrap_ci.R publishes 5th-95th percentile intervals on Sharpe per
# strategy, and R/plan_leaderboard.R joins them onto the leaderboard including
# the ci_crosses_zero flag we use to call a strategy noise. Until now nothing
# checked them.
#
# Origin: https://statmodeling.stat.columbia.edu/2026/07/29/over-coverage-caught-by-pre-registration-47-of-56-inside-a-stated-50-interval/
# — where stated 50% intervals contained 83.9% of outcomes because interval
# width ignored the volatility regime.
#
# ── Two readings of the same interval ──────────────────────────────────────
#
# A bootstrap CI is an interval on the *estimator* — where the long-run Sharpe
# of this return series plausibly sits. A leaderboard reader almost always
# reads it as a *predictive* interval — where next year's Sharpe will land.
# Those are different targets with very different variance, and the second is
# far wider than the first.
#
# This plan measures both:
#   coverage_pred — does the CI contain the realised next-h-month Sharpe?
#   coverage_est  — does the CI contain the full-sample Sharpe estimate?
#
# We expect coverage_pred to come out well below nominal. That is not
# primarily a bug in the bootstrap; it is evidence that the leaderboard's
# presentation invites a category error. The gap between the two numbers is
# the finding.
#
# ── No diagnostic-stratum leakage (#600) ───────────────────────────────────
#
# Every interval is built from returns strictly prior to the outcome window.
# Nothing computed inside or after the outcome window may be used to form the
# interval or to define a stratum. See the look-ahead-bias-prevention rule.
#
# ── Known upstream defect (#603) ───────────────────────────────────────────
#
# boot_monthly_returns is NOT calendar-contiguous: an inner_join across four
# strategies drops any month where one is missing (128 rows spanning ~190
# calendar months). Block resampling over that row order splices non-adjacent
# months. This plan reports the gap count rather than silently inheriting it.

plan_interval_coverage <- function() {
  list(

    # ── Parameters ─────────────────────────────────────────────────────────
    targets::tar_target(ic_params, {
      list(
        min_train = 60L,   # months before the first origin
        horizon   = 12L,   # months in the outcome window
        step      = 1L,    # months between origins
        # 500 draws is ample for a 5th/95th percentile bound and keeps the
        # walk-forward (origins x strategies x draws) to a sane runtime.
        n_draws   = 500L,
        seed      = 42L
      )
    }),

    # ── Contiguity report (#603) ───────────────────────────────────────────
    # Surfaces the gap defect in pipeline output instead of letting the
    # coverage number silently absorb it.
    targets::tar_target(ic_contiguity, {
      d <- as.Date(paste0(boot_monthly_returns$ym, "-01"))
      d <- sort(d)
      span_months <- length(seq(min(d), max(d), by = "month"))
      n_rows <- length(d)

      out <- tibble::tibble(
        n_rows           = as.integer(n_rows),
        calendar_months  = as.integer(span_months),
        missing_months   = as.integer(span_months - n_rows),
        pct_missing      = round(100 * (span_months - n_rows) / span_months, 1),
        first_ym         = format(min(d), "%Y-%m"),
        last_ym          = format(max(d), "%Y-%m")
      )

      if (out$missing_months > 0L) {
        cli::cli_warn(c(
          "!" = "boot_monthly_returns is not calendar-contiguous: {out$n_rows} rows over {out$calendar_months} months ({out$pct_missing}% missing).",
          "i" = "Block resampling splices non-adjacent months. See issue #603.",
          "i" = "Coverage numbers below inherit this defect."
        ))
      }
      out
    }, cue = targets::tar_cue(mode = "always")),

    # ── Walk-forward: one interval per origin per strategy ─────────────────
    targets::tar_target(ic_walkforward, {
      returns_tbl <- boot_monthly_returns |> dplyr::arrange(ym)
      strat_names <- setdiff(names(returns_tbl), "ym")

      n <- nrow(returns_tbl)
      p <- ic_params
      last_origin <- n - p$horizon

      if (last_origin < p$min_train) {
        cli::cli_inform(c(
          "i" = "ic_walkforward: {n} months is too few for min_train={p$min_train} + horizon={p$horizon}.",
          "i" = "Returning zero rows; the coverage gate will report insufficient_data."
        ))
        return(tibble::tibble(
          strategy = character(), origin_ym = character(), train_n = integer(),
          sharpe_lo = numeric(), sharpe_hi = numeric(),
          realised_sharpe = numeric(), fullsample_sharpe = numeric()
        ))
      }

      origins <- seq(p$min_train, last_origin, by = p$step)

      # Same geometric Sharpe as plan_bootstrap_ci.R / hd_block_boot_sharpe_ci.
      sharpe_of <- function(x) {
        x <- x[!is.na(x)]
        if (length(x) < 2L) return(NA_real_)
        vol <- stats::sd(x) * sqrt(12)
        if (!is.finite(vol) || vol <= 0) return(NA_real_)
        (prod(1 + x)^(12 / length(x)) - 1) / vol
      }

      rows <- lapply(strat_names, function(s) {
        ret_all <- returns_tbl[[s]]
        full_sharpe <- sharpe_of(ret_all)

        per_origin <- lapply(origins, function(t) {
          # Interval uses ONLY returns 1..t — strictly prior to the outcome
          # window t+1..t+horizon. Do not widen this slice (#600).
          train <- ret_all[seq_len(t)]
          outcome <- ret_all[(t + 1L):(t + p$horizon)]

          ci <- hd_block_boot_sharpe_ci(
            train,
            n_draws    = p$n_draws,
            block_size = boot_params$block_size,
            ci_lo      = boot_params$ci_lo,
            ci_hi      = boot_params$ci_hi,
            # Vary the seed per origin so draws are not identical across the
            # walk-forward, while keeping the whole target reproducible.
            seed       = p$seed + t
          )

          tibble::tibble(
            strategy          = s,
            origin_ym         = returns_tbl$ym[t],
            train_n           = as.integer(t),
            sharpe_lo         = ci$sharpe_lo,
            sharpe_hi         = ci$sharpe_hi,
            realised_sharpe   = sharpe_of(outcome),
            fullsample_sharpe = full_sharpe
          )
        })
        dplyr::bind_rows(per_origin)
      })

      dplyr::bind_rows(rows)
    }),

    # ── Coverage summary ───────────────────────────────────────────────────
    # Reported PER STRATEGY, never pooled. Pooling four correlated strategies
    # into one binomial would inflate the effective sample size — the exact
    # error the source post makes. Cross-sectional pooling needs K_eff_xs
    # (#601) before it is defensible.
    targets::tar_target(qa_interval_coverage, {
      nominal <- boot_params$ci_hi - boot_params$ci_lo
      overlap <- ic_params$horizon / ic_params$step

      if (nrow(ic_walkforward) == 0L) {
        cli::cli_warn("qa_interval_coverage: no walk-forward rows; gate is uninformative.")
        return(tibble::tibble(
          strategy = character(), reading = character(), n = integer(),
          n_eff = numeric(), n_covered = integer(), coverage = numeric(),
          nominal = numeric(), excess = numeric(), mean_width = numeric(),
          mean_interval_score = numeric(), p_binom_eff = numeric(),
          fpr_equipoise = numeric(), verdict = character()
        ))
      }

      strat_names <- unique(ic_walkforward$strategy)

      summarise_one <- function(s, reading) {
        d <- ic_walkforward |> dplyr::filter(strategy == s)
        y <- if (reading == "predictive") d$realised_sharpe else d$fullsample_sharpe
        res <- hd_interval_coverage(
          y       = y,
          lower   = d$sharpe_lo,
          upper   = d$sharpe_hi,
          nominal = nominal,
          # The estimator reading compares against a single fixed number, so
          # the windows are not overlapping in the same sense; but the
          # intervals themselves still share training data, so the same
          # overlap discount is the conservative choice.
          overlap = overlap
        )
        dplyr::bind_cols(tibble::tibble(strategy = s, reading = reading), res)
      }

      out <- dplyr::bind_rows(
        lapply(strat_names, summarise_one, reading = "predictive"),
        lapply(strat_names, summarise_one, reading = "estimator")
      )

      flagged <- out |> dplyr::filter(verdict %in% c("over_covered", "under_covered"))
      if (nrow(flagged) > 0L) {
        cli::cli_warn(c(
          "!" = "Interval coverage inconsistent with nominal for {nrow(flagged)} strategy-reading pair{?s}.",
          "i" = "{paste(flagged$strategy, flagged$reading, paste0(round(100 * flagged$coverage, 1), '%'), flagged$verdict, collapse = '; ')}",
          "i" = "Nominal is {round(100 * nominal)}%. Over-coverage is a defect too - see issue #597."
        ))
      }

      # Deliberately does NOT abort. At n_eff of roughly
      # (origins / horizon) this gate is under-powered by construction; a
      # hard failure would be noise. Revisit once #602 supplies a faster
      # substrate.
      out
    }, cue = targets::tar_cue(mode = "always")),

    # ── Dynamic caption ────────────────────────────────────────────────────
    targets::tar_target(ic_caption, {
      if (nrow(qa_interval_coverage) == 0L) {
        return(paste0(
          "Interval coverage gate: insufficient data. ",
          "boot_monthly_returns has too few months for a ",
          ic_params$horizon, "-month walk-forward with a ",
          ic_params$min_train, "-month minimum training window."
        ))
      }

      pred <- qa_interval_coverage |> dplyr::filter(reading == "predictive")
      est  <- qa_interval_coverage |> dplyr::filter(reading == "estimator")
      nominal_pct <- round(100 * pred$nominal[1])

      paste0(
        "Realised coverage of the block-bootstrap Sharpe intervals published on ",
        "the leaderboard, measured by walk-forward over ",
        nrow(ic_walkforward) / length(unique(ic_walkforward$strategy)),
        " origins per strategy (minimum training window ", ic_params$min_train,
        " months, outcome horizon ", ic_params$horizon, " months, step ",
        ic_params$step, " month). Stated coverage is ", nominal_pct, "%. ",
        "Predictive reading (does the interval contain the realised next-",
        ic_params$horizon, "-month Sharpe?): ",
        paste0(pred$strategy, " ", round(100 * pred$coverage, 1), "%",
               collapse = ", "), ". ",
        "Estimator reading (does it contain the full-sample Sharpe?): ",
        paste0(est$strategy, " ", round(100 * est$coverage, 1), "%",
               collapse = ", "), ". ",
        "The estimator reading is optimistic by construction - the full-sample ",
        "Sharpe includes the outcome window - so treat it as an upper bound. ",
        "Effective sample size is ", round(pred$n_eff[1], 1), " per strategy ",
        "against a nominal ", pred$n[1], " origins, because ",
        ic_params$horizon, "-month windows stepped monthly overlap ",
        ic_params$horizon, "-deep; p-values are computed on the effective ",
        "count, not the nominal one. ",
        "Lower interval score is better; it penalises width and misses jointly, ",
        "which coverage alone cannot. ",
        "Sources: [plan_interval_coverage.R](https://github.com/JohnGavin/historical/blob/main/R/plan_interval_coverage.R#L1), ",
        "[hd_interval_coverage()](https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/calibration.R#L184), ",
        "[hd_block_boot_sharpe_ci()](https://github.com/JohnGavin/historical/blob/main/packages/historicaldata/R/calibration.R#L279). ",
        "See issues #597 (this gate), #599 (regime-conditional width), ",
        "#603 (calendar gaps in the input)."
      )
    })
  )
}
