#' @title Simulate joint multi-asset annual return paths
#' @description
#' Generates Monte Carlo paths for a set of assets using either a
#' parametric (multivariate-normal) or block-bootstrap approach.
#' Phase C of issue #389 — multivariate return simulation.
#'
#' @param n_paths    Positive integer. Number of simulation paths.
#' @param horizon_years Positive integer. Years to project forward.
#' @param assets     Character vector of asset tickers.
#' @param Sigma      Numeric matrix (n_assets x n_assets). Annualised
#'   covariance. If NULL, estimated from `.returns_wide`.
#' @param mu         Named numeric vector of annualised expected returns.
#'   If NULL, estimated as 12 x colMeans of `.returns_wide`.
#' @param method     One of `"parametric"` (MASS::mvrnorm) or
#'   `"bootstrap"` (block-bootstrap from `.returns_wide`).
#' @param cpi_annual_rate Numeric scalar. Constant annual CPI deflator
#'   (default 0.03). Phase E will replace with bootstrapped CPI draws.
#' @param block_size Integer. Monthly block length for bootstrap
#'   (default 12L — one year, preserves seasonal structure).
#' @param .returns_wide Data frame with columns `date` + one column
#'   per asset (monthly returns). Required for `method = "bootstrap"`
#'   and for estimating mu/Sigma when either is NULL.
#' @param .cpi_monthly Optional numeric vector of historical monthly CPI
#'   changes (month-over-month, e.g. from FRED CPIAUCSL). When supplied and
#'   `length(.cpi_monthly) >= block_size`, annual CPI rates are drawn by
#'   block-bootstrapping 12 consecutive monthly values (same `block_size` and
#'   `seed` as the return draws). When NULL (default), `cpi_annual_rate` is
#'   used as a constant. Phase E of issue #389.
#' @param seed       Integer random seed (default 42L).
#'
#' @return A tibble with 7 columns:
#'   \describe{
#'     \item{path_id}{Integer (1..n_paths)}
#'     \item{year}{Integer (1..horizon_years)}
#'     \item{asset}{Character ticker}
#'     \item{return_nominal}{Nominal annual return}
#'     \item{return_real}{Real return: (1+nominal)/(1+cpi) - 1}
#'     \item{cum_nominal}{Cumulative nominal growth factor from t=0}
#'     \item{cum_real}{Cumulative real growth factor from t=0}
#'   }
#' @export
hd_simulate_paths <- function(
  n_paths,
  horizon_years,
  assets,
  Sigma           = NULL,
  mu              = NULL,
  method          = c("parametric", "bootstrap"),
  cpi_annual_rate = 0.03,
  block_size      = 12L,
  .returns_wide   = NULL,
  .cpi_monthly    = NULL,   # NEW: vector of monthly CPI changes for bootstrap
  seed            = 42L
) {
  method <- match.arg(method)

  # --- input validation ---
  if (!is.numeric(n_paths) || length(n_paths) != 1L || n_paths < 1L || n_paths != as.integer(n_paths)) {
    cli::cli_abort(c(
      "x" = "{.arg n_paths} must be a positive integer.",
      "i" = "Got {.val {n_paths}} (class {.cls {class(n_paths)}})."
    ))
  }
  if (!is.numeric(horizon_years) || length(horizon_years) != 1L || horizon_years < 1L ||
      horizon_years != as.integer(horizon_years)) {
    cli::cli_abort(c(
      "x" = "{.arg horizon_years} must be a positive integer.",
      "i" = "Got {.val {horizon_years}} (class {.cls {class(horizon_years)}})."
    ))
  }
  if (!is.character(assets) || length(assets) == 0L) {
    cli::cli_abort(c(
      "x" = "{.arg assets} must be a non-empty character vector.",
      "i" = "Got {.cls {class(assets)}} of length {length(assets)}."
    ))
  }
  if (!is.numeric(cpi_annual_rate) || length(cpi_annual_rate) != 1L) {
    cli::cli_abort(c(
      "x" = "{.arg cpi_annual_rate} must be a scalar numeric.",
      "i" = "Got {.cls {class(cpi_annual_rate)}} of length {length(cpi_annual_rate)}."
    ))
  }

  if (!is.null(.cpi_monthly) && (!is.numeric(.cpi_monthly) || length(.cpi_monthly) == 0L)) {
    cli::cli_abort(c(
      "x" = "{.arg .cpi_monthly} must be a numeric vector of monthly CPI changes, or NULL.",
      "i" = "Got {.cls {class(.cpi_monthly)}} of length {length(.cpi_monthly)}."
    ))
  }

  # .returns_wide is required when mu or Sigma is NULL, or for bootstrap
  needs_returns <- is.null(mu) || is.null(Sigma) || method == "bootstrap"
  if (needs_returns && is.null(.returns_wide)) {
    cli::cli_abort(c(
      "x" = "{.arg .returns_wide} must be supplied when {.arg mu} or {.arg Sigma} is NULL, or when {.arg method} is {.val bootstrap}.",
      "i" = "Provide a data frame with columns {.field date} plus one column per asset."
    ))
  }

  # validate assets present in .returns_wide
  if (!is.null(.returns_wide)) {
    missing_assets <- setdiff(assets, colnames(.returns_wide))
    if (length(missing_assets) > 0L) {
      cli::cli_abort(c(
        "x" = "{length(missing_assets)} asset{?s} not found in {.arg .returns_wide}: {.val {missing_assets}}.",
        "i" = "Available columns: {.val {colnames(.returns_wide)}}."
      ))
    }
  }

  # validate Sigma if supplied
  if (!is.null(Sigma)) {
    if (!is.matrix(Sigma) || nrow(Sigma) != ncol(Sigma) || nrow(Sigma) != length(assets)) {
      cli::cli_abort(c(
        "x" = "{.arg Sigma} must be a square matrix with dimension {length(assets)} x {length(assets)}.",
        "i" = "Got matrix of dimension {nrow(Sigma)} x {ncol(Sigma)}."
      ))
    }
    eigs <- eigen(Sigma, only.values = TRUE)$values
    if (any(eigs < -1e-8)) {
      cli::cli_abort(c(
        "x" = "{.arg Sigma} must be positive semi-definite (all eigenvalues >= 0).",
        "i" = "Minimum eigenvalue: {round(min(eigs), 6)}."
      ))
    }
  }

  n_paths       <- as.integer(n_paths)
  horizon_years <- as.integer(horizon_years)
  block_size    <- as.integer(block_size)
  n_assets      <- length(assets)
  n_draws       <- n_paths * horizon_years

  # --- estimate mu / Sigma from .returns_wide if needed ---
  if (needs_returns) {
    ret_mat <- as.matrix(.returns_wide[, assets, drop = FALSE])
    if (is.null(mu)) {
      mu <- colMeans(ret_mat, na.rm = TRUE) * 12L
      names(mu) <- assets
    }
    if (is.null(Sigma)) {
      Sigma_m <- stats::cov(ret_mat, use = "complete.obs")
      Sigma   <- 12L * ((Sigma_m + t(Sigma_m)) / 2)
    }
  }

  # ensure mu has names matching assets
  if (is.null(names(mu))) names(mu) <- assets

  set.seed(seed)

  # --- CPI annual rates (length n_draws, one per path-year pair) ---
  if (!is.null(.cpi_monthly) && length(.cpi_monthly) >= block_size) {
    n_cpi_monthly    <- n_draws * 12L
    n_cpi_blocks     <- ceiling(n_cpi_monthly / block_size)
    max_start_cpi    <- length(.cpi_monthly) - block_size + 1L
    cpi_starts       <- sample(seq_len(max_start_cpi), size = n_cpi_blocks, replace = TRUE)
    cpi_idx          <- unlist(lapply(cpi_starts, function(s) seq.int(s, s + block_size - 1L)))
    cpi_idx          <- cpi_idx[seq_len(n_cpi_monthly)]
    cpi_monthly_samp <- .cpi_monthly[cpi_idx]
    # Compound each 12-month block to one annual CPI rate
    m12_cpi          <- matrix(cpi_monthly_samp, nrow = 12L, ncol = n_draws)
    cpi_annual_draws <- apply(m12_cpi, 2L, function(x) prod(1 + x) - 1)
  } else {
    cpi_annual_draws <- rep(cpi_annual_rate, n_draws)
  }

  # --- draw annual returns: (n_draws x n_assets) matrix ---
  if (method == "parametric") {
    draws <- MASS::mvrnorm(n = n_draws, mu = mu, Sigma = Sigma)
    if (n_assets == 1L) draws <- matrix(draws, ncol = 1L)
    colnames(draws) <- assets

  } else {
    # block-bootstrap: sample monthly rows in blocks, then compound to annual
    ret_mat <- as.matrix(.returns_wide[, assets, drop = FALSE])
    complete_rows <- which(stats::complete.cases(ret_mat))
    n_complete <- length(complete_rows)

    # total monthly samples needed: n_draws * 12 months
    n_monthly <- n_draws * 12L

    # sample block starts
    n_blocks_needed <- ceiling(n_monthly / block_size)
    max_start       <- n_complete - block_size + 1L
    if (max_start < 1L) {
      cli::cli_abort(c(
        "x" = "Not enough complete rows in {.arg .returns_wide} for block-bootstrap.",
        "i" = "Need at least {.val {block_size}} complete rows; got {.val {n_complete}}."
      ))
    }
    starts <- sample(seq_len(max_start), size = n_blocks_needed, replace = TRUE)

    # expand blocks into row indices
    row_idx <- unlist(lapply(starts, function(s) complete_rows[s:(s + block_size - 1L)]))
    row_idx <- row_idx[seq_len(n_monthly)]

    monthly_draws <- ret_mat[row_idx, , drop = FALSE]  # n_monthly x n_assets

    # compound 12 months → 1 annual return, for each draw-year and asset
    draws <- matrix(NA_real_, nrow = n_draws, ncol = n_assets)
    for (j in seq_len(n_assets)) {
      m <- matrix(monthly_draws[, j], nrow = 12L, ncol = n_draws)  # 12 x n_draws
      draws[, j] <- apply(m, 2L, function(x) prod(1 + x) - 1)
    }
    colnames(draws) <- assets
  }

  # --- reshape to long tibble ---
  long <- tibble::tibble(
    path_id       = rep(seq_len(n_paths), each = horizon_years),
    year          = rep(seq_len(horizon_years), times = n_paths),
    .row          = seq_len(n_draws)
  )

  # pivot each asset
  asset_list <- lapply(assets, function(a) {
    tibble::tibble(
      path_id        = long$path_id,
      year           = long$year,
      asset          = a,
      return_nominal = draws[long$.row, a]
    )
  })
  long2 <- do.call(rbind, asset_list)
  long2 <- long2[order(long2$path_id, long2$asset, long2$year), ]

  # --- real returns and cumulative factors ---
  # Broadcast per-(path_id, year) CPI draw to each asset row
  long_cpi <- data.frame(
    path_id    = rep(seq_len(n_paths), each = horizon_years),
    year       = rep(seq_len(horizon_years), times = n_paths),
    cpi_draw   = cpi_annual_draws,
    stringsAsFactors = FALSE
  )
  long2 <- dplyr::left_join(long2, long_cpi, by = c("path_id", "year"))
  long2$return_real <- (1 + long2$return_nominal) / (1 + long2$cpi_draw) - 1
  long2$cpi_draw    <- NULL

  long2 <- dplyr::group_by(long2, .data$path_id, .data$asset)
  long2 <- dplyr::mutate(long2,
    cum_nominal = cumprod(1 + .data$return_nominal),
    cum_real    = cumprod(1 + .data$return_real)
  )
  long2 <- dplyr::ungroup(long2)

  tibble::as_tibble(long2[, c("path_id", "year", "asset",
                               "return_nominal", "return_real",
                               "cum_nominal", "cum_real")])
}
