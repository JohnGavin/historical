# BDBB R-Metric Position-Sizing Overlay -- Graduation Test (issue #443)
#
# TESTS A PRE-REGISTERED, SEALED HYPOTHESIS. Do not re-derive or re-word the
# claim -- see the sealed rows in inst/extdata/research_log/hypotheses/
# (uuid c0e60522-... for BTC, e9357c9b-... for SOL), sealed 2026-09-19 by
# commit 7706205 ("research(prereg): seal BDBB R-sizing overlay hypotheses
# at inception (#443)"). This script runs exactly the test that was
# pre-registered and reports what happened -- including a null result,
# which is a SUCCESSFUL outcome of this dispatch, not a failed one.
#
# ---------------------------------------------------------------------------
# THE SEALED CLAIM (verbatim from the hypothesis rows, not restated in my
# own words beyond what is needed to implement it)
# ---------------------------------------------------------------------------
# economic_claim (BTC row): "Scaling gross exposure down when the BDBB
#   R-metric (variance per unit signed flow) is in its trailing top tercile
#   improves risk-adjusted return versus buy-and-hold in BTC/USD, because
#   high R marks periods where a given amount of order flow generates
#   unusually much volatility -- i.e. thin absorption capacity and elevated
#   probability of an extreme move."
# economic_claim (SOL row): the same overlay tested out-of-sample on SOL/USD
#   ("SOL is the out-of-sample asset: Varma's evidence is BTC-only, so a
#   mechanism that is real rather than BTC-specific should survive here.")
#
# null_hypothesis (both): H0: the R-sizing overlay's HAC-adjusted annual
#   Sharpe is <= that of buy-and-hold over the same sample and cost model.
#
# decision_rule (from extra_json, both rows, applied LITERALLY below):
#   supported: overlay sharpe_hac > benchmark sharpe_hac AND overlay
#     detection verdict is powered
#   refuted: overlay sharpe_hac <= benchmark sharpe_hac AND overlay
#     detection verdict is powered
#   inconclusive-underpowered: overlay |sharpe| < min_detectable_annual_sr
#     (0.75 BTC, 1.17 SOL; alpha=0.05, power=0.80, ann_factor=8760)
#
# INTERPRETATION CHOICE (documented, not hidden): "overlay |sharpe|" in the
# inconclusive-underpowered row is not sharpe_hac-qualified the way the
# other two rows are. hd_detection_power()'s theoretical basis (Lo 2002 /
# Mertens correction) is the classic (naive) Sharpe-ratio sampling
# distribution, not a HAC-adjusted one, and this repo's own reference
# exploration (momentum_max_lottery) feeds hd_detection_power() the naive
# Sharpe throughout. I follow that precedent: "|sharpe|" below means the
# NAIVE annualised Sharpe. Applied as a single ordered decision procedure
# (the inconclusive-underpowered gate is evaluated FIRST, unconditional on
# sign, since it is about whether the sample can resolve the question at
# all; only once that gate is passed are supported/refuted evaluated):
#   1. if |sharpe_naive(overlay)| < asset_threshold  -> inconclusive-underpowered
#   2. else if sharpe_hac(overlay) > sharpe_hac(benchmark) -> supported
#   3. else -> refuted
# Applied to the NET-of-cost return series as primary (costs are not
# optional for a tradeable-position-sizing claim); gross is also reported.
#
# required_controls (from extra_json, both rows -- all three implemented):
#   complement: scale UP (to 1/w_low, capped at 2.0) when R is in the top
#     tercile. If overlay and complement perform alike, R is not sizing
#     anything.
#   correlation: cor(rank(R), rank(realised_vol)) -- R must not be a
#     repackaged vol filter. A vol-sizing benchmark (same overlay mechanics,
#     driven by trailing realised vol terciles instead of R) is run
#     alongside.
#   turnover: overlay vs buy-and-hold turnover and net-of-cost Sharpe.
#
# look_ahead_controls (from extra_json, both rows):
#   tercile_breakpoints: "trailing/expanding only -- never full-sample"
#   diagnostic_lag: "R at window_end t sizes exposure for bar t+1 (strictly
#     outside the window)"
#   blocked_by: "#868 -- bdbb_tail_predict() currently scores the in-window
#     bar" -- this is why bdbb_tail_predict() is NOT used here. Sizing is
#     built directly from bdbb_fit()'s window_end/R output, joined to the
#     bar-level table, then EXPLICITLY LAGGED BY ONE ROW so tercile_t sizes
#     the return realised over row t+1 -- never the bar the window itself
#     ends on. "Next bar" is resolved by ROW ORDER within ticker (not clock
#     arithmetic): Kraken bars exist only where trades occurred, so an
#     hourly gap is normal and `window_end + 3600s` is not reliably the
#     next bar. See the `dplyr::lag(R_tercile, 1L)` step below.
#
# combination_mode: "time" (per .claude/rules/strategy-combination-modes.md)
#   -- R scales gross exposure over time. It is NOT a filter (it never
#   changes which asset is held) and NOT a blend (it is not averaged with
#   another score). This is declared here per that rule's requirement to
#   name the mode before writing any code.
# ---------------------------------------------------------------------------

