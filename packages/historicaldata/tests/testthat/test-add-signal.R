# Tests for ADD (Anomaly-Driven Demand) signal computation
# References:
#   Kjær & Posselt (2025) "Anomaly-Driven Demand"
#   knowledge/wiki/anomaly-driven-demand.md
#
# All tests are OFFLINE — no network calls, no file I/O.
# testthat edition 3.

# ── Synthetic data helpers ────────────────────────────────────────────────────

# 3 stocks × 6 months × 2 anomalies
# Quintile convention: Q1 = short leg, Q5 = long leg, Q2-4 = neutral
make_quintile_tbl <- function() {
  tibble::tibble(
    stock      = rep(c("A", "B", "C"), times = 12),
    date       = rep(
      rep(as.Date(paste0("2023-0", 1:6, "-01")), each = 3),
      2
    ),
    anomaly_id = rep(c("val", "mom"), each = 18),
    quintile   = as.integer(c(
      # anomaly "val": A, B, C × months 1-6
      # month 1: A=1, B=3, C=5
      # month 2: A=5, B=3, C=1   (A jumps to long; C drops to short)
      # month 3: A=5, B=3, C=1   (no change)
      # month 4: A=3, B=5, C=3   (A exits long; B enters long; C exits short)
      # month 5: A=3, B=5, C=3   (no change)
      # month 6: A=1, B=3, C=5   (A enters short; B exits long; C enters long)
      1, 3, 5,   # month 1
      5, 3, 1,   # month 2
      5, 3, 1,   # month 3
      3, 5, 3,   # month 4
      3, 5, 3,   # month 5
      1, 3, 5,   # month 6
      # anomaly "mom": A, B, C × months 1-6
      # month 1: A=3, B=5, C=3
      # month 2: A=5, B=1, C=3
      # month 3: A=1, B=5, C=3
      # month 4: A=5, B=1, C=3
      # month 5: A=5, B=1, C=3
      # month 6: A=3, B=5, C=3
      3, 5, 3,   # month 1
      5, 1, 3,   # month 2
      1, 5, 3,   # month 3
      5, 1, 3,   # month 4
      5, 1, 3,   # month 5
      3, 5, 3    # month 6
    ))
  )
}

# ── hd_compute_add: basic structure ──────────────────────────────────────────

test_that("hd_compute_add: returns expected columns", {
  tbl <- hd_compute_add(make_quintile_tbl())
  expect_s3_class(tbl, "tbl_df")
  expect_true(all(c("stock", "date", "anomaly_id", "quintile", "add") %in% names(tbl)))
})

test_that("hd_compute_add: same number of rows as input", {
  input <- make_quintile_tbl()
  tbl   <- hd_compute_add(input)
  expect_equal(nrow(tbl), nrow(input))
})

test_that("hd_compute_add: ADD is NA on the first month of each (stock, anomaly_id) pair", {
  tbl <- hd_compute_add(make_quintile_tbl())
  first_months <- tbl |>
    dplyr::group_by(stock, anomaly_id) |>
    dplyr::slice_min(date, n = 1L) |>
    dplyr::ungroup()
  expect_true(all(is.na(first_months$add)))
})

# ── hd_compute_add: hand-calculated values ────────────────────────────────────

test_that("hd_compute_add: correct ADD for 'val' anomaly transition month 2", {
  # "val" month 2:
  #   A: Q1→Q5 → NET changes from -1 to +1 → ADD = +2
  #   B: Q3→Q3 → NET stays   0       → ADD =  0
  #   C: Q5→Q1 → NET changes from +1 to -1 → ADD = -2
  tbl   <- hd_compute_add(make_quintile_tbl())
  month2 <- as.Date("2023-02-01")
  result <- tbl |>
    dplyr::filter(anomaly_id == "val", date == month2) |>
    dplyr::arrange(stock)
  expect_equal(result$add[result$stock == "A"],  2L)
  expect_equal(result$add[result$stock == "B"],  0L)
  expect_equal(result$add[result$stock == "C"], -2L)
})

test_that("hd_compute_add: ADD is 0 when quintile does not change", {
  # "val" months 3 and 5 have no quintile change
  tbl    <- hd_compute_add(make_quintile_tbl())
  months <- c(as.Date("2023-03-01"), as.Date("2023-05-01"))
  result <- tbl |> dplyr::filter(anomaly_id == "val", date %in% months)
  expect_true(all(result$add == 0L))
})

