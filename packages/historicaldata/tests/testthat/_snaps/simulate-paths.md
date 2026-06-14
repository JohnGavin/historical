# bootstrap without .returns_wide aborts with informative message

    Code
      hd_simulate_paths(n_paths = 3L, horizon_years = 2L, assets = c("A", "B"),
      method = "bootstrap")
    Condition
      Error in `hd_simulate_paths()`:
      x `.returns_wide` must be supplied when `mu` or `Sigma` is NULL, or when `method` is "bootstrap".
      i Provide a data frame with columns date plus one column per asset.

# asset absent from .returns_wide aborts with informative message

    Code
      hd_simulate_paths(n_paths = 3L, horizon_years = 2L, assets = c("A", "X_MISSING"),
      method = "parametric", mu = c(A = 0.07, X_MISSING = 0.05), Sigma = make_sigma(),
      .returns_wide = rw)
    Condition
      Error in `hd_simulate_paths()`:
      x 1 asset not found in `.returns_wide`: "X_MISSING".
      i Available columns: "date", "A", and "B".

# non-positive n_paths aborts with informative message

    Code
      hd_simulate_paths(n_paths = 0L, horizon_years = 2L, assets = c("A", "B"), mu = make_mu(),
      Sigma = make_sigma())
    Condition
      Error in `hd_simulate_paths()`:
      x `n_paths` must be a positive integer.
      i Got 0 (class <integer>).

# function signature is stable (catches API drift)

    Code
      args(hd_simulate_paths)
    Output
      function (n_paths, horizon_years, assets, Sigma = NULL, mu = NULL, 
          method = c("parametric", "bootstrap"), cpi_annual_rate = 0.03, 
          block_size = 12L, .returns_wide = NULL, seed = 42L) 
      NULL