suppressMessages(pkgload::load_all("packages/historicaldata", quiet = TRUE))
suppressMessages(library(dplyr))

RESULTS_DIR <- "explorations/bdbb_r_sizing/results"
dir.create(RESULTS_DIR, showWarnings = FALSE, recursive = TRUE)

ANN_FACTOR <- 8760L        # hourly bars, 24 * 365
WINDOW_DAYS <- 30L
MIN_FRAC <- 0.7
MIN_HISTORY <- 250L        # prior windows required before first tercile assignment
W_GRID <- c(0.00, 0.25, 0.50, 0.75)
FEE_RATE <- 0.0026         # Kraken taker fee, 0.26% per side (task-specified, sourced)
COMPLEMENT_CAP <- 2.0

ASSETS <- tibble::tribble(
  ~asset, ~hyp_uuid,                              ~min_detectable_sr,
  "BTC",  "c0e60522-5a51-4563-a619-14b4a557779c", 0.75,
  "SOL",  "e9357c9b-d162-4317-bd6e-960736809c69", 1.17
)

cat("========================================================\n")
cat("BDBB R-metric position-sizing overlay -- graduation test\n")
cat("========================================================\n\n")

# ── Helper: expanding percentile rank via a Fenwick (BIT) tree ─────────────
# For each temporal position i (in the order x is given), returns the
# fraction of {x_1, ..., x_i} (INCLUSIVE of x_i, i.e. "at or before t") that
# is <= x_i. NA values are skipped entirely (neither inserted nor scored).
# Coordinate-compressed by VALUE only (a static transform of each element's
# own numeric value -- this does not use any element's TEMPORAL position,
# so compressing against the full vector cannot leak future information
# into a prefix-only rank/quantile computed from it), then queried with a
# Binary Indexed Tree so the whole pass is O(n log n) rather than O(n^2)
# (a naive re-sort at every row is infeasible at n ~ 1e5).
expanding_percentile_rank <- function(x) {
  n <- length(x)
  out <- rep(NA_real_, n)
  valid_idx <- which(!is.na(x))
  m <- length(valid_idx)
  if (m == 0L) return(out)
  xv <- x[valid_idx]
  uniq_sorted <- sort(unique(xv))
  coord <- match(xv, uniq_sorted)
  U <- length(uniq_sorted)
  bit <- integer(U + 1L)
  res <- numeric(m)
  for (k in seq_len(m)) {
    i <- coord[k]
    while (i <= U) {
      bit[i] <- bit[i] + 1L
      i <- i + bitwAnd(i, -i)
    }
    j <- coord[k]
    s <- 0L
    while (j > 0L) {
      s <- s + bit[j]
      j <- j - bitwAnd(j, -j)
    }
    res[k] <- s / k
  }
  out[valid_idx] <- res
  out
}

# ── Helper: trailing realised vol, same window length as bdbb_fit() ────────
trailing_vol <- function(log_ret, window_days = WINDOW_DAYS, min_frac = MIN_FRAC) {
  n_bars <- window_days * 24L
  min_n <- ceiling(min_frac * n_bars)
  slider::slide_dbl(
    log_ret,
    .f = function(w) {
      wv <- w[!is.na(w)]
      if (length(wv) < min_n) return(NA_real_)
      stats::sd(wv)
    },
    .before = n_bars - 1L,
    .complete = TRUE
  )
}

