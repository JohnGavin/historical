# roll_mean_safe errors with cli_abort on negative n

    Code
      roll_mean_safe(1:10, n = -1)
    Condition
      Error in `.validate_rolling_args()`:
      x `n` must be a single positive integer.
      i Received: -1

# roll_mean_safe errors with cli_abort on min_frac > 1

    Code
      roll_mean_safe(1:10, n = 5, min_frac = 1.5)
    Condition
      Error in `.validate_rolling_args()`:
      x `min_frac` must be a single numeric value in (0, 1].
      i Received: 1.5

# roll_quantile_safe errors with cli_abort on probs > 1

    Code
      roll_quantile_safe(1:10, n = 5, probs = 1.5)
    Condition
      Error in `roll_quantile_safe()`:
      x `probs` must be a single numeric value in [0, 1].
      i Received: 1.5

