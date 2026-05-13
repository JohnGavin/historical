testthat::local_edition(3)
source(here::here("R/dataset_registry.R"))
source(here::here("R/utils_dates.R"))       # to_month_end_bizday() needed by check_monthly_convention
source(here::here("R/utils_validation.R"))

# ── Helper factories ──────────────────────────────────────────────────────────

# Build a fake read_fn that returns pre-built tibbles keyed by name.
# The parameter approach avoids any targets store I/O in tests.
make_reader <- function(...) {
  store <- list(...)
  function(nm) {
    if (!nm %in% names(store)) stop(paste0("target not found: ", nm))
    store[[nm]]
  }
}

make_registry <- function(...) {
  rows <- list(...)
  tibble::tibble(
    target_name = vapply(rows, `[[`, character(1), "name"),
    kind = "returns", freq = "monthly", date_anchor = "end_bizday", notes = NA_character_
  )
}

date_df <- function(cls = "Date") {
  d <- if (cls == "Date") as.Date("2025-01-31") else as.POSIXct("2025-01-31")
  tibble::tibble(date = d, value = 1.0)
}

# ── Test 1: Homogeneous Date types → returns OK tibble ───────────────────────

test_that("homogeneous Date types returns ok tibble without aborting", {
  reg <- tibble::tibble(
    target_name = c("a", "b", "c"),
    kind = "returns", freq = "monthly", date_anchor = "end_bizday", notes = NA_character_
  )
  reader <- make_reader(
    a = date_df("Date"),
    b = date_df("Date"),
    c = date_df("Date")
  )
  result <- check_date_key_types(reg, read_fn = reader)
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 3L)
  expect_true(all(result$status == "ok"))
  expect_true(all(result$date_class == "Date"))
})

# ── Test 2: Mixed Date and POSIXct → aborts ──────────────────────────────────

test_that("mixed Date and POSIXct triggers cli_abort naming both class types", {
  reg <- tibble::tibble(
    target_name = c("d_date", "d_posix", "d_date2"),
    kind = "returns", freq = "monthly", date_anchor = "end_bizday", notes = NA_character_
  )
  reader <- make_reader(
    d_date  = date_df("Date"),
    d_posix = date_df("POSIXct"),
    d_date2 = date_df("Date")
  )
  expect_error(
    check_date_key_types(reg, read_fn = reader),
    class = "rlang_error"
  )
})

test_that("mixed-types abort message names the offending targets and classes", {
  reg <- tibble::tibble(
    target_name = c("d_date", "d_posix"),
    kind = "returns", freq = "monthly", date_anchor = "end_bizday", notes = NA_character_
  )
  reader <- make_reader(
    d_date  = date_df("Date"),
    d_posix = date_df("POSIXct")
  )
  # Snapshot the user-facing abort message — this is the primary user surface
  expect_snapshot(
    error = TRUE,
    check_date_key_types(reg, read_fn = reader)
  )
})

# ── Test 3: Missing date column → aborts with no-date-column message ─────────

test_that("target lacking date column is flagged and causes abort", {
  reg <- tibble::tibble(
    target_name = c("no_date_col"),
    kind = "returns", freq = "monthly", date_anchor = "end_bizday", notes = NA_character_
  )
  reader <- make_reader(
    no_date_col = tibble::tibble(value = 1.0)  # no date column
  )
  expect_error(
    check_date_key_types(reg, read_fn = reader),
    class = "rlang_error"
  )
})

# ── Test 4: Missing/broken target → skipped, does not abort ──────────────────

test_that("uncached target marked missing does not contribute to unique-class count", {
  reg <- tibble::tibble(
    target_name = c("present", "broken"),
    kind = "returns", freq = "monthly", date_anchor = "end_bizday", notes = NA_character_
  )
  # "broken" is not in the reader store → simulates a cache-miss
  reader <- make_reader(present = date_df("Date"))

  # Should not abort — only one present target, unique classes = {Date}
  result <- check_date_key_types(reg, read_fn = reader)
  expect_equal(nrow(result), 2L)
  expect_equal(result$status[result$target_name == "present"], "ok")
  expect_equal(result$status[result$target_name == "broken"], "missing")
})

test_that("missing target does not cause false type mismatch abort", {
  reg <- tibble::tibble(
    target_name = c("real_date", "missing_one"),
    kind = "returns", freq = "monthly", date_anchor = "end_bizday", notes = NA_character_
  )
  reader <- make_reader(real_date = date_df("Date"))
  # No abort expected: only one ok row, unique date_class has length 1
  result <- check_date_key_types(reg, read_fn = reader)
  expect_equal(sum(result$status == "ok"), 1L)
  expect_equal(sum(result$status == "missing"), 1L)
})

