### **Backtesting & Methodology**
* *Prioritize* **robustness** over **precision**
    * *Partition* **data** into three segments
        * *Allocate* 40% **in-sample** **training**
        * *Rollforward* 40% **out-of-sample** (**OOS**) **testing**
        * *Reserve* 20% **OOS** **validation** for final **evaluation**
    * *Judge* **forecast** via **P&L** rather than **Sharpe**
    * *Verify* **reproducibility** does not equal **persistence**
* *Simulate* **execution** with **friction**
    * *Apply* 0.50% **slippage** and **fees** per **trade**
    * *Account* for 3% **annual** **borrow** **costs**
    * *Reinvest* **dividends** and **gains**
    * *Benchmark* **cash** against **3-month** **Treasury** **rate**
* *Test* **decay** via **lag** **analysis**
    * *Delay* **trades** 1 to 5 **days**
    * *Measure* **impact** on **performance**
* *Utilize* **Vignette** **templates**
    * *Extend* **files** with **perspectiveR**
        * *Leverage* **WebAssembly** **engine** for **scalability**
        * *Stream* **live** **updates** via **Shiny**
        * *Implement* **pivot** **tables** for **financial** **dashboards**

---

### **Risk & Regime Classification**
* *Classify* **risk** **regimes** instead of *predicting* **returns**
    * *Detect* **regime** **stability**
        * *Identify* **risk** **clustering**
        * *Recognize* **persistence**
    * *Execute* **market** **exit** during **high-risk** **periods**
        * *Establish* **automated** **reentry** **points**
* *Adjust* **exposure** based on **tail** **events**
    * *Differentiate* **normal** **risk** (80% **middle** **data**)
    * *Isolate* **high-risk** **regimes** (10% **outer** **tails**)
* *Perform* **risk** **resampling**
    * *Bootstrap* **datasets**
    * *Execute* **n-fold** **cross-validation**

> **Quirky Fact:** Markets spend 80% of the time in "boring" normality and 20% in "terrifying" tails. Successful trading is surviving the 20.

---

### **Position Sizing & Robustness**
* *Scale* **wins** and *control* **losses**
    * *Focus* on **allocation** over **entry** **signals**
    * *Size* **positions** for **survival**
* *Implement* **fixed** **percentage** **risk**
    * *Limit* **risk** to 1–2% per **trade**
    * *Standardize* **drawdown** (**DD**) across **portfolio**
* *Adopt* **adaptive** **sizing**
    * *Reduce* **size** during **volatility**
    * *Maintain* **consistent** **risk** **exposure**
* *Seek* **stable** **plateaus**
    * *Avoid* **sharp** **backtest** **peaks**
    * *Ignore* **perfect** **parameters**
    * *Value* **unexplained** **signals** for lower **crowding**

---

### **Edge & Alpha Reality**
* *Accept* **alpha** **decay**
    * *Measure* **performance** at **t+1** through **T+10**
    * *Utilize* **Point-in-Time** **data** to *avoid* **look-forward** **bias**
* *Source* **edge** from **structural** **inefficiencies**
    * *Exploit* **institutional** **limitations**
    * *Target* **liquidity** **mandates** or **tax** **barriers**
* *Disregard* **narrative** **justification**
    * *Prioritize* **high** **t-stats** over **post-hoc** **theories**
    * *Assume* **forecasting** **inferiority**

> **Mnemonic: PIPE (Plumbing, Institutional, Persistence, Execution)**
> *Alpha is in the "plumbing" of the market infrastructure.*

---

### **Data & Assets**
* *Execute* **multi-frequency** **backtests**
    * *Run* **daily**, **weekly**, and **monthly** **frequencies**
* *Use* **proxy** **indices** for **historical** **depth**
    * *Substitute* **VNQ** with **MSCI** **US** **REIT** **Index** (1995)
    * *Substitute* with **FTSE** **NAREIT** **Index** for **monthly** **data** (1972)
* *Apply* **liquidity** **filters**
    * *Match* **expense** **ratios** of **liquid** **ETFs** (e.g., **SPY**)
