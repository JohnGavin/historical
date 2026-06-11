# .cmr_register_runs schema and row counts are stable

    Code
      cat("result columns:", paste(names(result), collapse = ", "), "\n")
    Output
      result columns: partition, run_uuid 
    Code
      cat("result nrow:   ", nrow(result), "\n")
    Output
      result nrow:    3 
    Code
      cat("partitions:    ", paste(sort(result$partition), collapse = ", "), "\n")
    Output
      partitions:     1m, 3m, 6m 

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
      n_metric_rows:    45 

# .tom_register_runs schema and row counts are stable

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
      strategy_id:    tom 

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
      n_metric_rows:    20 

# .pso_optimal_register_runs schema and row counts are stable

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
      strategy_id:    pso_optimal 

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
      n_metric_rows:    13 

