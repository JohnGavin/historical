# check_lending_status_registry throws on NA lending_status

    Code
      check_lending_status_registry(bad)
    Condition
      Error in `check_lending_status_registry()`:
      x strategy_cost_convention has 1 strategy/strategies with NA lending_status (#665):
      i  CMR
      i Every strategy must resolve to a status in LENDING_STATUS_ALLOWED (R/plan_cost_convention.R) -- never NA.

# check_lending_status_registry throws on an out-of-vocabulary status

    Code
      check_lending_status_registry(bad)
    Condition
      Error in `check_lending_status_registry()`:
      x strategy_cost_convention has lending_status value(s) outside the allowed vocabulary: bogus_status
      i Allowed values: zero_assumed_immaterial, embedded_in_source, inherited, not_tradeable.

# check_lending_status_registry throws when required columns are missing

    Code
      check_lending_status_registry(bad)
    Condition
      Error in `check_lending_status_registry()`:
      x strategy_cost_convention is missing 1 required column(s): lending_status.
      i check_lending_status_registry() (S18) requires strategy, lending_status.

