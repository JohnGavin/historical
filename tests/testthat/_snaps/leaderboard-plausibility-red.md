# implied years > 100 is flagged as RED -- reproduces the #717 shape

    Code
      check_leaderboard_plausibility_red(bad, bad_obs)
    Condition
      Error in `check_leaderboard_plausibility_red()`:
      x Leaderboard has 1 physically impossible metric value(s) (#719 Layer 1 Red tier):
      i  CMR / Full Period -- implied_years = 565.8 (expected <= 100)
      i These are RED-tier: not a peer-relative outlier judgement, a value that cannot be true under any correct computation. See #717 for the worked case (566 implied years from a mis-annualised daily series).

