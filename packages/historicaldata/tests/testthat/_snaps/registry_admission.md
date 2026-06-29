# override = TRUE without reason triggers cli_abort

    Code
      hd_admission_register(con = con, strategy = "override_strat", hypothesis = "Testing override guard",
        expected = list(), reviewer = "tester", override = TRUE)
    Condition
      Error in `hd_admission_register()`:
      x `override_reason` must be supplied when `override` is TRUE.
      i Provide a non-empty reason string.

# strategy_admission schema is stable

    Code
      schema
    Output
                    column_name data_type
      1          admission_uuid   VARCHAR
      2                strategy   VARCHAR
      3             admitted_at TIMESTAMP
      4              git_commit   VARCHAR
      5                reviewer   VARCHAR
      6              hypothesis   VARCHAR
      7    expected_incr_sharpe    DOUBLE
      8  expected_var_reduction    DOUBLE
      9  expected_target_regime   VARCHAR
      10      expected_max_corr    DOUBLE
      11           gate_overall   VARCHAR
      12       gate_detail_json   VARCHAR
      13               override   BOOLEAN
      14        override_reason   VARCHAR

# hd_admission_register() signature is stable

    Code
      args(hd_admission_register)
    Output
      function (con, strategy, hypothesis, expected = list(), reviewer, 
          gate_result = NULL, override = FALSE, override_reason = NA_character_) 
      NULL

# hd_admission_read() signature is stable

    Code
      args(hd_admission_read)
    Output
      function (con = NULL, path = hd_registry_path()) 
      NULL

