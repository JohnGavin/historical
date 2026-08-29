# Validation helpers for cross-series data quality
#
# These are standalone functions (not targets) so they can be unit-tested
# without a live targets store. The `dv_join_key_types` target in _targets.R
# calls `check_date_key_types()` with the real store path.

# Build the default read_fn that reads directly from the RDS store.
# tar_read_raw() is forbidden inside a targets pipeline (nested store access).
# Reading the RDS file directly is the supported workaround for a validation
# target that must inspect sibling targets without declaring them as deps.
.make_store_reader <- function(store) {
  function(nm) {
    path <- file.path(store, "objects", nm)
    if (!file.exists(path)) stop(paste0("object file not found: ", path))
    readRDS(path)
  }
}

#' Check date-key type consistency across registered datasets
#'
#' For each target in the registry, reads its current value, captures the class
#' of its `date` column, and aborts if classes are not identical across all
#' present series. A `Date` vs `POSIXct` mix is the silent-failure bug found
#' three times during the 2026-05-12 session.
#'
#' Targets that don't currently exist in the cache (e.g., not yet built, or
#' broken upstream) are skipped with an informational message — they aren't
#' counted as failures, since this validator is about consistency among what
#' DOES exist.
#'
#' @param registry Tibble from `dataset_registry()`.
#' @param read_fn Function with signature `read_fn(name)` that returns the
#'   target value. Default reads RDS objects directly from `store`.
#'   Pass a fake in tests to avoid touching the targets store.
#' @param store Path to the targets store directory. Used only when `read_fn`
#'   is not explicitly provided. Defaults to `"_targets"` (relative to cwd —
#'   the standard default when running from `docs/`).
#' @return Tibble: target_name, status ("ok", "missing", "no-date-column"),
#'   date_class.
#' @export
check_date_key_types <- function(
    registry = dataset_registry(),
    # read_fn accepts a string name and returns the target object.
    # The parameter exists so tests can inject a fake without file I/O.
    read_fn = NULL,
    store   = "_targets") {

  # Build default reader from store path when caller did not provide one.
  # This avoids calling tar_read_raw() inside a pipeline (unsupported).
  if (is.null(read_fn)) {
    read_fn <- .make_store_reader(store)
  }

  # Early return for empty registry — nothing to check
  if (nrow(registry) == 0L) {
    return(tibble::tibble(
      target_name = character(0),
      status      = character(0),
      date_class  = character(0)
    ))
  }

  rows <- purrr::map(registry$target_name, function(nm) {
    obj <- tryCatch(
      read_fn(nm),
      error = function(e) {
        cli::cli_inform(c("i" = "Skipping {nm}: not in cache ({conditionMessage(e)})"))
        NULL
      }
    )

    if (is.null(obj)) {
      return(tibble::tibble(target_name = nm, status = "missing", date_class = NA_character_))
    }

    # A 0-column tibble is a broken/placeholder target — treat as missing
    # rather than a "no-date-column" schema error (e.g. cb_data when #145 fails)
    if (!is.data.frame(obj) || ncol(obj) == 0L) {
      cli::cli_inform(c("i" = "Skipping {nm}: target exists but has no columns (broken/placeholder)"))
      return(tibble::tibble(target_name = nm, status = "missing", date_class = NA_character_))
    }

    if (!("date" %in% names(obj))) {
      return(tibble::tibble(target_name = nm, status = "no-date-column", date_class = "no-date-column"))
    }

    cls <- paste(class(obj$date), collapse = "/")
    tibble::tibble(target_name = nm, status = "ok", date_class = cls)
  })

  result <- dplyr::bind_rows(rows)

  # Only "ok" targets vote on consistency (missing/no-date-column are separate fail modes)
  ok_rows     <- dplyr::filter(result, status == "ok")
  no_date_rows <- dplyr::filter(result, status == "no-date-column")

  # Report targets without a date column as a separate issue
  if (nrow(no_date_rows) > 0L) {
    offenders <- paste(no_date_rows$target_name, collapse = ", ")
    cli::cli_abort(c(
      "x" = "{nrow(no_date_rows)} registered target(s) lack a `date` column.",
      "i" = "Targets: {offenders}",
      "i" = "Add a `date` column or remove from the registry."
    ))
  }

  unique_classes <- unique(ok_rows$date_class)

  if (length(unique_classes) > 1L) {
    detail <- paste(ok_rows$target_name, ok_rows$date_class, sep = ": ", collapse = "; ")
    cli::cli_abort(c(
      "x" = "Inconsistent date-key types across {nrow(ok_rows)} present series.",
      "i" = "{detail}",
      "i" = "Coerce to a common type ({.code as.Date()}) at the producing target."
    ))
  }

  result
}

