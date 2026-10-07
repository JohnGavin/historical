# a blend label aborts rather than guessing a cash weight

    Code
      fals_excess_input(inp, .rf_tbl(inp$date), "CMR Conditioned")
    Condition
      Error in `fals_excess_input()`:
      x fals_excess_input(): "CMR Conditioned" has basis "blend"; only "total" and "excess" are supported here.
      i A blend needs a per-observation cash weight; route it through hd_excess_returns() with `cash_weight`.

# a malformed rf table aborts naming the missing columns

    Code
      fals_excess_input(inp, tibble::tibble(date = inp$date), "TOM")
    Condition
      Error in `fals_excess_input()`:
      x fals_excess_input(): `rf_tbl` is missing 1 required column: rf.
      i Expected tibble(date, rf) for "TOM".

