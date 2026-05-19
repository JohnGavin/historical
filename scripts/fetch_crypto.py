"""Fetch crypto daily OHLCV via yfinance batch download.

Uses yf.download() for batch fetching (same as equity).
Crypto tickers use {SYMBOL}-USD format on Yahoo.

Usage:
    python scripts/fetch_crypto.py                     # All default tokens
    python scripts/fetch_crypto.py BTC-USD ETH-USD     # Specific tickers
"""

import sys
import time
from pathlib import Path

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

try:
    import yfinance as yf
except ImportError:
    sys.exit("yfinance required. In Nix shell: already available.")

# 14 tokens: major + Solana ecosystem + stablecoins
# Yahoo uses {SYMBOL}-USD format
DEFAULT_TICKERS = [
    "BTC-USD", "ETH-USD", "BNB-USD", "SOL-USD",
    "XRP-USD", "ADA-USD", "DOGE-USD", "DOT-USD",
    "USDC-USD", "USDT-USD",
    "RAY-USD", "HNT-USD", "BONK-USD", "PYTH-USD",
]

# Map Yahoo ticker back to our short symbol
def short_ticker(yahoo_sym: str) -> str:
    return yahoo_sym.replace("-USD", "")


def main():
    tickers = sys.argv[1:] if len(sys.argv) > 1 else DEFAULT_TICKERS
    output_dir = Path("data/raw")
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Fetching {len(tickers)} crypto tickers via yf.download batch")
    t0 = time.time()

    raw = yf.download(tickers, period="max", group_by="ticker", auto_adjust=False, threads=True)

    if raw.empty:
        print("No data!")
        return

    # Reshape multi-level to long format
    frames = []
    for tkr in tickers:
        try:
            if len(tickers) == 1:
                sub = raw.copy()
                if hasattr(sub.columns, 'get_level_values'):
                    sub.columns = sub.columns.get_level_values(-1)
            else:
                if tkr not in raw.columns.get_level_values(0):
                    continue
                sub = raw[tkr].copy()

            sub = sub.reset_index()
            sub.columns = [str(c).lower().replace(" ", "_") for c in sub.columns]
            sub["ticker"] = short_ticker(tkr)
            sub["source"] = "yahoo"
            sub["asset_class"] = "crypto"
            sub = sub.dropna(subset=["close"])
            if len(sub) > 0:
                frames.append(sub)
        except Exception as e:
            print(f"  WARNING: {tkr}: {e}")

    if not frames:
        print("No data after reshape!")
        return

    combined = pd.concat(frames, ignore_index=True)

    # Validate required columns immediately after concat, before any column access.
    required = {"date", "close", "ticker"}
    missing = required - set(combined.columns)
    if missing:
        raise ValueError(f"Missing required columns after reshape: {missing}")

    # Standardise columns
    # Note: crypto data has no adjusted-close column (CoinGecko/Yahoo crypto never
    # had one); the adj_close → adjusted rename was dead code and is removed.
    # keep list below selects only columns that actually exist in crypto OHLCV.

    if hasattr(combined["date"].dtype, "tz") and combined["date"].dt.tz is not None:
        combined["date"] = combined["date"].dt.tz_localize(None)

    keep = ["date", "open", "high", "low", "close", "volume",
            "ticker", "source", "asset_class"]
    combined = combined[[c for c in keep if c in combined.columns]]
    combined = combined.sort_values(["ticker", "date"]).reset_index(drop=True)

    out_path = output_dir / "crypto_all.parquet"
    pq.write_table(pa.Table.from_pandas(combined), out_path, compression="zstd",
                   use_dictionary=True, write_statistics=True)

    elapsed = time.time() - t0
    print(f"\nDone in {elapsed:.1f}s")
    print(f"Total: {len(combined):,} rows, {combined['ticker'].nunique()} tokens")
    print(f"Date range: {combined['date'].min().date()} to {combined['date'].max().date()}")
    print(f"File: {out_path} ({out_path.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
