# empty strategy triggers cli_abort

    Code
      hd_admission_preregister(strategy = "", hypothesis = "x", reviewer = "tester",
        base_dir = base_dir)
    Condition
      Error in `hd_admission_preregister()`:
      x `strategy` must be a non-empty character string.
      i Got "".

# empty hypothesis triggers cli_abort

    Code
      hd_admission_preregister(strategy = "s", hypothesis = "", reviewer = "tester",
        base_dir = base_dir)
    Condition
      Error in `hd_admission_preregister()`:
      x `hypothesis` must be a non-empty character string.
      i Got "".

# missing reviewer triggers cli_abort

    Code
      hd_admission_preregister(strategy = "s", hypothesis = "x", reviewer = "",
        base_dir = base_dir)
    Condition
      Error in `hd_admission_preregister()`:
      x `reviewer` must be a non-empty character string.
      i Got "".

# hd_admission_preregister() signature is stable (catches API drift)

    Code
      args(hd_admission_preregister)
    Output
      function (strategy, hypothesis, expected = list(), reviewer, 
          counterparty = NA_character_, kill_criterion = NA_character_, 
          expected_sharpe = NA_real_, ann_factor = 12, n_tests = 1, 
          correction = c("none", "bonferroni"), target_power = 0.8, 
          gate_result = NULL, revises = FALSE, base_dir = NULL, seal = TRUE) 
      NULL

# hd_admission_read() signature is stable (catches API drift)

    Code
      args(hd_admission_read)
    Output
      function (strategy = NULL, base_dir = NULL) 
      NULL

