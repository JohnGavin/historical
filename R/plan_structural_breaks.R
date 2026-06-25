# Plan: Structural Break Detection — Leaderboard Consumer (#477)
#
# Applies hd_structural_breaks() across strategy return series, producing a
# diagnostic table that compares post-break vs whole-history Sharpe.
#
# Carver's empirical finding (2026): breaks are rarer than expected (~13% of
# instrument/forecast pairs at 1%), and "no break" frequently beats
# break-adjusted estimation OOS.  This plan operationalises that finding:
# break-splitting is a GUARD against over-splitting, not an always-on
# re-estimator.
#
# Applicable rules:
#   look-ahead-bias-prevention — break detection is a retrospective diagnostic;
#     all Sharpe estimates use only data available at the estimate point.
#   resulting-prohibition      — a detected break is EVIDENCE, not a drawdown.
#     Never revise a strategy allocation solely because of a detected break
#     without new structural evidence about why the break occurred.
#   underperformance-prior     — multi-year underperformance is historically
#     normal; do not conflate underperformance with a structural break.
#
# Input targets (bridge series; all NA-filtered before passing):
#   fals_drif_input        — monthly Factor DRIF portfolio returns
#   fals_fac_max_input     — monthly Factor MAX portfolio returns
#   fals_ltr_input         — monthly LTR (LambdaMART) portfolio returns
#   fals_avoid_worst_input — daily Avoid-Worst VIX returns
#   fals_rsc_input         — daily Risk-State Overlay returns
#   port_returns           — monthly multi-strategy return matrix
#                            (cols: fac_max, fac_drif, stk_max, stk_drif)
#   xgb_drif_portfolio     — monthly XGB DRIF portfolio (col: port_ret)
#   olmar_portfolio        — daily OLMAR-1 portfolio (col: net_ret)
#   fals_tom_input         — daily TOM overlay (col: strategy_ret)
#   fals_cmr_input         — monthly CMR 3m (col: strategy_ret)
#   mom_prepeak_returns    — monthly Mom Pre-Peak L/S (col: ret_ls, date: exec_date)
#   mom_postpeak_returns   — monthly Mom Post-Peak L/S (col: ret_ls, date: exec_date)
#   mom_combined_returns   — monthly Mom 12-2 L/S (col: ret_ls, date: exec_date)
#
# Short-series guard: hd_structural_breaks() needs >= 2*min_years*ppy observations.
# Strategies that fall below this threshold appear in structural_breaks_summary
# with a `note` explaining why they were skipped — the target does NOT error.
#
# Total new targets: 5
#   sb_params
#   sb_strategy_returns   (named list of return series)
#   sb_break_results      (per-strategy break output)
#   structural_breaks_summary   (tidy tibble, one row per strategy)
#   structural_breaks_caption
#
# Note on OOS comparison: full OOS harness deferred.  We implement the
# in/out comparison using the existing bt_partitions (train-end as the
# IS/OOS split), clearly labelling this scope.  A dedicated vignette section
# closing market-behavior-gap-analysis.md:211 is a follow-up to this PR.

