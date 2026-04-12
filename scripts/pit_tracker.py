"""Point-in-Time (PIT) tracking for metadata changes.

Compares old vs new metadata DataFrames, records diffs in an
append-only amendments log. Every computed or enriched field
is tracked so changes can be audited and rolled back.

Usage:
    from pit_tracker import track_amendments
    amendments = track_amendments(old_df, new_df, source="fetch_metadata.py v2")
"""

from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq


# Columns to track for changes (skip ticker/dataset — they're keys)
TRACKED_COLUMNS = [
    "long_name", "exchange", "full_exchange", "currency", "instrument_type",
    "sector", "industry", "country", "market_cap", "volume_avg",
    "fifty_two_week_high", "fifty_two_week_low",
    "expense_ratio", "yield_pct", "category", "fund_family",
    "nav_price", "beta_3yr", "ytd_return", "three_yr_return",
    "start_date", "end_date", "total_obs", "missing_pct",
]


def _to_str(val) -> str:
    """Convert any value to string for comparison. None/NaN → empty string."""
    if val is None or (isinstance(val, float) and pd.isna(val)):
        return ""
    return str(val)


def track_amendments(
    old_df: pd.DataFrame,
    new_df: pd.DataFrame,
    source: str = "fetch_metadata.py",
    method: str = "",
    amended_by: str = "pipeline",
) -> pd.DataFrame:
    """Compare old vs new metadata, return amendment log rows.

    Args:
        old_df: Previous metadata (or empty DataFrame if first run)
        new_df: Updated metadata
        source: Data source description
        method: Computation method description
        amended_by: Who/what made the change

    Returns:
        DataFrame of amendment records (may be empty if no changes)
    """
    now = datetime.now(timezone.utc).isoformat()
    amendments = []

    # Index by ticker for fast lookup
    old_idx = old_df.set_index("ticker") if len(old_df) > 0 else pd.DataFrame()
    new_idx = new_df.set_index("ticker") if len(new_df) > 0 else pd.DataFrame()

    for ticker in new_idx.index:
        for col in TRACKED_COLUMNS:
            if col not in new_idx.columns:
                continue

            new_val = new_idx.at[ticker, col] if ticker in new_idx.index else None
            old_val = old_idx.at[ticker, col] if (len(old_idx) > 0 and ticker in old_idx.index and col in old_idx.columns) else None

            new_str = _to_str(new_val)
            old_str = _to_str(old_val)

            # Skip if unchanged
            if new_str == old_str:
                continue

            # Skip if both effectively empty
            if not new_str and not old_str:
                continue

            amendments.append({
                "ticker": ticker,
                "field": col,
                "old_value": old_str if old_str else None,
                "new_value": new_str if new_str else None,
                "source": source,
                "method": method,
                "amended_at": now,
                "amended_by": amended_by,
                "reversible": True,
            })

    return pd.DataFrame(amendments) if amendments else pd.DataFrame(columns=[
        "ticker", "field", "old_value", "new_value",
        "source", "method", "amended_at", "amended_by", "reversible"
    ])


def save_amendments(amendments_df: pd.DataFrame, path: Path):
    """Append amendments to the log file (create if doesn't exist)."""
    if amendments_df.empty:
        print("No amendments to save.")
        return

    if path.exists():
        existing = pq.read_table(path).to_pandas()
        combined = pd.concat([existing, amendments_df], ignore_index=True)
    else:
        combined = amendments_df

    pq.write_table(pa.Table.from_pandas(combined), path, compression="zstd")
    print(f"Saved {len(amendments_df)} amendments ({len(combined)} total in log)")
