#' @title Compute quantile fan from simulated paths
#' @description
#' Summarises the output of \code{\link{hd_simulate_paths}} into a quantile
#' table suitable for fan-chart visualisation. Phase D of issue #389.
#'
#' @param paths  Tibble from \code{hd_simulate_paths()}.
#' @param metric Character scalar: \code{"cum_nominal"} (default) or
#'   \code{"cum_real"}.
#' @param probs  Numeric vector of quantile probabilities in [0, 1].
#'   Default: \code{c(0.10, 0.25, 0.50, 0.75, 0.90)}.
#'
#' @return Tibble with columns \code{year}, \code{asset}, and one column per
#'   probability named \code{q<pct>} (e.g. \code{q10}, \code{q50}, \code{q90}).
#' @export
hd_path_quantiles <- function(
  paths,
  metric = c("cum_nominal", "cum_real"),
  probs  = c(0.10, 0.25, 0.50, 0.75, 0.90)
) {
  metric <- match.arg(metric)

  required_cols <- c("path_id", "year", "asset", metric)
  missing_cols  <- setdiff(required_cols, colnames(paths))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg paths} is missing required columns: {.val {missing_cols}}.",
      "i" = "Supply the output of {.fn hd_simulate_paths}."
    ))
  }
  if (!is.numeric(probs) || length(probs) == 0L || any(probs < 0) || any(probs > 1)) {
    cli::cli_abort("{.arg probs} must be a non-empty numeric vector in [0, 1].")
  }

  q_names <- paste0("q", as.integer(probs * 100))

  result <- dplyr::group_by(paths, .data$year, .data$asset)
  result <- dplyr::summarise(
    result,
    qs = list(stats::quantile(.data[[metric]], probs = probs, names = FALSE, na.rm = TRUE)),
    .groups = "drop"
  )

  qs_mat <- do.call(rbind, result$qs)
  colnames(qs_mat) <- q_names

  tibble::as_tibble(cbind(result[, c("year", "asset")], qs_mat))
}


#' @title Fan chart of simulated path quantiles
#' @description
#' Plots quantile ribbons from \code{\link{hd_path_quantiles}} output.
#' Requires columns \code{q10}, \code{q25}, \code{q50}, \code{q75}, \code{q90}.
#' Phase D of issue #389.
#'
#' @param quantiles Tibble from \code{hd_path_quantiles()} with columns
#'   \code{year}, \code{asset}, \code{q10}, \code{q25}, \code{q50},
#'   \code{q75}, \code{q90}.
#' @param title   Plot title (character scalar).
#' @param y_label Y-axis label (character scalar).
#' @param palette Named character vector of 3 colours for outer ribbon,
#'   inner ribbon, and median line: \code{c(outer=, inner=, median=)}.
#'
#' @return A \code{ggplot2} object. Faceted by asset when >1 asset is present.
#' @export
hd_plot_fan_chart <- function(
  quantiles,
  title   = "Multi-asset return paths",
  y_label = "Cumulative growth factor",
  palette = c(outer = "#BDD7EE", inner = "#4472C4", median = "#1F3864")
) {
  required <- c("year", "asset", "q10", "q25", "q50", "q75", "q90")
  missing  <- setdiff(required, colnames(quantiles))
  if (length(missing) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg quantiles} is missing required columns: {.val {missing}}.",
      "i" = "Supply the output of {.fn hd_path_quantiles} with default probs."
    ))
  }

  p <- ggplot2::ggplot(quantiles, ggplot2::aes(x = .data$year)) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = .data$q10, ymax = .data$q90),
      fill  = palette[["outer"]],
      alpha = 0.6
    ) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = .data$q25, ymax = .data$q75),
      fill  = palette[["inner"]],
      alpha = 0.5
    ) +
    ggplot2::geom_line(
      ggplot2::aes(y = .data$q50),
      colour    = palette[["median"]],
      linewidth = 0.9
    ) +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed", colour = "grey50") +
    ggplot2::labs(title = title, x = "Year", y = y_label) +
    ggplot2::theme_minimal(base_size = 11)

  if (dplyr::n_distinct(quantiles$asset) > 1L) {
    p <- p + ggplot2::facet_wrap(ggplot2::vars(.data$asset), scales = "free_y")
  }

  p
}