# ── Helper: tercile from an expanding percentile rank + min-history gate ───
# Requires MIN_HISTORY PRIOR valid observations (i.e. this is at least the
# (MIN_HISTORY+1)-th valid observation) before assigning a tercile; NA
# before that ("emit NA and hold no position before that").
tercile_from_pctrank <- function(pct_rank, valid_count) {
  dplyr::case_when(
    is.na(pct_rank) ~ NA_integer_,
    valid_count <= MIN_HISTORY ~ NA_integer_,
    TRUE ~ pmin(3L, as.integer(ceiling(pct_rank * 3)))
  )
}

skewness_sample <- function(r) {
  r <- r[!is.na(r)]
  m <- mean(r); s <- stats::sd(r)
  if (s == 0 || length(r) < 3) return(NA_real_)
  mean((r - m)^3) / s^3
}

max_drawdown_log <- function(r) {
  r <- r[!is.na(r)]
  cum <- exp(cumsum(r))
  peak <- cummax(cum)
  min(cum / peak - 1)
}

compute_metrics <- function(r, ann_factor = ANN_FACTOR) {
  r <- r[!is.na(r)]
  n <- length(r)
  hac <- hd_hac_sharpe(r, ann_factor = ann_factor)
  ann_log_ret <- sum(r) * (ann_factor / n)
  cagr <- exp(ann_log_ret) - 1
  list(
    n_obs = n,
    ann_ret_cagr = cagr,
    ann_ret_arith = hac$annualised_mean,
    ann_vol = hac$annualised_vol,
    sharpe_naive = hac$naive_sharpe,
    sharpe_hac = hac$hac_tstat * sqrt(ann_factor / hac$T),
    max_dd = max_drawdown_log(r),
    skew = skewness_sample(r)
  )
}

detection_verdict <- function(sharpe_naive, n_obs, ann_factor = ANN_FACTOR) {
  if (is.na(sharpe_naive) || sharpe_naive <= 0) {
    return(list(
      power = NA_real_, underpowered = NA, min_n_years = NA_real_,
      verdict = "N/A (non-positive naive Sharpe: one-sided H1 has nothing positive to detect)"
    ))
  }
  d <- hd_detection_power(sharpe_annual = sharpe_naive, n_obs = n_obs, ann_factor = ann_factor)
  d$verdict <- if (isTRUE(d$underpowered)) "UNDERPOWERED" else "adequately powered"
  d
}

turnover_annual_fn <- function(exposure, ann_factor = ANN_FACTOR) {
  exposure_prev <- dplyr::lag(exposure, default = 0)
  step <- abs(exposure - exposure_prev)
  mean(step, na.rm = TRUE) * ann_factor
}

all_summary_rows <- list()
all_decision_rows <- list()
all_corr_rows <- list()
all_turnover_rows <- list()
all_series_frames <- list()

