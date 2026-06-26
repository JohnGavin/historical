# Tests for digest.R — hd_digest_delta, hd_digest_attention, hd_digest_html,
# hd_digest_snapshot_write.
#
# Snapshot policy (snapshot-test-policy.md):
#   - 9+ test_that blocks → ≥ 30% snapshots → need ≥ 3 snapshots.
#   - This file has 12 test blocks → needs ≥ 4 snapshots.
#   - Snapshots cover: error messages, hd_digest_html body string,
#     hd_digest_attention output, function signature.
#
# Issue: #482 (Slice 1)

# ── Fixtures ──────────────────────────────────────────────────────────────────

.make_current <- function() {
  tibble::tibble(
    strategy        = c("Factor MAX", "Factor DRIF", "LTR"),
    period          = c("Full Period", "Full Period", "Full Period"),
    sharpe          = c(1.2, 0.9, 0.6),
    net_cagr        = c(0.12, 0.08, 0.05),
    max_dd          = c(-0.15, -0.20, -0.25),
    redundant       = c(FALSE, FALSE, FALSE),
    add_flag        = c(FALSE, FALSE, FALSE),
    wfc_verdict     = c("structural_edge", "noise", "structural_edge"),
    ci_crosses_zero = c(FALSE, FALSE, FALSE),
    dsr_pvalue      = c(0.03, 0.08, 0.02)
  )
}

.make_prior_clean <- function() {
  # Identical to current → all "unchanged"
  .make_current()
}

.make_prior_with_changes <- function() {
  tibble::tibble(
    strategy        = c("Factor MAX", "Factor DRIF"),
    period          = c("Full Period", "Full Period"),
    sharpe          = c(1.5, 0.9),       # MAX sharpe was 1.5, now 1.2 → d_sharpe = -0.3
    net_cagr        = c(0.15, 0.08),
    max_dd          = c(-0.10, -0.20),
    redundant       = c(FALSE, TRUE),    # DRIF was redundant, MAX was not
    add_flag        = c(FALSE, FALSE),
    wfc_verdict     = c("structural_edge", "structural_edge"),  # DRIF changed
    ci_crosses_zero = c(FALSE, FALSE),
    dsr_pvalue      = c(0.02, 0.03)      # DRIF was significant, now 0.08 → sig_flip
  )
}

# current with a "became_redundant" and a "became_crowded" strategy
.make_current_flagged <- function() {
  tibble::tibble(
    strategy        = c("Factor MAX", "Factor DRIF", "LTR"),
    period          = c("Full Period", "Full Period", "Full Period"),
    sharpe          = c(1.2, 0.9, 0.6),
    net_cagr        = c(0.12, 0.08, 0.05),
    max_dd          = c(-0.15, -0.20, -0.25),
    redundant       = c(TRUE,  FALSE, FALSE),  # MAX became redundant
    add_flag        = c(FALSE, TRUE,  FALSE),  # DRIF became crowded
    wfc_verdict     = c("structural_edge", "consistently_loss_making", "noise"),
    ci_crosses_zero = c(TRUE,  FALSE, FALSE),  # MAX ci now crosses zero
    dsr_pvalue      = c(0.03, 0.08, 0.06)
  )
}

# ── 1. Baseline run (prior = NULL) ────────────────────────────────────────────

test_that("baseline run sets status='new' and all flags FALSE", {
  cur   <- .make_current()
  delta <- hd_digest_delta(cur, prior = NULL)

  expect_s3_class(delta, "tbl_df")
  expect_equal(nrow(delta), 3L)
  expect_true(all(delta$status == "new"))
  expect_true(all(!delta$became_redundant))
  expect_true(all(!delta$became_crowded))
  expect_true(all(!delta$wfc_verdict_changed))
  expect_true(all(!delta$ci_now_crosses_zero))
  expect_true(all(!delta$dsr_sig_flip))
})

test_that("baseline run: delta columns are NA, sharpe_now is filled", {
  cur   <- .make_current()
  delta <- hd_digest_delta(cur, prior = NULL)

  expect_true(all(is.na(delta$d_sharpe)))
  expect_true(all(is.na(delta$sharpe_prev)))
  expect_equal(delta$sharpe_now, cur$sharpe)
})