# Map registry freq string to expected inter-observation gap in days
.freq_to_days <- function(freq) {
  freq_map <- c(
    "daily"     = 1L,
    "weekly"    = 7L,
    "monthly"   = 30L,
    "quarterly" = 91L,
    "annual"    = 365L,
    "yearly"    = 365L
  )
  unname(freq_map[freq])
}

#' Check sampling frequency alignment for registered datasets
#'
#' For each target in the registry, reads its cached value, computes the median
#' inter-observation interval in days, and compares it against the declared
#' frequency in `registry$freq`. Warns (does not abort) when the observed median
#' interval exceeds twice the declared frequency. Returns a summary tibble so
#' the caller can inspect the detail.
#'
#' Mirrors `check_date_key_types()` — same `read_fn` injection pattern for
#' testability without touching the targets store.
#'
#' @param registry Tibble from `dataset_registry()`. Must have columns
#'   `target_name` and `freq`.
#' @param read_fn Function with signature `read_fn(name)` returning the target
#'   object. Default reads RDS objects directly from `store`. Pass a fake in
#'   tests to avoid touching the targets store.
#' @param store Path to the targets store directory. Defaults to `"_targets"`.
#' @return Tibble: `target_name`, `expected_freq_days`, `observed_median_days`,
#'   `status` ("ok", "missing", "violation").
#' @export
check_frequency_alignment <- function(
    registry = dataset_registry(),
    read_fn  = NULL,
    store    = "_targets") {

  if (is.null(read_fn)) {
    read_fn <- .make_store_reader(store)
  }

  # Early return for empty registry
  if (nrow(registry) == 0L) {
    return(tibble::tibble(
      target_name        = character(0),
      expected_freq_days = integer(0),
      observed_median_days = numeric(0),
      status             = character(0)
    ))
  }

  rows <- purrr::map(seq_len(nrow(registry)), function(i) {
    nm   <- registry$target_name[[i]]
    freq <- registry$freq[[i]]

    expected_days <- .freq_to_days(freq)

    # If freq is unrecognised, skip with a note
    if (is.na(expected_days)) {
      cli::cli_inform(c("i" = "Skipping {nm}: unrecognised freq {.val {freq}}."))
      return(tibble::tibble(
        target_name        = nm,
        expected_freq_days = NA_integer_,
        observed_median_days = NA_real_,
        status             = "missing"
      ))
    }

    obj <- tryCatch(
      read_fn(nm),
      error = function(e) {
        cli::cli_inform(c("i" = "Skipping {nm}: not in cache ({conditionMessage(e)})"))
        NULL
      }
    )

    if (is.null(obj) || !is.data.frame(obj) || ncol(obj) == 0L) {
      return(tibble::tibble(
        target_name        = nm,
        expected_freq_days = expected_days,
        observed_median_days = NA_real_,
        status             = "missing"
      ))
    }

    if (!("date" %in% names(obj))) {
      cli::cli_inform(c("i" = "Skipping {nm}: no `date` column."))
      return(tibble::tibble(
        target_name        = nm,
        expected_freq_days = expected_days,
        observed_median_days = NA_real_,
        status             = "missing"
      ))
    }

    dates <- sort(unique(as.Date(obj$date)))

    if (length(dates) < 2L) {
      # Can't compute an interval with < 2 distinct dates
      cli::cli_inform(c("i" = "Skipping {nm}: fewer than 2 unique dates."))
      return(tibble::tibble(
        target_name        = nm,
        expected_freq_days = expected_days,
        observed_median_days = NA_real_,
        status             = "missing"
      ))
    }

    gaps <- as.numeric(diff(dates), units = "days")
    med_gap <- stats::median(gaps)

    status <- if (med_gap > 2L * expected_days) "violation" else "ok"

    tibble::tibble(
      target_name        = nm,
      expected_freq_days = expected_days,
      observed_median_days = med_gap,
      status             = status
    )
  })

  result <- dplyr::bind_rows(rows)

  violations <- dplyr::filter(result, status == "violation")
  if (nrow(violations) > 0L) {
    n_v <- nrow(violations)
    detail <- paste0(
      violations$target_name,
      " (expected ~", violations$expected_freq_days, "d, observed median ",
      round(violations$observed_median_days, 1), "d)",
      collapse = "; "
    )
    suffix <- if (n_v == 1L) "" else "s"
    cli::cli_warn(c(
      "!" = paste0(n_v, " target", suffix,
                   " have observed sampling frequency > 2× declared frequency."),
      "i" = detail,
      "i" = "Check {.arg freq} in {.fn dataset_registry} or the data source."
    ))
  }

  result
}

