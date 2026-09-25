# Tests for the Open Source Asset Pricing (OSAP) loader (#816, #862).
#
# All tests run against a SYNTHETIC fixture written to a tempdir -- no real
# OSAP data is ever downloaded or committed in this test file, per
# public-private-repo-boundary and the #862 P3 unresolved-licence finding.
# testthat edition 3.

testthat::local_edition(3)

# ── Synthetic fixture helpers ────────────────────────────────────────────────

write_signaldoc_fixture <- function(path, acronyms = c("SigA", "SigB", "SigC"), ...) {
  df <- data.frame(
    Acronym         = acronyms,
    Authors         = paste0("Author", seq_along(acronyms)),
    Year            = 2000L + seq_along(acronyms),
    LongDescription = paste0("Description of ", acronyms),
    Journal         = "JF",
    Cat.Signal      = "Predictor",
    Cat.Data        = "Accounting",
    Cat.Economic    = "risk",
    SampleStartYear = 1970L,
    SampleEndYear   = 2000L,
    Sign            = c(1L, -1L, 1L)[seq_along(acronyms)],
    stringsAsFactors = FALSE
  )
  utils::write.csv(df, path, row.names = FALSE)
  invisible(path)
}

write_portfolios_fixture <- function(path, acronyms = c("SigA", "SigB", "SigC"),
                                      scale = "percent", bad_date_row = FALSE, ...) {
  dates <- format(seq(as.Date("2020-01-31"), by = "1 month", length.out = 6), "%Y-%m-%d")
  if (bad_date_row) dates[3] <- "not-a-date"

  df <- data.frame(date = dates, stringsAsFactors = FALSE)
  set.seed(42)
  for (a in acronyms) {
    vals <- round(stats::rnorm(length(dates), mean = 1, sd = 5), 4)  # percent scale
    if (scale == "fraction") vals <- vals / 100
    df[[a]] <- vals
  }
  utils::write.csv(df, path, row.names = FALSE)
  invisible(path)
}

write_full_fixture <- function(dir, ...) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write_signaldoc_fixture(file.path(dir, "SignalDoc.csv"), ...)
  write_portfolios_fixture(file.path(dir, "portfolios_wide.csv"), ...)
  invisible(dir)
}

# ── hd_osap_data_dir ──────────────────────────────────────────────────────────

test_that("hd_osap_data_dir: defaults to ~/.cache/historical/osap", {
  withr::local_envvar(OSAP_DATA_DIR = NA)
  expect_equal(hd_osap_data_dir(), path.expand("~/.cache/historical/osap"))
})

test_that("hd_osap_data_dir: honours OSAP_DATA_DIR", {
  withr::local_envvar(OSAP_DATA_DIR = "/tmp/custom_osap_dir")
  expect_equal(hd_osap_data_dir(), "/tmp/custom_osap_dir")
})

# ── hd_osap_load: happy path ──────────────────────────────────────────────────

test_that("hd_osap_load: returns expected structure on a synthetic fixture", {
  tmp <- withr::local_tempdir()
  write_full_fixture(tmp)

  out <- hd_osap_load(tmp, min_predictors = 1L)

  expect_s3_class(out, "tbl_df")
  expect_named(out, c(
    "predictor", "date", "ret", "metric_unit",
    "signal_sign", "signal_authors", "signal_year", "signal_description",
    "signal_journal", "signal_category", "signal_data_category",
    "signal_economic_category", "signal_sample_start", "signal_sample_end"
  ))
  expect_equal(nrow(out), 3L * 6L)  # 3 predictors x 6 months
  expect_true(inherits(out$date, "Date"))
  expect_true(all(out$metric_unit == "fraction"))
  expect_setequal(unique(out$predictor), c("SigA", "SigB", "SigC"))
})

test_that("hd_osap_load: converts percent to fraction (divides by 100)", {
  tmp <- withr::local_tempdir()
  write_full_fixture(tmp, acronyms = "SigA")
  raw <- utils::read.csv(file.path(tmp, "portfolios_wide.csv"))

  out <- hd_osap_load(tmp, min_predictors = 1L)
  out <- out[order(out$date), ]

  expect_equal(out$ret, raw$SigA / 100, tolerance = 1e-9)
})

