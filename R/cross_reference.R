# Cross-reference functions: compare same ticker from multiple sources

#' Compare a numeric column across two sources for the same (ticker, date)
#'
#' @param source_a Tibble from source A
#' @param source_b Tibble from source B
#' @param by Join columns (default: c("ticker", "date"))
#' @param compare_col Column to compare (default: "close")
#' @param tolerance Relative tolerance (0.001 = 0.1%)
#' @param label Human-readable label for the comparison
#' @return Tibble with comparison results and discrepancy flags
cross_reference <- function(source_a, source_b,
                            by = c("ticker", "date"),
                            compare_col = "close",
                            tolerance = 0.001,
                            label = "unknown") {

  col_a <- paste0(compare_col, "_a")
  col_b <- paste0(compare_col, "_b")

  joined <- dplyr::inner_join(
    source_a |> dplyr::select(dplyr::all_of(c(by, compare_col))) |>
      dplyr::rename(!!col_a := !!compare_col),
    source_b |> dplyr::select(dplyr::all_of(c(by, compare_col))) |>
      dplyr::rename(!!col_b := !!compare_col),
    by = by
  )

  if (nrow(joined) == 0) {
    cli::cli_warn("No overlapping dates for cross-reference: {label}")
    return(dplyr::tibble(
      label = label,
      n_overlap = 0L, n_match = 0L, n_discrepancy = 0L,
      match_pct = NA_real_, max_rel_diff = NA_real_,
      median_rel_diff = NA_real_
    ))
  }

  result <- joined |>
    dplyr::mutate(
      midpoint = (.data[[col_a]] + .data[[col_b]]) / 2,
      abs_diff = abs(.data[[col_a]] - .data[[col_b]]),
      rel_diff = dplyr::if_else(
        midpoint > 0,
        abs_diff / midpoint,
        NA_real_
      ),
      is_match = rel_diff <= tolerance | is.na(rel_diff)
    )

  n_overlap <- nrow(result)
  n_match <- sum(result$is_match, na.rm = TRUE)
  n_disc <- n_overlap - n_match

  cli::cli_inform(c(
    "i" = "{label}: {n_overlap} overlapping dates, {n_match} match ({round(100 * n_match / n_overlap, 1)}%), {n_disc} discrepancies"
  ))

  dplyr::tibble(
    label = label,
    n_overlap = n_overlap,
    n_match = n_match,
    n_discrepancy = n_disc,
    match_pct = 100 * n_match / n_overlap,
    max_rel_diff = max(result$rel_diff, na.rm = TRUE),
    median_rel_diff = median(result$rel_diff, na.rm = TRUE)
  )
}
