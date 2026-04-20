
# Backtesting Focus
+ Focus on:
	+ Control risk
	+ Manage exposure
	+ Optimise sizing
	+ Implementation details
	+ 👉 Robustness > precision
		+ backtesting overfits in-sample training data
			+ => Strategies fail out-of-sample
			+ so partition data:
				+ in-sample training (first 40%), 
				+ OOS testing (next 40%) by rollforward, 
				+ OOS valdiation (last 20%) not used until very end
	+ “Reproducibility is not persistence”
		+ Academic papers Often reproducible in-sample (training)
		+ It is out of sample that matters (testing)
	+ Simplicity
+ Judge backtest forecast via P&L
	+ e.g. adjusting strategy weights to optimise portfolio P&L
	+ do not rely on standard deviation/volatility cos returns nor normal.
		+ so you cannot rely on sharpe

# Vignette format
+ use the most recent existing strategy vignette (.qmd) file in this project as a template.
+ Consider extending to include perspectiveR. 
	+ Plan how to do this.
		+ i.e. what does perspectiveR offer that we are missing for financial or timeseries datasets.
			+ e.g. visualisation, scalability, robustness such as smaller webpages?
	+ https://github.com/EydlinIlya/perspectiveR
	+ htmlwidgets binding for FINOS Perspective
	+ WebAssembly data engine
	+ e.g. financial dashboards
	+ focus on pivot tables with live 
		+ grouping, splitting, filtering 
		+ all running client-side
	+ pairs well with Shiny
		+ data updates stream in without re-rendering the chart
	+ to leverage the duckdb and market view examples
		+ https://perspective-dev.github.io/examples.html
		+ https://perspective-dev.github.io/block.html?example=duckdb
		+ https://perspective-dev.github.io/block.html?example=market
		+ https://eydlinilya.github.io/perspectiveR/articles/introduction.html

# Risk
+ focus on managing exposure based on **risk regimes**
	+ allocation risk is about position sizing
	+ adjust portfolio weights agressively when risk regime changes
		+ e.g. best and worst trading days cluster
			+ worst - best days are net negative on average
				+ so better to be out of market during high risk regimes
					+ but only if there is an automated reentry point
+ use risk resampling as a measurement tool
	+ i.e. bootstrapping or n-fold cross-validation

# Robustness
+ **know how to know when things (risk, portfolios, models) are not working and have precomputed what to do about it**
+ Trading is about allocating risk correctly
	+ not about predicting well
	+ allocation risk is about position sizing
	+ we need:
		+ Controlled losses
		+ Scalable wins
	+ not perfect predictions
+ Robustness over optimisation
	+ long quiet P&L periods with short violently volatile drawdown periods
	+ MUST survive the short volatile drawdown periods
		+ e.g. reduce exposure via reweighting
			+ so perhaps give up the best up days
			+ but pre-automated and pre-calibrated method to reenter market
+ Prefer:
	+ Broad stable regions (“plateaus”)
	+ Models that survive variation
+ Avoid:
	+ “perfect parameter”
	+ sharp backtest peaks
+ signals that are hard to explain and Don’t fit neat theory
	+ 👉 May persist longer cos less crowded, less overexploited
+ **alpha decay**
	+ trade on t+1, t+2, ..., T+10 to measure 
	+ look-forward errors
		+ use Point in Time data to avoid revisions to data
			+ e.g. macro announcements
+ define your trade exit conditons before entering trade
	+ e.g. conditions might be adaptive but definition is fixed and know in advance

# Thesis
+ Risk classification more reliable than return prediction
	+ Prediction requires precision; 
	+ classification requires usefulness
+ Focus on classifying risk regimes
	+ risk conditions are more
		+ stable
			+ Risk is clustered, persistent
		+ detectable
			+ e.g. Low risk → increase exposure
			+ e.g. High risk → reduce or exit
	+ Prediction is the wrong goal in trading
		+ Markets are too noisy for reliable prediction
	+ correlations require bivariate normality.
		+ better to do this for normal-risk regime
			+ the 80% of the data in the middle
		+ high-risk days are the 10% in each tail
			+ seperate regime 
			+ possibly different risk (fat-tails) in each tail

+ Decide how much risk to take, not what will happen
	+ e.g. how to adjust weights across a basket of assets
	+ e.g. bet size relative to capital
+ 👉 Shift from “What will returns be?” 
	+ → to “Is this a high-risk or low-risk environment?”

# Position/bet sizing/weights
+ Position sizing is more important than entry signals
	+ 👉 It’s the bridge between theory and real P&L
+ size positions so that 
	+ wins outweigh losses over time 
	+ without blowing up.
