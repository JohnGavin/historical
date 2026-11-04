# a selected ticker missing from the metadata aborts and names it

    Code
      ticker_universe_provenance(meta_fixture(), c("AAA", "ZZZ"), top_n = 2L)
    Condition
      Error in `ticker_universe_provenance()`:
      x 1 selected ticker not found in the metadata snapshot: "ZZZ".
      i The selection and the snapshot must come from the same read.

