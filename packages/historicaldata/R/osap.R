# Open Source Asset Pricing (Chen & Zimmermann) -- loader
#
# Reads the two SMALL free files downloaded by scripts/fetch_osap.R:
#   SignalDoc.csv        -- documentation for 331 anomaly signals
#   portfolios_wide.csv  -- monthly long-short portfolio returns, wide
#                           (date + one column per predictor, percent scale)
#
# See #816 (survivorship-inclusive universe) and #862 (verification of the
# four OSAP presumptions -- P1 PASS delisting-inclusive, P2 FAIL no returns
# in the firm-level file so only these portfolio-level series are usable,
# P3 no data licence stated so raw files stay local-only, P4 PASS no WRDS
# credentials needed).
#
# Unit determination (#637 -- units must be verified, never assumed):
# `portfolios_wide.csv` values are in PERCENT, confirmed empirically
# 2026-09-25 against the live download: `Mom12m` has mean 0.90, sd 8.18,
# range [-88.7, 29.5] -- consistent with monthly percent returns (a monthly
# *fraction* return of that magnitude would be implausible). hd_osap_load()
# divides by 100 and labels the result "fraction" (house convention, see
# hd_metric_units()), and re-checks this assumption on every load rather
# than trusting it silently forever -- see the `max_abs_ret` guard below.

#' Directory holding the local OSAP download cache
#'
#' Reads `OSAP_DATA_DIR`, defaulting to `~/.cache/historical/osap`. This
#' directory is never created or written to by this function -- it only
#' resolves the path. Use [hd_osap_load()] to read the data, and
#' `scripts/fetch_osap.R` to populate the directory.
#'
#' @return Character path (not guaranteed to exist).
#' @export
hd_osap_data_dir <- function() {
  path.expand(Sys.getenv("OSAP_DATA_DIR", "~/.cache/historical/osap"))
}

#' Expected SignalDoc.csv metadata columns consumed by [hd_osap_load()]
#' @return Character vector of column names.
#' @keywords internal
.hd_osap_signaldoc_cols <- function() {
  c(
    "Acronym", "Authors", "Year", "LongDescription", "Journal",
    "Cat.Signal", "Cat.Data", "Cat.Economic",
    "SampleStartYear", "SampleEndYear", "Sign"
  )
}

