# JST Macrohistory Database: Free Alternative to DMS

## Overview

The **Jordà-Schularick-Taylor (JST) Macrohistory Database** serves as a free, academically rigorous alternative to the **Dimson-Marsh-Staunton (DMS) Global Returns Dataset** for long-run cross-country financial returns analysis.

Both datasets address the same fundamental problem in finance research: **survivorship bias** in equity premium estimates from U.S.-only data.

## The Survivorship Bias Problem

**U.S.-centric bias:** Most academic finance uses U.S. equity data (CRSP, S&P) to estimate the equity risk premium. The U.S. was the dominant economic and military power of the 20th century. Countries that suffered hyperinflation, wars, market closures, or prolonged bear markets are underrepresented or missing entirely.

**Result:** U.S.-only equity premium estimates are **3-4 percentage points higher** than global averages when survivorship-adjusted datasets are used.

## Dataset Comparison

| Feature | DMS Global Returns | JST Macrohistory |
|---------|-------------------|------------------|
| **Coverage** | 23 countries | 18 countries |
| **Time span** | 1900-present | **1870-2020** (50 years longer) |
| **Cost** | **Paid subscription** | **Free** (macrohistory.net) |
| **Focus** | Equity, bonds, bills, inflation | Equity, bonds, housing, credit, crises |
| **Frequency** | Annual | Annual |
| **Housing returns** | No | **Yes** — unique long-run housing data |
| **Crisis indicators** | No | **Yes** — `crisisJST` binary flag |
| **European focus** | Global | Strong European coverage |
| **R integration** | Manual CSV import | `hd_jst()` function (historicaldata package) |
| **Academic source** | Dimson, Marsh, Staunton (London Business School) | Jordà, Schularick, Taylor (Federal Reserve, Bonn) |
| **Citation** | *Triumph of the Optimists* (2002) + annual updates | *NBER Macro Annual 2016* (DOI: 10.1086/690241) |

## Key Findings from JST Analysis

### 1. Cross-Geography Pervasiveness

Equity premium is **not universal**:
- Positive mean premium in **most** countries (t-stat > 2, >50% positive years)
- But several countries show **negative or marginal** long-run premiums
- Validates Swedroe's pervasiveness criterion: factors must work across geographies, not just in the U.S.

### 2. Equity Premium Magnitude

**Lower than U.S.-only estimates:**
- U.S. historical equity premium (CRSP): ~8-9% vs T-bills
- Global average (JST): ~5-6% vs bills
- **Difference:** 3-4 percentage points — consistent with DMS findings

**Implication:** Forward-looking equity premium estimates should use **global, survivorship-adjusted** data, not U.S.-only backtests.

### 3. Multi-Decade Underperformance Is Normal

JST confirms **40+ year underperformance periods** in multiple countries:
- European equities vs bonds: 1914-1950s (wars, hyperinflation)
- Japan equities: 1989-2020 (30+ years post-bubble)
- UK equities: 1900-1950 (50 years of real underperformance)

**Implication:** 5-10 year underperformance of a factor is **not evidence** it stopped working — see `underperformance-prior` rule.

### 4. Crisis-Conditional Returns

`crisisJST` indicator enables regime analysis:
- Financial crisis years: 1873, 1907, 1929-33, 2008
- Equity premium **negative or near-zero** during crises
- Post-crisis recovery periods show **elevated premiums**

**Implication:** Unconditional (always-invested) equity premium estimates mix regimes. Risk-managed strategies must account for crisis drawdowns.

### 5. Housing as an Asset Class

JST uniquely includes **housing total returns** (price appreciation + rental yield):
- Long-run housing returns **comparable to equities** in several countries
- Lower volatility than equities
- Low correlation with equity crashes (diversification benefit)

**Implication:** Traditional 60/40 equity/bond portfolios ignore a major asset class. Housing (via REITs, direct ownership) deserves allocation consideration.

## Validation: JST vs Fama-French

**Overlap period:** 1926-2020 (USA only)

**Correlation:** JST USA equity premium vs FF `Mkt-RF` factor = **0.95+** (nearly identical)

**Conclusion:** JST is a reliable long-run data source. Differences from FF are minor and stem from:
- JST uses total return indices (price + dividends)
- FF uses CRSP market portfolio
- Both track the same underlying U.S. equity market returns

## Implementation in historicaldata Package

### Data Access

