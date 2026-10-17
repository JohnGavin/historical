# seed script is idempotent: second run writes nothing

    Code
      cat(sub("written: .*|skipped \\(already in ledger\\): .*", "<names>", c(first,
        "--- second run ---", second)), sep = "\n")
    Output
      seed_past_strategy_results: written=11 skipped=0
        <names>
      --- second run ---
      seed_past_strategy_results: written=0 skipped=11
        <names>

