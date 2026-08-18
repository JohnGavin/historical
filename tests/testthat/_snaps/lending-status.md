# an override outside LENDING_STATUS_ALLOWED aborts

    Code
      derive_lending_status("Bogus", override = "not_a_real_status")
    Condition
      Error in `FUN()`:
      x "Bogus": override lending_status "not_a_real_status" is not in the allowed set.
      i Allowed values: zero_assumed_immaterial, embedded_in_source, inherited, not_tradeable.

