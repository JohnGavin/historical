# check_leaderboard_cost_metrics_joint_presence throws and names the offending strategy when only one column is populated

    Code
      check_leaderboard_cost_metrics_joint_presence(offender_leaderboard)
    Condition
      Error in `check_leaderboard_cost_metrics_joint_presence()`:
      x Leaderboard has 1 row(s) where net_cagr/cvar_95/credible disagree on presence -- these three columns come from the SAME cost_rows join and must be jointly NA or jointly non-NA:
      i  New Strategy / Full Period -- net_cagr present, cvar_95 NA, credible NA
      i check_leaderboard_cost_metrics_joint_presence() (S23) guards the fail-loud-not-null.md defect class (#637/#640/#641/#643): if one of these three columns is populated for a strategy/period without the other two, docs/leaderboard.qmd's single 'not computed' verdict for Credible/Net CAGR/CVaR 95% no longer matches the underlying data. Check calc_cost_metrics() and the cost_rows join in R/plan_leaderboard.R's leaderboard target.

# check_leaderboard_cost_metrics_joint_presence throws when leaderboard is missing required columns

    Code
      check_leaderboard_cost_metrics_joint_presence(bad)
    Condition
      Error in `check_leaderboard_cost_metrics_joint_presence()`:
      x Leaderboard is missing 1 required column(s): cvar_95.
      i check_leaderboard_cost_metrics_joint_presence() (S23) requires strategy, period, net_cagr, cvar_95, credible.

