# .prob_sharpe_input_n aborts on mismatched input lengths

    Code
      .prob_sharpe_input_n("Full Period", c(10, 20), 10, TRUE)
    Condition
      Error in `.prob_sharpe_input_n()`:
      x .prob_sharpe_input_n(): all inputs must have the same length.
      i Got period 1, months 2, dsr_T_obs 1, dsr_covered 1.

---

    Code
      args(.prob_sharpe_input_n)
    Output
      function (period, months, dsr_T_obs, dsr_covered) 
      NULL

