## Backtesting & Methodology
- Prioritize robustness over precision
- Partition data into three segments:
  - 40% in-sample _training_
  - 40% rollforward out-of-sample (OOS) _testing_
  - 20% OOS _validation_ (final evaluation)
- Judge forecasts via P&L (not Sharpe)
- Simulate execution with friction:
  - e.g. 0.50% slippage + fees per trade
  - e.g. 3% annual borrow costs
- Reinvest dividends and gains
- Benchmark cash vs 3-month Treasury rate
- Test decay via lag analysis:
  - Delay trades 1–10 days
  - Measure performance impact
- Use Vignette templates
- Extend files with perspectiveR, if appropriate
- Leverage WebAssembly for scalability
- Stream live updates via Shiny / perspectiveR
- Use pivot tables for dashboards
- Mnemonic: 
  - **PROD** (Partition, Risk, OOS, Decay)
  - Segment distributions:
    - 80% normal regime
    - 10% + 10% tail regimes

## Risk & Regime Classification
- **Classify regimes instead of predicting returns**
- Detect:
  - risk Stability
  - risk Clustering
  - risk Persistence
- Exit/deleverage during high-risk regimes
  - Define and auto execute automated reentry rules
- Adjust exposure for tail events
- Perform resampling:
  - Bootstrap datasets
  - n-fold cross-validation

## Position Sizing & Robustness
- Focus on **weight allocation over signals**
- Risk 1–2% of remaining capital per trade
  - max 3-4% of remaining capital 
- **Standardize drawdowns across portfolio**
- Use **adaptive sizing**:
  - Reduce size in high volatility
  - Maintain consistent risk exposure
- Prefer stable performance plateaus
- Avoid overfit peaks
- Don’t chase “perfect” parameters
- Value **unexplained signals**
  - i.e. less crowded
- Survival
  - 90% Market is "boring"/normalal & 10% terrifying
    - Successful trading is surviving the fog of war.

- Mnemonic: **SASS** (Size, Adapt, Survive, Standardize)

## Edge & Alpha Reality
- Assume alpha decays
- Assume forecasting limitations
- Measure forward performance (t+1 to T+10)
- Use point-in-time data 
  - (avoid look-ahead bias)
- Source edge from structural inefficiencies:
  - Institutional constraints
  - Liquidity mandates
  - Tax frictions
- Ignore narrative explanations
- Prioritize statistical significance (t-stats)
  - False positive rates
+ Verify **reproducibility** does not equal **persistence**

## Data & Assets
- Run multi-frequency backtests:
  - Daily
  - Weekly
  - Monthly
- Use proxy indices for deeper history:
  - VNQ → MSCI US REIT Index (1995)
  - VNQ → FTSE NAREIT Index (monthly, 1972)