#' Check temporal coverage (expected vs actual trading-day observations)
#'
#' For each `freq == "daily"` target in the registry, computes the fraction
#' of expected trading days -- Mon-Fri within the target's own observed date
#' range, no holiday calendar (the same approximation documented in
#' [to_month_end_bizday()]) -- that are actually present, and aborts /
#' warns per the thresholds in `data-validation-timeseries` rule #1.
#'
#' Coverage is computed over the target's `date` column as a whole, not
#' per-entity within cross-sectional targets (e.g. `stk_universe`, keyed by
#' `ticker`) -- a coarse, target-level signal. Per-entity coverage (e.g. a
#' newly-IPO'd ticker legitimately having fewer observations than the
#' universe) is a follow-up; see #617.
#'
#' Non-daily targets (`freq` != "daily") are reported with status
#' "skipped-freq": the weekday-based expected-count approximation does not
#' apply to monthly/quarterly/annual cadence.
#'
#' @inheritParams check_date_key_types
#' @param min_coverage_abort Coverage fraction below which the pipeline
#'   aborts. Default `0.30`.
#' @param min_coverage_warn Coverage fraction below which a warning is
#'   emitted (and the abort threshold has not already fired). Default `0.80`.
#' @return Tibble: `target_name`, `status` ("ok", "missing", "skipped-freq"),
#'   `expected_obs`, `actual_obs`, `coverage`.
#' @export
check_temporal_coverage <- function(
    registry = dataset_registry(),
    read_fn = NULL,
    store   = "_targets",
    min_coverage_abort = 0.30,
    min_coverage_warn  = 0.80) {

  if (is.null(read_fn)) {
    read_fn <- .make_store_reader(store)
  }

  if (nrow(registry) == 0L) {
    return(tibble::tibble(
      target_name  = character(0),
      status       = character(0),
      expected_obs = integer(0),
      actual_obs   = integer(0),
      coverage     = numeric(0)
    ))
  }

  rows <- purrr::map(seq_len(nrow(registry)), function(i) {
    nm   <- registry$target_name[[i]]
    freq <- registry$freq[[i]]

    if (!identical(freq, "daily")) {
      return(tibble::tibble(
        target_name = nm, status = "skipped-freq",
        expected_obs = NA_integer_, actual_obs = NA_integer_, coverage = NA_real_
      ))
    }

    obj <- tryCatch(
      read_fn(nm),
      error = function(e) {
        cli::cli_inform(c("i" = "Skipping {nm}: not in cache ({conditionMessage(e)})"))
        NULL
      }
    )

    if (is.null(obj) || !is.data.frame(obj) || ncol(obj) == 0L || !("date" %in% names(obj))) {
      return(tibble::tibble(
        target_name = nm, status = "missing",
        expected_obs = NA_integer_, actual_obs = NA_integer_, coverage = NA_real_
      ))
    }

    dates <- sort(unique(as.Date(obj$date)))
    dates <- dates[!is.na(dates)]

    if (length(dates) < 2L) {
      return(tibble::tibble(
        target_name = nm, status = "missing",
        expected_obs = NA_integer_, actual_obs = NA_integer_, coverage = NA_real_
      ))
    }

    all_days <- seq(dates[[1L]], dates[[length(dates)]], by = "day")
    # %u: ISO weekday, Mon=1 .. Sun=7 -- exclude Sat(6)/Sun(7). No holiday
    # calendar (documented limitation, matches to_month_end_bizday()).
    expected <- sum(!(format(all_days, "%u") %in% c("6", "7")))
    actual   <- length(dates)
    coverage <- actual / expected

    tibble::tibble(
      target_name = nm, status = "ok",
      expected_obs = expected, actual_obs = actual, coverage = coverage
    )
  })

  result <- dplyr::bind_rows(rows)
  ok_rows <- dplyr::filter(result, status == "ok")

  aborts <- dplyr::filter(ok_rows, coverage < min_coverage_abort)
  if (nrow(aborts) > 0L) {
    detail <- paste0(
      aborts$target_name, ": ", round(aborts$coverage * 100, 1), "%",
      collapse = "; "
    )
    cli::cli_abort(
      c(
        "x" = paste0(
          nrow(aborts), " target", if (nrow(aborts) == 1L) "" else "s",
          " below the ", min_coverage_abort * 100, "% temporal-coverage floor."
        ),
        "i" = "{detail}",
        "i" = "Coverage = distinct trading days present / expected weekdays in the target's date range."
      ),
      class = "hd_temporal_coverage_abort"
    )
  }

  warns <- dplyr::filter(ok_rows, coverage >= min_coverage_abort, coverage < min_coverage_warn)
  if (nrow(warns) > 0L) {
    detail <- paste0(
      warns$target_name, ": ", round(warns$coverage * 100, 1), "%",
      collapse = "; "
    )
    cli::cli_warn(c(
      "!" = paste0(
        nrow(warns), " target", if (nrow(warns) == 1L) "" else "s",
        " below ", min_coverage_warn * 100, "% temporal coverage (above the abort floor)."
      ),
      "i" = "{detail}"
    ))
  }

  result
}

