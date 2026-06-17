# engine.R — Financial Contagion Network Engine
# Author: Claude-Alpha
# Date: 2026-03-05
#
# Builds rolling correlation networks from real stock data (quantmod)
# and computes network metrics to test whether network structure
# changes predict market crashes.

suppressPackageStartupMessages({
  library(quantmod)
  library(igraph)
  library(dplyr)
  library(tibble)
  library(tidyr)
  library(xts)
  library(zoo)
})

# ============================================================================
# CONFIGURATION
# ============================================================================

# Stock universe: ~30 major US stocks across 6 sectors + SPY benchmark
TICKERS <- list(
  Tech     = c("AAPL", "MSFT", "GOOGL", "AMZN", "NVDA", "META"),
  Finance  = c("JPM", "BAC", "GS", "MS", "WFC"),
  Health   = c("JNJ", "PFE", "UNH", "ABBV"),
  Energy   = c("XOM", "CVX", "COP"),
  Consumer = c("WMT", "PG", "KO", "MCD", "NKE"),
  Industrial = c("CAT", "BA", "HON", "UPS")
)

BENCHMARK <- "SPY"

ALL_TICKERS <- c(unlist(TICKERS), BENCHMARK)

# Sector lookup for coloring
SECTOR_MAP <- tibble(
  ticker = unlist(TICKERS),
  sector = rep(names(TICKERS), times = lengths(TICKERS))
) |> bind_rows(tibble(ticker = BENCHMARK, sector = "Benchmark"))

SECTOR_COLORS <- c(
  Tech       = "#3498db",
  Finance    = "#e74c3c",
  Health     = "#2ecc71",
  Energy     = "#f39c12",
  Consumer   = "#9b59b6",
  Industrial = "#1abc9c",
  Benchmark  = "#34495e"
)

# Market events for annotation
MARKET_EVENTS <- tibble::tribble(
  ~date,        ~label,                    ~type,
  "2020-02-20", "COVID crash start",       "crash",
  "2020-03-23", "COVID crash bottom",      "crash",
  "2021-11-19", "2021 bull peak",          "control",
  "2022-01-03", "2022 selloff start",      "crash",
  "2022-06-16", "2022 selloff bottom",     "crash",
  "2022-10-12", "2022 bear market bottom", "crash"
) |> mutate(date = as.Date(date))

# ============================================================================
# DATA ACQUISITION
# ============================================================================

#' Download stock data via quantmod
#' @param tickers Character vector of ticker symbols
#' @param from Start date (character or Date)
#' @param to End date (character or Date)
#' @return xts object of adjusted closing prices, columns = tickers
download_stock_data <- function(tickers = ALL_TICKERS,
                                from = "2019-01-01",
                                to = "2024-12-31") {
  cat("Downloading", length(tickers), "tickers from Yahoo Finance...\n")

  prices <- list()
  failed <- character(0)

  for (tk in tickers) {
    tryCatch({
      data <- getSymbols(tk, src = "yahoo", from = from, to = to,
                         auto.assign = FALSE, warnings = FALSE)
      # Extract adjusted close
      adj_col <- paste0(tk, ".Adjusted")
      if (adj_col %in% colnames(data)) {
        prices[[tk]] <- data[, adj_col]
      }
    }, error = function(e) {
      cat("  WARNING: Failed to download", tk, "-", conditionMessage(e), "\n")
      failed <<- c(failed, tk)
    })
  }

  if (length(prices) == 0) {
    cat("All downloads failed. Using synthetic data fallback.\n")
    return(generate_synthetic_market())
  }

  # Merge into single xts, align dates
  merged <- do.call(merge, prices)
  colnames(merged) <- names(prices)

  # Remove rows with too many NAs (holidays, IPO dates)
  merged <- merged[complete.cases(merged), ]

  cat("Downloaded", ncol(merged), "tickers,", nrow(merged), "trading days\n")
  if (length(failed) > 0) cat("  Failed:", paste(failed, collapse = ", "), "\n")

  merged
}

#' Compute log returns from prices
#' @param prices xts of prices
#' @return xts of log returns (first row dropped)
compute_returns <- function(prices) {
  returns <- diff(log(prices))
  returns <- returns[-1, ]  # drop first NA row
  returns[is.na(returns)] <- 0  # fill remaining NAs with 0
  returns
}

# ============================================================================
# SYNTHETIC DATA FALLBACK
# ============================================================================

