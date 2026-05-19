testthat::local_edition(3)
source(here::here("docs/vignette_utils.R"))

# ---------------------------------------------------------------------------
# .parse_vignette_strict — issue #232
# VIGNETTE_STRICT=1 must ENABLE strict mode (not disable it silently via NA)
# ---------------------------------------------------------------------------

test_that(".parse_vignette_strict: unset env var returns FALSE (strict mode OFF)", {
  withr::with_envvar(list(VIGNETTE_STRICT = ""), {
    expect_false(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=true returns TRUE (logical string)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "true"), {
    expect_true(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=TRUE returns TRUE (case-insensitive)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "TRUE"), {
    expect_true(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=1 returns TRUE (numeric string, issue #232)", {
  # as.logical('1') == NA, so isTRUE(as.logical('1')) == FALSE — this was the bug.
  # The fix adds '1' to the truthy-string list before calling as.logical().
  withr::with_envvar(list(VIGNETTE_STRICT = "1"), {
    expect_true(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=yes returns TRUE (common truthy alias)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "yes"), {
    expect_true(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=on returns TRUE (common truthy alias)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "on"), {
    expect_true(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=false returns FALSE", {
  withr::with_envvar(list(VIGNETTE_STRICT = "false"), {
    expect_false(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=0 returns FALSE", {
  withr::with_envvar(list(VIGNETTE_STRICT = "0"), {
    # '0' is not in the truthy list, as.logical('0') == NA, isTRUE(NA) == FALSE
    expect_false(.parse_vignette_strict())
  })
})

# ---------------------------------------------------------------------------
# safe_tar_read NULL fallback — issue #231
# Missing targets must return a stale_marker, NOT NULL or a real number
# ---------------------------------------------------------------------------

test_that("safe_tar_read: returns stale_marker when target and RDS files are absent", {
  withr::with_envvar(list(VIGNETTE_STRICT = ""), {
    result <- safe_tar_read("nonexistent_target_xyz_12345")
    expect_true(is_stale_marker(result))
    expect_true(is.na(result))
    expect_equal(attr(result, "target"), "nonexistent_target_xyz_12345")
  })
})

test_that("is_stale_marker: returns TRUE for stale markers, FALSE for real values", {
  marker <- NA_real_
  class(marker) <- "stale_marker"
  expect_true(is_stale_marker(marker))
  expect_false(is_stale_marker(42.0))
  expect_false(is_stale_marker(NULL))
  expect_false(is_stale_marker(NA_real_))  # bare NA without class is NOT a marker
})

test_that("safe_tar_read: stops in strict mode when target is absent", {
  withr::with_envvar(list(VIGNETTE_STRICT = "true"), {
    expect_error(
      safe_tar_read("nonexistent_target_xyz_12345"),
      regexp = "VIGNETTE_STRICT"
    )
  })
})

test_that("safe_tar_read: VIGNETTE_STRICT=1 triggers strict error (issue #232 + #231 integration)", {
  # Confirms that the #232 parser fix flows through to safe_tar_read behaviour:
  # setting =1 must cause strict-mode error, not silent NULL/stale return.
  withr::with_envvar(list(VIGNETTE_STRICT = "1"), {
    expect_error(
      safe_tar_read("nonexistent_target_xyz_12345"),
      regexp = "VIGNETTE_STRICT"
    )
  })
})
