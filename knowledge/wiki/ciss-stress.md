## CISS: Composite Indicator of Systemic Stress

ECB's flagship systemic risk indicator. Published weekly (composite) and daily (sub-indices). Range 0 (calm) to 1 (systemic crisis). Peak: 0.84 during GFC (2008).

### Sub-Market Decomposition

| Component | Key suffix | What it measures | r vs VIX |
|-----------|-----------|-----------------|------:|
| **Equity market** | SS_EMN.CON | Stock market vol + returns | **+0.751** |
| **Composite** | SS_CIN.IDX | Weighted combination of all 5 | +0.649 |
| **Financial intermediary** | SS_FIN.CON | Bank/insurance sector stress | +0.626 |
| **Bond market** | SS_BMN.CON | Govt bond vol + spreads | +0.612 |
| **FX market** | SS_FXN.CON | Currency volatility | +0.563 |
| **Money market** | SS_MMN.CON | Interbank/money market stress | +0.507 |
| **Cross-correlation** | SS_CON.CON | Contagion between markets | -0.198 |
| **Sovereign** | SOV_EWN.IDX | Equal-weighted sovereign stress | N/A |

All correlations: Spearman, 6,653 overlapping daily obs, 2000-2026.

### Crisis vs Calm Regime

| Component | Crisis (VIX>25) r | Calm (VIX≤25) r |
|-----------|------------------:|----------------:|
| CISS equity | +0.560 | +0.627 |
| CISS financial | +0.550 | +0.473 |
| CISS bond | +0.437 | +0.463 |
| CISS FX | +0.410 | +0.439 |
| CISS money | +0.357 | +0.352 |
| **CISS correlation** | **+0.256** | **-0.286** |

**Key finding:** Cross-market correlation flips from negative (calm: markets independent) to positive (crisis: contagion). This is the mechanism behind "correlations go to 1 in a crisis."

### Country-Level CISS vs VIX

| Country | r vs VIX | Obs |
|---------|--------:|----:|
| US (ECB-computed) | +0.737 | 6,654 |
| Germany | +0.651 | 6,654 |
| UK | +0.621 | 6,653 |
| France | +0.611 | 6,653 |
| Italy | +0.523 | 6,653 |

### Strategy Relevance

- **CISS equity as European vol proxy:** r = 0.75 with VIX — strong enough for regime classification
- Wired into `plan_european_overlay.R` as `eur_ciss_regime` target
- Uses percentile-based thresholds (33rd/67th) → benign/cautious/hostile
- Applied to STOXX 600, Euro Stoxx 50, FTSE Europe, Germany, France ETFs

### No Free European Implied Vol

VSTOXX (Euro STOXX 50 implied vol) is a Qontigo commercial product. No free API. CISS equity is the best available free proxy.

## Sources

- ECB CISS methodology paper: Holló, Kremer & Lo Duca (2012), ECB WP #1426
- Data: ECB SDMX REST API, tested 2026-05-07
- VIX: FRED VIXCLS series
