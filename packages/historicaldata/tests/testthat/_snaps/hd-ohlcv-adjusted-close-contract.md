# .hd_assert_price_schema() fires when adjusted_close is missing for a dataset that promises it (#669)

    Code
      historicaldata:::.hd_assert_price_schema(c("date", "open", "close", "volume"),
      "equity_daily")
    Condition
      Error:
      x "equity_daily" promises an "adjusted_close" column but it is missing after the read-time alias.
      i Columns present: "date", "open", "close", and "volume".
      i The underlying parquet's adjusted-price column has apparently been renamed to something the `hd_ohlcv()`/`hd_lazy()` alias does not recognise.
      > Update the "adjusted" -> "adjusted_close" alias in `hd_ohlcv_single()` / `hd_lazy()` to match the new upstream column name.

