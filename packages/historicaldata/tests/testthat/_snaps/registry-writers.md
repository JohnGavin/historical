# hd_strategy_upsert aborts when underlying_signals has > 1 leg and leg_count is not supplied

    Code
      hd_strategy_upsert(con, tibble::tibble(strategy_id = "ensemble2", short_name = "ENS2",
        long_name = "Ensemble 2"), underlying_signals = c("sig_a", "sig_b"))
    Condition
      Error in `hd_strategy_upsert()`:
      x `strategy_row` for "ensemble2" is missing leg_count.
      i `underlying_signals` lists 2 legs blended into this strategy.
      i Composite (multi-leg) strategies must declare leg_count explicitly -- it is not safe to silently default to 1.
      i Pass `leg_count` = 2 (or a leg_count column in `strategy_row`).

# hd_strategy_upsert aborts when leg_count does not match length(underlying_signals)

    Code
      hd_strategy_upsert(con, tibble::tibble(strategy_id = "ensemble3", short_name = "ENS3",
        long_name = "Ensemble 3"), underlying_signals = c("sig_a", "sig_b"),
      leg_count = 5L)
    Condition
      Error in `hd_strategy_upsert()`:
      x leg_count (5) does not match `length(underlying_signals)` (2) for "ensemble3".
      i These must agree -- leg_count is meant to record exactly how many legs went into this book.

