# apply_adv_cap: function signature is stable (catches API drift)

    Code
      args(apply_adv_cap)
    Output
      function (w, adv_by_ticker, adv_pct_cap = 0.1) 
      NULL

# apply_adv_cap: uninvested-cash cli_warn wording is stable (#r2122)

    Code
      result <- apply_adv_cap(w, adv, adv_pct_cap = 0.3)
    Condition
      Warning:
      ! apply_adv_cap: 10% of portfolio left as uninvested cash.
      i ADV caps are too tight to fully invest. Increase `adv_pct_cap` or accept the cash drag.

# market_impact_cost rejects negative order_usd

    Code
      market_impact_cost(order_usd = -1, adv_usd = 1e+08, sigma = 0.02)
    Condition
      Error in `market_impact_cost()`:
      x `order_usd` must be numeric, non-NA, and >= 0.
      i Got -1.

# market_impact_cost rejects non-positive adv_usd

    Code
      market_impact_cost(order_usd = 1e+06, adv_usd = 0, sigma = 0.02)
    Condition
      Error in `market_impact_cost()`:
      x `adv_usd` must be numeric, non-NA, and > 0.
      i Got 0.

# market_impact_cost rejects negative sigma

    Code
      market_impact_cost(order_usd = 1e+06, adv_usd = 1e+08, sigma = -0.01)
    Condition
      Error in `market_impact_cost()`:
      x `sigma` must be numeric, non-NA, and >= 0.
      i Got -0.01.

# market_impact_cost rejects non-positive eta

    Code
      market_impact_cost(order_usd = 1e+06, adv_usd = 1e+08, sigma = 0.02, eta = 0)
    Condition
      Error in `market_impact_cost()`:
      x `eta` must be a single positive number.
      i Got 0.

# market_impact_cost function signature is stable

    Code
      args(market_impact_cost)
    Output
      function (order_usd, adv_usd, sigma, eta = 1) 
      NULL

# portfolio_longshort_hrp: impact_eta requires adv_monthly

    Code
      portfolio_longshort_hrp(fx$df, fx$returns_wide, lookback_months = 1L,
      impact_eta = 1, impact_aum = 1e+07, impact_sigma = 0.02)
    Condition
      Error in `validate_impact_args()`:
      ! impact_eta requires adv_monthly to be supplied.

# portfolio_longshort_hrp: impact_eta requires impact_aum

    Code
      portfolio_longshort_hrp(fx$df, fx$returns_wide, lookback_months = 1L,
      adv_monthly = fx$adv_monthly, impact_eta = 1, impact_sigma = 0.02)
    Condition
      Error in `validate_impact_args()`:
      x impact_aum must be a single positive number.
      i Got .

# portfolio_longshort_hrp: impact_eta requires impact_sigma

    Code
      portfolio_longshort_hrp(fx$df, fx$returns_wide, lookback_months = 1L,
      adv_monthly = fx$adv_monthly, impact_eta = 1, impact_aum = 1e+07)
    Condition
      Error in `validate_impact_args()`:
      x impact_sigma must be a single non-negative number.
      i Got .

# portfolio_longshort_hrp: invalid impact_eta value errors

    Code
      portfolio_longshort_hrp(fx$df, fx$returns_wide, lookback_months = 1L,
      adv_monthly = fx$adv_monthly, impact_eta = -1, impact_aum = 1e+07,
      impact_sigma = 0.02)
    Condition
      Error in `validate_impact_args()`:
      x impact_eta must be a single positive number, or NULL to disable.
      i Got -1.

# portfolio_longshort_hrp: function signature is stable (impact params present)

    Code
      args(portfolio_longshort_hrp)
    Output
      function (df, returns_wide, long_decile = 1L, short_decile = 10L, 
          lookback_months = 36L, cost_per_trade = 0.005, borrow_rate_annual = 0.03, 
          max_monthly_ret = 0.2, adv_monthly = NULL, adv_pct_cap = 0.1, 
          impact_eta = NULL, impact_aum = NULL, impact_sigma = NULL) 
      NULL

# market_impact_sensitivity rejects an empty eta_grid

    Code
      market_impact_sensitivity(fx$df, fx$returns_wide, eta_grid = numeric(0),
      lookback_months = 1L, adv_monthly = fx$adv_monthly, impact_aum = 1e+07,
      impact_sigma = 0.02)
    Condition
      Error in `validate_eta_grid()`:
      x eta_grid must be a non-empty numeric vector of positive values.
      i Got .

# market_impact_sensitivity requires adv_monthly

    Code
      market_impact_sensitivity(fx$df, fx$returns_wide, eta_grid = 1,
      lookback_months = 1L, adv_monthly = NULL, impact_aum = 1e+07, impact_sigma = 0.02)
    Condition
      Error in `validate_eta_grid()`:
      ! adv_monthly is required to sweep market-impact cost.

# market_impact_sensitivity function signature is stable

    Code
      args(market_impact_sensitivity)
    Output
      function (df, returns_wide, eta_grid, long_decile = 1L, short_decile = 10L, 
          lookback_months = 36L, cost_per_trade = 0.005, borrow_rate_annual = 0.03, 
          max_monthly_ret = 0.2, adv_monthly, adv_pct_cap = 0.1, impact_aum, 
          impact_sigma, rf = NULL, rf_col = "rf_ret") 
      NULL

