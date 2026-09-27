# check_leaderboard_strategy_traceability: aborts, naming the decoy match, on the #813 wiring

    Code
      check_leaderboard_strategy_traceability(tbl)
    Condition
      Error in `check_leaderboard_strategy_traceability()`:
      x qa_leaderboard_strategy_traceability (S42): 2 leaderboard metrics failed to trace to the strategy's own return series.
      i  Avoid Worst / sharpe -- published=2.4800, recomputed=-1.8000, decoy=2.4800 (MATCHES THE DECOY -- #813 regression)
      i  Avoid Worst / cagr -- published=0.3850, recomputed=-0.1720, decoy=0.3850 (MATCHES THE DECOY -- #813 regression)
      i Refs #813 -- a leaderboard strategy row must be computed from that strategy's own tradeable return series, never from another target's illustrative/hindsight scenario.

# check_leaderboard_strategy_traceability: aborts on a table missing required columns

    Code
      check_leaderboard_strategy_traceability(tibble::tibble(strategy = "x"))
    Condition
      Error in `check_leaderboard_strategy_traceability()`:
      x check_leaderboard_strategy_traceability() (S42) received a table missing 5 required columns: metric, published, recomputed, decoy, and verdict.
      i Expected the output of build_leaderboard_traceability_table().

# build_leaderboard_traceability_table: aborts when the leaderboard has no matching Avoid Worst / Full Period row

    Code
      build_leaderboard_traceability_table(leaderboard, fx$aw_practical_backtest, fx$
        aw_daily_rf, fx$aw_metrics)
    Condition
      Error in `build_leaderboard_traceability_table()`:
      x build_leaderboard_traceability_table() (S42): expected exactly one Avoid Worst / Full Period leaderboard row, found 0.
      i Check R/plan_leaderboard.R's .norm_aw() / aw_strategy_metrics wiring (Refs #813).

# build_leaderboard_traceability_table: aborts when aw_metrics has no matching decoy row

    Code
      build_leaderboard_traceability_table(leaderboard, fx$aw_practical_backtest, fx$
        aw_daily_rf, bad_aw_metrics)
    Condition
      Error in `build_leaderboard_traceability_table()`:
      x build_leaderboard_traceability_table() (S42): expected exactly one aw_metrics 'Remove 10 Worst' / Full Period row, found 0.
      i Check R/plan_avoid_worst.R's aw_metrics target (Refs #813).