for (a in seq_len(nrow(ASSETS))) {
  asset <- ASSETS$asset[a]
  hyp_uuid <- ASSETS$hyp_uuid[a]
  min_detectable_sr <- ASSETS$min_detectable_sr[a]

  cat(sprintf("\n\n########## ASSET: %s (hypothesis %s) ##########\n", asset, hyp_uuid))

  # ── 1. Fetch bars ─────────────────────────────────────────────────────
  cat(sprintf("=== 1. Fetch %s hourly OHLCVT bars ===\n", asset))
  bars <- hd_kraken_ohlcvt(asset, interval_min = 60L)
  bars <- bars |> dplyr::arrange(time)
  n_tickers <- dplyr::n_distinct(bars$ticker)
  if (n_tickers != 1L) {
    cli::cli_abort(c("x" = "Expected exactly 1 ticker for {.val {asset}}, got {n_tickers}."))
  }
  cat(sprintf(
    "  n_bars = %d, span = %s -> %s (%.2f yrs)\n",
    nrow(bars), format(min(bars$time)), format(max(bars$time)),
    as.numeric(difftime(max(bars$time), min(bars$time), units = "days")) / 365.25
  ))

  # ── 2. Bar-level return + BDBB diagnostic ────────────────────────────
  cat("=== 2. bar log-returns + bdbb_fit() ===\n")
  bars <- bars |>
    dplyr::mutate(log_ret = log(close / dplyr::lag(close)))

  cat(sprintf(
    "  running bdbb_fit(window_days=%d, min_frac=%.1f) over %d bars ...\n",
    WINDOW_DAYS, MIN_FRAC, nrow(bars)
  ))
  t0 <- Sys.time()
  diag <- bdbb_fit(bars, window_days = WINDOW_DAYS, min_frac = MIN_FRAC)
  cat(sprintf(
    "  bdbb_fit() done in %.1fs, %d diagnostic rows, %d with non-NA R\n",
    as.numeric(difftime(Sys.time(), t0, units = "secs")), nrow(diag), sum(!is.na(diag$R))
  ))

  # ── 3. Merge diagnostic onto bars by time == window_end (1:1, row-order) ──
  merged <- bars |>
    dplyr::select(time, close, log_ret) |>
    dplyr::left_join(
      diag |> dplyr::select(window_end, R),
      by = c("time" = "window_end")
    ) |>
    dplyr::arrange(time) |>
    dplyr::mutate(row_id = dplyr::row_number())

  # ── 4. Trailing realised vol (same window length, for the vol-sizing
  #        control and the R-vs-vol correlation check) ─────────────────
  cat("=== 4. trailing realised vol (control #2) ===\n")
  merged <- merged |>
    dplyr::mutate(trailing_realised_vol = trailing_vol(log_ret))

  n_both_valid <- sum(!is.na(merged$R) & !is.na(merged$trailing_realised_vol))
  r_vol_cor <- stats::cor(
    merged$R, merged$trailing_realised_vol,
    method = "spearman", use = "pairwise.complete.obs"
  )
  cat(sprintf(
    "  cor(rank(R), rank(trailing_vol)) = %.4f  (n_pairs = %d)\n",
    r_vol_cor, n_both_valid
  ))
  all_corr_rows[[asset]] <- tibble::tibble(
    asset = asset, r_vol_spearman_cor = r_vol_cor, n_pairs = n_both_valid
  )

  # ── 5. Expanding terciles (R and trailing_vol), min-history gated ──────
  cat("=== 5. expanding terciles (trailing/expanding breakpoints, min history) ===\n")
  merged <- merged |>
    dplyr::mutate(
      R_valid_count = cumsum(!is.na(R)),
      R_pct_rank = expanding_percentile_rank(R),
      R_tercile = tercile_from_pctrank(R_pct_rank, R_valid_count),

      vol_valid_count = cumsum(!is.na(trailing_realised_vol)),
      vol_pct_rank = expanding_percentile_rank(trailing_realised_vol),
      vol_tercile = tercile_from_pctrank(vol_pct_rank, vol_valid_count)
    )

  # ── LOOK-AHEAD GUARD: lag tercile by ONE ROW (row order, not clock) so
  #    the tercile known as of window_end = t sizes the return realised at
  #    ROW t+1 (strictly the next row), never the return ending the window
  #    itself. This is the exact control #868 was filed against.
  merged <- merged |>
    dplyr::mutate(
      R_tercile_lag1 = dplyr::lag(R_tercile, 1L),
      vol_tercile_lag1 = dplyr::lag(vol_tercile, 1L)
    )

  first_sizeable_row <- min(which(!is.na(merged$R_tercile_lag1)))
  cat(sprintf(
    "  first row with a usable (lagged) R tercile: row %d of %d (%.1f%% of bars excluded as warm-up)\n",
    first_sizeable_row, nrow(merged), 100 * (first_sizeable_row - 1) / nrow(merged)
  ))

  # ── 6. Analysis sample: rows where BOTH R and vol terciles (lagged) are
  #        available, and log_ret is non-NA. Benchmark restricted to the
  #        SAME rows for an apples-to-apples comparison (not the full raw
  #        sample) -- see run.R header note on this being a deliberate
  #        choice, not zero-filling the warm-up. ─────────────────────────
  analysis <- merged |>
    dplyr::filter(!is.na(R_tercile_lag1), !is.na(vol_tercile_lag1), !is.na(log_ret)) |>
    dplyr::arrange(row_id)

  cat(sprintf(
    "=== 6. analysis sample: %d bars (of %d raw bars; %d dropped as warm-up/incomplete) ===\n\n",
    nrow(analysis), nrow(merged), nrow(merged) - nrow(analysis)
  ))

  # ── 7. Build every variant's exposure + return series ──────────────────
  variant_returns <- list()
  variant_turnover <- list()

  # benchmark: constant exposure = 1 throughout the analysis sample
  bench_exposure <- rep(1.0, nrow(analysis))
  variant_returns[["benchmark"]] <- list(
    w_low = NA_real_,
    gross = analysis$log_ret,
    exposure = bench_exposure
  )

  for (w_low in W_GRID) {
    w_tag <- sprintf("%.2f", w_low)

    # overlay: scale DOWN to w_low when top tercile of R (lagged)
    overlay_exposure <- ifelse(analysis$R_tercile_lag1 == 3L, w_low, 1.0)
    variant_returns[[paste0("overlay_w", w_tag)]] <- list(
      w_low = w_low, gross = overlay_exposure * analysis$log_ret, exposure = overlay_exposure
    )

    # complement: scale UP to 1/w_low (capped) when top tercile of R (lagged)
    up_scale <- if (w_low <= 0) COMPLEMENT_CAP else min(1 / w_low, COMPLEMENT_CAP)
    complement_exposure <- ifelse(analysis$R_tercile_lag1 == 3L, up_scale, 1.0)
    variant_returns[[paste0("complement_w", w_tag)]] <- list(
      w_low = w_low, gross = complement_exposure * analysis$log_ret, exposure = complement_exposure
    )

    # vol-sizing benchmark: identical mechanics, driven by trailing vol tercile
    volsizing_exposure <- ifelse(analysis$vol_tercile_lag1 == 3L, w_low, 1.0)
    variant_returns[[paste0("volsizing_w", w_tag)]] <- list(
      w_low = w_low, gross = volsizing_exposure * analysis$log_ret, exposure = volsizing_exposure
    )
  }

  # ── 8. Turnover + cost application (gross vs net) ──────────────────────
  cat("=== 8. turnover + cost model (Kraken taker fee 0.26%/side, on exposure change) ===\n")
  for (nm in names(variant_returns)) {
    v <- variant_returns[[nm]]
    turn <- turnover_annual_fn(v$exposure)
    variant_turnover[[nm]] <- turn

    if (nm == "benchmark") {
      # single one-time entry cost at the first row of the analysis sample
      cost <- rep(0, length(v$gross))
      cost[1] <- FEE_RATE
    } else {
      exposure_prev <- dplyr::lag(v$exposure, default = 0)
      cost <- abs(v$exposure - exposure_prev) * FEE_RATE
    }
    variant_returns[[nm]]$net <- v$gross - cost
    cat(sprintf("  %-16s turnover_annual = %6.2fx\n", nm, turn))
  }
  cat("\n")

  # ── 9. Metrics + detection power for every variant, gross and net ──────
  cat("=== 9. metrics + detection power (naive Sharpe fed to hd_detection_power(), per repo precedent) ===\n\n")
  for (nm in names(variant_returns)) {
    v <- variant_returns[[nm]]
    for (cost_type in c("gross", "net")) {
      r <- if (cost_type == "gross") v$gross else v$net
      m <- compute_metrics(r)
      dp <- detection_verdict(m$sharpe_naive, m$n_obs)
      fixed_underpowered <- if (is.na(m$sharpe_naive)) NA else abs(m$sharpe_naive) < min_detectable_sr

      cat(sprintf(
        "  [%-6s] %-16s w_low=%s  sharpe_naive=%+.3f sharpe_hac=%+.3f cagr=%+.2f%% max_dd=%+.2f%% turnover=%5.2fx  detect=%s\n",
        cost_type, nm, ifelse(is.na(v$w_low), "NA", sprintf("%.2f", v$w_low)),
        m$sharpe_naive, m$sharpe_hac, 100 * m$ann_ret_cagr, 100 * m$max_dd,
        variant_turnover[[nm]], dp$verdict
      ))

      all_summary_rows[[length(all_summary_rows) + 1]] <- tibble::tibble(
        asset = asset, variant = nm, w_low = v$w_low, cost_type = cost_type,
        n_obs = m$n_obs, ann_ret_cagr = m$ann_ret_cagr, ann_ret_arith = m$ann_ret_arith,
        ann_vol = m$ann_vol, sharpe_naive = m$sharpe_naive, sharpe_hac = m$sharpe_hac,
        max_dd = m$max_dd, skew = m$skew, turnover_annual = variant_turnover[[nm]],
        detection_power = dp$power,
        detection_underpowered_hd = dp$underpowered,
        detection_min_n_years = dp$min_n_years,
        detection_verdict = dp$verdict,
        fixed_threshold_used = min_detectable_sr,
        fixed_threshold_underpowered = fixed_underpowered
      )
    }
  }
  cat("\n")

  # ── 10. Pre-registered decision rule, applied literally, per weight ────
  cat("=== 10. decision rule (applied literally, NET-of-cost as primary) ===\n\n")
  bench_net <- variant_returns[["benchmark"]]$net
  bench_m <- compute_metrics(bench_net)

  for (w_low in W_GRID) {
    w_tag <- sprintf("%.2f", w_low)
    ov <- variant_returns[[paste0("overlay_w", w_tag)]]
    ov_m <- compute_metrics(ov$net)

    if (is.na(ov_m$sharpe_naive) || abs(ov_m$sharpe_naive) < min_detectable_sr) {
      status <- "inconclusive-underpowered"
    } else if (ov_m$sharpe_hac > bench_m$sharpe_hac) {
      status <- "supported"
    } else {
      status <- "refuted"
    }

    cat(sprintf(
      "  w_low=%.2f: overlay sharpe_naive=%+.3f sharpe_hac=%+.3f vs benchmark sharpe_hac=%+.3f -> %s\n",
      w_low, ov_m$sharpe_naive, ov_m$sharpe_hac, bench_m$sharpe_hac, status
    ))

    all_decision_rows[[length(all_decision_rows) + 1]] <- tibble::tibble(
      asset = asset, w_low = w_low, status = status,
      overlay_sharpe_naive = ov_m$sharpe_naive, overlay_sharpe_hac = ov_m$sharpe_hac,
      benchmark_sharpe_naive = bench_m$sharpe_naive, benchmark_sharpe_hac = bench_m$sharpe_hac,
      fixed_threshold_used = min_detectable_sr,
      n_obs = ov_m$n_obs
    )
  }
  cat("\n")

  all_turnover_rows[[asset]] <- tibble::tibble(
    asset = asset,
    variant = names(variant_turnover),
    turnover_annual = unlist(variant_turnover)
  )

  # ── keep the small analysis-sample series for provenance (not committed
  #    if large -- see SUMMARY.md Files section) ─────────────────────────
  all_series_frames[[asset]] <- analysis |>
    dplyr::mutate(asset = asset) |>
    dplyr::select(asset, time, log_ret, R, R_tercile_lag1, trailing_realised_vol, vol_tercile_lag1)
}

