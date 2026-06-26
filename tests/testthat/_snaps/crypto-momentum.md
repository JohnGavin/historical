# C2: backtest_crypto_momentum aborts informatively on empty signals

    Code
      backtest_crypto_momentum(empty_signals, empty_returns)
    Condition
      Warning:
      There was 1 warning in `dplyr::filter()`.
      i In argument: `date == max(date)`.
      Caused by warning in `max.default()`:
      ! no non-missing arguments to max; returning -Inf
      Error in `backtest_crypto_momentum()`:
      x backtest_crypto_momentum(): no signals / rebalance dates.
      i nrow(signals) = 0, length(rebalance_dates) = 0.
      i An empty universe upstream (e.g. Date-vs-POSIXct filter mismatch) is the most common cause.

