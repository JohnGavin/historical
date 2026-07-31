testthat::local_edition(3)

# Tests for hypothesis sealing (#598).
#
# The point of a seal is that a claim cannot be silently reworded after the
# outcome is known.  These tests pin that property.

make_hyp <- function(n = 2L) {
  tibble::tibble(
    uuid            = sprintf("uuid-%02d", seq_len(n)),
    parent_uuid     = NA_character_,
    timestamp       = as.POSIXct("2026-07-31 12:00:00", tz = "UTC"),
    git_commit      = "abc1234",
    sandbox_image_hash = "deadbeef",
    economic_claim  = sprintf("claim %d", seq_len(n)),
    dependent_var   = "fwd_ret_1m",
    predictor       = "vol_regime",
    sample_spec     = "2010-01/2026-01, monthly",
    null_hypothesis = "beta = 0",
    status          = "proposed",
    commit_hash     = NA_character_,
    sealed_at       = as.POSIXct(NA),
    seal_method     = NA_character_,
    extra_json      = NA_character_
  )
}

FIXED_TIME <- as.POSIXct("2026-07-31 09:00:00", tz = "UTC")

# ── Sealing ─────────────────────────────────────────────────────────────────

test_that("sealing fills the commitment columns", {
  out <- hd_rlog_seal(make_hyp(2L), sealed_at = FIXED_TIME)
  expect_true(all(nzchar(out$commit_hash)))
  expect_equal(nchar(out$commit_hash), c(64L, 64L))  # SHA-256 hex
  expect_equal(out$seal_method, rep("sha256-v1", 2L))
  expect_false(any(is.na(out$sealed_at)))
})

test_that("distinct hypotheses get distinct hashes", {
  out <- hd_rlog_seal(make_hyp(3L), sealed_at = FIXED_TIME)
  expect_equal(length(unique(out$commit_hash)), 3L)
})

test_that("sealing is deterministic across calls", {
  a <- hd_rlog_seal(make_hyp(2L), sealed_at = FIXED_TIME)
  b <- hd_rlog_seal(make_hyp(2L), sealed_at = FIXED_TIME)
  expect_equal(a$commit_hash, b$commit_hash)
})

test_that("the hash is insensitive to surrounding whitespace", {
  h <- make_hyp(1L)
  h2 <- h
  h2$economic_claim <- paste0("  ", h$economic_claim, "  ")
  expect_equal(
    hd_rlog_seal(h,  sealed_at = FIXED_TIME)$commit_hash,
    hd_rlog_seal(h2, sealed_at = FIXED_TIME)$commit_hash
  )
})

test_that("status is excluded from the hash so it can advance after sealing", {
  h <- make_hyp(1L)
  sealed <- hd_rlog_seal(h, sealed_at = FIXED_TIME)
  sealed$status <- "rejected"
  expect_true(hd_rlog_seal_verify(sealed)$ok)
})

test_that("re-sealing an already-sealed row is refused by default", {
  sealed <- hd_rlog_seal(make_hyp(1L), sealed_at = FIXED_TIME)
  original <- sealed$commit_hash

  sealed$economic_claim <- "a completely different claim"
  expect_snapshot(reseal <- hd_rlog_seal(sealed, sealed_at = FIXED_TIME))
  expect_equal(reseal$commit_hash, original)  # untouched

  # ...but overwrite = TRUE is honoured, and breaks the commitment
  forced <- hd_rlog_seal(sealed, sealed_at = FIXED_TIME, overwrite = TRUE)
  expect_false(identical(forced$commit_hash, original))
})

test_that("sealing refuses rows missing a claim field", {
  h <- make_hyp(1L)
  h$null_hypothesis <- NULL
  expect_snapshot(error = TRUE, hd_rlog_seal(h))
})

test_that("sealing an empty frame is a no-op", {
  empty <- make_hyp(1L)[0, ]
  expect_equal(nrow(hd_rlog_seal(empty)), 0L)
})

# ── Verification ────────────────────────────────────────────────────────────

test_that("verification passes for untouched sealed rows", {
  sealed <- hd_rlog_seal(make_hyp(3L), sealed_at = FIXED_TIME)
  res <- hd_rlog_seal_verify(sealed)
  expect_equal(nrow(res), 3L)
  expect_true(all(res$ok))
})

test_that("verification detects a reworded claim", {
  sealed <- hd_rlog_seal(make_hyp(2L), sealed_at = FIXED_TIME)
  sealed$economic_claim[2] <- "quietly reworded after seeing the outcome"

  expect_snapshot(res <- hd_rlog_seal_verify(sealed))
  expect_equal(res$ok, c(TRUE, FALSE))
})

test_that("verification detects a changed sample specification", {
  # The subtler tamper: same claim, sample window widened after the fact.
  sealed <- hd_rlog_seal(make_hyp(1L), sealed_at = FIXED_TIME)
  sealed$sample_spec <- "2015-01/2026-01, monthly"
  expect_warning(res <- hd_rlog_seal_verify(sealed))
  expect_false(res$ok)
})

test_that("strict verification aborts on mismatch", {
  sealed <- hd_rlog_seal(make_hyp(1L), sealed_at = FIXED_TIME)
  sealed$economic_claim <- "tampered"
  expect_snapshot(error = TRUE, hd_rlog_seal_verify(sealed, strict = TRUE))
})

test_that("unsealed rows verify as NA, not as tampered", {
  rows <- make_hyp(2L)  # commit_hash all NA
  res <- hd_rlog_seal_verify(rows)
  expect_true(all(is.na(res$ok)))
})

test_that("verification refuses rows with no commit_hash column", {
  rows <- make_hyp(1L)
  rows$commit_hash <- NULL
  expect_snapshot(error = TRUE, hd_rlog_seal_verify(rows))
})

# ── Schema ──────────────────────────────────────────────────────────────────

test_that("hypotheses schema carries the commitment columns", {
  s <- hd_rlog_schema("hypotheses")
  expect_true(all(c("commit_hash", "sealed_at", "seal_method") %in% names(s)))
  expect_type(s$commit_hash, "character")
  expect_s3_class(s$sealed_at, "POSIXct")
})

# ── API stability ───────────────────────────────────────────────────────────

test_that("sealing function signatures are stable", {
  expect_snapshot(args(hd_rlog_seal))
  expect_snapshot(args(hd_rlog_seal_verify))
  expect_snapshot(args(hd_rlog_seal_export))
})
