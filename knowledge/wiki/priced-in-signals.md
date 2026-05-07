## Priced-In Signals — Evidence Log

### Rule

Public information available to all market participants is already reflected in current prices. A signal built from public data has no edge unless you have a speed advantage (HFT) or a processing advantage that others haven't exploited.

See: `priced-in-prohibition` rule in `~/docs_gh/llm/.claude/rules/`.

### Evidence from This Project

| Signal | Source | Method | Same-month r | Next-month r | Verdict |
|--------|--------|--------|------------:|------------:|---------|
| "recession" count | NYT (#82) | keyword freq | — | ~0 | No signal |
| "inflation" count | NYT (#82) | keyword freq | — | ~0 | No signal |
| "recession" count | Guardian (#89) | keyword freq | +0.022 | +0.144 | No signal |
| "inflation" count | Guardian (#89) | keyword freq | -0.094 | -0.090 | No signal |
| "stock market" count | Guardian (#89) | keyword freq | -0.109 | +0.103 | No signal |
| "recession" sentiment | Guardian (#89) | sentimentr NLP | +0.058 | +0.070 | No signal |
| "inflation" sentiment | Guardian (#89) | sentimentr NLP | +0.277 | +0.005 | **Contemporaneous only** |
| "stock market" sentiment | Guardian (#89) | sentimentr NLP | +0.272 | +0.077 | **Contemporaneous only** |

### Pattern

1. **Keyword counts** from major newspapers: zero predictive power across all keywords and both sources (NYT, Guardian)
2. **NLP body sentiment**: moderate same-month correlation (r ≈ 0.27) but zero next-month prediction
3. **Processing advantage fails**: even negation-aware sentence-level NLP cannot overcome the timing problem — newspapers report *after* the market moves

### What Might Work Instead

| Signal type | Why it might have edge | Status |
|-------------|----------------------|--------|
| CISS sub-market stress | Not widely followed outside ECB watchers | Testing (#88) |
| Kalshi prediction markets | Small market, possibly less efficient | Testing (#47) |
| Proprietary/alternative data | Genuine information asymmetry | Not available |
| Speed advantage on public data | HFT execution | Not our domain |

### Implication for Strategy Design

Do not build strategies that assume public news contains predictive information. The only public data that shows signal in our tests is **structural/institutional** data (factor returns, CISS stress decomposition, yield curve shape) — not narrative data (newspaper text).

## Sources

- `priced-in-prohibition` rule
- Guardian NLP analysis, 2026-05-07 ([[guardian-nlp]])
- NYT analysis, 2026-05-02 (issue #82)
- Swedroe evidence-based investing framework (llm/knowledge/wiki/swedroe-evidence-investing.md)
