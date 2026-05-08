# Regime-conditional cross-asset correlations
# Gap from #105: no cross-asset correlations; correlations not regime-conditional
# Implements contagion analysis from #102 findings

#' Calculate correlation matrix with regime splits
#'
#' @param returns_wide Wide tibble with columns: date, strategy1, strategy2, ..., SPY, TLT, GLD, DBC
#' @param vix_data Tibble with columns: date, vix
#' @return List of correlation matrices by regime
#' @export
regime_correlations <- function(returns_wide, vix_data) {
  # Join with VIX data
  data_with_vix <- returns_wide |>
    dplyr::left_join(vix_data, by = "date")

  # Define regimes
  data_with_regimes <- data_with_vix |>
    dplyr::mutate(
      vix_regime = dplyr::case_when(
        vix < 20 ~ "low",
        vix >= 20 & vix < 30 ~ "medium",
        vix >= 30 ~ "high",
        TRUE ~ NA_character_
      ),
      crisis = vix >= 30,
      # Tail classification based on VIX percentiles
      vix_pct = stats::ecdf(vix)(vix),
      tail_regime = dplyr::case_when(
        vix_pct <= 0.05 ~ "bottom_5pct",
        vix_pct >= 0.95 ~ "top_5pct",
        TRUE ~ "middle_90pct"
      )
    )

  # Calculate correlation matrices for each regime
  list(
    unconditional = calculate_corr_matrix(data_with_regimes),
    vix_low = calculate_corr_matrix(data_with_regimes |> dplyr::filter(vix_regime == "low")),
    vix_medium = calculate_corr_matrix(data_with_regimes |> dplyr::filter(vix_regime == "medium")),
    vix_high = calculate_corr_matrix(data_with_regimes |> dplyr::filter(vix_regime == "high")),
    crisis = calculate_corr_matrix(data_with_regimes |> dplyr::filter(crisis == TRUE)),
    calm = calculate_corr_matrix(data_with_regimes |> dplyr::filter(crisis == FALSE)),
    bottom_5pct = calculate_corr_matrix(data_with_regimes |> dplyr::filter(tail_regime == "bottom_5pct")),
    middle_90pct = calculate_corr_matrix(data_with_regimes |> dplyr::filter(tail_regime == "middle_90pct")),
    top_5pct = calculate_corr_matrix(data_with_regimes |> dplyr::filter(tail_regime == "top_5pct")),
    n_obs = list(
      unconditional = nrow(data_with_regimes),
      vix_low = sum(data_with_regimes$vix_regime == "low", na.rm = TRUE),
      vix_medium = sum(data_with_regimes$vix_regime == "medium", na.rm = TRUE),
      vix_high = sum(data_with_regimes$vix_regime == "high", na.rm = TRUE),
      crisis = sum(data_with_regimes$crisis, na.rm = TRUE),
      calm = sum(!data_with_regimes$crisis, na.rm = TRUE)
    )
  )
}

#' Calculate correlation matrix (helper)
#' @keywords internal
calculate_corr_matrix <- function(data) {
  # Remove date, vix, regime columns
  returns_only <- data |>
    dplyr::select(-dplyr::any_of(c("date", "vix", "vix_regime", "crisis", "vix_pct", "tail_regime")))

  if (nrow(returns_only) < 10) {
    cli::cli_warn("Fewer than 10 observations for correlation calculation")
    return(NULL)
  }

  stats::cor(returns_only, use = "pairwise.complete.obs")
}

