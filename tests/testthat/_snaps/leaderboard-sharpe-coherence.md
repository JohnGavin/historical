# check_leaderboard_sharpe_coherence throws when required columns are missing

    Code
      check_leaderboard_sharpe_coherence(bad)
    Condition
      Error in `check_leaderboard_sharpe_coherence()`:
      x Leaderboard is missing 1 required column(s): ann_rf.
      i check_leaderboard_sharpe_coherence() (S17) requires strategy, period, cagr, vol, sharpe, ann_rf.

# check_leaderboard_sharpe_coherence throws when ann_rf is NA (#677 defect B, one level up)

    Code
      check_leaderboard_sharpe_coherence(bad)
    Condition
      Error in `check_leaderboard_sharpe_coherence()`:
      x Leaderboard has 1 row(s) with NA ann_rf -- Sharpe coherence cannot be verified (#677):
      i  LTR / Full Period
      i Every source metrics target that computes sharpe MUST also publish the ann_rf it used -- see R/utils_metrics.R::sharpe_ratio_rf() and the module-level 'ann_rf (#677 slice 4)' comment in R/plan_leaderboard.R.

# check_leaderboard_sharpe_coherence throws when vol is zero

    Code
      check_leaderboard_sharpe_coherence(bad)
    Condition
      Error in `check_leaderboard_sharpe_coherence()`:
      x Leaderboard has 1 row(s) with a non-positive or NA vol -- Sharpe coherence cannot be verified:
      i  LTR / Full Period
      i (cagr - ann_rf) / vol is undefined when vol is 0 or NA.

# check_leaderboard_sharpe_coherence throws when sharpe does not match (cagr - ann_rf) / vol

    Code
      check_leaderboard_sharpe_coherence(bad)
    Condition
      Error in `check_leaderboard_sharpe_coherence()`:
      x Leaderboard sharpe is incoherent with cagr/vol/ann_rf in 1 place(s) (tol = 0.02), #677:
      i  LTR / Full Period -- sharpe = 1.5, (cagr - ann_rf) / vol = 0.3453, diff = 1.15
      i sharpe must equal (cagr - ann_rf) / vol -- check the offending strategy's source metrics target and its .norm_* helper in R/plan_leaderboard.R for a formula or unit-conversion bug.

# check_leaderboard_sharpe_coherence catches LTR's pre-fix state (a naive HAC Sharpe renamed into sharpe)

    Code
      check_leaderboard_sharpe_coherence(ltr_prefix)
    Condition
      Error in `check_leaderboard_sharpe_coherence()`:
      x Leaderboard sharpe is incoherent with cagr/vol/ann_rf in 1 place(s) (tol = 0.02), #677:
      i  LTR / Full Period -- sharpe = 2.36, (cagr - ann_rf) / vol = 0.3453, diff = 2.01
      i sharpe must equal (cagr - ann_rf) / vol -- check the offending strategy's source metrics target and its .norm_* helper in R/plan_leaderboard.R for a formula or unit-conversion bug.

# check_leaderboard_sharpe_coherence catches the no-rf family's signature (sharpe == cagr / vol exactly, despite a non-zero ann_rf)

    Code
      check_leaderboard_sharpe_coherence(value_no_rf)
    Condition
      Error in `check_leaderboard_sharpe_coherence()`:
      x Leaderboard sharpe is incoherent with cagr/vol/ann_rf in 1 place(s) (tol = 0.02), #677:
      i  Value (HML) / Full Period -- sharpe = 0.488, (cagr - ann_rf) / vol = 0.06833, diff = 0.42
      i sharpe must equal (cagr - ann_rf) / vol -- check the offending strategy's source metrics target and its .norm_* helper in R/plan_leaderboard.R for a formula or unit-conversion bug.