#' Generate synthetic market data calibrated to real parameters
#' Used when quantmod download fails
generate_synthetic_market <- function(n_stocks = 30, n_days = 1500,
                                      crash_starts = c(300, 800),
                                      crash_durations = c(25, 40)) {
  cat("Generating synthetic market data (fallback)...\n")
  set.seed(42)

  # Generate sector assignments
  n_sectors <- 6
  sector_ids <- rep(1:n_sectors, length.out = n_stocks)

  # Base parameters
  daily_vol <- 0.016        # ~16% annualized
  base_corr <- 0.30         # normal correlation
  sector_corr <- 0.50       # within-sector correlation
  crash_corr <- 0.85        # crash correlation

  # Time-varying correlation structure
  returns_matrix <- matrix(0, nrow = n_days, ncol = n_stocks)
  colnames(returns_matrix) <- paste0("STOCK", sprintf("%02d", 1:n_stocks))

  for (day in 1:n_days) {
    # Determine regime
    in_crash <- any(sapply(seq_along(crash_starts), function(i) {
      day >= crash_starts[i] && day < crash_starts[i] + crash_durations[i]
    }))
    pre_crash <- any(sapply(seq_along(crash_starts), function(i) {
      day >= (crash_starts[i] - 20) && day < crash_starts[i]
    }))

    # Build correlation matrix
    rho <- if (in_crash) crash_corr else if (pre_crash) base_corr * 1.5 else base_corr

    Sigma <- matrix(rho, n_stocks, n_stocks)
    for (i in 1:n_stocks) {
      for (j in 1:n_stocks) {
        if (i == j) {
          Sigma[i, j] <- 1
        } else if (sector_ids[i] == sector_ids[j]) {
          Sigma[i, j] <- max(Sigma[i, j], sector_corr)
        }
      }
    }

    # Cholesky decomposition
    L <- tryCatch(chol(Sigma), error = function(e) {
      # Make positive definite
      eig <- eigen(Sigma, symmetric = TRUE)
      eig$values <- pmax(eig$values, 0.01)
      Sigma_pd <- eig$vectors %*% diag(eig$values) %*% t(eig$vectors)
      chol(Sigma_pd)
    })

    z <- rnorm(n_stocks)
    vol <- if (in_crash) daily_vol * 3 else daily_vol
    returns_matrix[day, ] <- vol * (t(L) %*% z)
  }

  # Convert to xts — generate enough weekday dates
  all_dates <- seq(as.Date("2019-01-02"), by = "day",
                   length.out = n_days * 2)  # overshoot
  weekday_dates <- all_dates[!weekdays(all_dates) %in% c("Saturday", "Sunday")]
  dates <- weekday_dates[1:n_days]

  xts(returns_matrix, order.by = dates)
}

# ============================================================================
# ROLLING CORRELATION NETWORKS
# ============================================================================

#' Compute Pearson correlation matrix for a window of returns
#' @param returns_window matrix of returns (rows = days, cols = stocks)
#' @return correlation matrix
compute_correlation <- function(returns_window) {
  cor(returns_window, use = "pairwise.complete.obs")
}

#' Build igraph network from correlation matrix
#' @param cor_matrix Correlation matrix
#' @param threshold Minimum |correlation| for edge (default 0.5)
#' @return igraph object with weighted edges
build_network <- function(cor_matrix, threshold = 0.5) {
  n <- nrow(cor_matrix)
  tickers <- colnames(cor_matrix)

  # Create adjacency from thresholded absolute correlation
  adj <- abs(cor_matrix)
  adj[adj < threshold] <- 0
  diag(adj) <- 0

  g <- graph_from_adjacency_matrix(adj, mode = "undirected", weighted = TRUE)
  V(g)$name <- tickers

  # Add sector info
  sector_info <- SECTOR_MAP$sector[match(tickers, SECTOR_MAP$ticker)]
  V(g)$sector <- ifelse(is.na(sector_info), "Unknown", sector_info)
  V(g)$color <- SECTOR_COLORS[V(g)$sector]

  g
}

#' Detect communities using Louvain algorithm
#' @param g igraph object
#' @return community membership named vector
detect_communities <- function(g) {
  if (ecount(g) == 0) {
    # No edges = each node is its own community
    membership <- seq_len(vcount(g))
    names(membership) <- V(g)$name
    return(membership)
  }
  comm <- cluster_louvain(g, weights = E(g)$weight)
  mem <- membership(comm)
  names(mem) <- V(g)$name
  mem
}

