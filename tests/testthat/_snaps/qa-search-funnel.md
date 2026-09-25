# build_search_funnel_table aborts on an empty families registry

    Code
      build_search_funnel_table(list(), families = list())
    Condition
      Error in `build_search_funnel_table()`:
      x QA_SEARCH_FUNNEL_FAMILIES (or the `families` override) is empty.
      i build_search_funnel_table() (S38) needs at least one registered strategy family.

# build_search_funnel_table aborts when trial_tables is missing a registered family

    Code
      build_search_funnel_table(list(), families = fam)
    Condition
      Error in `build_search_funnel_table()`:
      x `trial_tables` is missing 1 registered family: a.

# check_search_funnel aborts on an empty (zero-row) funnel

    Code
      check_search_funnel(empty)
    Condition
      Error in `check_search_funnel()`:
      x check_search_funnel() (S38) received a zero-row funnel table.
      i build_search_funnel_table() already aborts on an empty families registry -- this should be unreachable.

# check_search_funnel aborts when min-trades-pass exceeds tried

    Code
      check_search_funnel(bad)
    Condition
      Error in `check_search_funnel()`:
      x Internally inconsistent search funnel for family: a.
      i Each stage must be <= the stage before it (tried >= min-trades-pass >= deflation-survivors).

# check_search_funnel aborts when deflation-survivors exceeds min-trades-pass

    Code
      check_search_funnel(bad)
    Condition
      Error in `check_search_funnel()`:
      x Internally inconsistent search funnel for family: a.
      i Each stage must be <= the stage before it (tried >= min-trades-pass >= deflation-survivors).