#' Check data freshness (latest observation within a lookback window)
#'
#' For each target in the registry, computes the number of days between the
#' target's most recent `date` value and `as_of`, and warns (does not abort)
#' when it exceeds the threshold for that target's declared `freq`. A weekly
#' data poll can fail silently (#613) and nothing downstream would otherwise
#' notice stale data.
#'
#' @inheritParams check_date_key_types
#' @param as_of Reference date to measure staleness against. Default
#'   `Sys.Date()`. Pass an explicit date in tests for determinism.
#' @param max_stale_days Named numeric vector of staleness thresholds (days),
#'   one entry per `freq` value expected in the registry, plus a `"default"`
#'   fallback for any unrecognised `freq`. Default: `daily = 7, weekly = 14,
#'   monthly = 45, quarterly = 120, annual = 400, yearly = 400, default = 30`.
#' @return Tibble: `target_name`, `status` ("ok", "stale", "missing"),
#'   `latest_date`, `days_stale`, `threshold_days`.
#' @export
check_freshness <- function(
    registry = dataset_registry(),
    read_fn = NULL,
    store   = "_targets",
    as_of   = Sys.Date(),
    max_stale_days = c(daily = 7, weekly = 14, monthly = 45,
                        quarterly = 120, annual = 400, yearly = 400,
                        default = 30)) {

  if (is.null(read_fn)) {
    read_fn <- .make_store_reader(store)
  }
  as_of <- as.Date(as_of)

  if (nrow(registry) == 0L) {
    return(tibble::tibble(
      target_name    = character(0),
      status         = character(0),
      latest_date    = as.Date(character(0)),
      days_stale     = integer(0),
      threshold_days = integer(0)
    ))
  }

  rows <- purrr::map(seq_len(nrow(registry)), function(i) {
    nm   <- registry$target_name[[i]]
    freq <- registry$freq[[i]]

    threshold <- unname(max_stale_days[freq])
    if (is.na(threshold)) threshold <- unname(max_stale_days[["default"]])

    obj <- tryCatch(
      read_fn(nm),
      error = function(e) {
        cli::cli_inform(c("i" = "Skipping {nm}: not in cache ({conditionMessage(e)})"))
        NULL
      }
    )

    if (is.null(obj) || !is.data.frame(obj) || ncol(obj) == 0L || !("date" %in% names(obj))) {
      return(tibble::tibble(
        target_name = nm, status = "missing", latest_date = as.Date(NA),
        days_stale = NA_integer_, threshold_days = threshold
      ))
    }

    dates <- as.Date(obj$date)
    dates <- dates[!is.na(dates)]

    if (length(dates) == 0L) {
      return(tibble::tibble(
        target_name = nm, status = "missing", latest_date = as.Date(NA),
        days_stale = NA_integer_, threshold_days = threshold
      ))
    }

    latest     <- max(dates)
    stale_days <- as.integer(as_of - latest)
    status     <- if (stale_days > threshold) "stale" else "ok"

    tibble::tibble(
      target_name = nm, status = status, latest_date = latest,
      days_stale = stale_days, threshold_days = threshold
    )
  })

  result <- dplyr::bind_rows(rows)

  stale_rows <- dplyr::filter(result, status == "stale")
  if (nrow(stale_rows) > 0L) {
    detail <- paste0(
      stale_rows$target_name, ": ", stale_rows$days_stale, "d stale (threshold ",
      stale_rows$threshold_days, "d)", collapse = "; "
    )
    cli::cli_warn(c(
      "!" = paste0(
        nrow(stale_rows), " target", if (nrow(stale_rows) == 1L) "" else "s",
        " exceed", if (nrow(stale_rows) == 1L) "s" else "", " their freshness threshold."
      ),
      "i" = "{detail}",
      "i" = "A weekly data poll can fail silently (#613) -- check the upstream fetch."
    ))
  }

  result
}

