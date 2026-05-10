# Momentum Decomposition Functions
# Based on De Boer, Gao, Montminy (2025): "Optimizing the Persistence of Price Momentum"
#
# IMPLEMENTATION NOTE: 4 vs 5 Components
#
# The paper decomposes momentum into 5 components:
#   1. Beta momentum (market exposure)
#   2. Country momentum (geographic exposure)
#   3. Style momentum (factor loadings: HML, SMB, RMW, CMA)
#   4. Industry momentum (sector trends)
#   5. Stock-specific momentum (residual)
#
# For US-only stocks (our LTR universe), country momentum is zero because all
# stocks share the same geography. Therefore, this implementation uses 4
# components, omitting country momentum.
#
# Fama-French 5-Factor Model Definitions:
#   - HML (High Minus Low): Value factor — high book-to-market vs low
#   - SMB (Small Minus Big): Size factor — small-cap vs large-cap
#   - RMW (Robust Minus Weak): Profitability — high operating profit vs low
#   - CMA (Conservative Minus Aggressive): Investment — low asset growth vs high

#' Download Ken French Factor Data
#'
#' Downloads factor return data from Ken French Data Library. Supports monthly
#' and daily frequencies for various factor models.
#'
#' @param dataset Character. Dataset name from Ken French library:
#'   - "F-F_Research_Data_5_Factors_2x3" (5-factor model: Mkt-RF, SMB, HML, RMW, CMA)
#'   - "F-F_Momentum_Factor" (UMD momentum factor)
#'   - "12_Industry_Portfolios" (industry returns)
#'   - "49_Industry_Portfolios" (finer industry classification)
#' @param frequency Character. "monthly" or "daily"
#' @param cache Logical. Cache results to avoid repeated downloads?
#'
#' @return A tibble with columns: date, factor names (e.g., Mkt.RF, SMB, HML),
#'   and RF (risk-free rate)
#'
#' @examples
#' \dontrun{
#' # 5-factor model
#' factors <- hd_ff_factors("F-F_Research_Data_5_Factors_2x3", "monthly")
#'
#' # Momentum factor
#' momentum <- hd_ff_factors("F-F_Momentum_Factor", "monthly")
#'
#' # Industry portfolios
#' industries <- hd_ff_factors("12_Industry_Portfolios", "monthly")
#' }
#'
#' @export
hd_ff_factors <- function(dataset = "F-F_Research_Data_5_Factors_2x3",
                          frequency = c("monthly", "daily"),
                          cache = TRUE) {
  frequency <- match.arg(frequency)

  # Cache directory (use R standard cache location)
  cache_dir <- file.path(
    tools::R_user_dir("historicaldata", "cache"),
    "ken_french"
  )
  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)

  cache_file <- file.path(cache_dir, paste0(dataset, "_", frequency, ".rds"))

  # Return cached if exists
  if (cache && file.exists(cache_file)) {
    cli::cli_alert_info("Using cached {dataset} ({frequency})")
    return(readRDS(cache_file))
  }

  # Construct download URL
  base_url <- "https://mba.tuck.dartmouth.edu/pages/faculty/ken.french/ftp"
  file_suffix <- if (frequency == "daily") "_daily" else ""
  zip_name <- paste0(dataset, file_suffix, "_CSV.zip")
  url <- paste0(base_url, "/", zip_name)

  # Download and extract
  temp_zip <- tempfile(fileext = ".zip")
  temp_dir <- tempdir()

  cli::cli_alert_info("Downloading {dataset} from Ken French library...")
  tryCatch({
    download.file(url, temp_zip, mode = "wb", quiet = TRUE)
    unzip(temp_zip, exdir = temp_dir)
  }, error = function(e) {
    cli::cli_abort("Failed to download {dataset}: {e$message}")
  })

  # Find CSV file (name varies)
  csv_files <- list.files(temp_dir, pattern = "\\.csv$", full.names = TRUE, ignore.case = TRUE)
  if (length(csv_files) == 0) {
    cli::cli_abort("No CSV file found in {zip_name}")
  }
  csv_file <- csv_files[1]

  # Read CSV (Ken French format: skip header rows, handle multiple tables)
  raw_lines <- readLines(csv_file)

  # Find data start (first line with numeric date like "192607" or "19260701")
  date_pattern <- if (frequency == "monthly") "^\\d{6}," else "^\\d{8},"
  data_start <- which(grepl(date_pattern, raw_lines))[1]

  if (is.na(data_start)) {
    cli::cli_abort("Could not find data start in {basename(csv_file)}")
  }

  # Find data end (blank line or footer)
  data_lines <- raw_lines[data_start:length(raw_lines)]
  data_end_rel <- which(data_lines == "" | grepl("^\\s*$", data_lines))[1]
  data_end <- if (is.na(data_end_rel)) length(raw_lines) else (data_start + data_end_rel - 2)

  # Read data section
  data_text <- paste(raw_lines[data_start:data_end], collapse = "\n")
  con <- textConnection(data_text)
  df <- read.csv(con, header = FALSE, stringsAsFactors = FALSE)
  close(con)

  # Parse based on dataset type
  if (grepl("5_Factors|Research_Data_Factors", dataset)) {
    # Format: Date, Mkt-RF, SMB, HML, RMW, CMA, RF
    names(df) <- c("date", "Mkt.RF", "SMB", "HML", "RMW", "CMA", "RF")
  } else if (grepl("Momentum", dataset)) {
    # Format: Date, Mom (UMD)
    names(df) <- c("date", "Mom")
  } else if (grepl("Industry", dataset)) {
    # Format: Date, Ind1, Ind2, ...
    n_cols <- ncol(df)
    names(df) <- c("date", paste0("Ind", seq_len(n_cols - 1)))
  } else {
    cli::cli_abort("Unsupported dataset: {dataset}")
  }

  # Convert date
  if (frequency == "monthly") {
    df$date <- as.Date(paste0(df$date, "01"), format = "%Y%m%d")
  } else {
    df$date <- as.Date(as.character(df$date), format = "%Y%m%d")
  }

  # Convert returns from percent to decimal
  numeric_cols <- setdiff(names(df), "date")
  df[numeric_cols] <- lapply(df[numeric_cols], function(x) as.numeric(x) / 100)

  df <- dplyr::as_tibble(df)

  # Cache if requested
  if (cache) {
    saveRDS(df, cache_file)
    cli::cli_alert_success("Cached {dataset} to {basename(cache_file)}")
  }

  df
}


