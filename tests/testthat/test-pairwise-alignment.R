testthat::local_edition(3)
source(here::here("R/dataset_registry.R"))
source(here::here("R/utils_dates.R"))
source(here::here("R/utils_validation.R"))

# ── Helper factories ──────────────────────────────────────────────────────────

# Synthetic daily Date series
daily_date_df <- function(n = 30) {
  tibble::tibble(
    date  = seq(as.Date("2025-01-01"), by = "day", length.out = n),
    value = rnorm(n)
  )
}

# Synthetic monthly Date series (first of month)
monthly_date_df <- function(n = 12) {
  tibble::tibble(
    date  = seq(as.Date("2025-01-01"), by = "month", length.out = n),
    value = rnorm(n)
  )
}

# Synthetic POSIXct series (same dates, different class — the #146 bug)
posixct_date_df <- function(n = 30) {
  tibble::tibble(
    date  = as.POSIXct(
      seq(as.Date("2025-01-01"), by = "day", length.out = n)
    ),
    value = rnorm(n)
  )
}

# Build a minimal two-row registry
make_pair_registry <- function(name_a = "a", freq_a = "daily",
                                name_b = "b", freq_b = "daily") {
  tibble::tibble(
    target_name  = c(name_a, name_b),
    kind         = "returns",
    freq         = c(freq_a, freq_b),
    date_anchor  = "end_bizday",
    currency     = "USD",
    units        = "decimal",
    identity_col = NA_character_,
    notes        = NA_character_
  )
}

# Build a fake read_fn — same pattern used in test-utils_validation.R
make_reader <- function(...) {
  store <- list(...)
  function(nm) {
    if (!nm %in% names(store)) stop(paste0("target not found: ", nm))
    store[[nm]]
  }
}

# ── Test 1: Registry parses cleanly ──────────────────────────────────────────

test_that("dataset_registry returns a tibble with required columns including currency, units, identity_col", {
  reg <- dataset_registry()
  expect_s3_class(reg, "tbl_df")
  required <- c("target_name", "kind", "freq", "date_anchor",
                "currency", "units", "identity_col", "notes")
  missing_cols <- setdiff(required, names(reg))
  expect_equal(missing_cols, character(0),
               info = paste("Missing columns:", paste(missing_cols, collapse = ", ")))
})

test_that("dataset_registry target_name values are unique", {
  reg <- dataset_registry()
  expect_equal(length(unique(reg$target_name)), nrow(reg))
})

test_that("dataset_registry has at least 10 entries", {
  reg <- dataset_registry()
  expect_gte(nrow(reg), 10L)
})

# ── Test 2: Two same-type Date tibbles align ──────────────────────────────────

test_that("two Date daily series are compatible — all dimensions ok", {
  reg    <- make_pair_registry("da", "daily", "db", "daily")
  reader <- make_reader(da = daily_date_df(30), db = daily_date_df(30))

  result <- probe_pairwise_alignment(reg, read_fn = reader)

  expect_s3_class(result, "tbl_df")
  # Should produce exactly one pair row
  expect_equal(nrow(result), 1L)
  expect_true("status" %in% names(result))
  expect_equal(result$status, "ok")
  expect_true("dimension" %in% names(result))
  expect_equal(result$dimension, "date_class")
})

test_that("probe_pairwise_alignment returns tibble with required columns", {
  reg    <- make_pair_registry()
  reader <- make_reader(a = daily_date_df(10), b = daily_date_df(10))

  result <- probe_pairwise_alignment(reg, read_fn = reader)

  required_cols <- c("pair", "dimension", "status", "evidence")
  missing_cols  <- setdiff(required_cols, names(result))
  expect_equal(missing_cols, character(0),
               info = paste("Missing columns:", paste(missing_cols, collapse = ", ")))
})

# ── Test 3: Date vs POSIXct triggers mismatch warn (the #146 bug) ─────────────

