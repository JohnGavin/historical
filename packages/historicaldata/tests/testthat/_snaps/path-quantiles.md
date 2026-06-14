# missing cum_nominal column gives informative error

    Code
      hd_path_quantiles(bad_paths, metric = "cum_nominal")
    Condition
      Error in `hd_path_quantiles()`:
      x `paths` is missing required columns: "cum_nominal".
      i Supply the output of `hd_simulate_paths()`.

# probs outside [0, 1] gives informative error

    Code
      hd_path_quantiles(paths, probs = c(0.1, 1.5))
    Condition
      Error in `hd_path_quantiles()`:
      ! `probs` must be a non-empty numeric vector in [0, 1].

# hd_plot_fan_chart() with missing q50 gives informative error

    Code
      hd_plot_fan_chart(bad_q)
    Condition
      Error in `hd_plot_fan_chart()`:
      x `quantiles` is missing required columns: "q50".
      i Supply the output of `hd_path_quantiles()` with default probs.

# hd_path_quantiles() function signature is stable

    Code
      args(hd_path_quantiles)
    Output
      function (paths, metric = c("cum_nominal", "cum_real"), probs = c(0.1, 
          0.25, 0.5, 0.75, 0.9)) 
      NULL

# hd_plot_fan_chart() function signature is stable

    Code
      args(hd_plot_fan_chart)
    Output
      function (quantiles, title = "Multi-asset return paths", y_label = "Cumulative growth factor", 
          palette = c(outer = "#BDD7EE", inner = "#4472C4", median = "#1F3864")) 
      NULL

