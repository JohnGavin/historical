# a portfolio without net_ret/rf_ret aborts instead of aliasing

    Code
      .olmar_research_log_write(.mk_metrics(), .mk_params(), .mk_prices(), bad,
      base_dir = d)
    Condition
      Error:
      x olmar_research_log: `olmar_portfolio` lacks columns net_ret and rf_ret.
      i Both are needed to derive the HAC Sharpe on the excess series.

# a missing Full Period row aborts

    Code
      .olmar_research_log_write(bad, .mk_params(), .mk_prices(), .mk_port(),
      base_dir = d)
    Condition
      Error:
      x olmar_research_log: expected exactly one "Full Period" row in `olmar_metrics`, found 0.
      i Periods present: "Training" and "Testing"

# an unreadable log aborts instead of looking empty

    Code
      .olmar_research_log_write(.mk_metrics(), .mk_params(), .mk_prices(), .mk_port(),
      base_dir = d)
    Condition
      Error:
      x olmar_research_log: cannot read research-log table "hypotheses".
      i Underlying error: <arrow message>