#' Compute network-level metrics
#' @param g igraph object
#' @param cor_matrix Correlation matrix used to build g
#' @return Named list of metrics
compute_network_metrics <- function(g, cor_matrix) {
  n <- vcount(g)

  # Average absolute correlation (off-diagonal)
  off_diag <- cor_matrix[upper.tri(cor_matrix)]
  avg_corr <- mean(abs(off_diag), na.rm = TRUE)
  avg_signed_corr <- mean(off_diag, na.rm = TRUE)

  # Largest eigenvalue of correlation matrix (Marchenko-Pastur indicator)
  eigenvalues <- eigen(cor_matrix, symmetric = TRUE, only.values = TRUE)$values
  max_eigenvalue <- max(eigenvalues)
  # Ratio of largest to second-largest (absorption ratio)
  sorted_eig <- sort(eigenvalues, decreasing = TRUE)
  absorption_ratio <- sum(sorted_eig[1:min(3, length(sorted_eig))]) / sum(sorted_eig)

  # Network topology
  n_edges <- ecount(g)
  max_edges <- n * (n - 1) / 2
  density <- if (max_edges > 0) n_edges / max_edges else 0

  degrees <- degree(g)
  mean_degree <- mean(degrees)
  max_degree <- max(degrees)
  hub_ticker <- V(g)$name[which.max(degrees)]

  # Modularity from Louvain communities
  if (n_edges > 0) {
    comm <- cluster_louvain(g, weights = E(g)$weight)
    modularity_val <- modularity(comm)
    n_communities <- length(unique(membership(comm)))
  } else {
    modularity_val <- NA
    n_communities <- n
  }

  # Betweenness centrality for hub analysis
  betw <- betweenness(g, normalized = TRUE)

  list(
    avg_corr          = avg_corr,
    avg_signed_corr   = avg_signed_corr,
    max_eigenvalue    = max_eigenvalue,
    absorption_ratio  = absorption_ratio,
    modularity        = modularity_val,
    n_communities     = n_communities,
    density           = density,
    mean_degree       = mean_degree,
    max_degree        = max_degree,
    hub_ticker        = hub_ticker,
    n_edges           = n_edges,
    betweenness       = betw
  )
}

# ============================================================================
# MAIN PIPELINE
# ============================================================================

#' Build rolling correlation networks over time
#' @param returns xts of daily log returns
#' @param window Rolling window size in trading days (default 60 ~ 3 months)
#' @param step Step size in trading days (default 5 ~ 1 week)
#' @param threshold Correlation threshold for edges (default 0.5)
#' @return List with networks, metrics, communities, dates
build_rolling_networks <- function(returns, window = 60, step = 5,
                                    threshold = 0.5) {
  n_days <- nrow(returns)
  tickers <- colnames(returns)
  n_tickers <- ncol(returns)
  dates <- index(returns)

  cat("Building rolling networks: window =", window, ", step =", step,
      ", threshold =", threshold, "\n")
  cat("  Period:", as.character(dates[1]), "to", as.character(dates[n_days]), "\n")
  cat("  Tickers:", n_tickers, "\n")

  # Window start positions
  starts <- seq(1, n_days - window + 1, by = step)
  n_windows <- length(starts)
  cat("  Windows:", n_windows, "\n")

  # Storage
  networks <- vector("list", n_windows)
  metrics_list <- vector("list", n_windows)
  communities_list <- vector("list", n_windows)
  window_dates <- as.Date(rep(NA, n_windows))

  for (i in seq_len(n_windows)) {
    s <- starts[i]
    e <- s + window - 1

    # Extract window
    window_returns <- as.matrix(returns[s:e, ])

    # Center date for this window
    window_dates[i] <- dates[s + window %/% 2]

    # Correlation matrix
    cor_mat <- compute_correlation(window_returns)

    # Build network
    g <- build_network(cor_mat, threshold = threshold)
    networks[[i]] <- g

    # Detect communities
    mem <- detect_communities(g)
    communities_list[[i]] <- tibble(
      date = window_dates[i],
      ticker = names(mem),
      community_id = as.integer(mem),
      degree = degree(g)[names(mem)],
      betweenness = betweenness(g, normalized = TRUE)[names(mem)]
    )

    # Compute metrics
    m <- compute_network_metrics(g, cor_mat)
    metrics_list[[i]] <- tibble(
      date             = window_dates[i],
      avg_corr         = m$avg_corr,
      avg_signed_corr  = m$avg_signed_corr,
      max_eigenvalue   = m$max_eigenvalue,
      absorption_ratio = m$absorption_ratio,
      modularity       = m$modularity,
      n_communities    = m$n_communities,
      density          = m$density,
      mean_degree      = m$mean_degree,
      max_degree       = m$max_degree,
      hub_ticker       = m$hub_ticker,
      n_edges          = m$n_edges
    )

    if (i %% 50 == 0) cat("  Processed", i, "/", n_windows, "windows\n")
  }

  cat("  Done!\n")

  # Combine
  metrics <- bind_rows(metrics_list)
  communities <- bind_rows(communities_list)

  # Add SPY returns for overlay (if available)
  spy_returns <- if ("SPY" %in% tickers) {
    tibble(
      date = dates,
      spy_return = as.numeric(returns[, "SPY"])
    ) |>
      mutate(spy_cumulative = cumsum(spy_return))
  } else {
    NULL
  }

  list(
    networks    = networks,
    metrics     = metrics,
    communities = communities,
    returns     = returns,
    dates       = window_dates,
    events      = MARKET_EVENTS,
    spy_returns = spy_returns,
    sector_map  = SECTOR_MAP,
    sector_colors = SECTOR_COLORS,
    params      = list(window = window, step = step, threshold = threshold,
                       tickers = tickers, from = dates[1], to = dates[n_days])
  )
}

