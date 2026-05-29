#' Select top-N DRIF factors via rank-first, filter-benchmark-second
#'
#' Shared selection logic used by both the production DRIF pipeline
#' (`plan_drif.R`) and the multiverse runner (`plan_drif_v2.R`).
#'
#' The order of operations is critical:
#' 1. Rank **all** predicted series (including benchmark) within each date
#'    group so that the benchmark competes for rank.
#' 2. Filter to the investable factor pool (`params$factors`), dropping the
#'    benchmark ticker.
#' 3. Retain only rows where `pred_rank <= top_n`.
#'
#' Doing the filter before the rank (the old multiverse code path) produced
#' different decile membership when the benchmark ranked highly, making the
#' multiverse's "current spec" non-comparable to production.
#'
#' @param predictions A tibble with at least the columns:
#'   - `factor_name` character — ticker / factor identifier
#'   - `ym` character — year-month key (`"YYYY-MM"`)
#'   - `pred_rank` integer — pre-computed rank within each `ym` group
#'     (lower = higher predicted return).  If absent, the function ranks
#'     on `predicted_ret` (production column name) or `predicted`
#'     (multiverse column name).
#'   - One of `predicted_ret` or `predicted` — the raw prediction value,
#'     used to compute `pred_rank` when it is missing.
#' @param params A list with at least:
#'   - `factors` character vector — investable factor names (benchmark excluded)
#' @param top_n Integer scalar — number of top-ranked factors to select.
#'
#' @return A tibble of the same column structure as `predictions`, filtered to
#'   the top-`top_n` factors (benchmark excluded) per month.  Returns a
#'   zero-row tibble (same columns as input) if no rows survive.
#'
#' @export
hd_drif_select_topn <- function(predictions, params, top_n) {
  # ── Input validation ──────────────────────────────────────────────────────
  if (!is.data.frame(predictions)) {
    cli::cli_abort(c(
      "x" = "{.arg predictions} must be a data frame.",
      "i" = "Got {.cls {class(predictions)}}."
    ))
  }
  if (!is.list(params) || is.null(params$factors)) {
    cli::cli_abort(c(
      "x" = "{.arg params} must be a list with a {.field factors} element.",
      "i" = "Got {.cls {class(params)}}."
    ))
  }
  if (!rlang::is_scalar_integerish(top_n) || top_n < 1L) {
    cli::cli_abort(c(
      "x" = "{.arg top_n} must be a positive integer scalar.",
      "i" = "Got {.val {top_n}}."
    ))
  }
  top_n <- as.integer(top_n)

  # ── Early exit on empty input ─────────────────────────────────────────────
  if (nrow(predictions) == 0L) return(predictions)

  # ── Ensure pred_rank exists (rank ALL series within each ym) ─────────────
  if (!"pred_rank" %in% names(predictions)) {
    # Support both column name conventions
    pred_col <- if ("predicted_ret" %in% names(predictions)) {
      "predicted_ret"
    } else if ("predicted" %in% names(predictions)) {
      "predicted"
    } else {
      cli::cli_abort(c(
        "x" = "{.arg predictions} has no {.field pred_rank}, {.field predicted_ret}, or {.field predicted} column.",
        "i" = "Cannot rank without a prediction value column."
      ))
    }
    predictions <- predictions |>
      dplyr::group_by(ym) |>
      dplyr::mutate(
        pred_rank = rank(-.data[[pred_col]], ties.method = "min")
      ) |>
      dplyr::ungroup()
  }

  # ── Filter-benchmark-SECOND, then apply top_n ─────────────────────────────
  predictions |>
    dplyr::filter(.data$factor_name %in% params$factors) |>
    dplyr::filter(.data$pred_rank <= top_n)
}
