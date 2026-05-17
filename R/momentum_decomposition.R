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
                               lookback_months = 24,
                               min_obs = 6) {

  # F6 guard: OLS with 5 FF factors + 12 industry dummies = 17 parameters.
  # With lookback_months < 24, observations (n) can be less than parameters (p),
  # producing a degenerate fit (perfect in-sample R², zero generalisation).
  # Minimum 24 months provides 7 degrees of freedom vs 17 parameters.
  # (roborev cluster B, finding F6)
  n_ff_params <- 5L   # Mkt.RF, SMB, HML, RMW, CMA
  n_ind_params <- if (!is.null(industry_returns)) 12L else 0L
  n_params <- 1L + n_ff_params + n_ind_params  # intercept + factors + industries
  min_lookback <- n_params + 7L  # require at least 7 df
  if (lookback_months < min_lookback) {
    cli::cli_abort(c(
      "x" = "{.arg lookback_months} must be >= {min_lookback} to avoid overfitting.",
      "i" = "Regression has {n_params} parameters ({n_ff_params} FF factors + \\
{n_ind_params} industry dummies + 1 intercept).",
      "i" = "Received: {.val {lookback_months}} months ({lookback_months} obs vs {n_params} params).",
      "i" = "Use lookback_months >= {min_lookback} for at least 7 degrees of freedom."
    ))
  }

  # Join stock returns with factors using year-month (dates may differ by convention)
  stock_ym <- stock_returns |>
    dplyr::mutate(ym = format(date, "%Y-%m"))

  factor_ym <- factor_returns |>
    dplyr::mutate(ym = format(date, "%Y-%m")) |>
    dplyr::select(-date)

  combined <- stock_ym |>
    dplyr::inner_join(factor_ym, by = "ym") |>
    dplyr::arrange(ticker, date)

  # F1 assertion: join must produce rows (dates differ by convention — FF uses
  # month-START e.g. 2024-01-01, stock returns use month-END e.g. 2024-01-31;
  # the ym key coerces both sides to "YYYY-MM" before joining so they match.
  # Zero rows means date format mismatch — abort before any downstream
  # computation silently consumes empty data. (roborev cluster B, finding F1)
  if (nrow(combined) == 0L) {
    cli::cli_abort(c(
      "x" = "Factor join produced 0 rows — date convention mismatch.",
      "i" = "stock_returns date range: {min(stock_returns$date)} to {max(stock_returns$date)}",
      "i" = "factor_returns date range: {min(factor_returns$date)} to {max(factor_returns$date)}",
      "i" = "Both sides are coerced to YYYY-MM keys before joining.",
      "i" = "Check that factor_returns has a 'date' column with parseable dates."
    ))
  }

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

    # Join signal with forward returns. The signal at month T must predict
    # returns over T+1 through T+h. Lead the return series by one period
    # first, then take a forward window of length h. Without the lead, the
    # window T:T+h-1 includes month T's own return — i.e., the signal is
    # "predicting" the month it was computed in (roborev #941, look-ahead
    # bias).
    forward <- stock_returns |>
      dplyr::group_by(ticker) |>
      dplyr::arrange(date) |>
      dplyr::mutate(
        monthly_ret_lead = dplyr::lead(monthly_ret, n = 1L),
        forward_ret = slider::slide_dbl(
          monthly_ret_lead,
          ~prod(1 + .x, na.rm = FALSE) - 1,
          .before = 0,
          .after = h_months - 1,
          .complete = TRUE
        )
      ) |>
      dplyr::select(-monthly_ret_lead) |>
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