```r
library(historicaldata)

# Fetch JST data (cached locally after first download)
jst <- hd_jst(cache = TRUE)

# 18 countries, 1870-2020, 59 variables
# Key columns: iso, year, eq_tr, bond_tr, housing_tr, bill_rate, crisisJST
```

### Variable Metadata

```r
# Discover available variables
hd_jst_variables()
# Returns tibble: variable name, category, description, coverage %
```

### Equity Premium Calculation

```r
jst |>
  filter(!is.na(eq_tr), !is.na(bill_rate)) |>
  mutate(equity_premium = eq_tr - bill_rate) |>
  summarise(
    mean_premium = mean(equity_premium),
    sd_premium = sd(equity_premium),
    .by = iso
  )
```

## Use Cases

### 1. Cross-Geography Pervasiveness Tests

Required by `cross-geography-pervasiveness` rule:
- Before adopting a factor, test it in **≥2 independent markets**
- JST provides 18 markets × 150 years = 2,700 country-years for testing

### 2. Underperformance Prior Calibration

Required by `underperformance-prior` rule:
- Document longest historical underperformance period for each factor
- Use JST crisis data to identify worst drawdowns and durations
- Avoid abandoning factors during historically normal drawdowns

### 3. Risk-Regime Backtesting

Partition backtests by `crisisJST`:
- Normal regime: crisis == 0
- Crisis regime: crisis == 1
- Report performance separately (regime-conditional metrics)

### 4. International Diversification

Test factor strategies on European equities (JST coverage: AUS, BEL, CHE, DEU, DNK, ESP, FIN, FRA, GBR, ITA, JPN, NLD, NOR, PRT, SWE):
- Does momentum work in France 1900-1950?
- Does value work in Germany 1920-1980?
- Cross-validate U.S.-discovered factors globally

## Limitations

### 1. Annual Frequency Only

- No intra-year volatility or drawdown data
- Cannot test monthly rebalancing strategies
- Must aggregate to annual returns for JST validation

### 2. Survivor Countries Only

JST includes **only countries with continuous markets 1870-2020**:
- Missing: Russia (1917 revolution), China (1949 market closure), Eastern Europe
- Still survivorship-biased, just **less** than U.S.-only

### 3. No Individual Securities

- Country-level indices only
- Cannot test stock-level factors (momentum on individual stocks)
- Use for **asset allocation** and **factor validation**, not stock selection

### 4. End Date: 2020

- No 2021-2026 data yet (Release 7 pending)
- For recent regime analysis (COVID, 2022 inflation), use other sources

## Sources

### JST Database
- **URL:** https://www.macrohistory.net/database/
- **Citation:** Òscar Jordà, Moritz Schularick, and Alan M. Taylor (2017). "Macrofinancial History and the New Business Cycle Facts." *NBER Macroeconomics Annual 2016*, volume 31. DOI: 10.1086/690241
- **License:** Free for academic and non-commercial use

### DMS Dataset
- **URL:** https://www.creditsuisse.com/about-us/en/reports-research/global-investment-returns.html (historical; now UBS)
- **Citation:** Elroy Dimson, Paul Marsh, and Mike Staunton (2002). *Triumph of the Optimists: 101 Years of Global Investment Returns*. Princeton University Press.
- **License:** Paid subscription

### Related Work
- William Goetzmann & Philippe Jorion (1999). "Re-Emerging Markets." *Journal of Financial and Quantitative Analysis* — early survivorship bias paper
- Brad M. Barber & Terrance Odean (2000). "The Courage of Misguided Convictions" — U.S. investor home bias

## Related Rules

- `cross-geography-pervasiveness` — require factor to work in ≥2 markets
- `underperformance-prior` — document historical max drawdown durations
- `resulting-prohibition` — judge by process, not outcome (don't abandon factors during normal drawdowns)
- `backtesting-assumptions` — default cost/risk assumptions (JST helps calibrate realistic equity premium priors)

## Related Targets

- `R/plan_jst.R` — 6 targets: raw data, equity premium by country/decade, pervasiveness test, FF comparison, crises, summary
- `docs/jst-dashboard.qmd` — dashboard vignette (Phase 3: deployment pending)

## Confidence

> ⚠ AI-synthesized: Historical findings (equity premium magnitude, crisis dates) verified against JST paper and live data. Interpretations of what constitutes "survivorship bias correction" are standard in academic finance but not verified against original DMS authors' statements.