#' Probe pairwise alignment between two registered datasets
#'
#' Given a two-row registry slice (one row per dataset in the pair), reads each
#' target from the cache and checks the `date_class` alignment dimension.
#' Returns a one-row tibble summarising compatibility. Emits
#' `cli::cli_warn()` on mismatch but does NOT abort — this is a canary
#' (informational), not a gate.
#'
#' Currently checks Dimension 1 (date class) and Dimension 2 (frequency).
#' The function is designed for future extension: additional `dimension` rows
#' can be appended to the returned tibble.
#'
#' @param registry Two-row tibble (or slice from `dataset_registry()`).
#'   Must have at least columns `target_name` and `freq`.
#' @param read_fn Function `read_fn(name)` returning the target object.
#'   Default reads RDS objects directly from `store`. Pass a fake in tests.
#' @param store Path to the targets store directory. Defaults to `"_targets"`.
#' @return One-row tibble: `pair` (chr), `dimension` ("date_class"),
#'   `status` ("ok", "warn", "missing"), `evidence` (chr detail).
#' @export
probe_pairwise_alignment <- function(
    registry,
    read_fn = NULL,
    store   = "_targets") {

  stopifnot(nrow(registry) == 2L)

  if (is.null(read_fn)) {
    read_fn <- .make_store_reader(store)
  }

  nm_a <- registry$target_name[[1L]]
  nm_b <- registry$target_name[[2L]]
  pair_label <- paste0(nm_a, " vs ", nm_b)

  # Read both targets; catch cache misses gracefully
  obj_a <- tryCatch(
    read_fn(nm_a),
    error = function(e) {
      cli::cli_inform(c("i" = "Skipping {nm_a}: not in cache ({conditionMessage(e)})"))
      NULL
    }
  )
  obj_b <- tryCatch(
    read_fn(nm_b),
    error = function(e) {
      cli::cli_inform(c("i" = "Skipping {nm_b}: not in cache ({conditionMessage(e)})"))
      NULL
    }
  )

  # If either is missing, return a "missing" row — not an error
  if (is.null(obj_a) || is.null(obj_b)) {
    return(tibble::tibble(
      pair      = pair_label,
      dimension = "date_class",
      status    = "missing",
      evidence  = paste0(
        if (is.null(obj_a)) nm_a else "",
        if (is.null(obj_a) && is.null(obj_b)) " and " else "",
        if (is.null(obj_b)) nm_b else "",
        " not in cache"
      )
    ))
  }

  # Extract date column classes
  cls_a <- if ("date" %in% names(obj_a)) {
    paste(class(obj_a$date), collapse = "/")
  } else {
    NA_character_
  }
  cls_b <- if ("date" %in% names(obj_b)) {
    paste(class(obj_b$date), collapse = "/")
  } else {
    NA_character_
  }

  # Dimension: date_class
  if (!is.na(cls_a) && !is.na(cls_b) && cls_a != cls_b) {
    evidence <- paste0(nm_a, ": ", cls_a, "; ", nm_b, ": ", cls_b)
    cli::cli_warn(c(
      "!" = "Date-class mismatch detected for pair {.val {pair_label}}.",
      "i" = "{evidence}",
      "i" = paste0(
        "A Date/POSIXct join produces 0 matching rows silently. ",
        "Coerce both to {.code as.Date()} at the producing target."
      )
    ))
    return(tibble::tibble(
      pair      = pair_label,
      dimension = "date_class",
      status    = "warn",
      evidence  = evidence
    ))
  }

  # Dimension: freq mismatch (from registry metadata — no live data inspection)
  freq_a <- registry$freq[[1L]]
  freq_b <- registry$freq[[2L]]
  if (!is.na(freq_a) && !is.na(freq_b) && freq_a != freq_b) {
    evidence <- paste0(nm_a, ": ", freq_a, "; ", nm_b, ": ", freq_b)
    cli::cli_warn(c(
      "!" = "Frequency mismatch detected for pair {.val {pair_label}}.",
      "i" = "{evidence}",
      "i" = paste0(
        "Joining daily and monthly series produces a sparse result. ",
        "Use align_period() (#148) before joining."
      )
    ))
    return(tibble::tibble(
      pair      = pair_label,
      dimension = "freq",
      status    = "warn",
      evidence  = paste0("freq mismatch: ", evidence)
    ))
  }

  # All checked dimensions pass
  tibble::tibble(
    pair      = pair_label,
    dimension = "date_class",
    status    = "ok",
    evidence  = paste0("both ", cls_a %||% "unknown", "; freq both ", freq_a %||% "unknown")
  )
}

