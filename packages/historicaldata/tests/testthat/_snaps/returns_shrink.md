# james_stein without sigma aborts with informative error

    Code
      hd_returns_shrink(mu, method = "james_stein", n_obs = 100L)
    Condition
      Error in `hd_returns_shrink()`:
      ! `sigma` is required for `method = "james_stein"`.
      i Provide a 5 × 5 positive-definite covariance matrix.

# james_stein without n_obs aborts with informative error

    Code
      hd_returns_shrink(mu, method = "james_stein", sigma = sigma)
    Condition
      Error in `hd_returns_shrink()`:
      ! `n_obs` is required for `method = "james_stein"`.
      i Provide the number of observations (T) used to estimate `mu`.

# equilibrium without w_mkt aborts with informative error

    Code
      hd_returns_shrink(mu, method = "equilibrium", sigma = sigma, risk_aversion = 2)
    Condition
      Error in `hd_returns_shrink()`:
      ! `w_mkt` is required for `method = "equilibrium"`.
      i Provide market-cap weights that sum to 1.

# sigma with wrong dimensions aborts with informative error

    Code
      hd_returns_shrink(mu, method = "james_stein", sigma = sigma_3x3, n_obs = 100L)
    Condition
      Error in `hd_returns_shrink()`:
      ! `sigma` must be a 5 × 5 matrix (matching `mu` length 5).
      x Got a 3 × 3 matrix.

# risk_aversion <= 0 aborts with informative error

    Code
      hd_returns_shrink(mu, method = "equilibrium", sigma = sigma, w_mkt = w_mkt,
        risk_aversion = -1, intensity = 0.5)
    Condition
      Error in `hd_returns_shrink()`:
      ! `risk_aversion` must be a positive scalar; got -1.

# function signature is stable (catches API drift)

    Code
      args(hd_returns_shrink)
    Output
      function (mu, method = c("james_stein", "grand_mean", "equilibrium"), 
          sigma = NULL, n_obs = NULL, w_mkt = NULL, risk_aversion = NULL, 
          intensity = NULL) 
      NULL

