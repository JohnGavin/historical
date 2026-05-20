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