#' Build Optimized Momentum Signals
#'
#' Combine momentum components into optimized signals based on different
#' weighting schemes.
#'
#' @param decomposed_momentum Tibble from decompose_momentum()
#' @param scheme Character. One of:
#'   - "paper" (Style + Industry)
#'   - "data_driven" (Industry + Stock-Specific)
#'   - "conservative" (Industry only)
#'   - "baseline" (Total 12-month return, for comparison)
#' @param weights Numeric vector of length 2 for "paper" and "data_driven".
#'   Defaults to equal weights (0.5, 0.5).
#'
#' @return Tibble with columns: ticker, date, signal, scheme
#'
#' @export
build_optimized_signals <- function(decomposed_momentum,
                                   scheme = c("paper", "data_driven", "conservative", "baseline"),
                                   weights = c(0.5, 0.5)) {

  scheme <- match.arg(scheme)

  if (scheme == "baseline") {
    # Baseline is the ACTUAL trailing 12-month return (ret_12m), NOT the sum of
    # decomposition components. Summing components is degenerate — by construction
    # the decomposition is exhaustive so the sum is mechanically close to ret_12m,
    # making the comparison uninformative. (roborev cluster B, finding F3)
    result <- decomposed_momentum |>
      dplyr::mutate(signal = ret_12m) |>
      dplyr::select(ticker, date, signal) |>
      dplyr::mutate(scheme = "baseline")

  } else if (scheme == "paper") {
    # Paper recommendation: Style + Industry
    result <- decomposed_momentum |>
      dplyr::mutate(
        signal = weights[1] * style_momentum + weights[2] * industry_momentum
      ) |>
      dplyr::select(ticker, date, signal) |>
      dplyr::mutate(scheme = "paper")

  } else if (scheme == "data_driven") {
    # Data-driven: Industry + Stock-Specific
    result <- decomposed_momentum |>
      dplyr::mutate(
        signal = weights[1] * industry_momentum + weights[2] * stock_specific_momentum
      ) |>
      dplyr::select(ticker, date, signal) |>
      dplyr::mutate(scheme = "data_driven")

  } else if (scheme == "conservative") {
    # Conservative: Industry only
    result <- decomposed_momentum |>
      dplyr::mutate(signal = industry_momentum) |>
      dplyr::select(ticker, date, signal) |>
      dplyr::mutate(scheme = "conservative")
  }

  result
}