#' Decompose Momentum into Components via Attribution Regression
#'
#' Decomposes trailing 12-month stock returns into factor-driven and stock-specific
#' components using rolling regression. Based on De Boer et al. (2025).
#'
#' @param stock_returns Tibble with columns: date, ticker, monthly_ret
#' @param factor_returns Tibble with columns: date, Mkt.RF, SMB, HML, RMW, CMA, RF
#' @param industry_returns Tibble with columns: date, Ind1, Ind2, ..., Ind12
#' @param lookback_months Integer. Trailing window for computing momentum (default: 12)
#' @param min_obs Integer. Minimum observations required for regression (default: 6)
#'
#' @return Tibble with columns:
#'   - date, ticker
#'   - ret_12m: Total 12-month return
#'   - beta_momentum: Market beta × market return
#'   - style_momentum: Factor loadings × factor returns (SMB, HML, RMW, CMA)
#'   - industry_momentum: Industry loading × industry return
#'   - stock_specific_momentum: Residual (alpha + epsilon)
#'
#' @details
#' For each stock at each month, runs regression:
#'   r_t = alpha + beta * Mkt.RF + s_SMB * SMB + ... + s_IND * IND + epsilon
#'
#' Then computes components:
#'   - Beta momentum = beta * sum(Mkt.RF over 12m)
#'   - Style momentum = sum(factor_loadings * factor_returns over 12m)
#'   - Industry momentum = industry_loading * sum(IND over 12m)
#'   - Stock-specific = alpha * 12 + sum(epsilon over 12m)
#'
#' @export
decompose_momentum <- function(stock_returns,
                               factor_returns,
                               industry_returns = NULL,
                               lookback_months = 12,
                               min_obs = 6) {

  # Join stock returns with factors using year-month (dates may differ by convention)
  stock_ym <- stock_returns |>
    dplyr::mutate(ym = format(date, "%Y-%m"))

  factor_ym <- factor_returns |>
    dplyr::mutate(ym = format(date, "%Y-%m")) |>
    dplyr::select(-date)

  combined <- stock_ym |>
    dplyr::inner_join(factor_ym, by = "ym") |>
    dplyr::arrange(ticker, date)

  # If industry returns provided, join them
  if (!is.null(industry_returns)) {
    industry_ym <- industry_returns |>
      dplyr::mutate(ym = format(date, "%Y-%m")) |>
      dplyr::select(-date)

    combined <- combined |>
      dplyr::left_join(industry_ym, by = "ym")
  }

  # Compute 12-month trailing returns (for validation)
  combined <- combined |>
    dplyr::group_by(ticker) |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      ret_12m = RcppRoll::roll_prodr(1 + monthly_ret, n = lookback_months) - 1
    ) |>
    dplyr::ungroup()

  # For each stock-month, run rolling regression on trailing 12 months
  # Store factor loadings and compute attributed returns

  decomp_results <- combined |>
    dplyr::group_by(ticker) |>
    dplyr::arrange(date) |>
    dplyr::group_modify(function(.data, .key) {
      # Need at least lookback_months observations
      if (nrow(.data) < lookback_months) {
        return(tibble::tibble())
      }

      n <- nrow(.data)
      results <- vector("list", n - lookback_months + 1)

      for (i in lookback_months:n) {
        # Window: [i-lookback_months+1, i]
        window <- .data[(i - lookback_months + 1):i, ]

        # Skip if insufficient data
        if (sum(!is.na(window$monthly_ret)) < min_obs) {
          next
        }

        # Regression: monthly_ret ~ Mkt.RF + SMB + HML + RMW + CMA [+ Industry]
        formula_str <- "monthly_ret ~ Mkt.RF + SMB + HML + RMW + CMA"

        # Add industry if available
        if (!is.null(industry_returns)) {
          ind_cols <- grep("^Ind\\d+$", names(window), value = TRUE)
          if (length(ind_cols) > 0) {
            formula_str <- paste0(formula_str, " + ", paste(ind_cols, collapse = " + "))
          }
        }

        model <- tryCatch(
          lm(as.formula(formula_str), data = window),
          error = function(e) NULL
        )

        if (is.null(model)) next

        # Extract coefficients
        coefs <- coef(model)
        alpha <- coefs["(Intercept)"]
        beta <- coefs["Mkt.RF"]

        # Style loadings
        style_loadings <- coefs[c("SMB", "HML", "RMW", "CMA")]
        style_loadings[is.na(style_loadings)] <- 0

        # Industry loadings (if any)
        ind_cols <- grep("^Ind\\d+$", names(coefs), value = TRUE)
        if (length(ind_cols) > 0) {
          ind_loadings <- coefs[ind_cols]
          ind_loadings[is.na(ind_loadings)] <- 0
        } else {
          ind_loadings <- 0
        }

        # Compute attributed returns over the 12-month window
        # Beta momentum = beta * sum(Mkt.RF)
        beta_momentum <- beta * sum(window$Mkt.RF, na.rm = TRUE)

        # Style momentum = sum(loadings * factor_returns)
        style_momentum <- sum(
          style_loadings["SMB"] * sum(window$SMB, na.rm = TRUE),
          style_loadings["HML"] * sum(window$HML, na.rm = TRUE),
          style_loadings["RMW"] * sum(window$RMW, na.rm = TRUE),
          style_loadings["CMA"] * sum(window$CMA, na.rm = TRUE),
          na.rm = TRUE
        )

        # Industry momentum = sum(industry_loading * industry_return)
        if (length(ind_cols) > 0 && !is.null(industry_returns)) {
          industry_momentum <- sum(sapply(ind_cols, function(col) {
            ind_loadings[col] * sum(window[[col]], na.rm = TRUE)
          }), na.rm = TRUE)
        } else {
          industry_momentum <- 0
        }

        # Stock-specific = alpha * 12 + sum(residuals)
        residuals <- residuals(model)
        stock_specific_momentum <- alpha * lookback_months + sum(residuals, na.rm = TRUE)

        # Total return (for validation)
        ret_12m <- window$ret_12m[lookback_months]

        results[[i - lookback_months + 1]] <- tibble::tibble(
          date = window$date[lookback_months],
          ret_12m = ret_12m,
          beta_momentum = beta_momentum,
          style_momentum = style_momentum,
          industry_momentum = industry_momentum,
          stock_specific_momentum = stock_specific_momentum
        )
      }

      dplyr::bind_rows(results)
    }) |>
    dplyr::ungroup()

  decomp_results
}