# ── Test 5: Empty registry → returns empty tibble without abort ───────────────

test_that("empty registry returns zero-row tibble without aborting", {
  reg <- tibble::tibble(
    target_name = character(0),
    kind = character(0), freq = character(0),
    date_anchor = character(0), notes = character(0)
  )
  reader <- make_reader()  # nothing in store
  result <- check_date_key_types(reg, read_fn = reader)
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 0L)
})

test_that("single-target registry returns ok without abort", {
  reg <- tibble::tibble(
    target_name = "solo",
    kind = "returns", freq = "monthly", date_anchor = "end_bizday", notes = NA_character_
  )
  reader <- make_reader(solo = date_df("Date"))
  result <- check_date_key_types(reg, read_fn = reader)
  expect_equal(nrow(result), 1L)
  expect_equal(result$status, "ok")
})

# ── Test 6: dataset_registry() returns the expected columns ──────────────────

test_that("dataset_registry returns a tibble with expected columns", {
  reg <- dataset_registry()
  expect_s3_class(reg, "tbl_df")
  expect_true(all(c("target_name", "kind", "freq", "date_anchor", "notes") %in% names(reg)))
  expect_true(nrow(reg) >= 1L)
})

# ── Tests 7-11: check_monthly_convention() ───────────────────────────────────
# Note: dv_monthly_convention target body is a one-liner that calls
# check_monthly_convention(), so unit tests here exercise the full logic.
# Direct testing of the target body is not feasible without a live targets
# store — the read_fn injection pattern makes the helper fully testable.

make_monthly_reader <- function(...) {
  store <- list(...)
  function(nm) {
    if (!nm %in% names(store)) stop(paste0("target not found: ", nm))
    store[[nm]]
  }
}

# Build a tibble of month-end-bizday dates (last biz day of each month)
month_end_dates <- function(n = 12) {
  # Use known month-end business days for 2025
  dates <- as.Date(c(
    "2025-01-31", "2025-02-28", "2025-03-31", "2025-04-30",
    "2025-05-30", "2025-06-30", "2025-07-31", "2025-08-29",
    "2025-09-30", "2025-10-31", "2025-11-28", "2025-12-31"
  ))
  tibble::tibble(date = dates[seq_len(n)], ret = rnorm(n))
}

# Build a tibble with mid-month dates (not month-end-bizday)
mid_month_dates <- function(n = 12) {
  dates <- seq(as.Date("2025-01-15"), by = "month", length.out = n)
  tibble::tibble(date = dates, ret = rnorm(n))
}

test_that("check_monthly_convention returns ok tibble when all dates are month-end-bizday", {
  reader <- make_monthly_reader(
    tgt_a = month_end_dates(12),
    tgt_b = month_end_dates(6)
  )
  result <- check_monthly_convention(c("tgt_a", "tgt_b"), read_fn = reader)
  expect_s3_class(result, "tbl_df")
  expect_equal(nrow(result), 2L)
  expect_true(all(result$status == "ok"))
  expect_true(all(result$pct_match >= 0.95, na.rm = TRUE))
})

test_that("check_monthly_convention warns and returns ok row when dates deviate", {
  reader <- make_monthly_reader(tgt_mid = mid_month_dates(12))
  expect_warning(
    result <- check_monthly_convention("tgt_mid", read_fn = reader),
    regexp = NULL  # any warning is expected
  )
  expect_equal(nrow(result), 1L)
  expect_equal(result$status, "ok")
  expect_true(result$pct_match < 0.95)
})

test_that("check_monthly_convention marks missing targets with status=missing not status=ok", {
  reader <- make_monthly_reader(present = month_end_dates(6))
  # "absent" is not in the store — simulates an unbuilt target
  result <- check_monthly_convention(c("present", "absent"), read_fn = reader)
  expect_equal(nrow(result), 2L)
  expect_equal(result$status[result$target == "present"], "ok")
  expect_equal(result$status[result$target == "absent"], "missing")
  expect_equal(result$n[result$target == "absent"], 0L)
})

test_that("check_monthly_convention marks target lacking date column as missing", {
  reader <- make_monthly_reader(no_date = tibble::tibble(ret = 1:12))
  result <- check_monthly_convention("no_date", read_fn = reader)
  expect_equal(nrow(result), 1L)
  expect_equal(result$status, "missing")
})

test_that("check_monthly_convention snapshot — ok tibble structure", {
  reader <- make_monthly_reader(snap_tgt = month_end_dates(3))
  result <- check_monthly_convention("snap_tgt", read_fn = reader)
  expect_snapshot(names(result))
  expect_snapshot(result$status)
})