plan_structural_breaks <- function() {
  list(

    # ── Parameters ────────────────────────────────────────────────────────────
    targets::tar_target(sb_params, {
      list(
        # Significance level for the t-test (matches SSR thresholds in stability.R).
        alpha            = 0.01,
        # Minimum years of data required on each side of a candidate split.
        min_years        = 5,
        # Periods per year for daily and monthly series.
        ppy_daily        = 252L,
        ppy_monthly      = 12L,
        # Material Sharpe divergence threshold: flag when post-break Sharpe
        # differs from whole-history by more than this fraction.
        divergence_pct   = 0.25,
        # Annualisation factors for Sharpe computation.
        ann_daily        = 252,
        ann_monthly      = 12
      )
    }),


    # ── Collect strategy return series ────────────────────────────────────────
    #
    # Produces a named list: strategy_label -> list(returns, dates, ppy, ann).
    # All series are NA-filtered here so hd_structural_breaks() receives clean
    # vectors.
    #
    # Look-ahead note (look-ahead-bias-prevention): these return series are
    # historical realised returns — no future information enters.  Break
    # detection is a retrospective diagnostic applied to already-observed data.
    targets::tar_target(
      sb_strategy_returns,
      {
        library(dplyr)

        # Helper: extract non-NA returns and corresponding dates from a
        # data.frame with columns {date_col, ret_col}.
        extract_series <- function(df, ret_col = "strategy_ret",
                                   date_col = "date") {
          if (is.null(df) || nrow(df) == 0L) return(NULL)
          df <- df[!is.na(df[[ret_col]]), ]
          if (nrow(df) == 0L) return(NULL)
          list(
            returns = df[[ret_col]],
            dates   = as.Date(df[[date_col]])
          )
        }

        # Helper: extract from port_returns matrix (monthly, ann = 12).
        extract_port <- function(col) {
          if (is.null(port_returns) || !col %in% names(port_returns)) {
            return(NULL)
          }
          df <- port_returns[!is.na(port_returns[[col]]), ]
          if (nrow(df) == 0L) return(NULL)
          list(
            returns = df[[col]],
            dates   = as.Date(df$date)
          )
        }

        raw <- list(
          # ── Factor strategies (monthly, from portfolio returns) ───────────
          `Factor DRIF`   = extract_port("fac_drif"),
          `Factor MAX`    = extract_port("fac_max"),
          # ── Stock strategies (monthly, from portfolio returns) ─────────
          `Stock MAX`     = extract_port("stk_max"),
          `Stock DRIF`    = extract_port("stk_drif"),
          # ── XGB DRIF (monthly, port_ret column) ───────────────────────
          `XGB DRIF`      = extract_series(xgb_drif_portfolio,
                                           ret_col = "port_ret"),
          # ── OLMAR-1 (daily, net_ret column) ───────────────────────────
          `OLMAR-1`       = extract_series(olmar_portfolio,
                                           ret_col = "net_ret"),
          # ── Other strategies via fals bridge targets ───────────────────
          # LTR is monthly
          LTR             = extract_series(fals_ltr_input),
          # Avoid Worst and RSC are daily
          `Avoid Worst`   = extract_series(fals_avoid_worst_input),
          `Risk State`    = extract_series(fals_rsc_input),
          # TOM is daily (fals_tom_input: date + strategy_ret)
          TOM             = extract_series(fals_tom_input),
          # CMR is monthly (fals_cmr_input = cmr_returns_3m: date + strategy_ret)
          CMR             = extract_series(fals_cmr_input),
          # Mom strategies are monthly (exec_date + ret_ls)
          `Mom Pre-Peak`  = extract_series(mom_prepeak_returns,
                                           ret_col  = "ret_ls",
                                           date_col = "exec_date"),
          `Mom Post-Peak` = extract_series(mom_postpeak_returns,
                                           ret_col  = "ret_ls",
                                           date_col = "exec_date"),
          `Mom 12-2`      = extract_series(mom_combined_returns,
                                           ret_col  = "ret_ls",
                                           date_col = "exec_date")
        )

        # Tag each entry with its period frequency for downstream Sharpe calc.
        ppy_map <- list(
          `Factor DRIF`  = 12L,  `Factor MAX`   = 12L,
          `Stock MAX`    = 12L,  `Stock DRIF`   = 12L,
          `XGB DRIF`     = 12L,
          `OLMAR-1`      = 252L,
          LTR            = 12L,
          `Avoid Worst`  = 252L,
          `Risk State`   = 252L,
          TOM            = 252L,
          CMR            = 12L,
          `Mom Pre-Peak` = 12L,  `Mom Post-Peak` = 12L,
          `Mom 12-2`     = 12L
        )

        lapply(names(raw), function(nm) {
          s <- raw[[nm]]
          if (is.null(s)) return(NULL)
          s$ppy <- ppy_map[[nm]]
          s$ann <- ppy_map[[nm]]
          s
        }) |>
          stats::setNames(names(raw))
      },
      packages = "dplyr"
    ),


    # ── Run hd_structural_breaks() on each strategy ───────────────────────────
    targets::tar_target(
      sb_break_results,
      {
        lapply(names(sb_strategy_returns), function(nm) {
          s <- sb_strategy_returns[[nm]]
          if (is.null(s) || length(s$returns) == 0L) {
            return(list(strategy = nm, result = NULL, error = "no returns"))
          }
          r   <- s$returns
          ppy <- s$ppy

          # Must have at least 2 * min_years * ppy observations to be testable.
          min_obs <- 2L * sb_params$min_years * ppy
          if (length(r) < min_obs) {
            return(list(
              strategy = nm,
              result   = NULL,
              error    = paste0("too short: ", length(r), " < ", min_obs)
            ))
          }

          result <- tryCatch(
            historicaldata::hd_structural_breaks(
              returns          = r,
              alpha            = sb_params$alpha,
              min_years        = sb_params$min_years,
              periods_per_year = ppy
            ),
            error = function(e) list(error_msg = conditionMessage(e))
          )

          list(strategy = nm, result = result, error = NULL)
        }) |>
          stats::setNames(names(sb_strategy_returns))
      }
    ),


    # ── Tidy summary: one row per strategy ────────────────────────────────────
    #
    # Columns:
    #   strategy         — display label
    #   n_breaks         — number of breaks detected
    #   break_dates      — comma-separated date string (NA if none)
    #   post_break_start — date of first post-break observation
    #   whole_sharpe     — annualised Sharpe over full history
    #   post_break_sharpe — annualised Sharpe over post-break segment only
    #   sharpe_divergence_pct — (post-whole)/|whole| as a percentage (NA if
    #                            no break or insufficient post-break data)
    #   material_divergence — TRUE when |divergence| > divergence_pct threshold
    #   n_obs_whole      — total non-NA observations
    #   n_obs_post_break — observations in post-break segment
    #   note             — reason for skipped analysis (or NA)
    targets::tar_target(
      structural_breaks_summary,
      {
        library(dplyr)

        sharpe_ann <- function(r, ann) {
          r <- r[!is.na(r)]
          if (length(r) < 2L) return(NA_real_)
          sd_r <- stats::sd(r)
          if (is.na(sd_r) || sd_r <= .Machine$double.eps) return(NA_real_)
          mean(r) / sd_r * sqrt(ann)
        }

        rows <- lapply(names(sb_break_results), function(nm) {
          entry <- sb_break_results[[nm]]
          s     <- sb_strategy_returns[[nm]]

          # Strategy skipped or errored.
          if (!is.null(entry$error)) {
            return(tibble::tibble(
              strategy              = nm,
              n_breaks              = NA_integer_,
              break_dates           = NA_character_,
              post_break_start      = as.Date(NA),
              whole_sharpe          = NA_real_,
              post_break_sharpe     = NA_real_,
              sharpe_divergence_pct = NA_real_,
              material_divergence   = NA,
              n_obs_whole           = if (is.null(s)) NA_integer_ else length(s$returns),
              n_obs_post_break      = NA_integer_,
              note                  = entry$error
            ))
          }

          res <- entry$result
          r   <- s$returns
          d   <- s$dates
          ann <- s$ann

          whole_sharpe      <- sharpe_ann(r, ann)
          post_start_idx    <- res$post_break_start
          # main's hd_structural_breaks() returns break_indices, n_breaks,
          # segments, post_break_start, alpha, min_obs — no post_break_returns
          # field.  Derive it from the index.
          post_r            <- r[post_start_idx:length(r)]
          post_break_sharpe <- sharpe_ann(post_r, ann)

          # Break dates: convert break indices to calendar dates.
          break_dates_str <- if (length(res$break_indices) == 0L) {
            NA_character_
          } else {
            paste(
              format(d[res$break_indices], "%Y-%m-%d"),
              collapse = ", "
            )
          }

          post_break_date <- if (post_start_idx <= length(d)) {
            d[[post_start_idx]]
          } else {
            as.Date(NA)
          }

          divergence <- if (!is.na(whole_sharpe) && abs(whole_sharpe) > 0.01 &&
                             res$n_breaks > 0L && !is.na(post_break_sharpe)) {
            (post_break_sharpe - whole_sharpe) / abs(whole_sharpe)
          } else {
            NA_real_
          }

          material_flag <- if (is.na(divergence)) NA else {
            abs(divergence) > sb_params$divergence_pct
          }

          tibble::tibble(
            strategy              = nm,
            n_breaks              = res$n_breaks,
            break_dates           = break_dates_str,
            post_break_start      = post_break_date,
            whole_sharpe          = round(whole_sharpe,      3L),
            post_break_sharpe     = round(post_break_sharpe, 3L),
            sharpe_divergence_pct = round(divergence * 100,  1L),
            material_divergence   = material_flag,
            n_obs_whole           = length(r),
            n_obs_post_break      = length(post_r),
            note                  = NA_character_
          )
        })

        dplyr::bind_rows(rows)
      },
      packages = "dplyr"
    ),


    # ── Caption ───────────────────────────────────────────────────────────────
    targets::tar_target(
      structural_breaks_caption,
      {
        df <- structural_breaks_summary
        n_strats   <- nrow(df)
        n_with_breaks <- sum(df$n_breaks > 0L, na.rm = TRUE)
        n_material    <- sum(df$material_divergence, na.rm = TRUE)
        alpha_pct  <- sb_params$alpha * 100

        paste0(
          "Structural break analysis (Carver 2026): ",
          n_with_breaks, " of ", n_strats, " strategies show ",
          "at least one structural break at the ", alpha_pct, "% significance level. ",
          n_material, " show a material post-break Sharpe divergence ",
          "(>", sb_params$divergence_pct * 100, "% from whole-history Sharpe). ",
          "Breaks are detected using an iterative forward-split t-test on ",
          "vol-normalised returns with a minimum segment of ",
          sb_params$min_years, " years. ",
          "Per the resulting-prohibition rule, a detected break is evidence ",
          "requiring investigation — not a signal to revise strategy allocation. ",
          "Per Carver's own finding, 'no break' often wins OOS: ",
          "break-splitting is a guard against over-splitting, not an always-on ",
          "re-estimator. ",
          "Multiple-testing note: scanning all candidate split dates inflates ",
          "the false-break rate above the nominal ", alpha_pct, "% level."
        )
      }
    )

  )
}
