# correction script appends one critiques row and is idempotent

    Code
      cat(sub("(uuid|parent_uuid): [0-9a-f-]+", "\\1: <uuid>", c(first,
        "--- second run ---", second)), sep = "\n")
    Output
      seed_olmar_results_correction: written=1 skipped=0
        uuid: <uuid> 
        parent_uuid: <uuid> 
        affected_rows: 5 ( 3 x naive geometric, 2 x arithmetic no-rf )
      --- second run ---
      seed_olmar_results_correction: written=0 skipped=1
        skipped (a metric-basis critique already hangs off an OLMAR results row)

# finding states the corrected basis, labels quoted figures, links issues

    Code
      cat(gsub("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@",
        "<uuid>@", f))
    Output
      CORRECTION of the stored OLMAR sharpe_hac values; the 5 results rows are append-only and are left unchanged. Neither stored value is a HAC Sharpe. (1) 3 rows hold 0.78 in sharpe_hac. That is the naive geometric rf-adjusted Sharpe (CAGR minus mean rf, over volatility), not a HAC Sharpe ([#975](https://github.com/JohnGavin/historical/issues/975)). The HAC Sharpe on the same series is 0.9271 (HAC t 3.723 times sqrt(252/4063)); quoted from a one-off analysis of 2026-10-18, not recomputed by this script. (2) 2 rows hold 0.883 in sharpe_hac. That is the arithmetic total-return Sharpe with no risk-free rate deducted, over 4093 rows. OLMAR-1 is a total-return series, so on the #937 basis rf is deducted; the comparable figures are 0.8117 (arithmetic, excess) and 0.78 (geometric, excess), both quoted from the same analysis. Those rows are on the wrong basis ([#974](https://github.com/JohnGavin/historical/issues/974)). The writer fix is in [PR #979](https://github.com/JohnGavin/historical/pull/979): new results rows carry the HAC value. Read the stored column as: 0.78 = naive geometric rf-adjusted; 0.883 = arithmetic, no rf. Tracked under [#962](https://github.com/JohnGavin/historical/issues/962). This row is not a verdict on the strategy. affected_rows (uuid@timestamp), naive_geometric_0.78 [3]: <uuid>@2026-08-18T20:31:17Z, <uuid>@2026-09-21T13:20:05Z, <uuid>@2026-09-28T15:39:55Z; arithmetic_no_rf_0.883 [2]: <uuid>@2026-05-23T22:58:43Z, <uuid>@2026-08-06T23:00:12Z.

