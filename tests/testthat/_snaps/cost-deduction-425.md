# drif_portfolio deducts cost per #425 (snapshot)

    Code
      print(result, n = Inf)
    Output
      # A tibble: 3 x 5
        ym      gross_port_ret turnover  cost portfolio_ret
        <chr>            <dbl>    <dbl> <dbl>         <dbl>
      1 2024-01          0.025        1 0.002         0.023
      2 2024-02          0.025        0 0             0.025
      3 2024-03          0.03         1 0.002         0.028

# fm_portfolio deducts cost per #425 (snapshot)

    Code
      print(result, n = Inf)
    Output
      # A tibble: 3 x 5
        ym      gross_port_ret turnover  cost portfolio_ret
        <chr>            <dbl>    <dbl> <dbl>         <dbl>
      1 2024-02          0.025        1 0.002         0.023
      2 2024-03          0.025        0 0             0.025
      3 2024-04          0.03         1 0.002         0.028

# rsc_portfolio deducts cost on exposure changes per #425 (snapshot)

    Code
      print(result, n = Inf)
    Output
      # A tibble: 5 x 7
          day exposure spy_ret exposure_change trade_cost gross_ret_strategy
        <int>    <dbl>   <dbl>           <dbl>      <dbl>              <dbl>
      1     1      1     0.01              0       0                   0.01 
      2     2      1     0.005             0       0                   0.005
      3     3      0.5  -0.02              0.5     0.0005             -0.01 
      4     4      0.1  -0.03              0.4     0.0004             -0.003
      5     5      1     0.015             0.9     0.0009              0.015
      # i 1 more variable: ret_strategy <dbl>

