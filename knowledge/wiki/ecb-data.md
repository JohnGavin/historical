## ECB Statistical Data Warehouse — API Reference

### API Endpoint

`https://data-api.ecb.europa.eu/service/data/{series_key}`

- Accept: `text/csv` (returns CSV with KEY, TIME_PERIOD, OBS_VALUE columns)
- Query params: `startPeriod`, `endPeriod`, `detail=dataonly`
- No authentication required
- No documented rate limit

### Series Key Patterns

| Dataflow | Example key | Returns |
|----------|------------|---------|
| EXR (exchange rates) | `EXR/D.USD.EUR.SP00.A` | Daily FX rates |
| FM (financial markets) | `FM/D.U2.EUR.4F.KR.MRR_FR.LEV` | Daily ECB refi rate |
| FM (financial markets) | `FM/M.U2.EUR.RT.MM.EURIBOR3MD_.HSTA` | Monthly EURIBOR |
| YC (yield curve) | `YC/B.U2.EUR.4F.G_N_A.SV_C_YM.SR_10Y` | Business-daily yields |
| YC (Svensson params) | `YC/B.U2.EUR.4F.G_N_A.SV_C_YM.BETA0` | Yield curve shape |
| CISS (stress) | `CISS/D.U2.Z0Z.4F.EC.SS_CIN.IDX` | Daily composite stress |
| CISS (sub-market) | `CISS/D.U2.Z0Z.4F.EC.SS_EMN.CON` | Daily equity stress |
| ICP (inflation) | `ICP/M.U2.N.000000.4.ANR` | Monthly HICP |
| BSI (money supply) | `BSI/M.U2.Y.V.M30.X.1.U2.2300.Z01.E` | Monthly M3 |

### Key Naming Conventions

- `D` = daily, `M` = monthly, `B` = business daily
- `U2` = euro area, `DE/FR/IT/GB/US` = country
- `.IDX` suffix = index level, `.CON` suffix = contribution to composite
- `N` suffix (e.g. `SS_CIN` vs `SS_CI`) = new methodology, longer history
- `HSTA` = historical average

### Gotchas

1. **Bond yields are NOT in `FM/M`** — they're in `YC/B` (yield curve dataflow). `FM/M.DE.EUR.FR2.RT.GBD10YR.HSTA` returns 404.
2. **CISS sub-indices use `.CON` not `.IDX`** — `SS_BO.IDX` returns 404, `SS_BMN.CON` works.
3. **Wildcard search** works: `CISS/D.U2.Z0Z.4F.EC..IDX` returns all matching series.
4. **Date format**: monthly = `YYYY-MM`, daily = `YYYY-MM-DD`. Parse accordingly.
5. **HICP core** (`ICP/M.U2.N.TOT_X_NRG_FOOD.4.ANR`) returns 404 — series key may have changed.
6. **Frequency mixing**: daily, business-daily, and monthly series in same pipeline need frequency-aware joins (LOCF for monthly→daily).

### 29 Series Inventory (2026-05-07)

| Category | Count | Frequency | History |
|----------|------:|-----------|---------|
| FX | 4 | Daily | 2000-2026, ~6,800 obs each |
| Interest rates | 3 | Daily+Monthly | 2000-2026 |
| Yield curve | 7 | Business daily | 2004-2026, ~5,500 obs each |
| CISS stress | 8 | Daily | 2000-2026, ~6,800 obs each |
| CISS country | 5 | Daily | 2000-2026 |
| Macro | 2 | Monthly | 2000-2026, ~310 obs each |

## Sources

- ECB API docs: https://data.ecb.europa.eu/help/api/data
- Tested 2026-05-07 via `hd_ecb()` in historicaldata package
- CISS methodology: https://www.ecb.europa.eu/pub/pdf/scpwps/ecbwp1426.pdf
