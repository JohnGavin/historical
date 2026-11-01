testthat::local_edition(3)
source(here::here("R/momentum_decomposition.R"))

# Regression for the Ken French shared-tempdir collision (2026-11-01): every
# download used to be unzipped into the shared tempdir() and csv_files[1] was
# read, so after 12_Industry_Portfolios the 5-factor and momentum fetches read
# the industries file and failed with "undefined columns selected".
# NO network: download.file and unzip are mocked.

.ff_fake_csv <- function(ncol_data, header = "Mkt-RF,SMB") {
  rows <- vapply(c("192607", "192608", "192609"), function(d) {
    paste(c(d, round(seq_len(ncol_data - 1L) * 1.5 - 2, 2)), collapse = ",")
  }, character(1))
  c(
    "This file was created by CMPT_ME_BEME_RETS using the 202409 CRSP database.",
    "",
    paste0(",", header),
    unname(rows),
    "",
    "  Annual Factors: January-December",
    ",Mkt-RF,SMB"
  )
}

.ff_ncol <- c(
  "F-F_Research_Data_5_Factors_2x3" = 7L,
  "F-F_Momentum_Factor"             = 2L,
  "12_Industry_Portfolios"          = 13L
)

# Mock the two network-touching calls: "download" records the requested
# dataset in the zip file; "unzip" writes that dataset's fake CSV into exdir.
.ff_mock_network <- function(env = parent.frame()) {
  testthat::local_mocked_bindings(
    download.file = function(url, destfile, ...) {
      ds <- sub("_CSV\\.zip$", "", basename(url))
      writeLines(ds, destfile)
      0L
    },
    unzip = function(zipfile, exdir, ...) {
      ds <- readLines(zipfile)
      writeLines(.ff_fake_csv(.ff_ncol[[ds]]), file.path(exdir, paste0(ds, ".csv")))
      invisible(NULL)
    },
    .package = "utils",
    .env = env
  )
}

test_that("the helper parses each dataset shape from its own directory", {
  for (ds in names(.ff_ncol)) {
    d <- withr::local_tempdir()
    writeLines(.ff_fake_csv(.ff_ncol[[ds]]), file.path(d, "x.csv"))
    out <- .ff_read_csv_dir(d, ds, "monthly")
    expect_equal(ncol(out), .ff_ncol[[ds]])
    expect_equal(nrow(out), 3L)
    expect_s3_class(out$date, "Date")
    expect_equal(out$date[1], as.Date("1926-07-01"))
  }
  d <- withr::local_tempdir()
  writeLines(.ff_fake_csv(7L), file.path(d, "x.csv"))
  expect_equal(
    names(.ff_read_csv_dir(d, "F-F_Research_Data_5_Factors_2x3", "monthly")),
    c("date", "Mkt.RF", "SMB", "HML", "RMW", "CMA", "RF")
  )
})

test_that("a download after the industries fetch is not confused by it", {
  .ff_mock_network()
  ind <- suppressMessages(hd_ff_factors("12_Industry_Portfolios", "monthly", cache = FALSE))
  expect_equal(ncol(ind), 13L)
  f5 <- suppressMessages(hd_ff_factors("F-F_Research_Data_5_Factors_2x3", "monthly", cache = FALSE))
  expect_equal(ncol(f5), 7L)
  expect_equal(names(f5)[2:3], c("Mkt.RF", "SMB"))
  mom <- suppressMessages(hd_ff_factors("F-F_Momentum_Factor", "monthly", cache = FALSE))
  expect_equal(names(mom), c("date", "Mom"))
})

test_that("a wrong column count aborts naming dataset, expected and found", {
  d <- withr::local_tempdir()
  writeLines(.ff_fake_csv(13L), file.path(d, "ind.csv"))
  expect_snapshot(
    .ff_read_csv_dir(d, "F-F_Research_Data_5_Factors_2x3", "monthly"),
    error = TRUE
  )
  expect_snapshot(
    .ff_read_csv_dir(d, "F-F_Momentum_Factor", "monthly"),
    error = TRUE
  )
})

test_that("an extraction directory without a csv aborts", {
  d <- withr::local_tempdir()
  expect_error(.ff_read_csv_dir(d, "F-F_Momentum_Factor", "monthly"), "No CSV file")
})
