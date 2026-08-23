# .build_wide_corr_matrix aborts (does not silently return NA) when fewer than 2 columns qualify

    Code
      .build_wide_corr_matrix(ret_tbl, "only_col", min_obs = 12L)
    Condition
      Error in `.build_wide_corr_matrix()`:
      x Need at least 2 strategies with >= 12 observations to compute the leaderboard-wide correlation matrix.
      i Got 1 qualifying strategy/strategies: only_col.