# ── 2. Incremental run — unchanged strategies ─────────────────────────────────

test_that("identical current and prior: all strategies 'unchanged'", {
  cur   <- .make_current()
  pri   <- .make_prior_clean()
  delta <- hd_digest_delta(cur, prior = pri)

  # prior_clean = current → all three strategies in both sets → all "unchanged"
  expect_true(all(delta$status == "unchanged"))
  expect_equal(delta$status[delta$strategy == "Factor MAX"], "unchanged")
  expect_equal(delta$status[delta$strategy == "Factor DRIF"], "unchanged")
  expect_equal(delta$status[delta$strategy == "LTR"], "unchanged")
})

# ── 3. Incremental run — structural flag changes ──────────────────────────────

test_that("structural flags detected correctly against prior", {
  cur   <- .make_current_flagged()
  # Use .make_prior_with_changes() which only has Factor MAX + Factor DRIF,
  # so LTR is genuinely "new" (absent from the prior).
  pri   <- .make_prior_with_changes()
  delta <- hd_digest_delta(cur, prior = pri)

  # Factor MAX: became_redundant, ci_now_crosses_zero → status = "changed"
  fmax <- delta[delta$strategy == "Factor MAX", ]
  expect_true(fmax$became_redundant)
  expect_true(fmax$ci_now_crosses_zero)
  expect_equal(fmax$status, "changed")

  # Factor DRIF: became_crowded, wfc_verdict_changed → status = "changed"
  fdrif <- delta[delta$strategy == "Factor DRIF", ]
  expect_true(fdrif$became_crowded)
  expect_true(fdrif$wfc_verdict_changed)
  expect_equal(fdrif$status, "changed")

  # LTR: new in current, not in prior
  ltr <- delta[delta$strategy == "LTR", ]
  expect_equal(ltr$status, "new")
})

test_that("dsr_sig_flip: was < 0.05, now >= 0.05", {
  cur <- tibble::tibble(
    strategy = "DRIF", period = "Full Period",
    sharpe = 0.9, net_cagr = 0.08, max_dd = -0.20,
    dsr_pvalue = 0.08   # now >= 0.05 → flip
  )
  pri <- tibble::tibble(
    strategy = "DRIF", period = "Full Period",
    sharpe = 0.9, net_cagr = 0.08, max_dd = -0.20,
    dsr_pvalue = 0.03   # was < 0.05 → significant
  )
  delta <- hd_digest_delta(cur, prior = pri)
  expect_true(delta$dsr_sig_flip)
  expect_equal(delta$status, "changed")
})

test_that("Sharpe drop alone does NOT set status='changed'", {
  # Per resulting-prohibition: metric moves are information only.
  cur <- tibble::tibble(
    strategy = "LTR", period = "Full Period",
    sharpe = 0.5, net_cagr = 0.04, max_dd = -0.30
  )
  pri <- tibble::tibble(
    strategy = "LTR", period = "Full Period",
    sharpe = 1.0, net_cagr = 0.09, max_dd = -0.20
  )
  delta <- hd_digest_delta(cur, prior = pri)
  expect_equal(delta$status, "unchanged")
  expect_true(delta$d_sharpe < 0)  # drop is recorded, just not flagged
})

# ── 4. Missing columns — graceful degradation ─────────────────────────────────

test_that("missing optional columns are tolerated (NA inserted)", {
  cur <- tibble::tibble(strategy = "X", period = "Full Period", sharpe = 1.0)
  expect_no_error(hd_digest_delta(cur, prior = NULL))
  delta <- hd_digest_delta(cur, prior = NULL)
  expect_true(is.na(delta$net_cagr_now))
  expect_true(is.na(delta$max_dd_now))
})

# ── 5. Input validation ───────────────────────────────────────────────────────

test_that("non-data-frame current raises informative error", {
  expect_snapshot(error = TRUE, hd_digest_delta("not_a_df", prior = NULL))
})

test_that("missing strategy column raises informative error", {
  expect_snapshot(error = TRUE, hd_digest_delta(
    tibble::tibble(sharpe = 1.0, period = "Full Period"),
    prior = NULL
  ))
})

# ── 6. hd_digest_attention ────────────────────────────────────────────────────

