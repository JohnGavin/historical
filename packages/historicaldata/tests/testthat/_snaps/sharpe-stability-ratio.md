# hd_sharpe_stability_ratio: return is named list with correct field types

    Code
      args(hd_sharpe_stability_ratio)
    Output
      function (r, w, ann_factor = 252, lag_nw = NULL) 
      NULL

# hd_rolling_sharpe: rejects non-numeric r

    Code
      hd_rolling_sharpe("not numeric", w = 10L)
    Condition
      Error in `hd_rolling_sharpe()`:
      x `r` must be a numeric vector.

# hd_rolling_sharpe: rejects non-integer w

    Code
      hd_rolling_sharpe(rnorm(100), w = -1L)
    Condition
      Error in `hd_rolling_sharpe()`:
      x `w` must be a positive integer scalar.

# hd_sharpe_stability_ratio: rejects negative ann_factor

    Code
      hd_sharpe_stability_ratio(rnorm(100), w = 20L, ann_factor = -1)
    Condition
      Error in `hd_sharpe_stability_ratio()`:
      x `ann_factor` must be a positive numeric scalar.

# hd_sharpe_stability_ratio: rejects non-integer lag_nw

    Code
      hd_sharpe_stability_ratio(rnorm(100), w = 20L, lag_nw = 1.5)
    Condition
      Error in `hd_sharpe_stability_ratio()`:
      x `lag_nw` must be NULL or a non-negative integer scalar.

# hd_top5pct_share: pct=0 triggers error

    Code
      hd_top5pct_share(rep(0.01, 10L), pct = 0)
    Condition
      Error in `hd_top5pct_share()`:
      ! `pct` must be in (0, 1); got 0.

# hd_top5pct_share: pct=1 triggers error

    Code
      hd_top5pct_share(rep(0.01, 10L), pct = 1)
    Condition
      Error in `hd_top5pct_share()`:
      ! `pct` must be in (0, 1); got 1.

# hd_top5pct_share: pct=1.5 triggers error

    Code
      hd_top5pct_share(rep(0.01, 10L), pct = 1.5)
    Condition
      Error in `hd_top5pct_share()`:
      ! `pct` must be in (0, 1); got 1.5.

# hd_top5pct_share: pct=-0.1 triggers error

    Code
      hd_top5pct_share(rep(0.01, 10L), pct = -0.1)
    Condition
      Error in `hd_top5pct_share()`:
      ! `pct` must be in (0, 1); got -0.1.