test_that("hd_osap_load: joins SignalDoc metadata correctly", {
  tmp <- withr::local_tempdir()
  write_full_fixture(tmp)

  out <- hd_osap_load(tmp, min_predictors = 1L)

  sig_a <- out[out$predictor == "SigA", ]
  expect_true(all(sig_a$signal_authors == "Author1"))
  expect_true(all(sig_a$signal_sign == 1L))
  sig_b <- out[out$predictor == "SigB", ]
  expect_true(all(sig_b$signal_sign == -1L))
})

test_that("hd_osap_load: drops NA return observations", {
  tmp <- withr::local_tempdir()
  write_full_fixture(tmp)
  wide <- utils::read.csv(file.path(tmp, "portfolios_wide.csv"))
  wide$SigA[2] <- NA
  utils::write.csv(wide, file.path(tmp, "portfolios_wide.csv"), row.names = FALSE)

  out <- hd_osap_load(tmp, min_predictors = 1L)

  expect_equal(nrow(out), 3L * 6L - 1L)
  expect_false(any(is.na(out$ret)))
})

# ── hd_osap_load: abort paths (fail-loud-not-null) ───────────────────────────

test_that("hd_osap_load: aborts when the cache directory is missing files", {
  tmp <- withr::local_tempdir()  # empty -- neither file exists
  expect_snapshot(
    error = TRUE,
    transform = function(x) gsub(tmp, "<TMP>", x, fixed = TRUE),
    hd_osap_load(tmp)
  )
})

test_that("hd_osap_load: aborts on a malformed date", {
  tmp <- withr::local_tempdir()
  write_signaldoc_fixture(file.path(tmp, "SignalDoc.csv"))
  write_portfolios_fixture(file.path(tmp, "portfolios_wide.csv"), bad_date_row = TRUE)

  expect_snapshot(error = TRUE, hd_osap_load(tmp, min_predictors = 1L))
})

test_that("hd_osap_load: aborts when values look already-fraction scale", {
  tmp <- withr::local_tempdir()
  write_full_fixture(tmp, scale = "fraction")

  expect_snapshot(error = TRUE, hd_osap_load(tmp, min_predictors = 1L))
})

test_that("hd_osap_load: aborts on a predictor with no SignalDoc match", {
  tmp <- withr::local_tempdir()
  dir.create(tmp, showWarnings = FALSE)
  write_signaldoc_fixture(file.path(tmp, "SignalDoc.csv"), acronyms = c("SigA", "SigB"))
  write_portfolios_fixture(
    file.path(tmp, "portfolios_wide.csv"),
    acronyms = c("SigA", "SigB", "SigUnknown")
  )

  expect_snapshot(error = TRUE, hd_osap_load(tmp, min_predictors = 1L))
})

test_that("hd_osap_load: aborts when portfolios_wide.csv has no date column", {
  tmp <- withr::local_tempdir()
  dir.create(tmp, showWarnings = FALSE)
  write_signaldoc_fixture(file.path(tmp, "SignalDoc.csv"))
  bad <- data.frame(not_date = 1:3, SigA = c(1, 2, 3))
  utils::write.csv(bad, file.path(tmp, "portfolios_wide.csv"), row.names = FALSE)

  expect_snapshot(error = TRUE, hd_osap_load(tmp, min_predictors = 1L))
})

test_that("hd_osap_load: aborts when SignalDoc.csv is missing expected columns", {
  tmp <- withr::local_tempdir()
  dir.create(tmp, showWarnings = FALSE)
  bad_signaldoc <- data.frame(Acronym = "SigA", Authors = "A")
  utils::write.csv(bad_signaldoc, file.path(tmp, "SignalDoc.csv"), row.names = FALSE)
  write_portfolios_fixture(file.path(tmp, "portfolios_wide.csv"), acronyms = "SigA")

  expect_snapshot(error = TRUE, hd_osap_load(tmp, min_predictors = 1L))
})

test_that("hd_osap_load: aborts when there are fewer predictor columns than min_predictors", {
  tmp <- withr::local_tempdir()
  write_full_fixture(tmp)  # only 3 predictor columns

  expect_snapshot(error = TRUE, hd_osap_load(tmp))  # default min_predictors = 50L
})

# ── hd_register_add_dataset: OSAP-specific fields stay consistent ───────────

test_that("hd_register_add_dataset: expected_schema matches hd_osap_load()'s output columns", {
  tmp <- withr::local_tempdir()
  write_full_fixture(tmp)
  out <- hd_osap_load(tmp, min_predictors = 1L)

  reg <- hd_register_add_dataset()
  expect_setequal(reg$expected_schema, names(out))
})