#' Compute Persistence Metrics for Momentum Components
#'
#' Measures how well each momentum component predicts forward returns.
#' Based on De Boer et al. (2025) persistence analysis.
#'
#' @param decomposed_momentum Tibble from decompose_momentum()
#' @param stock_returns Tibble with columns: date, ticker, monthly_ret (forward returns)
#' @param horizons Character vector. Forecast horizons: "1m", "3m", "6m", "12m"
#'
#' @return Tibble with columns:
#'   - component: beta_momentum, style_momentum, industry_momentum, stock_specific_momentum
#'   - horizon: 1m, 3m, 6m, 12m
#'   - rank_ic: Spearman rank correlation (signal → forward return)
#'   - t_stat: t-statistic for rank IC
#'   - decay_rate: Signal decay rate (half-life in months)
#'
#' @details
#' For each component and horizon:
#'   1. Rank stocks by component value at month T
#'   2. Compute forward returns over horizon
#'   3. Spearman correlation between rank and forward return
#'   4. Repeat for all months, compute mean IC and t-stat
#'
#' @export
compute_persistence <- function(decomposed_momentum,
                                stock_returns,
                                horizons = c("1m", "3m", "6m", "12m")) {

  # Parse horizon strings to months
  horizon_months <- setNames(
    as.integer(sub("m$", "", horizons)),
    horizons
  )

  components <- c("beta_momentum", "style_momentum", "industry_momentum", "stock_specific_momentum")

  # For each component and horizon, compute rank IC
  results <- expand.grid(
    component = components,
    horizon = horizons,
    stringsAsFactors = FALSE
  ) |>
    dplyr::as_tibble()

  results$rank_ic <- NA_real_
  results$t_stat <- NA_real_
  results$n_months <- NA_integer_

  for (i in seq_len(nrow(results))) {
    comp <- results$component[i]
    h <- results$horizon[i]
    h_months <- horizon_months[h]

    # Join signal with forward returns
    forward <- stock_returns |>
      dplyr::group_by(ticker) |>
      dplyr::arrange(date) |>
      dplyr::mutate(
        forward_ret = RcppRoll::roll_prodr(1 + monthly_ret, n = h_months, align = "left") - 1
      ) |>
      dplyr::ungroup() |>
      dplyr::select(ticker, date, forward_ret)

    combined <- decomposed_momentum |>
      dplyr::select(ticker, date, signal = !!rlang::sym(comp)) |>
      dplyr::inner_join(forward, by = c("ticker", "date"))

    # For each month, compute rank IC
    monthly_ic <- combined |>
      dplyr::filter(!is.na(signal), !is.na(forward_ret)) |>
      dplyr::group_by(date) |>
      dplyr::summarise(
        ic = cor(signal, forward_ret, method = "spearman", use = "complete.obs"),
        n = dplyr::n(),
        .groups = "drop"
      ) |>
      dplyr::filter(!is.na(ic))

    if (nrow(monthly_ic) < 2) next

    # Mean IC and t-stat
    mean_ic <- mean(monthly_ic$ic, na.rm = TRUE)
    sd_ic <- sd(monthly_ic$ic, na.rm = TRUE)
    n_months <- nrow(monthly_ic)
    t_stat <- mean_ic / (sd_ic / sqrt(n_months))

    results$rank_ic[i] <- mean_ic
    results$t_stat[i] <- t_stat
    results$n_months[i] <- n_months
  }

  results |>
    dplyr::arrange(horizon, dplyr::desc(abs(rank_ic)))
}


