# .prob_sharpe_input_sharpe aborts on mismatched input lengths

    Code
      .prob_sharpe_input_sharpe("Full Period", c(0.1, 0.2), 0.1, TRUE)
    Condition
      Error in `.prob_sharpe_input_sharpe()`:
      x .prob_sharpe_input_sharpe(): all inputs must have the same length.
      i Got period 1, sharpe 2, arith_sharpe 1, dsr_covered 1.

---

    Code
      args(.prob_sharpe_input_sharpe)
    Output
      function (period, sharpe, arith_sharpe, dsr_covered) 
      NULL

