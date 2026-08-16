# an override outside BORROW_STATUS_ALLOWED aborts

    Code
      derive_borrow_status("Bogus", "long_only", FALSE, override = "not_a_real_status")
    Condition
      Error in `FUN()`:
      x "Bogus": override borrow_status "not_a_real_status" is not in the allowed set.
      i Allowed values: not_applicable, modelled, unmodelled, embedded_in_source, inherited, not_tradeable.

# NA directionality with no override aborts, naming the strategy

    Code
      derive_borrow_status("OLMAR-1", NA_character_, FALSE)
    Condition
      Error in `FUN()`:
      x "OLMAR-1": cannot derive borrow_status -- directionality is NA and no override is set.
      i Add a row to strategy_names (R/plan_strategy_names.R) or an entry to BORROW_STATUS_OVERRIDES (R/plan_cost_convention.R).

# an unrecognised directionality value aborts, naming the allowed set

    Code
      derive_borrow_status("Weird", "some_other_value", FALSE)
    Condition
      Error in `FUN()`:
      x "Weird": unrecognised directionality "some_other_value".
      i Allowed values: long_only, long_short, market_neutral, overlay.

