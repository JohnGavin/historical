
# Objective
+ produce a vignette backtesting one specific strategy
	+ using the previous strategy as a template 
	+ e.g. https://johngavin.github.io/historical/macro-defense-rotation.html

# Potential strategies to be backtested
+ one or more project datasets must cater for the asset classes mentioned in the urls below each of which explains a potential strategy to be backtested.
+ map which datasets are candidates for which strategies
	+ can we cross check a strategy between two or more sources?
	+ does history, frequency, other metadata from source first need enhancements or to be extended in order to be able to backtest a specific strategy

# Strategies to be considered now
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
+ Recency Matters:
	+ most recent _daily_ price movements carry most weight for
		+ predicting next _month’s_ performance.
+ Market Dynamics: 
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


# References to future potential strategies
+ these are excluded for now.
+ https://substack.com/@quantitativo/p-188964115
+ https://substack.com/@quantitativo/p-193265385
+ https://www.quantitativo.com/p/informational-edge
