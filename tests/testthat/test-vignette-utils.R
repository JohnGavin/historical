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

test_that(".parse_vignette_strict: VIGNETTE_STRICT=YES returns TRUE (uppercase alias, roborev 4046)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "YES"), {
    expect_true(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=ON returns TRUE (uppercase alias, roborev 4046)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "ON"), {
    expect_true(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=Yes returns TRUE (mixed-case alias, roborev 4046)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "Yes"), {
    expect_true(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=' yes ' returns TRUE (whitespace-tolerant, roborev 4046)", {
  withr::with_envvar(list(VIGNETTE_STRICT = " yes "), {
    expect_true(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=FALSE returns FALSE (uppercase falsy, roborev 4046)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "FALSE"), {
    expect_false(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=No returns FALSE (mixed-case falsy, roborev 4046)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "No"), {
    expect_false(.parse_vignette_strict())
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
# Missing targets return NULL (preserved contract; stale_marker sentinel was
# reverted — see roborev 3558)
# ---------------------------------------------------------------------------

test_that("safe_tar_read: returns NULL when target and RDS files are absent (non-strict mode)", {
  # NULL contract preserved for backwards-compatibility with all existing callers
  # that use `if (!is.null(result))` guards. The stale_marker sentinel is
  # reserved for future migration (is_stale_marker() predicate already exists).
  withr::with_envvar(list(VIGNETTE_STRICT = ""), {
    result <- safe_tar_read("nonexistent_target_xyz_12345")
    expect_null(result)
    expect_false(is_stale_marker(result))
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
    expect_snapshot(
      error = TRUE,
      safe_tar_read("nonexistent_target_xyz_12345")
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
    expect_snapshot(
      error = TRUE,
      safe_tar_read("nonexistent_target_xyz_12345")
    )
  })
})

# ---------------------------------------------------------------------------
# .parse_vignette_strict — t/f/off aliases + typo warning (roborev T1+T2)
# Group C added aliases but never tested t/f/off; T1 adds cli_warn for typos.
# ---------------------------------------------------------------------------

test_that(".parse_vignette_strict: VIGNETTE_STRICT=t returns TRUE (short truthy alias)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "t"), {
    expect_true(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=T returns TRUE (uppercase short alias, case-insensitive)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "T"), {
    expect_true(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=f returns FALSE (short falsy alias)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "f"), {
    expect_false(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=off returns FALSE (off alias)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "off"), {
    expect_false(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=Off returns FALSE (mixed-case off alias, case-insensitive)", {
  withr::with_envvar(list(VIGNETTE_STRICT = "Off"), {
    expect_false(.parse_vignette_strict())
  })
})

test_that(".parse_vignette_strict: VIGNETTE_STRICT=treu returns FALSE AND triggers cli_warn (typo guard, roborev T1)", {
  # 'treu' is not in any alias list; old code did isTRUE(suppressWarnings(as.logical('treu')))
  # which silently returned FALSE. New code surfaces a cli_warn so CI typos are visible.
  # Reset frequency tracking so this test is hermetic and not suppressed by other tests
  # that trigger the same warning (roborev 4039).
  withr::with_envvar(list(VIGNETTE_STRICT = "treu"), {
    rlang::reset_warning_verbosity("vignette_strict_typo_treu")
    withr::defer(rlang::reset_warning_verbosity("vignette_strict_typo_treu"))

    # expect_snapshot captures the full cli_warn wording (not just a regexp
    # match) so any drift in the typo-guard message is visible in review.
    expect_snapshot(result <- .parse_vignette_strict())
    expect_false(result)
  })
})

# ---------------------------------------------------------------------------
# Security audit: issue #210 Tier C — verify all canonical falsy aliases
# The critic report required confirming "0"/"false"/"FALSE"/"off"/"no"/"n"/""
# map to FALSE. "n" is NOT a recognised alias — it triggers cli_warn + FALSE
# (unrecognised value), which is the correct safe-default behaviour.
# ---------------------------------------------------------------------------

test_that(".parse_vignette_strict: all #210 required falsy aliases return FALSE", {
  # "0", "false", "FALSE", "off", "no" are first-class aliases in the falsy list
  for (val in c("0", "false", "FALSE", "off", "no")) {
    withr::with_envvar(list(VIGNETTE_STRICT = val), {
      expect_false(.parse_vignette_strict(), label = paste0("VIGNETTE_STRICT=", val))
    })
  }
  # "" (unset/empty) is the default-off case
  withr::with_envvar(list(VIGNETTE_STRICT = ""), {
    expect_false(.parse_vignette_strict(), label = "VIGNETTE_STRICT='' (empty)")
  })
})

test_that(".parse_vignette_strict: 'n' is unrecognised alias — warns and returns FALSE (safe default)", {
  # "n" is not in the canonical falsy list; correct behaviour is warn + default FALSE
  withr::with_envvar(list(VIGNETTE_STRICT = "n"), {
    rlang::reset_warning_verbosity("vignette_strict_typo_n")
    withr::defer(rlang::reset_warning_verbosity("vignette_strict_typo_n"))

    # expect_snapshot pins the exact wording (distinct from the "treu" case
    # above since {.val {raw}} interpolates the offending value into the text).
    expect_snapshot(result <- .parse_vignette_strict())
    expect_false(result)
  })
})

test_that(".parse_vignette_strict: typo warning fires AT MOST ONCE across N calls (roborev #4263)", {
  # When safe_tar_read() is called N times during a single vignette render
  # with a typo'd VIGNETTE_STRICT value, the cli_warn must not spam the console.
  # .frequency = "once" + .frequency_id in cli_warn() achieves this.
  withr::with_envvar(list(VIGNETTE_STRICT = "yse"), {
    # Reset rlang's frequency tracking so this test is hermetic
    rlang::reset_warning_verbosity("vignette_strict_typo_yse")
    withr::defer(rlang::reset_warning_verbosity("vignette_strict_typo_yse"))

    warnings_seen <- c()
    withCallingHandlers(
      {
        for (i in seq_len(5)) .parse_vignette_strict()
      },
      warning = function(w) {
        warnings_seen <<- c(warnings_seen, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
    expect_length(warnings_seen, 1L)
    expect_match(warnings_seen[[1]], "Unrecognised")
    # Pin the exact wording of the single captured warning (Tier A: CLI message).
    expect_snapshot(cat(warnings_seen[[1]]))
  })
})

# ---------------------------------------------------------------------------
# Function signature stability (catches API drift) — Tier A snapshots
# ---------------------------------------------------------------------------

test_that("function signatures are stable (catches API drift)", {
  expect_snapshot(args(.parse_vignette_strict))
  expect_snapshot(args(safe_tar_read))
  expect_snapshot(args(is_stale_marker))
  expect_snapshot(args(show_code))
})
