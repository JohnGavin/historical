# non-numeric x aborts

    Code
      hd_stationarity_diagnostics(c("a", "b", "c"))
    Condition
      Error in `hd_stationarity_diagnostics()`:
      x `x` must be a numeric vector.
      i Got class <character>.

# a series with fewer than 20 finite observations aborts

    Code
      hd_stationarity_diagnostics(stats::rnorm(10))
    Condition
      Error in `hd_stationarity_diagnostics()`:
      x `x` has only 10 finite observations after dropping non-finite values.
      i hd_stationarity_diagnostics() requires at least 20 to fit the ADF regression and compute ACF lags.
      i Raw input length was 10.

# acf_lags >= n_obs aborts

    Code
      hd_stationarity_diagnostics(stats::rnorm(20), acf_lags = 20L)
    Condition
      Error in `hd_stationarity_diagnostics()`:
      x `acf_lags` (20) must be less than the number of finite observations (20).
      i Reduce `acf_lags` or supply a longer `x`.

# a non-positive acf_lags aborts

    Code
      hd_stationarity_diagnostics(stats::rnorm(30), acf_lags = 0L)
    Condition
      Error in `hd_stationarity_diagnostics()`:
      x `acf_lags` must be a single positive integer.
      i Got 0.

# a negative adf_lag_order aborts

    Code
      hd_stationarity_diagnostics(stats::rnorm(30), adf_lag_order = -1L)
    Condition
      Error in `hd_stationarity_diagnostics()`:
      x `adf_lag_order` must be NULL or a single non-negative integer.
      i Got -1.

# an adf_lag_order too large for the sample aborts

    Code
      hd_stationarity_diagnostics(stats::rnorm(20), adf_lag_order = 15L)
    Condition
      Error in `hd_stationarity_diagnostics()`:
      x ADF augmenting lag order 15 leaves too few usable observations to fit the regression.
      i 20 finite observations yield only 4 usable rows for 17 parameters.
      i Supply a smaller `adf_lag_order` or a longer `x`.

# function signature is stable (catches API drift)

    Code
      args(hd_stationarity_diagnostics)
    Output
      function (x, acf_lags = 10L, adf_lag_order = NULL) 
      NULL

