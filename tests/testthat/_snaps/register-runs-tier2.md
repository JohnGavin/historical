# .stk_register_runs (stk_max) schema and row counts are stable

    Code
      cat("result columns:", paste(names(result), collapse = ", "), "\n")
    Output
      result columns: strategy_id, run_uuid 
    Code
      cat("result nrow:   ", nrow(result), "\n")
    Output
      result nrow:    1 
    Code
      cat("strategy_id:   ", result$strategy_id, "\n")
    Output
      strategy_id:    stk_max 

---

    Code
      cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    Output
      bt.strategy cols: strategy_id, short_name, asset_class, frequency, lifecycle 
    Code
      cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    Output
      bt.run cols:      strategy_id, partition, pipeline_version 
    Code
      cat("n_metric_rows:   ", q$n_metric_rows, "\n")
    Output
      n_metric_rows:    11 
    Code
      cat("n_diagnostic_rows:", nrow(q$diagnostics), "\n")
    Output
      n_diagnostic_rows: 1 

# .stk_register_runs (stk_drif) schema and row counts are stable

    Code
      cat("result columns:", paste(names(result), collapse = ", "), "\n")
    Output
      result columns: strategy_id, run_uuid 
    Code
      cat("result nrow:   ", nrow(result), "\n")
    Output
      result nrow:    1 
    Code
      cat("strategy_id:   ", result$strategy_id, "\n")
    Output
      strategy_id:    stk_drif 

---

    Code
      cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    Output
      bt.strategy cols: strategy_id, short_name, asset_class, frequency, lifecycle 
    Code
      cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    Output
      bt.run cols:      strategy_id, partition, pipeline_version 
    Code
      cat("n_metric_rows:   ", q$n_metric_rows, "\n")
    Output
      n_metric_rows:    11 
    Code
      cat("n_diagnostic_rows:", nrow(q$diagnostics), "\n")
    Output
      n_diagnostic_rows: 1 

# .xgb_drif_register_runs schema and row counts are stable

    Code
      cat("result columns:", paste(names(result), collapse = ", "), "\n")
    Output
      result columns: strategy_id, run_uuid 
    Code
      cat("result nrow:   ", nrow(result), "\n")
    Output
      result nrow:    1 
    Code
      cat("strategy_id:   ", result$strategy_id, "\n")
    Output
      strategy_id:    xgb_drif 

---

    Code
      cat("bt.strategy cols:", paste(names(q$strat), collapse = ", "), "\n")
    Output
      bt.strategy cols: strategy_id, short_name, asset_class, frequency, lifecycle 
    Code
      cat("bt.run cols:     ", paste(names(q$runs), collapse = ", "), "\n")
    Output
      bt.run cols:      strategy_id, partition, pipeline_version 
    Code
      cat("n_metric_rows:   ", q$n_metric_rows, "\n")
    Output
      n_metric_rows:    11 
    Code
      cat("n_diagnostic_rows:", nrow(q$diagnostics), "\n")
    Output
      n_diagnostic_rows: 1 