# ── 11. Write outputs ──────────────────────────────────────────────────────
cat("=== 11. write results/ ===\n")
summary_metrics <- dplyr::bind_rows(all_summary_rows)
decision_table <- dplyr::bind_rows(all_decision_rows)
corr_checks <- dplyr::bind_rows(all_corr_rows)
turnover_tbl <- dplyr::bind_rows(all_turnover_rows)
series_all <- dplyr::bind_rows(all_series_frames)

readr::write_csv(summary_metrics, file.path(RESULTS_DIR, "summary_metrics.csv"))
readr::write_csv(decision_table, file.path(RESULTS_DIR, "decision_table.csv"))
readr::write_csv(corr_checks, file.path(RESULTS_DIR, "correlation_checks.csv"))
readr::write_csv(turnover_tbl, file.path(RESULTS_DIR, "turnover.csv"))

series_path <- file.path(RESULTS_DIR, "analysis_sample_series.parquet")
arrow::write_parquet(series_all, series_path)
cat(sprintf(
  "  analysis_sample_series.parquet: %d rows, %.1fMB (%s committed -- see SUMMARY.md)\n",
  nrow(series_all), file.size(series_path) / 1e6,
  if (file.size(series_path) > 2e6) "NOT" else ""
))

cat("\n========================================================\n")
cat("Run complete. Outputs written to:", RESULTS_DIR, "\n")
cat("========================================================\n")
