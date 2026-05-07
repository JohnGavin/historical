## Guardian Open Platform — NLP Sentiment Analysis

### API Access

- Endpoint: `https://content.guardianapis.com/search`
- Free test key: 1 call/sec, 5,000/day — includes body text
- Developer key: 12 calls/sec — same body text access
- R functions: `hd_guardian()`, `hd_guardian_monthly()`

### Volume (2024, business section)

| Keyword | Articles | Per month |
|---------|--------:|----------:|
| inflation | 6,857 | 91 |
| stock market | 6,040 | 80 |
| interest rate | 5,256 | 69 |
| central bank | 5,233 | 69 |
| recession | 3,004 | 40 |
| trade war | 2,979 | 39 |

### Phase 2: Keyword Counts vs SP500

Spearman correlation, 75 months (2020-2026):

| Keyword | Same-month r | Next-month r |
|---------|------------:|------------:|
| recession | +0.022 | +0.144 |
| inflation | -0.094 | -0.090 |
| interest rate | -0.067 | +0.048 |
| stock market | -0.109 | +0.103 |
| central bank | -0.070 | +0.111 |
| trade war | -0.146 | -0.010 |

**All negligible.** Keyword frequency is priced in.

### Phase 3a: sentimentr Body Text vs SP500

`sentimentr` package — sentence-level, negation-aware. Scored first 2000 chars of body text. 50 articles per keyword per month, 60 months (2021-2025).

| Keyword | Same-month r | Next-month r | Mean sentiment |
|---------|------------:|------------:|---------------:|
| recession | +0.058 | +0.070 | -0.022 |
| **inflation** | **+0.277** | +0.005 | -0.010 |
| **stock market** | **+0.272** | +0.077 | +0.024 |

**Same-month moderate** (r ≈ 0.27) = sentiment reflects market mood contemporaneously.
**Next-month negligible** (all |r| < 0.08) = no predictive signal.

### Headline vs Body

- Headline sentiment: mean -0.201, sd 0.305
- Body sentiment: mean -0.014, sd 0.096
- Headline-body correlation: **r = 0.07** (essentially independent)
- Headlines are more extreme (higher sd); body text is more measured

### Why No Signal

1. **Priced in:** By the time an article is published, the market has already moved
2. **Contemporaneous, not causal:** r ≈ 0.27 same-month means news and market co-move, but the market moves first
3. **NLP quality is not the constraint:** sentimentr handles negation ("not doing well" = negative). A transformer (FinBERT) would score individual sentences better but can't fix the timing problem

### Comparison with NYT (#82)

| Dimension | Guardian | NYT |
|-----------|---------|-----|
| Signal (keyword counts) | None (|r| < 0.15) | None (|r| < 0.15) |
| Signal (body sentiment) | None for next-month | Not tested (NYT = snippets only) |
| Full text access | Yes (free) | No (snippets only) |
| Rate limit | 12/sec (dev key) | 10/min |
| Geographic focus | UK/international | US-centric |

### Decision: FinBERT Not Recommended

Given sentimentr (which handles negation and sentence structure) found no predictive signal, the constraint is timing, not NLP quality. FinBERT would cost compute time for the same null result.

## Sources

- Guardian API docs: https://open-platform.theguardian.com/documentation/
- sentimentr: Rinker (2019), CRAN
- Tested 2026-05-07 with developer API key
