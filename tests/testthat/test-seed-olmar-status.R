# Tests for scripts/seed_olmar_status.R (Refs #962, #937): OLMAR-1's
# `inconclusive-unmeasurable` status is an APPENDED row, idempotent, unsealed,
# grouped with the older rows, and never edits an existing row. Every run uses
# a temp base_dir seeded with synthetic OLMAR-1 rows; the tracked log is never
# touched.

testthat::local_edition(3)

.olmar_script <- function() here::here("scripts", "seed_olmar_status.R")

.run_olmar <- function(base_dir) {
  rscript <- file.path(R.home("bin"), "Rscript")
  out <- suppressWarnings(system2(
    rscript, c(shQuote(.olmar_script()), shQuote(base_dir)),
    stdout = TRUE, stderr = TRUE
  ))
  out[grepl("^seed_olmar_status:|^  (uuid|parent_uuid|skipped)", out)]
}

.skip_unless_olmar_runnable <- function() {
  testthat::skip_on_cran()
  testthat::skip_if_not(file.exists(.olmar_script()), "seed script not found")
  testthat::skip_if_not_installed("pkgload")
}

# Temp log holding two deprecated-status OLMAR-1 rows (the writer logs one per
# build) plus one unrelated finished idea, so the trial count has a baseline.
.make_olmar_log <- function() {
  d <- tempfile("seed-olmar-")
  dir.create(d)
  claim <- paste0("Equity prices mean-revert toward a short moving average ",
                  "over daily horizons. (synthetic test claim)")
  pred <- "MA/price ratio (OLMAR-1): SMA(25d) / p_t"
  for (i in 1:2) {
    # The deprecated status is what the real writer logs; it warns by design.
    testthat::expect_warning(
      hd_rlog_append("hypotheses", tibble::tibble(
        uuid = hd_rlog_uuid(), economic_claim = claim, predictor = pred,
        status = "tested", extra_json = NA_character_
      ), base_dir = d),
      "deprecated"
    )
  }
  hd_strategy_idea_append(
    name = "other_idea", economic_claim = "An unrelated finished idea",
    source = "test", priority = NA_character_, asset_class = "equity",
    status = "refuted", base_dir = d
  )
  d
}

test_that("seed script appends one status row and is idempotent", {
  .skip_unless_olmar_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_olmar_log()
  first <- .run_olmar(d)
  second <- .run_olmar(d)
  expect_snapshot(cat(sub("(uuid|parent_uuid): [0-9a-f-]+", "\\1: <uuid>",
                          c(first, "--- second run ---", second)), sep = "\n"))
  n_files <- length(list.files(file.path(d, "hypotheses"), pattern = "\\.parquet$"))
  expect_equal(n_files, 4L)
})

test_that("ledger shows OLMAR-1 as unmeasurable, old rows untouched, trials +1", {
  .skip_unless_olmar_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_olmar_log()
  before_rows <- hd_rlog_query("hypotheses", base_dir = d)
  before_led <- suppressMessages(hd_strategy_ledger(base_dir = d))
  before_n <- suppressMessages(hd_strategy_trial_count(base_dir = d))
  expect_equal(before_led$latest_status[grepl("OLMAR-1", before_led$name)], "tested")

  invisible(.run_olmar(d))

  after_rows <- hd_rlog_query("hypotheses", base_dir = d)
  after_led <- suppressMessages(hd_strategy_ledger(base_dir = d))
  olmar <- after_led[grepl("OLMAR-1", after_led$name), ]
  expect_equal(nrow(olmar), 1L)
  expect_equal(olmar$latest_status, "inconclusive-unmeasurable")
  expect_equal(olmar$n_attempts, 3L)

  # Append-only: every earlier row is present and identical.
  expect_equal(nrow(after_rows), nrow(before_rows) + 1L)
  old <- after_rows[after_rows$uuid %in% before_rows$uuid, ]
  old <- old[order(old$uuid), ]
  expect_equal(old, before_rows[order(before_rows$uuid), ])
  expect_equal(sum(old$status == "tested"), 2L)

  # The counter rises by exactly one: the OLMAR group moves from the excluded
  # deprecated status into the counted set.
  expect_equal(suppressMessages(hd_strategy_trial_count(base_dir = d)),
               before_n + 1L)
})

test_that("new row is unsealed, honest, parented on the newest old row", {
  .skip_unless_olmar_runnable()
  pkgload::load_all(here::here("packages", "historicaldata"), quiet = TRUE)
  d <- .make_olmar_log()
  old <- hd_rlog_query("hypotheses", base_dir = d)
  newest_old <- old[old$status == "tested", ]
  newest_old <- newest_old[order(newest_old$timestamp, newest_old$uuid,
                                 decreasing = TRUE)[1L], ]
  invisible(.run_olmar(d))

  rows <- hd_rlog_query("hypotheses", base_dir = d)
  new <- rows[rows$status == "inconclusive-unmeasurable", ]
  expect_equal(nrow(new), 1L)
  expect_equal(new$parent_uuid, newest_old$uuid)
  expect_equal(new$economic_claim, newest_old$economic_claim)
  expect_equal(new$predictor, newest_old$predictor)
  expect_true(is.na(new$commit_hash))
  expect_true(is.na(new$sealed_at))
  expect_true(is.na(new$seal_method))

  ex <- jsonlite::fromJSON(new$extra_json)
  expect_false(ex$preregistered)
  expect_match(ex$seal_omitted_reason, "not a new pre-registration")
  expect_match(ex$status_basis, "no Sharpe, deflated Sharpe or sample size")
  expect_match(ex$status_basis, "not a verdict on the strategy")
  expect_equal(ex$issue, 937L)
})
