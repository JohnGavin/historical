# compute_drawdowns_extracted: function signature is stable (catches API drift)

    Code
      args(compute_drawdowns_extracted)
    Output
      function (ret) 
      NULL

# compute_drawdowns_extracted: return-value schema is stable (non-empty path)

    Code
      names(dd)
    Output
      [1] "max_dd"              "avg_dd"              "max_dd_duration_obs"
      [4] "avg_dd_duration_obs" "n_drawdowns"         "recovery_obs"       
      [7] "peak_value"         

