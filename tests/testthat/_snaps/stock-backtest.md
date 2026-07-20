# apply_adv_cap: function signature is stable (catches API drift)

    Code
      args(apply_adv_cap)
    Output
      function (w, adv_by_ticker, adv_pct_cap = 0.1) 
      NULL

# apply_adv_cap: uninvested-cash cli_warn wording is stable (#r2122)

    Code
      result <- apply_adv_cap(w, adv, adv_pct_cap = 0.3)
    Condition
      Warning:
      ! apply_adv_cap: 10% of portfolio left as uninvested cash.
      i ADV caps are too tight to fully invest. Increase `adv_pct_cap` or accept the cash drag.

