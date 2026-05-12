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