test_that("attention: correct lines for structural flags", {
  delta <- tibble::tibble(
    strategy            = c("Factor MAX", "LTR", "DRIF"),
    status              = c("changed", "changed", "unchanged"),
    d_sharpe            = c(-0.3, 0.0, 0.0),   # drop NOT flagged
    became_redundant    = c(FALSE, TRUE, FALSE),
    became_crowded      = c(FALSE, FALSE, FALSE),
    wfc_verdict_changed = c(FALSE, FALSE, FALSE),
    wfc_verdict_from    = c(NA_character_, NA_character_, NA_character_),
    wfc_verdict_to      = c(NA_character_, NA_character_, NA_character_),
    ci_now_crosses_zero = c(TRUE, FALSE, FALSE),
    dsr_sig_flip        = c(FALSE, FALSE, FALSE)
  )
  attn <- hd_digest_attention(delta)
  expect_snapshot(attn)
  # LTR is newly redundant; Factor MAX has CI crossing zero
  expect_true(any(grepl("LTR.*redundant", attn)))
  expect_true(any(grepl("Factor MAX.*CI", attn)))
  # Sharpe drop for Factor MAX: NOT in attention
  expect_false(any(grepl("Sharpe.*drop|drop.*Sharpe|d_sharpe", attn)))
})

test_that("attention: empty vector when no structural flags", {
  delta <- tibble::tibble(
    strategy            = "Factor MAX",
    status              = "unchanged",
    d_sharpe            = -0.5,  # big drop but not structural
    became_redundant    = FALSE,
    became_crowded      = FALSE,
    wfc_verdict_changed = FALSE,
    wfc_verdict_from    = NA_character_,
    wfc_verdict_to      = NA_character_,
    ci_now_crosses_zero = FALSE,
    dsr_sig_flip        = FALSE
  )
  expect_equal(hd_digest_attention(delta), character(0L))
})

# ── 7. hd_digest_html ────────────────────────────────────────────────────────

test_that("hd_digest_html returns non-empty string with correct structure", {
  cur   <- .make_current()
  delta <- hd_digest_delta(cur, prior = NULL)
  attn  <- hd_digest_attention(delta)
  html  <- hd_digest_html(delta, attn, caption = "Test caption.")

  expect_type(html, "character")
  expect_length(html, 1L)
  expect_true(nzchar(html))
  expect_true(grepl("<!DOCTYPE html>", html, fixed = TRUE))
  expect_true(grepl("Strategy Digest", html, fixed = TRUE))
  expect_true(grepl("Test caption.", html, fixed = TRUE))
})

test_that("hd_digest_html snapshot stable on fixed input", {
  cur <- tibble::tibble(
    strategy        = c("Factor MAX", "Factor DRIF"),
    period          = c("Full Period", "Full Period"),
    sharpe          = c(1.2, 0.9),
    net_cagr        = c(0.12, 0.08),
    max_dd          = c(-0.15, -0.20),
    redundant       = c(FALSE, FALSE),
    add_flag        = c(TRUE,  FALSE),
    wfc_verdict     = c("structural_edge", "noise"),
    ci_crosses_zero = c(FALSE, FALSE),
    dsr_pvalue      = c(0.03, 0.08)
  )
  pri <- tibble::tibble(
    strategy        = "Factor MAX",
    period          = "Full Period",
    sharpe          = 1.5,
    net_cagr        = 0.15,
    max_dd          = -0.10,
    redundant       = FALSE,
    add_flag        = FALSE,
    wfc_verdict     = "structural_edge",
    ci_crosses_zero = FALSE,
    dsr_pvalue      = 0.02
  )
  delta <- hd_digest_delta(cur, prior = pri)
  attn  <- hd_digest_attention(delta)
  html  <- hd_digest_html(delta, attn, caption = "2 strategies; 1 needs attention.")
  # Snapshot covers structural content; strip any blastula-specific wrapper
  # by checking the inner body portion, which is always deterministic.
  # Use transform to remove any session-specific paths in error messages.
  expect_snapshot(
    cat(substr(html, 1L, 2000L)),
    transform = function(x) gsub("[0-9]{4}-[0-9]{2}-[0-9]{2}", "DATE", x)
  )
})

test_that("hd_digest_html: function signature is stable", {
  expect_snapshot(args(hd_digest_html))
})
