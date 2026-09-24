# .build_wide_corr_matrix aborts (does not silently return NA) when fewer than 2 columns qualify

    Code
      .build_wide_corr_matrix(ret_tbl, "only_col", min_obs = 12L)
    Condition
      Error in `.build_wide_corr_matrix()`:
      x Need at least 2 strategies with >= 12 observations to compute the leaderboard-wide correlation matrix.
      i Got 1 qualifying strategy/strategies: only_col.

# .warn_ltr_join_gap warns and names the dropped months when ltr_portfolio has a gap inside the family's window

    Code
      .warn_ltr_join_gap(base_ym = c("2020-01", "2020-02", "2020-03"), ltr_ym = c(
        "2020-01", "2020-03"))
    Condition
      Warning:
      ! strat_returns_aligned: 1 month in the 4-strategy family (port_returns) with no matching ltr_portfolio return -- dropped by inner_join.
      i Dropped ym: 2020-02.
      i This silently shrinks the window behind strat_corr_matrix / strat_keff_vertox / the published k_eff_family column on leaderboard.qmd.

