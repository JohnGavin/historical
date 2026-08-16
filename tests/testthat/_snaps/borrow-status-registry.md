# check_borrow_status_registry throws on NA borrow_status

    Code
      check_borrow_status_registry(bad)
    Condition
      Error in `check_borrow_status_registry()`:
      x strategy_cost_convention has 1 strategy/strategies with NA borrow_status (#664):
      i  CMR
      i Every strategy must resolve to a status in BORROW_STATUS_ALLOWED (R/plan_cost_convention.R) -- never NA.

# check_borrow_status_registry throws on an out-of-vocabulary status

    Code
      check_borrow_status_registry(bad)
    Condition
      Error in `check_borrow_status_registry()`:
      x strategy_cost_convention has borrow_status value(s) outside the allowed vocabulary: bogus_status
      i Allowed values: not_applicable, modelled, unmodelled, embedded_in_source, inherited, not_tradeable.

# check_borrow_status_registry throws when a modelled row has no rate

    Code
      check_borrow_status_registry(bad)
    Condition
      Error in `check_borrow_status_registry()`:
      x strategy_cost_convention has 1 row(s) where borrow_status contradicts borrow_rate_annual (#664):
      i  Stock MAX -- borrow_status = modelled, borrow_rate_annual = NA
      i A "modelled" row must have a non-NA borrow_rate_annual; every other status must have NA -- fix the registry row or the derivation in R/plan_cost_convention.R.

# check_borrow_status_registry throws when a non-modelled row HAS a rate

    Code
      check_borrow_status_registry(bad)
    Condition
      Error in `check_borrow_status_registry()`:
      x strategy_cost_convention has 1 row(s) where borrow_status contradicts borrow_rate_annual (#664):
      i  CMR -- borrow_status = unmodelled, borrow_rate_annual = 0.05
      i A "modelled" row must have a non-NA borrow_rate_annual; every other status must have NA -- fix the registry row or the derivation in R/plan_cost_convention.R.

# check_borrow_status_registry throws when required columns are missing

    Code
      check_borrow_status_registry(bad)
    Condition
      Error in `check_borrow_status_registry()`:
      x strategy_cost_convention is missing 1 required column(s): borrow_rate_annual.
      i check_borrow_status_registry() (S16) requires strategy, borrow_status, borrow_rate_annual.