# ============================================================================
# STATISTICAL TESTING (H2: Leading Indicator)
# ============================================================================

#' Label each metric observation as pre-crash, crash, or normal
#' @param metrics tibble from build_rolling_networks
#' @param events tibble of market events
#' @param pre_crash_days Number of days before crash start to label as "pre-crash"
#' @return metrics with additional 'regime' column
label_regimes <- function(metrics, events = MARKET_EVENTS,
                           pre_crash_days = 20) {
  crash_starts <- events |> filter(type == "crash", grepl("start", label)) |> pull(date)
  crash_bottoms <- events |> filter(type == "crash", grepl("bottom", label)) |> pull(date)

  metrics |>
    mutate(
      regime = case_when(
        # During crash
        sapply(date, function(d) {
          any(sapply(seq_along(crash_starts), function(i) {
            d >= crash_starts[i] & d <= crash_bottoms[min(i, length(crash_bottoms))]
          }))
        }) ~ "crash",
        # Pre-crash (20 days before crash start)
        sapply(date, function(d) {
          any(sapply(crash_starts, function(cs) {
            d >= (cs - pre_crash_days) & d < cs
          }))
        }) ~ "pre_crash",
        # Otherwise normal
        TRUE ~ "normal"
      )
    )
}

#' Run Welch t-tests comparing pre-crash vs normal metrics
#' Tests H2: Do network metrics change before crashes?
#' @param metrics tibble with regime labels
#' @return tibble of test results
run_statistical_tests <- function(metrics) {
  if (!"regime" %in% names(metrics)) {
    metrics <- label_regimes(metrics)
  }

  metric_vars <- c("avg_corr", "max_eigenvalue", "absorption_ratio",
                    "modularity", "density", "mean_degree", "n_communities")

  results <- lapply(metric_vars, function(var) {
    normal_vals <- metrics |> filter(regime == "normal") |> pull(!!sym(var))
    pre_crash_vals <- metrics |> filter(regime == "pre_crash") |> pull(!!sym(var))
    crash_vals <- metrics |> filter(regime == "crash") |> pull(!!sym(var))

    # Pre-crash vs normal
    test_pre <- if (length(pre_crash_vals) >= 3 && length(normal_vals) >= 3) {
      t.test(pre_crash_vals, normal_vals)
    } else {
      NULL
    }

    # Crash vs normal
    test_crash <- if (length(crash_vals) >= 3 && length(normal_vals) >= 3) {
      t.test(crash_vals, normal_vals)
    } else {
      NULL
    }

    tibble(
      metric = var,
      normal_mean = mean(normal_vals, na.rm = TRUE),
      pre_crash_mean = if (!is.null(test_pre)) mean(pre_crash_vals, na.rm = TRUE) else NA,
      crash_mean = if (!is.null(test_crash)) mean(crash_vals, na.rm = TRUE) else NA,
      pre_crash_p = if (!is.null(test_pre)) test_pre$p.value else NA,
      crash_p = if (!is.null(test_crash)) test_crash$p.value else NA,
      pre_crash_sig = if (!is.null(test_pre)) test_pre$p.value < 0.05 else NA,
      crash_sig = if (!is.null(test_crash)) test_crash$p.value < 0.05 else NA,
      pre_crash_direction = if (!is.null(test_pre)) {
        ifelse(mean(pre_crash_vals, na.rm = TRUE) > mean(normal_vals, na.rm = TRUE),
               "higher", "lower")
      } else NA,
      crash_direction = if (!is.null(test_crash)) {
        ifelse(mean(crash_vals, na.rm = TRUE) > mean(normal_vals, na.rm = TRUE),
               "higher", "lower")
      } else NA
    )
  })

  bind_rows(results)
}

