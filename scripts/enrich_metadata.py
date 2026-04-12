"""Enrich metadata with computed fields from price data.

Computes beta_3yr, ytd_return, annual_return_3yr from equity_daily.parquet.
All changes tracked via PIT amendments log.

Usage:
    python scripts/enrich_metadata.py
"""

import sys
from datetime import datetime, timezone, date
from pathlib import Path

import pandas as pd
import numpy as np
import pyarrow.parquet as pq
import pyarrow as pa

sys.path.insert(0, str(Path(__file__).parent))
from pit_tracker import track_amendments, save_amendments


def compute_returns_from_prices(data_dir: Path) -> pd.DataFrame:
    """Compute beta, YTD return, 3yr annualised return for all equity tickers."""
    equity_path = data_dir / "yfinance_equity.parquet"
    if not equity_path.exists():
        print("No equity data found")
        return pd.DataFrame()

    print("Loading equity data...")
    eq = pq.read_table(equity_path, columns=["ticker", "date", "close", "adjusted"]).to_pandas()
    eq["date"] = pd.to_datetime(eq["date"])

    # Use adjusted if available, else close
    price_col = "adjusted" if "adjusted" in eq.columns and eq["adjusted"].notna().any() else "close"
    eq["price"] = eq[price_col].astype(float)

    # SPY as benchmark for beta
    spy = eq[eq["ticker"] == "SPY"][["date", "price"]].rename(columns={"price": "spy_price"})

    results = []
    tickers = eq["ticker"].unique()
    print(f"Computing returns for {len(tickers)} tickers...")

    for i, tkr in enumerate(tickers):
        if i % 100 == 0:
            print(f"  [{i}/{len(tickers)}]...")

        sub = eq[eq["ticker"] == tkr][["date", "price"]].sort_values("date")
        if len(sub) < 20:
            continue

        latest_date = sub["date"].max()
        latest_price = sub.loc[sub["date"] == latest_date, "price"].iloc[0]

        # YTD return
        ytd_start = pd.Timestamp(latest_date.year, 1, 1)
        jan_rows = sub[sub["date"] >= ytd_start].head(1)
        ytd_ret = None
        if len(jan_rows) > 0:
            jan_price = jan_rows["price"].iloc[0]
            if jan_price > 0:
                ytd_ret = round((latest_price / jan_price - 1), 4)

        # 3yr annualised return
        three_yr_ago = latest_date - pd.Timedelta(days=3 * 365)
        three_yr_rows = sub[sub["date"] >= three_yr_ago].head(1)
        ann_ret_3yr = None
        if len(three_yr_rows) > 0:
            start_price = three_yr_rows["price"].iloc[0]
            days = (latest_date - three_yr_rows["date"].iloc[0]).days
            if start_price > 0 and days > 365:
                total_ret = latest_price / start_price
                ann_ret_3yr = round(total_ret ** (365 / days) - 1, 4)

        # Beta (3yr, vs SPY)
        beta = None
        if tkr != "SPY":
            merged = sub.merge(spy, on="date", how="inner")
            merged = merged[merged["date"] >= three_yr_ago]
            if len(merged) > 60:  # need at least ~3 months
                merged["ret"] = merged["price"].pct_change()
                merged["spy_ret"] = merged["spy_price"].pct_change()
                merged = merged.dropna(subset=["ret", "spy_ret"])
                if len(merged) > 30:
                    cov = np.cov(merged["ret"], merged["spy_ret"])
                    if cov[1, 1] > 0:
                        beta = round(float(cov[0, 1] / cov[1, 1]), 3)

        results.append({
            "ticker": tkr,
            "computed_beta_3yr": beta,
            "computed_ytd_return": ytd_ret,
            "computed_ann_return_3yr": ann_ret_3yr,
        })

    return pd.DataFrame(results)


def main():
    data_dir = Path("data/raw")
    meta_path = data_dir / "metadata.parquet"
    amendments_path = data_dir / "metadata_amendments.parquet"

    if not meta_path.exists():
        print("No metadata.parquet found. Run fetch_metadata.py first.")
        return

    # Load existing metadata
    old_meta = pq.read_table(meta_path).to_pandas()
    print(f"Loaded metadata: {len(old_meta)} tickers")

    # Compute returns
    computed = compute_returns_from_prices(data_dir)
    if computed.empty:
        print("No computed data")
        return

    print(f"Computed returns for {len(computed)} tickers")
    print(f"  beta_3yr: {computed['computed_beta_3yr'].notna().sum()} non-null")
    print(f"  ytd_return: {computed['computed_ytd_return'].notna().sum()} non-null")
    print(f"  ann_return_3yr: {computed['computed_ann_return_3yr'].notna().sum()} non-null")

    # Merge computed values into metadata (overwrite only if computed is not None)
    new_meta = old_meta.merge(computed, on="ticker", how="left")

    for src, dst in [("computed_beta_3yr", "beta_3yr"),
                     ("computed_ytd_return", "ytd_return"),
                     ("computed_ann_return_3yr", "three_yr_return")]:
        if src in new_meta.columns:
            # Only overwrite if computed value is not null
            mask = new_meta[src].notna()
            new_meta.loc[mask, dst] = new_meta.loc[mask, src]
            new_meta = new_meta.drop(columns=[src])

    # Track amendments (PIT)
    amendments = track_amendments(
        old_meta, new_meta,
        source="computed_from_price_data",
        method="beta=cov(ret,spy)/var(spy), ytd=close/jan_close-1, 3yr=annualised",
        amended_by="enrich_metadata.py"
    )
    print(f"\nAmendments: {len(amendments)} field changes tracked")

    # Save
    save_amendments(amendments, amendments_path)

    # Coerce types
    for col in ["market_cap", "volume_avg", "fifty_two_week_high", "fifty_two_week_low",
                 "missing_pct", "expense_ratio", "yield_pct", "nav_price",
                 "beta_3yr", "ytd_return", "three_yr_return"]:
        if col in new_meta.columns:
            new_meta[col] = pd.to_numeric(new_meta[col], errors="coerce")
    for col in ["start_date", "end_date"]:
        if col in new_meta.columns:
            new_meta[col] = pd.to_datetime(new_meta[col]).dt.date
    if "total_obs" in new_meta.columns:
        new_meta["total_obs"] = pd.to_numeric(new_meta["total_obs"], errors="coerce").astype("Int64")

    pq.write_table(pa.Table.from_pandas(new_meta), meta_path, compression="zstd")
    print(f"\nUpdated metadata: {len(new_meta)} tickers")

    # Coverage report
    for col in ["beta_3yr", "ytd_return", "three_yr_return"]:
        n = new_meta[col].notna().sum()
        pct = round(100 * n / len(new_meta))
        print(f"  {col}: {n}/{len(new_meta)} ({pct}%)")


if __name__ == "__main__":
    main()