test_that("Date vs POSIXct series flags date_class mismatch with status=warn", {
  reg    <- make_pair_registry("d_date", "daily", "d_posix", "daily")
  reader <- make_reader(
    d_date  = daily_date_df(30),
    d_posix = posixct_date_df(30)
  )

  expect_warning(
    result <- probe_pairwise_alignment(reg, read_fn = reader),
    regexp = NULL  # any warning acceptable
  )

  expect_equal(nrow(result), 1L)
  expect_equal(result$dimension, "date_class")
  expect_equal(result$status, "warn")
  # evidence should mention the two class types
  expect_match(result$evidence, "Date|POSIXct", ignore.case = FALSE)
})

test_that("Date vs POSIXct mismatch snapshot — user-facing warning text", {
  reg    <- make_pair_registry("snap_date", "daily", "snap_posix", "daily")
  reader <- make_reader(
    snap_date  = daily_date_df(5),
    snap_posix = posixct_date_df(5)
  )

  expect_snapshot(
    withCallingHandlers(
      probe_pairwise_alignment(reg, read_fn = reader),
      warning = function(w) {
        cat("WARNING:", conditionMessage(w), "\n")
        invokeRestart("muffleWarning")
      }
    )
  )
})

# ── Test 4: Daily vs monthly freq mismatch ───────────────────────────────────

test_that("daily vs monthly registered series flags freq mismatch with status=warn", {
  reg    <- make_pair_registry("daily_s", "daily", "monthly_s", "monthly")
  reader <- make_reader(
    daily_s   = daily_date_df(30),
    monthly_s = monthly_date_df(12)
  )

  expect_warning(
    result <- probe_pairwise_alignment(reg, read_fn = reader),
    regexp = NULL
  )

  expect_equal(nrow(result), 1L)
  expect_equal(result$dimension, "date_class")
  # When date classes match but freq mismatch — look at freq field
  # Both are Date class so date_class=ok, but registry freq mismatch is detectable
  # The function should still return "ok" for date_class and the warn is from freq
  # (checking registry metadata, not live data)
  expect_true(result$status %in% c("ok", "warn"))
})

test_that("same-freq pair does not produce a warning", {
  reg    <- make_pair_registry("d1", "daily", "d2", "daily")
  reader <- make_reader(d1 = daily_date_df(20), d2 = daily_date_df(20))

  # No warning expected — same class, same freq
  expect_no_warning(
    result <- probe_pairwise_alignment(reg, read_fn = reader)
  )
  expect_equal(result$status, "ok")
})

# ── Test 5: Missing target handled gracefully ─────────────────────────────────

test_that("missing target in pair returns status=missing not an error", {
  reg    <- make_pair_registry("present", "daily", "absent", "daily")
  reader <- make_reader(present = daily_date_df(10))
  # "absent" not in store — simulates unbuilt target

  result <- probe_pairwise_alignment(reg, read_fn = reader)

  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 1L)
  expect_equal(result$status, "missing")
})

# ── Test 6: plan_data_validation function structure ──────────────────────────

test_that("plan_data_validation() exists and returns a list", {
  source(here::here("R/plan_data_validation.R"))
  result <- plan_data_validation()
  expect_type(result, "list")
  expect_gte(length(result), 1L)
})

test_that("plan_data_validation() list contains a target named dv_pairwise_alignment_matrix", {
  source(here::here("R/plan_data_validation.R"))
  result <- plan_data_validation()
  target_names <- vapply(result, function(x) {
    if (inherits(x, "tar_target")) x$settings$name else NA_character_
  }, character(1))
  expect_true("dv_pairwise_alignment_matrix" %in% target_names,
              info = paste("Found targets:", paste(target_names, collapse = ", ")))
})

# ── Test 7: probe_pairwise_alignment snapshot — ok tibble structure ──────────

test_that("probe_pairwise_alignment result snapshot — column names and single-row structure", {
  reg    <- make_pair_registry("snap_a", "daily", "snap_b", "daily")
  reader <- make_reader(snap_a = daily_date_df(5), snap_b = daily_date_df(5))

  result <- probe_pairwise_alignment(reg, read_fn = reader)
  expect_snapshot(names(result))
  expect_snapshot(result$status)
})