#' Load Open Source Asset Pricing signal documentation + portfolio returns
#'
#' Reads `SignalDoc.csv` and `portfolios_wide.csv` from `data_dir` (as
#' written by `scripts/fetch_osap.R`), reshapes the wide portfolio-returns
#' file to tidy long form, converts percent returns to the house-canonical
#' fraction scale, and joins each predictor's SignalDoc metadata.
#'
#' This does **not** provide firm-level (per-stock) data -- #862's P2 check
#' found the free firm-level download has no return column at all, so only
#' portfolio-level (pre-aggregated long-short) series are available from
#' the free OSAP files. See [hd_register_add_dataset()] for the dataset
#' registration record.
#'
#' Every boundary here is validated rather than assumed (per
#' `fail-loud-not-null`): a missing cache directory, a malformed date
#' column, an unrecognised predictor (one with no matching SignalDoc row),
#' or a value scale inconsistent with the documented percent convention
#' all abort with `cli::cli_abort()` naming the problem -- none of them
#' silently produce `NA` or a dropped row.
#'
#' @param data_dir Directory containing `SignalDoc.csv` and
#'   `portfolios_wide.csv`. Defaults to [hd_osap_data_dir()].
#' @param min_predictors Soft floor on the number of predictor columns
#'   found in `portfolios_wide.csv`, used only as a schema-drift guard
#'   (the real OSAP file has 212 as of the 2024 release). Lower this for
#'   tests against a small synthetic fixture; never lower it for a real
#'   OSAP download.
#' @return A tibble with one row per (predictor, date):
#'   \describe{
#'     \item{predictor}{Signal acronym (character), e.g. `"Mom12m"`.}
#'     \item{date}{Month-end date (Date).}
#'     \item{ret}{Long-short portfolio return, decimal fraction (double).}
#'     \item{metric_unit}{Always `"fraction"` (character) -- see
#'       [hd_metric_units()].}
#'     \item{signal_sign}{Documented sign convention, `-1`/`1` (integer).}
#'     \item{signal_authors}{Originating paper's authors (character).}
#'     \item{signal_year}{Originating paper's publication year (integer).}
#'     \item{signal_description}{Short description (character).}
#'     \item{signal_journal}{Publishing journal, abbreviated (character).}
#'     \item{signal_category}{`Cat.Signal` -- e.g. `"Predictor"`
#'       (character).}
#'     \item{signal_data_category}{`Cat.Data` -- e.g. `"Accounting"`
#'       (character).}
#'     \item{signal_economic_category}{`Cat.Economic` (character).}
#'     \item{signal_sample_start}{Original paper's sample start year
#'       (integer).}
#'     \item{signal_sample_end}{Original paper's sample end year
#'       (integer).}
#'   }
#' @family osap
#' @export
hd_osap_load <- function(data_dir = hd_osap_data_dir(), min_predictors = 50L) {
  signaldoc_path  <- file.path(data_dir, "SignalDoc.csv")
  portfolios_path <- file.path(data_dir, "portfolios_wide.csv")
  needed <- c(signaldoc_path, portfolios_path)
  missing <- needed[!file.exists(needed)]
  if (length(missing) > 0L) {
    cli::cli_abort(c(
      "x" = "OSAP data not found in {.path {data_dir}}.",
      "i" = "Missing file{?s}: {.path {basename(missing)}}",
      "i" = "Fetch it first: {.code Rscript scripts/fetch_osap.R}",
      "i" = "Or set {.envvar OSAP_DATA_DIR} to an existing download directory."
    ))
  }

  signaldoc <- utils::read.csv(
    signaldoc_path, stringsAsFactors = FALSE, check.names = FALSE
  )
  required_meta_cols <- .hd_osap_signaldoc_cols()
  missing_meta_cols <- setdiff(required_meta_cols, names(signaldoc))
  if (length(missing_meta_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "{.path SignalDoc.csv} is missing expected column{?s}: {.field {missing_meta_cols}}.",
      "i" = "OSAP may have changed its export schema -- update hd_osap_load() before trusting this file.",
      "i" = "Found columns: {.field {names(signaldoc)}}"
    ))
  }

  wide <- utils::read.csv(
    portfolios_path, stringsAsFactors = FALSE, check.names = FALSE
  )
  if (!"date" %in% names(wide)) {
    cli::cli_abort(c(
      "x" = "{.path portfolios_wide.csv} has no {.field date} column.",
      "i" = "Found columns: {.field {head(names(wide), 10)}}{if (ncol(wide) > 10) '...' else ''}"
    ))
  }
  predictor_cols <- setdiff(names(wide), "date")
  if (length(predictor_cols) < min_predictors) {
    cli::cli_abort(c(
      "x" = "{.path portfolios_wide.csv} has only {length(predictor_cols)} predictor column{?s}.",
      "i" = "Expected at least {min_predictors} (OSAP has 212 as of the 2024 release).",
      "i" = "OSAP may have changed its export format -- verify before trusting this download."
    ))
  }

  parsed_dates <- as.Date(wide$date)
  if (anyNA(parsed_dates)) {
    n_bad <- sum(is.na(parsed_dates) & !is.na(wide$date))
    cli::cli_abort(c(
      "x" = "{.field date} column in {.path portfolios_wide.csv} has {n_bad} unparseable value{?s}.",
      "i" = "Expected an unambiguous date format (e.g. YYYY-MM-DD); got e.g. {.val {utils::head(wide$date[is.na(parsed_dates) & !is.na(wide$date)], 3)}}."
    ))
  }
  wide$date <- parsed_dates

  long <- wide |>
    tidyr::pivot_longer(
      cols      = dplyr::all_of(predictor_cols),
      names_to  = "predictor",
      values_to = "ret_percent"
    ) |>
    dplyr::filter(!is.na(.data$ret_percent))

  if (nrow(long) == 0L) {
    cli::cli_abort(
      "x" = "No non-missing portfolio-return observations after reshaping {.path portfolios_wide.csv}."
    )
  }

  # Unit-assumption guard: if the loudest observed value is < 1 in absolute
  # terms, this file is no longer on the percent scale we verified -- abort
  # rather than silently dividing an already-fractional value by 100 again.
  max_abs_ret <- max(abs(long$ret_percent), na.rm = TRUE)
  if (max_abs_ret < 1) {
    cli::cli_abort(c(
      "x" = "OSAP portfolio returns look like they are already in fraction scale (max abs value {round(max_abs_ret, 4)} < 1).",
      "i" = "hd_osap_load() assumes percent scale, verified empirically 2026-09-25 (Mom12m mean 0.90, sd 8.18) and divides by 100.",
      "i" = "OSAP may have changed its export format -- update the unit assumption in hd_osap_load() before trusting downstream results."
    ))
  }

  long <- long |>
    dplyr::mutate(
      ret         = .data$ret_percent / 100,
      metric_unit = "fraction"
    ) |>
    dplyr::select(-"ret_percent")

  meta <- signaldoc[required_meta_cols] |>
    dplyr::rename(
      predictor                = "Acronym",
      signal_authors            = "Authors",
      signal_year               = "Year",
      signal_description        = "LongDescription",
      signal_journal            = "Journal",
      signal_category           = "Cat.Signal",
      signal_data_category      = "Cat.Data",
      signal_economic_category  = "Cat.Economic",
      signal_sample_start       = "SampleStartYear",
      signal_sample_end         = "SampleEndYear",
      signal_sign               = "Sign"
    ) |>
    # A predictor may repeat in SignalDoc (e.g. revised entries) -- keep the
    # first documented row per acronym rather than fan out the join.
    dplyr::distinct(.data$predictor, .keep_all = TRUE)

  unmatched <- setdiff(unique(long$predictor), meta$predictor)
  if (length(unmatched) > 0L) {
    cli::cli_abort(c(
      "x" = "{length(unmatched)} predictor column{?s} in {.path portfolios_wide.csv} have no matching row in {.path SignalDoc.csv}: {.val {unmatched}}.",
      "i" = "Every predictor is expected to be documented (212/212 matched as of the 2024 release).",
      "i" = "This may indicate a renamed acronym or a schema change -- do not silently join NA metadata."
    ))
  }

  out <- long |>
    dplyr::left_join(meta, by = "predictor") |>
    dplyr::select(
      "predictor", "date", "ret", "metric_unit",
      "signal_sign", "signal_authors", "signal_year", "signal_description",
      "signal_journal", "signal_category", "signal_data_category",
      "signal_economic_category", "signal_sample_start", "signal_sample_end"
    ) |>
    dplyr::arrange(.data$predictor, .data$date)

  tibble::as_tibble(out)
}
