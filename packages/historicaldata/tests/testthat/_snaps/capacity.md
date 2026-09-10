# hd_market_impact rejects negative order_usd

    Code
      hd_market_impact(order_usd = -1, adv_usd = 1e+08, sigma = 0.02)
    Condition
      Error in `hd_market_impact()`:
      x `order_usd` must be a non-empty numeric vector with no NA and no negative values.
      i Got -1.

# hd_market_impact rejects non-positive adv_usd

    Code
      hd_market_impact(order_usd = 1e+06, adv_usd = 0, sigma = 0.02)
    Condition
      Error in `hd_market_impact()`:
      x `adv_usd` must be a non-empty numeric vector with no NA and strictly positive values.
      i Got 0.

# hd_market_impact rejects negative sigma

    Code
      hd_market_impact(order_usd = 1e+06, adv_usd = 1e+08, sigma = -0.01)
    Condition
      Error in `hd_market_impact()`:
      x `sigma` must be a non-empty numeric vector with no NA and no negative values.
      i Got -0.01.

# hd_market_impact rejects non-positive eta

    Code
      hd_market_impact(order_usd = 1e+06, adv_usd = 1e+08, sigma = 0.02, eta = 0)
    Condition
      Error in `hd_market_impact()`:
      x `eta` must be a single positive number.
      i Got 0.

# hd_market_impact method = 'istar' errors informatively and does not silently fall back

    Code
      hd_market_impact(order_usd = 1e+06, adv_usd = 1e+08, sigma = 0.02, method = "istar")
    Condition
      Error in `hd_market_impact()`:
      x `method` = "istar" is not implemented.
      i The Concretum Group I-Star model's public preview discloses only three calibration constants (a1=708, a2=0.55, a3=0.71), not the formula combining them with sigma/ADV -- that formula is behind the paywall. Guessing it would misattribute a fabricated model to a named third party (external-code-zero-trust.md). Use method = "sqrt" (the square-root law, publicly documented) instead, or supply a from-scratch derivation.

# hd_market_impact rejects an unrecognised method rather than silently defaulting

    Code
      hd_market_impact(order_usd = 1e+06, adv_usd = 1e+08, sigma = 0.02, method = "linear")
    Condition
      Error in `hd_market_impact()`:
      x `method` must be "sqrt".
      i Got "linear".

# hd_capacity_curve rejects a non-increasing aum_grid

    Code
      hd_capacity_curve(monthly_ret = stats::rnorm(24), aum_grid = c(1e+06, 1e+06,
        1e+07), adv_usd = 5e+07, turnover_frac = 1)
    Condition
      Error in `hd_capacity_curve()`:
      x `aum_grid` must be a non-empty, strictly increasing numeric vector with no NA and no negative values.
      i Got 1e+06, 1e+06, and 1e+07.

# hd_capacity_curve rejects turnover_frac outside (0, 1]

    Code
      hd_capacity_curve(monthly_ret = stats::rnorm(24), aum_grid = c(1e+06, 1e+07),
      adv_usd = 5e+07, turnover_frac = 1.5)
    Condition
      Error in `hd_capacity_curve()`:
      x `turnover_frac` must be a single number in (0, 1].
      i Got 1.5.

# hd_capacity_curve rejects too-short monthly_ret

    Code
      hd_capacity_curve(monthly_ret = 0.01, aum_grid = c(1e+06, 1e+07), adv_usd = 5e+07,
      turnover_frac = 1)
    Condition
      Error in `hd_capacity_curve()`:
      x `monthly_ret` must be a numeric vector with at least 2 observations.
      i Got length 1.

# hd_capacity_curve rejects non-positive adv_usd

    Code
      hd_capacity_curve(monthly_ret = stats::rnorm(24), aum_grid = c(1e+06, 1e+07),
      adv_usd = -1, turnover_frac = 1)
    Condition
      Error in `hd_capacity_curve()`:
      x `adv_usd` must be a single positive number.
      i Got -1.

# hd_market_impact() function signature is stable (catches API drift)

    Code
      args(hd_market_impact)
    Output
      function (order_usd, adv_usd, sigma, eta = 1, method = "sqrt") 
      NULL

# hd_capacity_curve() function signature is stable (catches API drift)

    Code
      args(hd_capacity_curve)
    Output
      function (monthly_ret, aum_grid, adv_usd, turnover_frac, eta = 1, 
          ann_factor = 12) 
      NULL

