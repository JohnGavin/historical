"""Fetch equity daily OHLCV via Yahoo Finance v8 JSON API.

Downloads full history for a list of tickers. No API key needed.
Outputs one consolidated Parquet file.

Usage:
    python scripts/fetch_equity.py                    # All 50 default tickers
    python scripts/fetch_equity.py AAPL MSFT GOOGL    # Specific tickers
"""

import sys
import json
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

# 50 major US stocks: FAANG + megacaps + sectors + some mid-cap
DEFAULT_TICKERS = [
    # Mega-cap tech
    "AAPL", "MSFT", "GOOGL", "AMZN", "META", "NVDA", "TSLA",
    # Semiconductors
    "AMD", "INTC", "AVGO", "QCOM",
    # Software/cloud
    "CRM", "ORCL", "ADBE", "NOW",
    # Financials
    "JPM", "BAC", "GS", "MS", "V", "MA",
    # Healthcare
    "JNJ", "UNH", "PFE", "ABBV", "MRK",
    # Consumer
    "WMT", "COST", "HD", "MCD", "KO", "PEP",
    # Industrials
    "CAT", "BA", "GE", "HON", "UPS",
    # Energy
    "XOM", "CVX", "COP",
    # Telecom/Media
    "DIS", "NFLX", "CMCSA", "T",
    # REITs / Other
    "PLD", "AMT",
    # ETFs (index-like)
    "SPY", "QQQ", "IWM", "DIA",
    # Volatility
    "VIXY",
]


def fetch_ticker_yahoo(symbol: str) -> pd.DataFrame | None:
    """Download full daily OHLCV for one ticker via Yahoo v8 JSON."""
    base = f"https://query2.finance.yahoo.com/v8/finance/chart/{symbol}"
    headers = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"}

    # Fetch in chunks to work around Yahoo's ~10yr limit per request
    chunks = []
    now_ts = int(datetime.now(timezone.utc).timestamp())
    boundaries = [
        int(datetime(1980, 1, 1, tzinfo=timezone.utc).timestamp()),
        int(datetime(2000, 1, 1, tzinfo=timezone.utc).timestamp()),
        int(datetime(2015, 1, 1, tzinfo=timezone.utc).timestamp()),
        now_ts,
    ]

    for i in range(len(boundaries) - 1):
        p1, p2 = boundaries[i], boundaries[i + 1]
        url = f"{base}?period1={p1}&period2={p2}&interval=1d"
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = json.loads(resp.read().decode("utf-8"))

            result = raw["chart"]["result"][0]
            if "timestamp" not in result:
                continue
            timestamps = result["timestamp"]
            quote = result["indicators"]["quote"][0]
            adjclose = result["indicators"].get("adjclose", [{}])[0].get("adjclose")

            df = pd.DataFrame({
                "date": pd.to_datetime(timestamps, unit="s").normalize(),
                "open": quote.get("open"),
                "high": quote.get("high"),
                "low": quote.get("low"),
                "close": quote.get("close"),
                "volume": quote.get("volume"),
                "adjusted": adjclose,
            })
            df = df.dropna(subset=["close"])
            chunks.append(df)
        except Exception:
            pass  # Chunk may not exist for newer tickers
        time.sleep(0.3)

    if not chunks:
        return None

    full = pd.concat(chunks, ignore_index=True).drop_duplicates(subset=["date"]).sort_values("date")
    full["ticker"] = symbol
    full["source"] = "yahoo"
    full["asset_class"] = "equity"
    full["date"] = full["date"].dt.tz_localize(None) if full["date"].dt.tz is not None else full["date"]
    return full


def main():
    tickers = sys.argv[1:] if len(sys.argv) > 1 else DEFAULT_TICKERS
    output_dir = Path("data/raw")
    output_dir.mkdir(parents=True, exist_ok=True)

    all_dfs = []
    for i, ticker in enumerate(tickers, 1):
        print(f"[{i}/{len(tickers)}] {ticker}...", end=" ", flush=True)
        df = fetch_ticker_yahoo(ticker)
        if df is not None:
            all_dfs.append(df)
            print(f"{len(df)} rows ({df['date'].min().date()} to {df['date'].max().date()})")
        else:
            print("FAILED")
        time.sleep(0.5)  # Rate limit

    if not all_dfs:
        print("No data fetched!")
        return

    combined = pd.concat(all_dfs, ignore_index=True)

    # Write combined file
    out_path = output_dir / "yfinance_equity.parquet"
    table = pa.Table.from_pandas(combined)
    pq.write_table(table, out_path, compression="zstd", use_dictionary=True, write_statistics=True)

    n_tickers = combined["ticker"].nunique()
    print(f"\nTotal: {len(combined)} rows, {n_tickers} tickers")
    print(f"Date range: {combined['date'].min().date()} to {combined['date'].max().date()}")
    print(f"File: {out_path} ({out_path.stat().st_size / 1e6:.1f} MB)")

    # Also keep the single-AAPL file for backward compat with prototype pipeline
    aapl = combined[combined["ticker"] == "AAPL"].copy()
    aapl_path = output_dir / "yfinance_aapl.parquet"
    pq.write_table(pa.Table.from_pandas(aapl), aapl_path, compression="zstd")
    print(f"Also wrote: {aapl_path}")


if __name__ == "__main__":
    main()
