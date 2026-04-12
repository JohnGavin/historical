"""Fetch equity daily OHLCV via yfinance batch download.

Downloads full history for all tickers in a single yf.download() call
(yfinance handles internal parallelism and rate limiting).

Usage:
    python scripts/fetch_equity.py                    # All default tickers
    python scripts/fetch_equity.py AAPL MSFT GOOGL    # Specific tickers
    python scripts/fetch_equity.py --batch-size 20    # Download in chunks of 20
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

# 51 major US stocks + ETFs
DEFAULT_TICKERS = [
    "AAPL", "MSFT", "GOOGL", "AMZN", "META", "NVDA", "TSLA",
    "AMD", "INTC", "AVGO", "QCOM",
    "CRM", "ORCL", "ADBE", "NOW",
    "JPM", "BAC", "GS", "MS", "V", "MA",
    "JNJ", "UNH", "PFE", "ABBV", "MRK",
    "WMT", "COST", "HD", "MCD", "KO", "PEP",
    "CAT", "BA", "GE", "HON", "UPS",
    "XOM", "CVX", "COP",
    "DIS", "NFLX", "CMCSA", "T",
    "PLD", "AMT",
    "SPY", "QQQ", "IWM", "DIA",
    "VIXY",
]


def fetch_batch(tickers: list[str], batch_size: int = 0) -> pd.DataFrame:
    """Download OHLCV for multiple tickers using yf.download() batch.

    Args:
        tickers: List of ticker symbols
        batch_size: 0 = all at once (default). >0 = download in chunks.

    Returns:
        Long-format DataFrame with ticker column.
    """
    if batch_size <= 0:
        batches = [tickers]
    else:
        batches = [tickers[i:i + batch_size] for i in range(0, len(tickers), batch_size)]

    all_dfs = []
    for batch_idx, batch in enumerate(batches, 1):
        print(f"Batch {batch_idx}/{len(batches)}: {len(batch)} tickers ({batch[0]}...{batch[-1]})")

        # yf.download handles parallelism internally (threads=True by default)
        raw = yf.download(
            batch,
            period="max",
            group_by="ticker" if len(batch) > 1 else "column",
            auto_adjust=False,
            threads=True,
            progress=True,
        )

        if raw.empty:
            print(f"  WARNING: empty result for batch {batch_idx}")
            continue

        # Reshape: yf.download returns multi-level columns when group_by="ticker"
        if len(batch) == 1:
            # Single ticker: flat columns (Date index, Open, High, Low, Close, ...)
            df = raw.reset_index()
            df.columns = [c.lower().replace(" ", "_") for c in df.columns]
            df["ticker"] = batch[0]
        else:
            # Multiple tickers: (ticker, column) multi-level
            frames = []
            for tkr in batch:
                try:
                    sub = raw[tkr].copy()
                    sub = sub.reset_index()
                    sub.columns = [c.lower().replace(" ", "_") for c in sub.columns]
                    sub["ticker"] = tkr
                    sub = sub.dropna(subset=["close"])
                    frames.append(sub)
                except KeyError:
                    print(f"  WARNING: {tkr} not in batch result")
            df = pd.concat(frames, ignore_index=True) if frames else pd.DataFrame()

        if not df.empty:
            all_dfs.append(df)
            n_tickers = df["ticker"].nunique()
            n_rows = len(df)
            print(f"  Got {n_rows:,} rows for {n_tickers} tickers")

        if batch_idx < len(batches):
            time.sleep(2)  # Pause between batches

    if not all_dfs:
        return pd.DataFrame()

    combined = pd.concat(all_dfs, ignore_index=True)

    # Standardise columns
    col_map = {
        "date": "date", "open": "open", "high": "high", "low": "low",
        "close": "close", "adj_close": "adjusted", "volume": "volume",
    }
    combined = combined.rename(columns=col_map)
    combined["source"] = "yahoo"
    combined["asset_class"] = "equity"

    # Ensure date is timezone-naive
    if hasattr(combined["date"].dtype, "tz") and combined["date"].dt.tz is not None:
        combined["date"] = combined["date"].dt.tz_localize(None)

    # Keep only standard columns
    keep = ["date", "open", "high", "low", "close", "adjusted", "volume",
            "ticker", "source", "asset_class"]
    combined = combined[[c for c in keep if c in combined.columns]]

    return combined.sort_values(["ticker", "date"]).reset_index(drop=True)


def main():
    # Parse args
    tickers = []
    batch_size = 0

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--batch-size" and i + 1 < len(args):
            batch_size = int(args[i + 1])
            i += 2
        else:
            tickers.append(args[i])
            i += 1

    if not tickers:
        tickers = DEFAULT_TICKERS

    output_dir = Path("data/raw")
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Fetching {len(tickers)} tickers (batch_size={batch_size or 'all'})")
    t0 = time.time()

    combined = fetch_batch(tickers, batch_size)

    if combined.empty:
        print("No data fetched!")
        return

    # Write combined Parquet
    out_path = output_dir / "yfinance_equity.parquet"
    table = pa.Table.from_pandas(combined)
    pq.write_table(table, out_path, compression="zstd",
                   use_dictionary=True, write_statistics=True)

    elapsed = time.time() - t0
    n_tickers = combined["ticker"].nunique()
    print(f"\nDone in {elapsed:.1f}s")
    print(f"Total: {len(combined):,} rows, {n_tickers} tickers")
    print(f"Date range: {combined['date'].min().date()} to {combined['date'].max().date()}")
    print(f"File: {out_path} ({out_path.stat().st_size / 1e6:.1f} MB)")


if __name__ == "__main__":
    main()