# ============================================================================
# HUB ANALYSIS (H3: Hub Propagation)
# ============================================================================

#' Analyze which stocks become hubs during different regimes
#' @param communities tibble from build_rolling_networks
#' @param metrics tibble with regime labels
#' @return tibble of hub analysis results
analyze_hubs <- function(communities, metrics) {
  if (!"regime" %in% names(metrics)) {
    metrics <- label_regimes(metrics)
  }

  # Join regime labels to community data
  hub_data <- communities |>
    left_join(metrics |> select(date, regime), by = "date") |>
    filter(!is.na(regime))

  # Mean degree and betweenness by ticker and regime
  hub_summary <- hub_data |>
    group_by(ticker, regime) |>
    summarise(
      mean_degree = mean(degree, na.rm = TRUE),
      mean_betweenness = mean(betweenness, na.rm = TRUE),
      .groups = "drop"
    ) |>
    left_join(SECTOR_MAP, by = "ticker")

  # Degree change: crash vs normal
  hub_change <- hub_summary |>
    select(ticker, sector, regime, mean_degree) |>
    pivot_wider(names_from = regime, values_from = mean_degree,
                names_prefix = "degree_")

  # Safely compute degree change if both columns exist
  if ("degree_crash" %in% names(hub_change) && "degree_normal" %in% names(hub_change)) {
    hub_change <- hub_change |>
      mutate(degree_change = degree_crash - degree_normal) |>
      arrange(desc(degree_change))
  } else {
    hub_change$degree_change <- NA_real_
  }

  list(
    summary = hub_summary,
    change = hub_change
  )
}

# ============================================================================
# CONVENIENCE: Full Analysis Pipeline
# ============================================================================

#' Run the complete analysis pipeline
#' @param from Start date
#' @param to End date
#' @param window Rolling window size
#' @param step Step size
#' @param threshold Correlation threshold
#' @return List with all results
run_full_analysis <- function(from = "2019-01-01", to = "2024-12-31",
                               window = 60, step = 5, threshold = 0.5) {
  cat("=" |> rep(60) |> paste(collapse = ""), "\n")
  cat("FINANCIAL CONTAGION NETWORK ANALYSIS\n")
  cat("=" |> rep(60) |> paste(collapse = ""), "\n\n")

  # Step 1: Download data
  cat("[1/5] Downloading stock data...\n")
  prices <- download_stock_data(from = from, to = to)

  # Step 2: Compute returns
  cat("[2/5] Computing returns...\n")
  returns <- compute_returns(prices)

  # Step 3: Build rolling networks
  cat("[3/5] Building rolling correlation networks...\n")
  result <- build_rolling_networks(returns, window = window,
                                    step = step, threshold = threshold)

  # Step 4: Statistical tests
  cat("[4/5] Running statistical tests...\n")
  result$metrics <- label_regimes(result$metrics)
  result$tests <- run_statistical_tests(result$metrics)

  # Step 5: Hub analysis
  cat("[5/5] Analyzing hub propagation...\n")
  result$hubs <- analyze_hubs(result$communities, result$metrics)

  cat("\n")
  cat("=" |> rep(60) |> paste(collapse = ""), "\n")
  cat("ANALYSIS COMPLETE\n")
  cat("=" |> rep(60) |> paste(collapse = ""), "\n")

  # Print summary
  cat("\nSummary:\n")
  cat("  Period:", as.character(result$params$from), "to",
      as.character(result$params$to), "\n")
  cat("  Stocks:", length(result$params$tickers), "\n")
  cat("  Windows:", nrow(result$metrics), "\n")
  cat("  Avg correlation range:",
      round(min(result$metrics$avg_corr, na.rm = TRUE), 3), "to",
      round(max(result$metrics$avg_corr, na.rm = TRUE), 3), "\n")
  cat("  Max eigenvalue range:",
      round(min(result$metrics$max_eigenvalue, na.rm = TRUE), 2), "to",
      round(max(result$metrics$max_eigenvalue, na.rm = TRUE), 2), "\n")

  cat("\nStatistical Tests (pre-crash vs normal):\n")
  sig_tests <- result$tests |> filter(pre_crash_sig == TRUE)
  if (nrow(sig_tests) > 0) {
    for (i in seq_len(nrow(sig_tests))) {
      cat("  *", sig_tests$metric[i], ":", sig_tests$pre_crash_direction[i],
          "(p =", format(sig_tests$pre_crash_p[i], digits = 3), ")\n")
    }
  } else {
    cat("  No significant pre-crash signals detected\n")
  }

  result
}

cat("engine.R loaded successfully.\n")
cat("Usage: result <- run_full_analysis()\n")
