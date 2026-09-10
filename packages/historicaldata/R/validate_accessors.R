# Accessor-layer date-type validation (#616)
#
# check_date_key_types() (root R/utils_validation.R) validates date-key
# consistency across *registered pipeline targets* only. It never calls the
# package's exported accessors (hd_ohlcv(), hd_macro(), hd_factors(), ...),
# so any caller that uses those directly -- rather than reading a target from
# a live targets store -- was unprotected. That is exactly how #611 hit the
# hd_ohlcv() (POSIXct) vs hd_macro() (Date) mismatch fixed in #615.
#
# This file extends the same "assert identical date-column class" mechanism
# to the accessor surface. It lives in the package (not a target) so it runs
# in `r-tests` CI on every PR touching packages/historicaldata/**, per the
# recommendation in #616.

#' Default accessor probe set for [hd_check_accessor_date_types()]
#'
#' Each thunk calls one exported, daily-frequency accessor against a small,
#' fixed date range so the probe is cheap and deterministic. Extend this list
#' whenever a new exported accessor gains a `date` column -- that is the
#' regression-prevention half of #616.
#'
#' @return Named list of zero-argument functions, each returning a data frame
#'   with a `date` column (or erroring, which [hd_check_accessor_date_types()]
#'   treats as "skip", not "fail" -- e.g. no local cache / no network).
#' @noRd
hd_accessor_date_probes <- function() {
  list(
    hd_ohlcv = function() {
      hd_ohlcv("AAPL", from = "2024-01-02", to = "2024-01-08")
    },
    hd_macro = function() {
      hd_macro("SP500", from = "2024-01-01", to = "2024-01-08")
    },
    hd_factors = function() {
      hd_factors("FF3", "daily", from = "2024-01-01", to = "2024-01-08")
    }
  )
}

#' Check date-column type consistency across exported accessors
#'
#' Calls each accessor in `accessors`, captures the class of its `date`
#' column, and aborts if classes are not identical across all accessors that
#' returned successfully. Mirrors `check_date_key_types()` in
#' `R/utils_validation.R` (root pipeline validation), but probes the
#' **exported accessor functions** rather than registered pipeline targets --
#' the gap identified in #616.
#'
#' An accessor that errors (e.g. no local cache and no network) is skipped
#' with an informational message, not counted as a failure -- this validator
#' is about consistency among what DOES return successfully, matching the
#' skip semantics of `check_date_key_types()`.
#'
#' @param accessors Named list of zero-argument thunks, each returning a data
#'   frame with a `date` column. Defaults to [hd_accessor_date_probes()].
#'   Pass a custom list in tests to exercise the mismatch/abort path without
#'   depending on real accessor behaviour.
#' @return Tibble: `accessor`, `status` ("ok", "skipped", "no-date-column"),
#'   `date_class`. Returned invisibly-compatible (not marked invisible, so it
#'   can be inspected interactively like `check_date_key_types()`'s result).
#' @family data-access
#' @family quality-audit
#' @export
#' @examplesIf interactive()
#' hd_check_accessor_date_types()
hd_check_accessor_date_types <- function(accessors = hd_accessor_date_probes()) {
  if (length(accessors) == 0L) {
    return(tibble::tibble(
      accessor   = character(0),
      status     = character(0),
      date_class = character(0)
    ))
  }

  nms <- names(accessors)
  if (is.null(nms) || any(!nzchar(nms))) {
    cli::cli_abort("{.arg accessors} must be a fully named list.")
  }

  rows <- purrr::map(nms, function(nm) {
    obj <- tryCatch(
      accessors[[nm]](),
      error = function(e) {
        cli::cli_inform(c("i" = "Skipping {nm}: {conditionMessage(e)}"))
        NULL
      }
    )

    if (is.null(obj)) {
      return(tibble::tibble(accessor = nm, status = "skipped", date_class = NA_character_))
    }

    if (!is.data.frame(obj) || !("date" %in% names(obj))) {
      return(tibble::tibble(accessor = nm, status = "no-date-column", date_class = NA_character_))
    }

    tibble::tibble(
      accessor   = nm,
      status     = "ok",
      date_class = paste(class(obj[["date"]]), collapse = "/")
    )
  })

  result <- dplyr::bind_rows(rows)

  no_date_rows <- dplyr::filter(result, status == "no-date-column")
  if (nrow(no_date_rows) > 0L) {
    offenders <- paste(no_date_rows$accessor, collapse = ", ")
    cli::cli_abort(
      c(
        "x" = "{nrow(no_date_rows)} accessor{?s} returned a value with no `date` column.",
        "i" = "Accessor{?s}: {offenders}",
        "i" = "Remove from the probe set if the accessor is not date-keyed, or fix the accessor."
      ),
      class = "hd_accessor_no_date_column"
    )
  }

  ok_rows <- dplyr::filter(result, status == "ok")
  unique_classes <- unique(ok_rows$date_class)

  if (length(unique_classes) > 1L) {
    detail <- paste(ok_rows$accessor, ok_rows$date_class, sep = ": ", collapse = "; ")
    cli::cli_abort(
      c(
        "x" = "Inconsistent `date` column types across {nrow(ok_rows)} exported accessors.",
        "i" = "{detail}",
        "i" = "Coerce to a common type ({.code as.Date()}) inside the accessor -- see #615."
      ),
      class = "hd_accessor_date_type_mismatch"
    )
  }

  result
}
