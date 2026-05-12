# non-list series triggers cli_abort

    Code
      align_period(series = "not_a_list")
    Condition
      Error in `align_period()`:
      x `series` must be a non-empty named list.
      i Received: <character> of length 1.

# bad to_period triggers cli_abort

    Code
      align_period(series = s, to_period = "fortnight")
    Condition
      Error in `align_period()`:
      x `to_period` must be one of "day", "week", "month", "quarter", and "year".
      i Got "fortnight".

# bad anchor triggers cli_abort

    Code
      align_period(series = s, anchor = "mid")
    Condition
      Error in `align_period()`:
      x `anchor` must be one of "end_bizday", "end", and "start".
      i Got "mid".

# missing value_col in series element triggers cli_abort

    Code
      align_period(series = list(x = bad), value_col = "strategy_ret")
    Condition
      Error in `map2()`:
      i In index: 1.
      i With name: x.
      Caused by error in `.f()`:
      x series[["x"]] is missing column(s): "strategy_ret".
      i Each tibble must have columns "date" and "strategy_ret".

