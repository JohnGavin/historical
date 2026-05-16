# Tail effective sample size (K_eff_acf) analysis
# Gap from #105: tail K_eff_acf mentioned in #55 but not implemented
# Measures effective independent observations accounting for autocorrelation

#' Calculate effective sample size (K_eff_acf) using Newey-West approach
#'
#' K_eff_acf adjusts sample size for autocorrelation. Higher autocorrelation
#' reduces effective sample size, affecting statistical power.
#'
#' Formula: K_eff_acf = N / (1 + 2 * sum(rho_k))
#' where rho_k are autocorrelations up to lag L
#'
#' @param x Numeric vector of observations
#' @param max_lag Maximum lag for autocorrelation (default: floor(N^(1/3)))
#' @return List with K_eff_acf, N, and autocorrelation sum
#' @export
calculate_keff <- function(x, max_lag = NULL) {
  x_clean <- x[!is.na(x)]
  N <- length(x_clean)

  if (N < 10) {
    cli::cli_warn("Fewer than 10 observations for K_eff_acf calculation")
    return(list(K_eff_acf = NA_real_, N = N, acf_sum = NA_real_))
  }

  if (is.null(max_lag)) {
    max_lag <- floor(N^(1/3))  # Newey-West bandwidth
  }
  max_lag <- min(max_lag, N - 1)

  # Calculate autocorrelations
  acf_values <- stats::acf(x_clean, lag.max = max_lag, plot = FALSE)$acf[-1]  # Exclude lag 0

  # Sum of autocorrelations (weighted by Newey-West kernel)
  lags <- seq_len(max_lag)
  nw_weights <- 1 - (lags / (max_lag + 1))  # Bartlett kernel
  acf_sum <- sum(acf_values * nw_weights, na.rm = TRUE)

  # Effective sample size
  K_eff_acf <- N / (1 + 2 * acf_sum)

  list(
    K_eff_acf = K_eff_acf,
    N = N,
    acf_sum = acf_sum,
    efficiency = K_eff_acf / N  # Proportion of "independent" observations
  )
}

#' Calculate tail K_eff_acf split by crisis regime
#'
#' Compares effective sample size in crisis (VIX ≥ 30) vs calm (VIX < 30) periods.
#' Crisis periods typically have higher autocorrelation → lower K_eff_acf.
#'
#' @param returns Numeric vector of strategy returns
#' @param dates Date vector (same length as returns)
#' @param vix_data Tibble with columns: date, vix
#' @param crisis_threshold VIX threshold for crisis (default 30)
#' @return Tibble with K_eff_acf for crisis, calm, and full sample
#' @export
tail_keff_crisis_calm <- function(returns, dates, vix_data, crisis_threshold = 30) {
  # Join returns with VIX
  data <- tibble::tibble(date = dates, return = returns) |>
    dplyr::left_join(vix_data, by = "date") |>
    dplyr::filter(!is.na(vix))

  # Split by regime
  crisis_returns <- data |> dplyr::filter(vix >= crisis_threshold) |> dplyr::pull(return)
  calm_returns <- data |> dplyr::filter(vix < crisis_threshold) |> dplyr::pull(return)

  # Calculate K_eff_acf for each regime
  keff_crisis <- calculate_keff(crisis_returns)
  keff_calm <- calculate_keff(calm_returns)
  keff_full <- calculate_keff(data$return)

  tibble::tibble(
    regime = c("Full Sample", "Crisis (VIX ≥ 30)", "Calm (VIX < 30)"),
    N = c(keff_full$N, keff_crisis$N, keff_calm$N),
    K_eff_acf = c(keff_full$K_eff_acf, keff_crisis$K_eff_acf, keff_calm$K_eff_acf),
    efficiency = c(keff_full$efficiency, keff_crisis$efficiency, keff_calm$efficiency),
    acf_sum = c(keff_full$acf_sum, keff_crisis$acf_sum, keff_calm$acf_sum)
  )
}

#' Calculate tail K_eff_acf for multiple strategies
#'
#' @param returns_df Tibble with columns: date, strategy, return
#' @param vix_data Tibble with columns: date, vix
#' @param crisis_threshold VIX threshold for crisis (default 30)
#' @return Tibble with K_eff_acf by strategy and regime
#' @export
tail_keff_by_strategy <- function(returns_df, vix_data, crisis_threshold = 30) {
  returns_df |>
    dplyr::group_by(strategy) |>
    dplyr::summarise(
      keff_results = list(
        tail_keff_crisis_calm(
          returns = return,
          dates = date,
          vix_data = vix_data,
          crisis_threshold = crisis_threshold
        )
      ),
      .groups = "drop"
    ) |>
    tidyr::unnest(keff_results)
}

#' Calculate K_eff_acf for tail partitions (5%/90%/5%)
#'
#' Splits returns into bottom 5%, middle 90%, top 5% and calculates
#' K_eff_acf for each partition.
#'
#' @param returns Numeric vector of returns
#' @return Tibble with K_eff_acf by tail partition
#' @export
tail_keff_partitions <- function(returns) {
  returns_clean <- returns[!is.na(returns)]

  # Define tail thresholds
  q05 <- stats::quantile(returns_clean, 0.05)
  q95 <- stats::quantile(returns_clean, 0.95)

  # Partition returns
  bottom_5 <- returns_clean[returns_clean <= q05]
  middle_90 <- returns_clean[returns_clean > q05 & returns_clean < q95]
  top_5 <- returns_clean[returns_clean >= q95]

  # Calculate K_eff_acf for each partition
  keff_bottom <- calculate_keff(bottom_5)
  keff_middle <- calculate_keff(middle_90)
  keff_top <- calculate_keff(top_5)

  tibble::tibble(
    partition = c("Bottom 5%", "Middle 90%", "Top 5%"),
    threshold_low = c(NA, q05, q95),
    threshold_high = c(q05, q95, NA),
    N = c(keff_bottom$N, keff_middle$N, keff_top$N),
    K_eff_acf = c(keff_bottom$K_eff_acf, keff_middle$K_eff_acf, keff_top$K_eff_acf),
    efficiency = c(keff_bottom$efficiency, keff_middle$efficiency, keff_top$efficiency)
  )
}

#' Plot K_eff_acf efficiency by regime
#'
#' @param keff_df Output from tail_keff_crisis_calm() or tail_keff_by_strategy()
#' @return ggplot bar chart
#' @export
plot_keff_efficiency <- function(keff_df) {
  # If multiple strategies, facet by strategy
  has_strategy <- "strategy" %in% names(keff_df)

  p <- ggplot2::ggplot(keff_df, ggplot2::aes(x = regime, y = efficiency, fill = regime)) +
    ggplot2::geom_col() +
    ggplot2::scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    ggplot2::labs(
      title = "Effective Sample Size Efficiency by Regime",
      subtitle = "Lower efficiency = higher autocorrelation (fewer independent observations)",
      x = NULL,
      y = "K_eff_acf / N (Efficiency)"
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      legend.position = "none",
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1)
    )

  if (has_strategy) {
    p <- p + ggplot2::facet_wrap(~strategy, scales = "free_x")
  }

  p
}
