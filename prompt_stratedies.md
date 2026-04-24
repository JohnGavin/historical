
# Objective
+ produce a vignette backtesting one specific strategy
	+ using the previous strategy as a template 
	+ e.g. https://johngavin.github.io/historical/macro-defense-rotation.html


# Potential strategies to be backtested
+ each url below explains a potential strategy to be backtested.
+ one or more historical project datasets must cater for the asset classes mentioned in the urls below. 
+ map which datasets are candidates for which strategies
	+ can we cross check a strategy between two or more sources?
	+ does history, frequency, other metadata from source first need enhancements or to be extended in order to be able to backtest a specific strategy


====

# Strategies to be considered now

## spy 2.11 sharpe
+ https://www.quantitativo.com/p/statistical-arbitrage
	+ Nov 10 2024
		+ spread between assets
		+ balance long and short positions
		+ reduce overall market movements
+ /Users/johngavin/docs_gh/blogs/quantitiativo.com/inst/qmd/quantitativo.com_spy_2.11_sharpe.qmd
  + **https://github.com/JohnGavin/quantitiativo.com/actions**
    + https://github.com/JohnGavin/llm
    + https://github.com/JohnGavin/r.package.example/actions/runs/10037744340
      + https://github.com/user-workshop-cicd/r.pkg.template/actions/runs/9466913950



## Beat the Stock Market by Avoiding Its Worst Days
+ https://www.morningstar.com/funds/you-can-beat-stock-market-by-avoiding-its-worst-days-you-wont
+ make more by avoiding market’s biggest losses 
	+ than you gave up by being out of the market on the days it notched its biggest gains
+ Replicate for S&P500
	+ extend to other indices in our datasets by asset category
	+ Ditto for Distance Between 10 Worst and 10 Best Days 
+ rolling v cumulative returns
+ Rolling Returns vs. _Net_ Reward of Avoiding 10 Worst Days

## Daily Return Information Factor (DRIF) (implemented — factor-level)
+ https://johngavin.github.io/historical/drif.html
+ A Unified Framework for Anomalies based on Daily Returns
	+ https://alphaarchitect.com/daily-stock-returns/
+ Idea: Daily returns contain underused predictive information
	+ dont isolate single signals (e.g. reversal, MAX)
+ use elastic net regression 
	+ extract information from past month of daily returns.
	+ i.e. Combine all daily returns from the past month
+ Two Data/Information Dimensions
	+ Chronological 
		+ order returns happen during a month.
	+ Rank
		+ magnitude of returns (from best to worst day)
+ Alpha = predictive power
	+ Daily Return Information Factor (DRIF) 
		+ 1.6% monthly return (~19% annualized) 
		+ ~1.6% monthly alpha
		+ high Sharpe ratio of 1.23.
	+ Works on both: Long and Short sides
	+ High turnover (~93% monthly)
	+ returns cover realistic trading costs
+ Inputs:
	+ Chronological info → when returns occurred
	+ Rank info → how extreme returns were
	+ Short-term price paths matter
		+ Not just returns — but sequence of returns
		+ “Recency” is critical
	+ Other inputs
		+ High turnover (~monthly full rebalance)
		+ Shorting (for full effect)
		+ Low trading costs
+ Timing > magnitude
	+ chronological is more predictive than rank
	+ market reacts more to recent price pressure and liquidity than 
		+ behavioral shocks from extreme single-day moves
	+ ~1.5% monthly spread
		+ Rank (extremes) adds less ~0.9%
+ Daily Return Information (DRI) factor
	+ Ranked just after market factor
	+ Above value, momentum, size
	+ core underlying factor
		+ May unify many existing short-term signals
+ DRIF explains away short-term anomalies like 
	+ short-term reversal, 
	+ volatility effects, and 
	+ lottery-style stock patterns.
	+ MAX effect
+ Robustness: 
	+ Works with: 1-day lag
	+ persisted for 90 years (1937–2024)
	+ Still works: 2000–2024 (~1% monthly) 
	+ works in large-cap stocks (not just illiquid small caps), and 
	+ profitable after accounting for _institutional_ trading costs.
		+ Breakeven cost: ~36–42 bps
	+ survived 2,000+ variations of tests
+ Recency Matters
	+ most recent _daily_ price movements carry most weight for
		+ predicting next _month’s_ performance.
+ Market Dynamics
	+ short-term prices driven by 
		+ temporary price pressure and liquidity needs 
		+ rather than just random noise
	+ microstructure explanation
		+ Liquidity effects
		+ Temporary price pressure
		+ Order flow dynamics
+ strategy performs best during periods of 
	+ high volatility (high VIX) regimes 
	+ high interest rates environments
	+ when market liquidity is most strained.
	+ Stronger in:
		+ Small caps
		+ Illiquid stocks

## The Many Facets of Stock Momentum: Distinguishing Factor and Stock Components
+ https://alphaarchitect.com/stock-specific-momentum/
+ there is a durable, stock-specific momentum component
	+ tied to how prices react to firm news around earnings dates
+ real stock-specific momentum, not just factor timing
	+ lower-risk way to capture momentum without leaning so heavily on broad factor moves
	+ 12-month momentum that comes only from returns in short windows around each firm’s earnings announcements over the prior year
	+ significant after controlling for changing factor exposures.


## Factor-max
+ https://alphaarchitect.com/factor-max/
+ predict factor returns by focusing on extreme within-month performance rather than cumulative returns
+ investors systematically underreact to factor-level news embedded in these extreme returns
	+ creating exploitable return predictability.
+ factors offer meaningful performance enhancement opportunities
	+ especially with factor MAX signals
	+ particularly during low-attention environments 
		+ and for systematic factors
+ factor MAX strategy works best when applied to
	+ well-established, liquid factors 
	+ rather than niche anomalies

## macro-defense-rotation (already done)
+ https://notfinancial.substack.com/p/defense-first-when-not-losing-is
	+ ETFs for index and defensive ETF tickers.
	+ Defense First is not a single hedge. It rotates among four:
		+ TLT — long-duration Treasuries (deflation / Fed easing)
		+ GLD — gold (monetary instability, falling real rates)
		+ DBC — broad commodities (stagflation, supply shocks)
		+ UUP — U.S. dollar index (global stress, funding crises)
		+ Each covers a different macro risk regime. 
		+ Idea: one or more does something useful at any given time
+ macro-defense-rotation strategy alread implemented
	+ https://johngavin.github.io/historical/macro-defense-rotation.html
	+ use as a template for other incomplete strategies





# References to future potential strategies
+ these are excluded for now.
+ https://www.quantitativo.com/p/learning-to-rank?open=false#%C2%A7the-strategy-our-implementation
+ https://substack.com/@quantitativo/p-188964115
+ https://substack.com/@quantitativo/p-193265385
+ https://www.quantitativo.com/p/informational-edge

+ Samir Varma
	+ https://medium.com/@samirvarma
	+ https://algoadvantage.substack.com/p/051-samir-varma-prediction-fails
	+ https://www.algoadvantage.io/podcast/050-samir-varma/