test_that("hd_compute_add: stock entering long leg AND exiting short leg → ADD = +2", {
  # "val" month 2: stock A transitions Q1 (short) → Q5 (long)
  #   NET(month 1) = -1, NET(month 2) = +1 → ADD = +2
  tbl    <- hd_compute_add(make_quintile_tbl())
  month2 <- as.Date("2023-02-01")
  add_A  <- tbl |>
    dplyr::filter(stock == "A", anomaly_id == "val", date == month2) |>
    dplyr::pull(add)
  expect_equal(add_A, 2L)
})

test_that("hd_compute_add: entering long leg only (from neutral) → ADD = +1", {
  # "mom" month 2: B goes Q5→Q1 but A goes Q3→Q5 (neutral to long).
  # For A, anomaly "mom": month 1 Q3 (NET=0), month 2 Q5 (NET=+1) → ADD = +1
  tbl    <- hd_compute_add(make_quintile_tbl())
  month2 <- as.Date("2023-02-01")
  add_A  <- tbl |>
    dplyr::filter(stock == "A", anomaly_id == "mom", date == month2) |>
    dplyr::pull(add)
  expect_equal(add_A, 1L)
})

test_that("hd_compute_add: exiting short leg only (to neutral) → ADD = +1", {
  # "val" month 4: C transitions Q1 (short) → Q3 (neutral)
  #   NET(month 3) = -1, NET(month 4) = 0 → ADD = +1
  tbl    <- hd_compute_add(make_quintile_tbl())
  month4 <- as.Date("2023-04-01")
  add_C  <- tbl |>
    dplyr::filter(stock == "C", anomaly_id == "val", date == month4) |>
    dplyr::pull(add)
  expect_equal(add_C, 1L)
})

# ── hd_compute_add: look-ahead protection ────────────────────────────────────

test_that("hd_compute_add: LOOK-AHEAD GUARD — perturbing only future quintiles does not change past ADD values", {
  # Create two versions: identical up to month 4, diverge at month 5 onwards.
  # ADD at months 2-4 must be identical in both versions.
  base_tbl <- make_quintile_tbl()

  # Perturb: flip all quintiles in months 5 and 6
  perturbed_tbl <- base_tbl |>
    dplyr::mutate(
      quintile = dplyr::if_else(
        date >= as.Date("2023-05-01"),
        dplyr::case_when(
          quintile == 1L ~ 5L,
          quintile == 5L ~ 1L,
          TRUE            ~ quintile
        ),
        quintile
      )
    )

  add_base      <- hd_compute_add(base_tbl)
  add_perturbed <- hd_compute_add(perturbed_tbl)

  # Months 2-4 must be unchanged
  months_2_4 <- seq(as.Date("2023-02-01"), as.Date("2023-04-01"), by = "month")
  base_early      <- add_base      |> dplyr::filter(date %in% months_2_4)
  perturbed_early <- add_perturbed |> dplyr::filter(date %in% months_2_4)

  expect_equal(
    base_early$add,
    perturbed_early$add,
    info = "ADD values before perturbation window must be identical"
  )
})

# ── hd_compute_add: error handling ───────────────────────────────────────────

test_that("hd_compute_add: errors on non-data-frame input", {
  expect_error(hd_compute_add("not a tibble"), "data frame or tibble")
})

test_that("hd_compute_add: errors on missing required columns", {
  bad <- tibble::tibble(stock = "A", date = Sys.Date())
  expect_error(hd_compute_add(bad), "missing required columns")
})

test_that("hd_compute_add: errors on empty input", {
  empty <- tibble::tibble(
    stock = character(), date = as.Date(character()),
    anomaly_id = character(), quintile = integer()
  )
  expect_error(hd_compute_add(empty), "must not be empty")
})

test_that("hd_compute_add: errors on non-Date date column", {
  bad <- tibble::tibble(
    stock = "A", date = "2023-01-01",
    anomaly_id = "val", quintile = 3L
  )
  expect_error(hd_compute_add(bad), "Date")
})

test_that("hd_compute_add: errors on out-of-range quintile values", {
  bad <- tibble::tibble(
    stock = "A", date = as.Date("2023-01-01"),
    anomaly_id = "val", quintile = 6L
  )
  expect_error(hd_compute_add(bad), "1-5")
})

