"""Pure-stdlib helpers for fetch_metadata.py.

Extracted so that test_fetch_metadata.py can import _yield_fields() without
triggering the heavy pandas/pyarrow/yfinance imports and the DATASETS
module-level side effect that live in fetch_metadata.py.
"""


def first_present(d: dict, *keys):
    """Return the first value that is not None, ignoring falsy-but-valid 0.0."""
    for k in keys:
        v = d.get(k)
        if v is not None:
            return v
    return None


def _yield_fields(info: dict) -> dict:
    """Return yield_pct and yield_type derived from the same source.

    Precedence (is-not-None, so 0.0 is treated as present):
      1. trailingAnnualDividendYield → yield_type = "trailing"
      2. yield > 0.20               → yield_type = "synthetic"
      3. yield present              → yield_type = "reported"
      4. neither present            → both None
    """
    trailing = info.get("trailingAnnualDividendYield")
    raw_yield = info.get("yield")
    if trailing is not None:
        return {"yield_pct": trailing, "yield_type": "trailing"}
    if raw_yield is not None:
        yield_type = "synthetic" if raw_yield > 0.20 else "reported"
        return {"yield_pct": raw_yield, "yield_type": yield_type}
    return {"yield_pct": None, "yield_type": None}


def _expected_trading_days(dataset: str, all_dates, start, end, days_span: int) -> int:
    """Estimate the number of expected trading days for one ticker's date range.

    Historical#569: replaces the old fixed 252/365 ratio, which was a
    hand-entered approximation feeding the published `missing_pct` metadata
    field, with a calendar derived from the data itself.

    - ``crypto_daily``: every calendar day counts, so ``days_span`` is
      returned directly. Crypto genuinely trades daily, but this still
      assumes no exchange/data-source outages.
    - every other dataset: the number of *distinct* dates in ``all_dates``
      (the date column of the FULL dataset, across every ticker — not just
      this ticker) that fall within ``[start, end]``. Using the dataset's own
      observed calendar as the trading-day estimate is more accurate than a
      fixed ratio because it reflects the actual exchange holidays/outages
      present in this data vintage, and it is directly verifiable (it comes
      from data, not an assumption).

      LIMITATION: for a single-ticker dataset, ``all_dates`` reduces to
      exactly this ticker's own dates, so the returned count equals the
      ticker's own observation count and ``missing_pct`` is 0 by
      construction — the union-calendar approach cannot detect gaps for the
      only ticker present in the dataset.

    Raises nothing itself; if ``all_dates`` entries are not comparable to
    ``start``/``end`` (e.g. wrong type), the comparison raises naturally
    rather than silently falling back to any ratio-based estimate.
    """
    if dataset == "crypto_daily":
        return days_span
    return len({d for d in all_dates if start <= d <= end})


def _missing_pct(total: int, expected: int) -> float:
    """Percent of expected observations missing, floored at 0.0.

    ``expected <= 0`` (e.g. a zero-length calendar, or a zero-day span with
    no other ticker contributing a date) is treated as "cannot estimate" and
    returns 0.0 rather than dividing by zero or reporting a nonsensical
    negative/inf value.
    """
    if expected <= 0:
        return 0.0
    return max(round(100 * (1 - total / expected), 1), 0.0)