#' Backtest Momentum Signals
#'
#' Simulate long-short portfolio returns from momentum signals with transaction costs.
#'
#' @param signals Tibble with columns: ticker, date, signal, scheme
#' @param stock_returns Tibble with monthly stock returns
#' @param n_long Integer. Number of stocks to long (default 50)
#' @param n_short Integer. Number of stocks to short (default 50)
#' @param cost_per_trade Numeric. One-way transaction cost as fraction of trade
#'   (default 0.00153, from issue #125)
#' @param leverage Numeric. Portfolio leverage (default 1 for long-short dollar-neutral)
#'
#' @return Tibble with columns: date, scheme, portfolio_ret, turnover, cost, net_ret
#'
#' @export
backtest_momentum_signals <- function(signals,
                                     stock_returns,
                                     n_long = 50,
                                     n_short = 50,
                                     cost_per_trade = 0.00153,
                                     leverage = 1) {

  # Join signals with next month's returns
  combined <- signals |>
    dplyr::inner_join(
      stock_returns |>
        dplyr::mutate(date_lag = date) |>
        dplyr::group_by(ticker) |>
        dplyr::mutate(date = dplyr::lag(date)) |>
        dplyr::filter(!is.na(date)) |>
        dplyr::select(ticker, date, next_ret = monthly_ret),
      by = c("ticker", "date")
    )

  # For each month, rank stocks and select top/bottom
  portfolio <- combined |>
    dplyr::group_by(scheme, date) |>
    dplyr::mutate(
      rank = rank(-signal, na.last = "keep", ties.method = "first"),
      n_stocks = dplyr::n()
    ) |>
    dplyr::filter(rank <= n_long | rank > (n_stocks - n_short)) |>
    dplyr::mutate(
      weight = dplyr::case_when(
        rank <= n_long ~ leverage / (2 * n_long),
        TRUE ~ -leverage / (2 * n_short)
      ),
      position = ifelse(rank <= n_long, "long", "short")
    ) |>
    dplyr::ungroup()

  # Compute portfolio returns
  monthly_returns <- portfolio |>
    dplyr::group_by(scheme, date) |>
    dplyr::summarise(
      portfolio_ret = sum(weight * next_ret, na.rm = TRUE),
      n_positions = dplyr::n(),
      .groups = "drop"
    )

  # Compute turnover over the UNION of names across consecutive months.
  # The naive lag()-per-ticker approach only covers stocks present in both old
  # and new periods. Stocks that exit the portfolio (new weight = 0) are absent
  # from the new period's rows, so their exit weight-change is never counted.
  # Fix: build a complete (scheme, ticker, date) grid, fill missing weights with
  # 0, then compute abs(new - old) over the full universe. (roborev cluster B, F4)
  all_dates <- sort(unique(portfolio$date))
  turnover <- portfolio |>
    dplyr::select(scheme, ticker, date, weight) |>
    dplyr::arrange(scheme, ticker, date) |>
    # Expand to full (scheme x ticker x date) universe so exits get weight = 0
    tidyr::complete(
      tidyr::nesting(scheme, ticker),
      date = all_dates,
      fill = list(weight = 0)
    ) |>
    dplyr::group_by(scheme, ticker) |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      prev_weight = dplyr::lag(weight, default = 0),
      weight_change = abs(weight - prev_weight)
    ) |>
    dplyr::group_by(scheme, date) |>
    dplyr::summarise(
      turnover = sum(weight_change, na.rm = TRUE) / 2,  # Divide by 2 for one-way turnover
      .groups = "drop"
    )

  # Join and compute costs
  result <- monthly_returns |>
    dplyr::left_join(turnover, by = c("scheme", "date")) |>
    dplyr::mutate(
      turnover = ifelse(is.na(turnover), 0, turnover),
      cost = turnover * cost_per_trade,
      net_ret = portfolio_ret - cost
    )

  result
}


#' Summarize Backtest Performance
#'
#' Compute performance metrics (Sharpe, cumulative return, max drawdown, turnover)
#' for backtested momentum signals.
#'
#' @param backtest_results Tibble from backtest_momentum_signals()
#' @param annual_rf Numeric. Annual risk-free rate (default 0.02)
#'
#' @return Tibble with one row per scheme and performance metrics
#'
#' @export
summarize_backtest_performance <- function(backtest_results, annual_rf = 0.02) {

  monthly_rf <- (1 + annual_rf)^(1/12) - 1

  backtest_results |>
    dplyr::group_by(scheme) |>
    dplyr::summarise(
      n_months = dplyr::n(),
      mean_ret = mean(net_ret, na.rm = TRUE),
      sd_ret = sd(net_ret, na.rm = TRUE),
      sharpe = (mean(net_ret, na.rm = TRUE) - monthly_rf) / sd(net_ret, na.rm = TRUE) * sqrt(12),
      cumulative_ret = prod(1 + net_ret, na.rm = TRUE) - 1,
      annual_ret = (1 + mean(net_ret, na.rm = TRUE))^12 - 1,
      mean_turnover = mean(turnover, na.rm = TRUE),
      mean_cost = mean(cost, na.rm = TRUE),
      gross_sharpe = (mean(portfolio_ret, na.rm = TRUE) - monthly_rf) / sd(portfolio_ret, na.rm = TRUE) * sqrt(12),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      max_dd = purrr::map_dbl(scheme, ~{
        rets <- backtest_results |>
          dplyr::filter(scheme == .x) |>
          dplyr::pull(net_ret)
        cumrets <- cumprod(1 + rets)
        cummax <- cummax(cumrets)
        dd <- (cumrets - cummax) / cummax
        min(dd, na.rm = TRUE)
      })
    ) |>
    dplyr::arrange(dplyr::desc(sharpe))
}
