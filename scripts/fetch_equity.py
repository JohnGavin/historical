"""Fetch AAPL daily OHLCV via yfinance.

Standalone script for running OUTSIDE the T pipeline (needs network).
The T pipeline's pyn node embeds the fetch logic directly.
This script is for manual/debug use.

Usage:
    python scripts/fetch_equity.py
"""

import yfinance as yf
import pyarrow as pa
import pyarrow.parquet as pq
from pathlib import Path


def fetch_ticker(symbol: str, output_dir: Path) -> Path:
    """Download full history for a ticker and save as Parquet."""
    ticker = yf.Ticker(symbol)
    df = ticker.history(period="max")
    df = df.reset_index()
    df = df.rename(columns={
        "Date": "date",
        "Open": "open",
        "High": "high",
        "Low": "low",
        "Close": "close",
        "Volume": "volume",
        "Dividends": "dividends",
        "Stock Splits": "stock_splits",
    })
    df["ticker"] = symbol
    df["source"] = "yahoo"
    df["asset_class"] = "equity"
    # Remove timezone info for Parquet compatibility
    df["date"] = df["date"].dt.tz_localize(None)

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / f"yfinance_{symbol.lower()}.parquet"
    table = pa.Table.from_pandas(df)
    pq.write_table(table, out_path, compression="zstd")

    print(f"Wrote {len(df)} rows to {out_path}")
    return out_path


if __name__ == "__main__":
    raw_dir = Path("data/raw")
    fetch_ticker("AAPL", raw_dir)
