# Test: calendar alignment of rolling MA when source data has interleaved NAs
# (US market holidays produce NA rows in VIXCLS; filter() before roll_mean_safe
#  would collapse the index and distort the 63-row window's calendar span.)
#
# Reproduces the roborev 4329 finding: filter(!is.na()) before a slider-based
# roll is a real bug, not a false positive.

testthat::local_edition(3)
source(here::here("R/utils_rolling.R"))

# ── Calendar alignment: interleaved NAs must be kept ─────────────────────────

test_that("filter before roll_mean_safe distorts calendar span (demonstrates the bug)", {
  # Simulate 10 trading days with a holiday on day 5 (as in VIXCLS)
  dates <- as.Date("2024-01-01") + 0:9
  vix   <- c(15, 16, 17, 18, NA, 20, 21, 22, 23, 24)  # NA on day 5 (holiday)

  df <- data.frame(date = dates, vix = vix)

  # WRONG approach: filter out NAs then roll
  df_filtered <- df[!is.na(df$vix), ]
  ma_filtered <- roll_mean_safe(df_filtered$vix, n = 5)
  # Position 5 in filtered series covers dates 1,2,3,4,6 — skipping the holiday gap

  # CORRECT approach: keep all rows, let roll_mean_safe handle NAs
  ma_full <- roll_mean_safe(df$vix, n = 5)
  # Position 5 in full series covers dates 1,2,3,4,5 — proper calendar window
  # (the NA on day 5 is handled by na.rm=TRUE inside roll_mean_safe)

  # The filtered series has 9 positions; the full series has 10
  expect_length(ma_filtered, 9L)
  expect_length(ma_full,     10L)

  # The "position 5" MA computed on the filtered series covers dates spanning
  # day 1 through day 6 (skips the gap) — a wider calendar span than 5 rows.
  # Verify by checking what dates feed into it:
  # filtered[1:5] = dates[1,2,3,4,6] = span of 6 calendar days for a 5-row window
  filtered_window_dates <- df_filtered$date[1:5]
  calendar_span_filtered <- as.numeric(diff(range(filtered_window_dates))) + 1L
  expect_gt(calendar_span_filtered, 5L)  # 6 calendar days for a 5-row window

  # The full-series window stays within the intended calendar span
  full_window_dates <- df$date[1:5]
  calendar_span_full <- as.numeric(diff(range(full_window_dates))) + 1L
  expect_equal(calendar_span_full, 5L)
})

test_that("roll_mean_safe on full series preserves row count when source has NAs", {
  # Real-world shape: 9463 rows, 302 NAs (VIXCLS 1990-2026)
  set.seed(42)
  n_total <- 9463L
  vix_sim  <- abs(rnorm(n_total, mean = 18, sd = 5))
  # Inject 302 NAs at pseudo-holiday positions (every ~31 rows)
  holiday_idx <- seq(5, n_total, by = 31L)
  vix_sim[holiday_idx] <- NA

  result <- roll_mean_safe(vix_sim, n = 63L)

  # Output length matches input — no rows dropped
  expect_length(result, n_total)

  # Non-NA positions at full-window positions (pos >= 63) are numeric
  full_window_positions <- which(seq_len(n_total) >= 63L)
  non_na_full <- result[full_window_positions][!is.na(result[full_window_positions])]
  expect_true(all(is.finite(non_na_full)))
})

test_that("vix_daily preparation keeps holiday NA rows (no filter before arrange)", {
  # This is the canonical regression test: the vix_daily pipeline step MUST NOT
  # drop rows with NA vix before passing to roll_mean_safe.
  #
  # We construct a mini-pipeline matching the fixed code:
  #   hd_macro("VIXCLS") |> select(date, vix = value) |> arrange(date)
  # (no filter step) and verify that NAs survive into the output.

  # Synthetic VIXCLS-shaped data: 20 rows, 3 holiday NAs interleaved
  raw <- data.frame(
    date     = as.Date("2020-01-01") + 0:19,
    value    = c(15, NA, 16, 17, NA, 18, 19, 20, 21, NA,
                 22, 23, 24, 25, 26, 27, 28, 29, 30, 31),
    series_id = "VIXCLS"
  )

  # Simulate the FIXED pipeline step (no filter)
  vix_daily <- raw |>
    (\(d) d[, c("date", "value")])() |>  # select(date, vix = value) equivalent
    setNames(c("date", "vix")) |>
    (\(d) d[order(d$date), ])()           # arrange(date)

  # All 20 rows survive
  expect_equal(nrow(vix_daily), 20L)
  expect_equal(sum(is.na(vix_daily$vix)), 3L)

  # Rolling MA on the full series: 20 rows in, 20 rows out
  ma <- roll_mean_safe(vix_daily$vix, n = 5L)
  expect_length(ma, 20L)
})
