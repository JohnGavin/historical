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
