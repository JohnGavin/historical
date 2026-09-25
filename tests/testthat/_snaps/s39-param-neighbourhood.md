# check_param_neighbourhood aborts on an un-acknowledged peak

    Code
      check_param_neighbourhood(windows, sharpes, centre = 20, strategy_label = "TEST-PEAK")
    Condition
      Error in `check_param_neighbourhood()`:
      x TEST-PEAK: dense parameter-neighbourhood check found a PEAK, not a plateau (reason: floor).
      i Sharpe at centre=20 is 2; min_retention_ratio=0.05 (floor 0.5); cv=2.036 (max 0.3) across 8 neighbour(s).
      i Per Bollinger's stated practice (#849, backtest-robustness.md): a parameter whose dense neighbourhood does not behave broadly similarly should be DISCARDED, not hand-tuned toward the best point.
      i To override with an explicit, documented human decision, add "TEST-PEAK" to HD_S39_ACKNOWLEDGED_PEAKS (R/plan_qa_gates.R) with a written reason -- see that constant's roxygen.

