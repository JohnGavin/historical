# Silence R CMD check NOTEs for dplyr NSE
utils::globalVariables(c("pub_date", ".release_n", "value", "final_value"))

#' Query macro data vintages (revision history)
#'
#' Returns the value of macro series as it was known at each publication date.
#' This is the "revision triangle" — essential for avoiding lookahead bias
#' in backtesting strategies that use macro data.
#'
#' @param series_id Character vector of FRED series IDs (e.g. "GDP", "PAYEMS")
#' @param from Start date (observation date). Default: no filter.
#' @param to End date. Default: no filter.
#' @param release Which release to return: "first", "latest", "all", or an integer
#'   (e.g. 2 for second release). Default: "all" returns full vintage triangle.
#' @return Tibble with series_id, date, pub_date, value columns
#' @family data-access
#' @export
#' @examplesIf interactive()
#' hd_macro_vintages("GDP")
#' hd_macro_vintages("PAYEMS", from = "2024-01-01", release = "first")
hd_macro_vintages <- function(series_id, from = NULL, to = NULL, release = "all") {
  ds <- hd_datasets()[["macro_vintages"]]

  lf <- duckplyr::read_parquet_duckdb(ds$url)

  if (!missing(series_id) && !is.null(series_id)) {
    lf <- lf |> dplyr::filter(series_id %in% !!series_id)
  }
  if (!is.null(from)) lf <- lf |> dplyr::filter(date >= !!as.character(from))
  if (!is.null(to))   lf <- lf |> dplyr::filter(date <= !!as.character(to))

  lf <- lf |> dplyr::arrange(series_id, date, pub_date)

  result <- dplyr::collect(lf)

  # Filter by release number
 if (!identical(release, "all")) {
    result <- result |>
      dplyr::group_by(series_id, date) |>
      dplyr::arrange(pub_date) |>
      dplyr::mutate(.release_n = dplyr::row_number())

    if (release == "first") {
      result <- result |> dplyr::filter(.release_n == 1L)
    } else if (release == "latest") {
      result <- result |> dplyr::filter(.release_n == max(.release_n))
    } else if (is.numeric(release)) {
      result <- result |> dplyr::filter(.release_n == as.integer(release))
    }

    result <- result |>
      dplyr::ungroup() |>
      dplyr::select(-".release_n")
  }

  result
}

#' Analyse revisions using the reviser package
#'
#' Wraps reviser's analysis functions. Requires the reviser package.
#'
#' @param series_id FRED series ID
#' @param from Start date
#' @return List with revision analysis results
#' @family quality
#' @export
#' @examplesIf interactive()
#' hd_revision_analysis("GDP")
hd_revision_analysis <- function(series_id, from = "2000-01-01") {
  rlang::check_installed("reviser")

  vintages <- hd_macro_vintages(series_id, from = from)

  if (nrow(vintages) == 0) {
    cli::cli_abort("No vintage data for {series_id}")
  }

  # Convert to reviser's wide format (revision triangle)
  wide <- vintages |>
    dplyr::select(series_id, date, pub_date, value) |>
    tidyr::pivot_wider(
      names_from = pub_date,
      values_from = value,
      id_cols = date
    )

  # Use reviser functions
  rev_data <- reviser::vintages_long(wide)
  analysis <- reviser::get_revision_analysis(rev_data)
  first_efficient <- tryCatch(
    reviser::get_first_efficient_release(rev_data),
    error = function(e) NULL
  )

  list(
    series_id = series_id,
    n_observations = nrow(vintages),
    n_vintages = dplyr::n_distinct(vintages$pub_date),
    analysis = analysis,
    first_efficient = first_efficient,
    vintages = vintages
  )
}