test_that("hd_compute_add: allows NA quintile (stock not ranked)", {
  tbl <- tibble::tibble(
    stock      = c("A", "A"),
    date       = as.Date(c("2023-01-01", "2023-02-01")),
    anomaly_id = c("val", "val"),
    quintile   = c(NA_integer_, 3L)
  )
  result <- hd_compute_add(tbl)
  # Row 1: first month → ADD = NA
  # Row 2: NET(t-1) from NA quintile treated as 0; NET(t) = 0 (Q3) → ADD = 0
  expect_equal(nrow(result), 2L)
  expect_true(is.na(result$add[1L]))
  expect_equal(result$add[2L], 0L)
})

# ── hd_aggregate_add: basic structure ────────────────────────────────────────

test_that("hd_aggregate_add: returns expected columns", {
  add_tbl <- hd_compute_add(make_quintile_tbl())
  agg     <- hd_aggregate_add(add_tbl)
  expect_s3_class(agg, "tbl_df")
  expect_true(all(c("stock", "date", "add_sum", "n_anomalies_valid") %in% names(agg)))
})

test_that("hd_aggregate_add: one row per (stock, date)", {
  add_tbl <- hd_compute_add(make_quintile_tbl())
  agg     <- hd_aggregate_add(add_tbl)
  n_stock_dates <- nrow(dplyr::distinct(add_tbl, stock, date))
  expect_equal(nrow(agg), n_stock_dates)
})

test_that("hd_aggregate_add: add_sum equals sum of individual anomaly ADDs", {
  # Month 2 for stock A: val=+2, mom=+1 → sum = 3
  add_tbl <- hd_compute_add(make_quintile_tbl())
  agg     <- hd_aggregate_add(add_tbl)
  month2  <- as.Date("2023-02-01")
  sum_A   <- agg |>
    dplyr::filter(stock == "A", date == month2) |>
    dplyr::pull(add_sum)
  expect_equal(sum_A, 3L)
})

test_that("hd_aggregate_add: n_anomalies_valid is 0 on the first month (all NAs)", {
  add_tbl <- hd_compute_add(make_quintile_tbl())
  agg     <- hd_aggregate_add(add_tbl)
  month1  <- as.Date("2023-01-01")
  n_valid <- agg |>
    dplyr::filter(date == month1) |>
    dplyr::pull(n_anomalies_valid)
  expect_true(all(n_valid == 0L))
})

# ── hd_aggregate_add: error handling ─────────────────────────────────────────

test_that("hd_aggregate_add: errors on non-data-frame input", {
  expect_error(hd_aggregate_add("bad"), "data frame or tibble")
})

test_that("hd_aggregate_add: errors on missing columns", {
  bad <- tibble::tibble(stock = "A", date = Sys.Date())
  expect_error(hd_aggregate_add(bad), "missing required columns")
})

test_that("hd_aggregate_add: errors on unsupported 'by' argument", {
  add_tbl <- hd_compute_add(make_quintile_tbl())
  expect_error(hd_aggregate_add(add_tbl, by = "anomaly_date"), "stock_date")
})

test_that("hd_aggregate_add: errors on empty input", {
  empty <- tibble::tibble(
    stock = character(), date = as.Date(character()),
    anomaly_id = character(), quintile = integer(), add = integer()
  )
  expect_error(hd_aggregate_add(empty), "must not be empty")
})

# ── hd_register_add_dataset ───────────────────────────────────────────────────

test_that("hd_register_add_dataset: returns a named list with required fields", {
  reg <- hd_register_add_dataset()
  expect_type(reg, "list")
  expected_fields <- c(
    "source_name", "portal_url", "download_url", "expected_schema",
    "frequency", "universe", "sample_start", "sample_end",
    "n_anomalies", "citation", "related_issues"
  )
  expect_true(all(expected_fields %in% names(reg)))
})

test_that("hd_register_add_dataset: n_anomalies is 209", {
  reg <- hd_register_add_dataset()
  expect_equal(reg$n_anomalies, 209L)
})

test_that("hd_register_add_dataset: portal_url is plausible", {
  reg <- hd_register_add_dataset()
  expect_match(reg$portal_url, "openassetpricing\\.com")
})
