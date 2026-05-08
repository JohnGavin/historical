# Tracking error and information ratio functions
# Gap from #105: no explicit TE or IR vs SPY benchmark

#' Calculate tracking error vs benchmark
#'
#' Tracking error is the standard deviation of excess returns (strategy - benchmark)
#'
#' @param strategy_returns Numeric vector of strategy returns
#' @param benchmark_returns Numeric vector of benchmark returns (same length)
#' @param annualize_factor Annualization factor (default 252 for daily, 12 for monthly)
#' @return Annualized tracking error
#' @export
tracking_error <- function(strategy_returns, benchmark_returns, annualize_factor = 12) {
  if (length(strategy_returns) != length(benchmark_returns)) {
    cli::cli_abort("strategy_returns and benchmark_returns must have same length")
  }

  excess_returns <- strategy_returns - benchmark_returns
  te <- stats::sd(excess_returns, na.rm = TRUE) * sqrt(annualize_factor)

  te
}

#' Calculate information ratio
#'
#' Information ratio = (active return) / (tracking error)
#' Measures excess return per unit of active risk
#'
#' @param strategy_returns Numeric vector of strategy returns
#' @param benchmark_returns Numeric vector of benchmark returns
#' @param annualize_factor Annualization factor (default 252 for daily, 12 for monthly)
#' @return Information ratio (annualized)
#' @export
information_ratio <- function(strategy_returns, benchmark_returns, annualize_factor = 12) {
  excess_returns <- strategy_returns - benchmark_returns
  mean_excess <- mean(excess_returns, na.rm = TRUE) * annualize_factor
  te <- tracking_error(strategy_returns, benchmark_returns, annualize_factor)

  if (te == 0) {
    return(NA_real_)
  }

  mean_excess / te
}

#' Calculate tracking error statistics for multiple strategies
#'
#' @param returns_df Tibble with columns: date, strategy, return
#' @param benchmark_df Tibble with columns: date, return (benchmark returns)
#' @param benchmark_name Name of benchmark for reporting (default "SPY")
#' @param frequency "daily" or "monthly" (affects annualization)
#' @return Tibble with TE and IR per strategy
#' @export
calculate_te_ir <- function(returns_df, benchmark_df, benchmark_name = "SPY", frequency = "monthly") {
  annualize_factor <- if (frequency == "daily") 252 else 12

  # Join returns with benchmark
  combined <- returns_df |>
    dplyr::inner_join(
      benchmark_df |> dplyr::rename(benchmark_return = return),
      by = "date"
    )

  # Calculate TE and IR per strategy
  combined |>
    dplyr::group_by(strategy) |>
    dplyr::summarise(
      tracking_error = tracking_error(return, benchmark_return, annualize_factor),
      information_ratio = information_ratio(return, benchmark_return, annualize_factor),
      active_return = mean(return - benchmark_return, na.rm = TRUE) * annualize_factor,
      correlation_to_benchmark = stats::cor(return, benchmark_return, use = "complete.obs"),
      n_obs = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      benchmark = benchmark_name,
      frequency = frequency
    )
}

#' Add TE/IR to existing leaderboard metrics
#'
#' @param leaderboard_df Tibble with strategy performance metrics
#' @param te_ir_df Tibble from calculate_te_ir()
#' @return Joined tibble with TE/IR columns added
#' @export
add_te_ir_to_leaderboard <- function(leaderboard_df, te_ir_df) {
  leaderboard_df |>
    dplyr::left_join(
      te_ir_df |> dplyr::select(strategy, tracking_error, information_ratio, active_return),
      by = "strategy"
    )
}
