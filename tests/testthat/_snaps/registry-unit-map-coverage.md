# .extract_units_map aborts informatively when the variable is not found

    Code
      .extract_units_map(file, "nonexistent_units")
    Condition
      Error in `.extract_units_map()`:
      x Could not find `nonexistent_units <- c(...)` in 'plan_ltr_momentum.R'.
      i The unit map may have been renamed or restructured.

