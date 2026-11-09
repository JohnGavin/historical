# the bullets render in cli_abort for the normal and fallback cases

    Code
      cli::cli_abort(historicaldata:::.hd_params_diff_bullets("x.parquet", "a=1;b=2",
        "a=1;b=3"))
    Condition
      Error:
      x 'x.parquet' was fetched with different parameters.
      i In the manifest only: "b=2"
      i In this run only: "b=3"
      i Re-fetch with `ALPACA_FORCE_REFETCH=1`.

---

    Code
      cli::cli_abort(historicaldata:::.hd_params_diff_bullets("x.parquet", "a=1;b=2",
        "b=2;a=1;"))
    Condition
      Error:
      x 'x.parquet' was fetched with different parameters.
      i Both params strings hold the same key=value pieces; only their order, repetition or an empty segment differ.
      i In the manifest: "a=1;b=2"
      i In this run: "b=2;a=1;"
      i Re-fetch with `ALPACA_FORCE_REFETCH=1`.