#' Plot Persistence Metrics by Component
#'
#' Visualize which momentum components persist vs revert over different horizons.
#'
#' @param persistence_metrics Tibble from compute_persistence()
#' @param title Character. Plot title
#'
#' @return A ggplot2 object
#'
#' @export
plot_persistence_by_component <- function(persistence_metrics,
                                          title = "Momentum Component Persistence") {

  # Reorder horizons
  persistence_metrics$horizon <- factor(
    persistence_metrics$horizon,
    levels = c("1m", "3m", "6m", "12m")
  )

  # Clean component names for display
  persistence_metrics$component_label <- dplyr::recode(
    persistence_metrics$component,
    beta_momentum = "Beta (Market)",
    style_momentum = "Style (HML/SMB/RMW/CMA)",
    industry_momentum = "Industry",
    stock_specific_momentum = "Stock-Specific"
  )

  ggplot2::ggplot(persistence_metrics, ggplot2::aes(x = horizon, y = rank_ic,
                                                     fill = component_label)) +
    ggplot2::geom_col(position = "dodge") +
    ggplot2::geom_hline(yintercept = 0, linetype = "dashed", color = "gray50") +
    ggplot2::labs(
      title = title,
      subtitle = "Spearman rank IC: signal at month T vs forward return",
      x = "Forecast Horizon",
      y = "Rank IC (Mean)",
      fill = "Component"
    ) +
    ggplot2::theme_minimal() +
    ggplot2::theme(legend.position = "bottom")
}
