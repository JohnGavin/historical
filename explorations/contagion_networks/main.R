# main.R — Integration Script
# Financial Contagion Network Dashboard
# Claude-to-Claude Collaboration — 2026-03-05
#
# Sources engine.R and visualize.R, downloads real data,
# runs the full analysis, and generates an interactive HTML dashboard.

cat("=" |> rep(60) |> paste(collapse = ""), "\n")
cat("FINANCIAL CONTAGION NETWORK DASHBOARD\n")
cat("Claude-to-Claude Collaboration — 2026-03-05\n")
cat("=" |> rep(60) |> paste(collapse = ""), "\n\n")

# Source components
cat("Loading engine...\n")
source("engine.R")
cat("Loading visualize...\n")
source("visualize.R")

# ============================================================================
# RUN ANALYSIS
# ============================================================================

cat("\n--- Running full analysis ---\n\n")

# Try real data first, fall back to synthetic
result <- tryCatch({
  run_full_analysis(
    from = "2019-01-01",
    to = "2024-12-31",
    window = 60,
    step = 5,
    threshold = 0.5
  )
}, error = function(e) {
  cat("\nReal data failed:", conditionMessage(e), "\n")
  cat("Falling back to synthetic data...\n\n")

  # Generate synthetic returns
  returns <- generate_synthetic_market(n_stocks = 30, n_days = 1500,
                                        crash_starts = c(300, 800),
                                        crash_durations = c(25, 40))

  result <- build_rolling_networks(returns, window = 60, step = 5,
                                    threshold = 0.4)
  result$metrics <- label_regimes(result$metrics)
  result$tests <- run_statistical_tests(result$metrics)
  result$hubs <- analyze_hubs(result$communities, result$metrics)

  result
})

# ============================================================================
# BUILD DASHBOARD
# ============================================================================

cat("\n--- Building dashboard ---\n\n")

output_file <- build_dashboard(result, output_file = "dashboard.html")

cat("\n")
cat("=" |> rep(60) |> paste(collapse = ""), "\n")
cat("DONE! Open dashboard.html in a browser.\n")
cat("=" |> rep(60) |> paste(collapse = ""), "\n")

# ============================================================================
# PRINT KEY FINDINGS
# ============================================================================

cat("\n### KEY FINDINGS ###\n\n")

# H1: Structure
cat("H1 (Crash dissolves communities):\n")
crash_tests <- result$tests |> dplyr::filter(crash_sig == TRUE)
cat("  ", nrow(crash_tests), "/", nrow(result$tests),
    "metrics significantly different during crashes\n")
if (nrow(crash_tests) > 0) {
  for (i in seq_len(nrow(crash_tests))) {
    cat("  -", crash_tests$metric[i], ":", crash_tests$crash_direction[i],
        "(p =", format(crash_tests$crash_p[i], digits = 3), ")\n")
  }
}

cat("\nH2 (Pre-crash leading indicator):\n")
pre_tests <- result$tests |> dplyr::filter(pre_crash_sig == TRUE)
cat("  ", nrow(pre_tests), "/", nrow(result$tests),
    "metrics change significantly BEFORE crashes\n")
if (nrow(pre_tests) > 0) {
  for (i in seq_len(nrow(pre_tests))) {
    cat("  -", pre_tests$metric[i], ":", pre_tests$pre_crash_direction[i],
        "(p =", format(pre_tests$pre_crash_p[i], digits = 3), ")\n")
  }
}

cat("\nH3 (Hub propagation):\n")
if (!is.null(result$hubs$change) && "degree_change" %in% names(result$hubs$change)) {
  top_hubs <- result$hubs$change |>
    dplyr::filter(!is.na(degree_change)) |>
    dplyr::arrange(dplyr::desc(degree_change)) |>
    head(5)
  if (nrow(top_hubs) > 0) {
    cat("  Top 5 stocks gaining connections during crashes:\n")
    for (i in seq_len(nrow(top_hubs))) {
      cat("  -", top_hubs$ticker[i], "(", top_hubs$sector[i], "):",
          round(top_hubs$degree_change[i], 1), "more connections\n")
    }
  }
} else {
  cat("  (Insufficient crash data for hub analysis)\n")
}
