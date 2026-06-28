# OOS min-variance / conditioning diagnostic targets (issue #498 Phase 3a)
#
# Provides three targets that answer: does regularised covariance improve
# out-of-sample minimum-variance portfolio performance and conditioning?
#
#   cov_diag_4asset     — 4-asset (SPY/TLT/GLD/DBC) universe (p << n; expects
#                         sample ≈ LW/RMT because conditioning is not strained)
#   cov_diag_wide_panel — wide (~30 large-cap US equities) monthly returns panel
#                         (p approaches train_window; expected wide-regime result:
#                         sample fails / huge condition, LW+RMT succeed)
#   cov_diag_wide       — OOS diagnostic on cov_diag_wide_panel
#   cov_diag_summary    — row-bound result with universe label; consumed by Phase 3b
#
# Phase 3b (future): wire cov_diag_summary into falsification.qmd robustness
# gauntlet and render. The eventual COV_METHOD flip to "ledoit_wolf" in
# cov_config.R is gated on this diagnostic demonstrating a conditioning benefit.
#
# NOTE: cov_diag_wide_panel fetches real data via hd_ohlcv(); missing tickers
# are dropped with a cli_warn. Phase 3b validates the actual fetch result.
# The real-data fetch is exercised at tar_make / Phase 3b, not in unit tests.

# ── Universe constant ──────────────────────────────────────────────────────────
#
# ~30 liquid large-cap US equities with long price histories. Phase 3b validates
# the actual intersection of available tickers in the database.
COV_DIAG_UNIVERSE <- c(
  "AAPL", "MSFT", "JNJ",  "JPM",  "XOM",  "PG",   "KO",   "WMT",
  "CVX",  "HD",   "MCD",  "MRK",  "ABT",  "VZ",   "T",    "PFE",
  "IBM",  "GE",   "BA",   "CAT",  "MMM",  "AXP",  "UNH",  "HON",
  "LLY",  "AMGN", "GS",   "BLK",  "USB",  "TGT"
)

# ── Helper: build wide monthly returns from hd_ohlcv ─────────────────────────
#
# Mirrors the convention in plan_returns.R (asset_monthly_returns_wide):
#   last-trading-day adjusted_close per month → simple arithmetic returns.
# Tickers absent from the database are dropped with a cli_warn.
# Rows with any NA across retained tickers are dropped (complete cases only).
.cov_diag_wide_panel <- function(tickers) {
  library(dplyr)

  raw <- hd_ohlcv(tickers, collect = TRUE) |>
    dplyr::mutate(date = as.Date(date))

  # Keep only tickers present in the data
  available <- unique(raw$ticker)
  missing_t <- setdiff(tickers, available)
  if (length(missing_t) > 0L) {
    cli::cli_warn(
      c(
        "Dropped {length(missing_t)} ticker{?s} absent from the database.",
        "i" = "Missing: {.val {missing_t}}"
      )
    )
  }
  if (length(available) < 2L) {
    cli::cli_abort(
      "Fewer than 2 tickers available in the database after filtering."
    )
  }

  # Last trading day per (ticker, year-month) → simple return
  long <- raw |>
    dplyr::filter(.data$ticker %in% available) |>
    dplyr::mutate(ym = format(date, "%Y-%m")) |>
    dplyr::group_by(.data$ticker, .data$ym) |>
    dplyr::filter(.data$date == max(.data$date)) |>
    dplyr::ungroup() |>
    dplyr::select("ticker", "date", "adjusted_close") |>
    dplyr::arrange(.data$ticker, .data$date) |>
    dplyr::group_by(.data$ticker) |>
    dplyr::mutate(ret = .data$adjusted_close / dplyr::lag(.data$adjusted_close) - 1) |>
    dplyr::filter(!is.na(.data$ret)) |>
    dplyr::ungroup() |>
    dplyr::select("ticker", "date", "ret")

  # Pivot wide then keep complete cases (inner-join on date)
  wide <- long |>
    tidyr::pivot_wider(names_from = "ticker", values_from = "ret") |>
    dplyr::filter(dplyr::if_all(-"date", ~ !is.na(.x))) |>
    dplyr::arrange(.data$date)

  wide
}

# ── Plan function ─────────────────────────────────────────────────────────────
plan_cov_diagnostic <- function() {
  list(

    # ── 4-asset diagnostic ──────────────────────────────────────────────
    # Thin universe (p = 4 << train_window = 60): expected result is that
    # sample ≈ LW ≈ RMT in conditioning (n >> p, sample cov is well-conditioned).
    targets::tar_target(cov_diag_4asset, {
      hd_cov_oos_diagnostic(
        returns      = asset_monthly_returns_wide,
        methods      = c("sample", "ledoit_wolf", "rmt_denoise"),
        train_window = 60L,
        lw_target    = COV_LW_TARGET
      )
    }),

    # ── Wide-universe monthly returns panel ─────────────────────────────
    # Fetches ~30 large-cap equities, mirrors asset_monthly_returns_wide
    # convention (last-trading-day adjusted close, simple returns, complete cases).
    targets::tar_target(cov_diag_wide_panel, {
      .cov_diag_wide_panel(COV_DIAG_UNIVERSE)
    }),

    # ── Wide-universe OOS diagnostic ────────────────────────────────────
    # Wide regime (p ≈ 20-30, train_window = 60): expected result is that
    # sample covariance has n_failed > 0 or enormous condition numbers, while
    # LW + RMT remain invertible with finite, lower condition numbers.
    targets::tar_target(cov_diag_wide, {
      hd_cov_oos_diagnostic(
        returns      = cov_diag_wide_panel,
        methods      = c("sample", "ledoit_wolf", "rmt_denoise"),
        train_window = 60L,
        lw_target    = COV_LW_TARGET
      )
    }),

    # ── Summary table (consumed by Phase 3b vignette) ──────────────────
    # Row-bind 4-asset and wide results with universe label and per-universe
    # metadata (n_assets, n_periods, train_window) extracted from tibble
    # attributes BEFORE dplyr operations strip them.
    # Columns: universe, method, n_assets, n_periods, train_window,
    #          n_oos, n_failed, oos_mean, oos_vol, oos_sharpe,
    #          mean_cond, median_cond.
    targets::tar_target(cov_diag_summary, {
      library(dplyr)

      # Capture attributes before any dplyr operations strip them
      add_universe_meta <- function(diag_tbl, univ_label) {
        tw  <- attr(diag_tbl, "train_window")
        np  <- attr(diag_tbl, "n_periods")
        na_ <- attr(diag_tbl, "n_assets")
        dplyr::mutate(
          diag_tbl,
          universe     = univ_label,
          n_assets     = na_,
          n_periods    = np,
          train_window = tw
        )
      }

      dplyr::bind_rows(
        add_universe_meta(cov_diag_4asset, "4-asset"),
        add_universe_meta(cov_diag_wide,   "wide")
      ) |>
        dplyr::relocate("universe", .before = "method")
    })

  )
}