+ Position sizing ≈ portfolio allocation decisions
+ Position sizing implies risk control first
	+ edge can disappear if sizing is wrong
	+ Position sizing determines:
		+ Survival
			+ How much to lose if wrong
				+ e.g. Risk a FIXED percentage per trade (e.g. 1–2%)
			+ Position sizing must assume worst-case sequences
		+ Large drawdowns require huge recoveries
			+ e.g. −50% → need +100% to recover
		+ Long-term compounding depends on sizing
			+ Position sizing determines:
				+ Volatility of equity curve
				+ Final wealth
+ Adaptive sizing based on:
	+ Volatility
		+ Higher volatility → smaller positions
		+ Keeps risk consistent across trades
	+ confidence
	+ market regime
	+ More powerful, but easier to get wrong
+ Risk a FIXED percentage per trade (e.g. 1–2%)
	+ Simple, robust
	+ e.g. fractional Kelly based on risk 
		+ e.g. willing to live with X% drawdown (DD)
			+ => max expected DD is X% so size position accordingly
			+ i.e. ~ standardise risk for every trade type to even out highs and lows
		+ keep constant the expected DD of the portfolio
			+ 100% in equity => cant vary position sizing.
				+ can only move weights around within equity basket
+ position sizing is what actually determines success
	+ not signal in sample (training) performance

# Statistics v academic theory
+ Strong statistics matter more than explanations
	+ High t-stat + False Positive Rate → more likely real
	+ Narrative justification → irrelevant
		+ tends to be post-hoc/After the fact (explanatory)
			+ Ex-ante Before the fact (predictive)
		+ Academics add narrative; Computers don’t
+ Don’t rely on: Academic papers alone
	+ Real edge ≠ published factors
	+ If something is: 
		+ Widely known
		+ Easy to implement
	+ Models assume:
		+ Perfect markets
		+ No frictions
		+ Rational behaviour
		+ Reality:
			+ Markets are messy, noisy, and behavioural

# Edge / alpha
+ alpha is not as predictable as risk
	+ if alpha is exploitable then it decays / disappears
		+ i.e. hard to detect/predict a weak signal
	+ risk does to disappear so cant be exploited
		+ it can be transferred 
		+ e.g. an option to hedge risk transform it into counterparty risk
+ build edge through relentless testing and experience.
+ True edge / alpha tends to come from:
	+ 👉 Edge comes from:
		+ Risk management, not prediction
		+ Assume: we do _not_ have superior forecasting ability
	+ Execution
		+ e.g. is our backtesting data identical to the data used for execution? 
	+ constraints others face create opportunity
		+ Institutional limitations 
			+ (e.g. mandates, liquidity, risk limits)
		+ Structural inefficiencies/barriers
			+ tax, access, behavioural biases
	+ 👉 The “plumbing” matters as much as the idea
+ Success depends on:
	+ Data quality
	+ Execution
	+ Risk management
	+ Not just: Backtests or signals
+ Expect alpha decay

# Backtesting
+ Process > theory
+ **“Test until you throw up”**
	+ i.e. Test across:
		+ parameters
		+ markets
		+ regimes
		+ find regimes where the model fails/breaks

# Assumptions
+ Include these simplifying assumptions in all backtests, 
	+ unless specifically noted otherwise. 
+ All strategies 
	+ trade at the market close (4 pm ET). 
	+ design strategies to capture broad market trends
	+ strategies have to be robust to reasonable delays in execution. e.g. delay trades by 1 to 5 days to measure impact on performance.
+ Transaction fees plus slippage = 0.50% per trade 
	+ i.e. (1.00% round-trip).
	+ Short borrow cost = 3% per annum
	+ Estimated portfolio turnover = 80% per month
	+ Winsorise monthly returns at ±20% 
+ Both dividends and gains are reinvested.
+ Return on cash (uninvested funds) = 3-month US Treasury rate.
+ Exclude taxes

+ apply expense ratio = most liquid similar ETF
	+ e.g. S&P 500 ETF 
		+ use SPY expense ratio == most liquid ETF
+ Monthly vs Daily Asset Data
	+ trade last day of the month
+ daily, weekly, monthly backtests
	+ do _all_ three frequencies
	+ monthly back further in time
	+ real estate ETF VNQ started 2004
		+ underlying index that VNQ tracks
			+ MSCI US REIT Index (Bloomberg: RMS/RMZ)
				+ daily data from 1995
		+ But FTSE NAREIT Index 
			+ (Bloomberg: FNER/FNERTR)
			+ very close proxy
			+ monthly data from 1972