#' Detect contagion: correlations that increase in crisis
#'
#' Contagion = correlation(crisis) - correlation(calm) > threshold
#'
#' @param regime_corr_list Output from regime_correlations()
#' @param threshold Minimum increase to flag as contagion (default 0.2)
#' @return Tibble with contagion pairs
#' @export
detect_contagion <- function(regime_corr_list, threshold = 0.2) {
  calm_corr <- regime_corr_list$calm
  crisis_corr <- regime_corr_list$crisis

  if (is.null(calm_corr) || is.null(crisis_corr)) {
    cli::cli_abort("Missing calm or crisis correlation matrices")
  }

  # Calculate difference matrix
  diff_matrix <- crisis_corr - calm_corr

  # Extract upper triangle (avoid duplicates)
  upper_tri_idx <- which(upper.tri(diff_matrix), arr.ind = TRUE)

  contagion_pairs <- tibble::tibble(
    asset1 = rownames(diff_matrix)[upper_tri_idx[, 1]],
    asset2 = colnames(diff_matrix)[upper_tri_idx[, 2]],
    corr_calm = calm_corr[upper_tri_idx],
    corr_crisis = crisis_corr[upper_tri_idx],
    corr_change = diff_matrix[upper_tri_idx],
    contagion_flag = diff_matrix[upper_tri_idx] > threshold
  ) |>
    dplyr::filter(contagion_flag) |>
    dplyr::arrange(dplyr::desc(corr_change))

  n_contagion <- nrow(contagion_pairs)
  if (n_contagion > 0) {
    cli::cli_inform(c(
      "v" = "{n_contagion} contagion pair(s) detected (correlation increase > {threshold})"
    ))
  }

  contagion_pairs
}

#' Create correlation heatmap for a regime
#'
#' @param corr_matrix Correlation matrix from regime_correlations()
#' @param regime_name Label for the plot title
#' @return ggplot heatmap
#' @export
plot_regime_correlation_heatmap <- function(corr_matrix, regime_name = "Unconditional") {
  if (is.null(corr_matrix)) {
    return(NULL)
  }

  # Convert to long format for ggplot
  corr_df <- as.data.frame(corr_matrix) |>
    tibble::rownames_to_column("asset1") |>
    tidyr::pivot_longer(-asset1, names_to = "asset2", values_to = "correlation")

  ggplot2::ggplot(corr_df, ggplot2::aes(x = asset1, y = asset2, fill = correlation)) +
    ggplot2::geom_tile() +
    ggplot2::scale_fill_gradient2(
      low = "#d7191c", mid = "white", high = "#2b83ba",
      midpoint = 0, limits = c(-1, 1),
      name = "Correlation"
    ) +
    ggplot2::geom_text(ggplot2::aes(label = sprintf("%.2f", correlation)), size = 3) +
    ggplot2::labs(
      title = paste("Correlation Heatmap:", regime_name),
      x = NULL, y = NULL
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      panel.grid = ggplot2::element_blank()
    )
}

#' Create regime comparison table for a specific asset pair
#'
#' @param regime_corr_list Output from regime_correlations()
#' @param asset1 First asset name
#' @param asset2 Second asset name
#' @return Tibble with correlations across regimes
#' @export
regime_correlation_comparison <- function(regime_corr_list, asset1, asset2) {
  extract_pair_corr <- function(mat) {
    if (is.null(mat)) return(NA_real_)
    if (!(asset1 %in% rownames(mat)) || !(asset2 %in% colnames(mat))) return(NA_real_)
    mat[asset1, asset2]
  }

  tibble::tibble(
    regime = c("Unconditional", "VIX Low", "VIX Medium", "VIX High",
               "Calm (VIX<30)", "Crisis (VIX≥30)",
               "Bottom 5%", "Middle 90%", "Top 5%"),
    correlation = c(
      extract_pair_corr(regime_corr_list$unconditional),
      extract_pair_corr(regime_corr_list$vix_low),
      extract_pair_corr(regime_corr_list$vix_medium),
      extract_pair_corr(regime_corr_list$vix_high),
      extract_pair_corr(regime_corr_list$calm),
      extract_pair_corr(regime_corr_list$crisis),
      extract_pair_corr(regime_corr_list$bottom_5pct),
      extract_pair_corr(regime_corr_list$middle_90pct),
      extract_pair_corr(regime_corr_list$top_5pct)
    ),
    n_obs = c(
      regime_corr_list$n_obs$unconditional,
      regime_corr_list$n_obs$vix_low,
      regime_corr_list$n_obs$vix_medium,
      regime_corr_list$n_obs$vix_high,
      regime_corr_list$n_obs$calm,
      regime_corr_list$n_obs$crisis,
      NA, NA, NA  # Tail counts not stored separately
    )
  ) |>
    dplyr::mutate(
      asset_pair = paste(asset1, "-", asset2)
    )
}