# Null-coalescing operator (base R doesn't have one; rlang's %||% used here)
`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L) y else x

#' Check month-end-bizday date convention for a set of targets
#'
#' For each named target, reads its cached RDS object and verifies that every
#' `date` value is the last business day of its calendar month (per #147).
#' Warns (does not abort) when a target has fewer than 95% of dates on
#' month-end-bizday dates so the pipeline can continue collecting data.
#'
#' `tar_read_raw()` is **forbidden** inside a targets pipeline body — nested
#' store access silently errors inside `tryCatch`, returning NULL and reporting
#' every target as "missing" even when built.  This helper uses `readRDS()`
#' directly (the same pattern as `.make_store_reader()`), and accepts a
#' `read_fn` parameter for unit-testing without touching the targets store.
#'
#' @param targets_vec Character vector of target names to validate.
#' @param read_fn Function with signature `read_fn(name)` returning the target
#'   object.  Default reads RDS objects directly from `store`.
#'   Pass a fake in tests to avoid touching the targets store.
#' @param store Path to the targets store directory.  Defaults to `"_targets"`.
#' @return Tibble: target, status ("ok", "missing"), n, pct_match.
#' @export
check_monthly_convention <- function(
    targets_vec,
    read_fn = NULL,
    store   = "_targets") {

  if (is.null(read_fn)) {
    read_fn <- .make_store_reader(store)
  }

  results <- purrr::map_dfr(targets_vec, function(nm) {
    df <- tryCatch(
      read_fn(nm),
      error = function(e) {
        cli::cli_inform(c("i" = "Skipping {nm}: not in cache ({conditionMessage(e)})"))
        NULL
      }
    )
    if (is.null(df) || !"date" %in% names(df)) {
      return(tibble::tibble(
        target = nm, status = "missing", n = 0L, pct_match = NA_real_
      ))
    }
    actual    <- as.Date(df$date)
    expected  <- to_month_end_bizday(actual)
    pct_match <- mean(actual == expected, na.rm = TRUE)
    tibble::tibble(target = nm, status = "ok", n = nrow(df), pct_match = pct_match)
  })

  off <- dplyr::filter(results, status == "ok", pct_match < 0.95)
  if (nrow(off) > 0L) {
    cli::cli_warn(c(
      "!" = "{nrow(off)} target{?s} do not follow month-end-bizday convention (#147):",
      "i" = "{paste0(off$target, ' (', round(off$pct_match * 100, 1), '%)', collapse = '; ')}",
      "i" = "Use {.fn to_month_end_bizday} when constructing these dates."
    ))
  }

  results
}
