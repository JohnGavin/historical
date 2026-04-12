"""Fetch equity daily OHLCV via yfinance batch download.

Downloads full history for all tickers in a single yf.download() call
(yfinance handles internal parallelism and rate limiting).

Usage:
    python scripts/fetch_equity.py                    # All US default tickers
    python scripts/fetch_equity.py --lse              # Add ~929 LSE ETFs
    python scripts/fetch_equity.py --lse --batch-size 50  # LSE in batches of 50
    python scripts/fetch_equity.py AAPL MSFT GOOGL    # Specific tickers
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

        # yf.download: always use group_by="ticker" for consistent multi-level output
        raw = yf.download(
            batch,
            period="max",
            group_by="ticker",
            auto_adjust=False,
            threads=True,
            progress=True,
        )

        if raw.empty:
            print(f"  WARNING: empty result for batch {batch_idx}")
            continue

        # yf.download returns multi-level columns: (Ticker, OHLCV) or (Price, OHLCV)
        # Extract per-ticker DataFrames
        frames = []
        for tkr in batch:
            try:
                if len(batch) == 1:
                    # Single ticker: columns are (Price, Open), (Price, Close), etc.
                    sub = raw.copy()
                    # Flatten: take second level of multi-index columns
                    if hasattr(sub.columns, 'get_level_values'):
                        sub.columns = sub.columns.get_level_values(-1)
                    sub = sub.reset_index()
                else:
                    # Multi-ticker: columns are (AAPL, Open), (MSFT, Open), etc.
                    if tkr not in raw.columns.get_level_values(0):
                        continue
                    sub = raw[tkr].copy()
                    sub = sub.reset_index()

                sub.columns = [str(c).lower().replace(" ", "_") for c in sub.columns]
                sub["ticker"] = tkr
                sub = sub.dropna(subset=["close"])
                if len(sub) > 0:
                    frames.append(sub)
            except (KeyError, Exception) as e:
                print(f"  WARNING: {tkr}: {e}")

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


def load_lse_tickers() -> list[str]:
    """Load LSE ETF tickers from the pre-built list."""
    lse_file = Path("lse_etf_tickers_yahoo.txt")
    if not lse_file.exists():
        lse_file = Path(__file__).parent.parent / "lse_etf_tickers_yahoo.txt"
    if not lse_file.exists():
        print("WARNING: lse_etf_tickers_yahoo.txt not found. Run research to generate it.")
        return []
    return [line.strip() for line in lse_file.read_text().splitlines() if line.strip()]


def log_telemetry(log_entries: list[dict], output_dir: Path):
    """Write download telemetry to Parquet."""
    if not log_entries:
        return
    df = pd.DataFrame(log_entries)
    out = output_dir / "download_log.parquet"
    # Append if exists
    if out.exists():
        existing = pq.read_table(out).to_pandas()
        df = pd.concat([existing, df], ignore_index=True)
    pq.write_table(pa.Table.from_pandas(df), out, compression="zstd")
    print(f"Telemetry: {len(log_entries)} batches logged to {out}")


def main():
    # Parse args
    tickers = []
    batch_size = 0
    include_lse = False

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--batch-size" and i + 1 < len(args):
            batch_size = int(args[i + 1])
            i += 2
        elif args[i] == "--lse":
            include_lse = True
            i += 1
        else:
            tickers.append(args[i])
            i += 1

    if not tickers:
        tickers = list(DEFAULT_TICKERS)

    if include_lse:
        lse = load_lse_tickers()
        print(f"Adding {len(lse)} LSE ETF tickers")
        tickers.extend(lse)
        if batch_size == 0:
            batch_size = 50  # Default batch size for large downloads

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
