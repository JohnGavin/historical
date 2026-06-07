# .drif_register_runs schema and row counts are stable

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
      strategy_id:    drif 

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

# .fm_register_runs schema and row counts are stable

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
      strategy_id:    fac_max 

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

# .ltr_register_runs schema and row counts are stable

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
      strategy_id:    ltr 

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
      n_metric_rows:    16 

# .avoid_worst_register_runs schema and row counts are stable

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
      strategy_id:    avoid_worst 

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
      n_metric_rows:    14 

# .rsc_register_runs schema and row counts are stable

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
      strategy_id:    rsc 

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

