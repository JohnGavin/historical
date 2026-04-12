"""Fetch ticker metadata for all datasets using yfinance.

Produces metadata.parquet with: ticker, dataset, long_name, exchange, currency,
instrument_type, sector, industry, country, market_cap, start_date, end_date,
total_obs, missing_pct, volume_avg.

Usage:
    python scripts/fetch_metadata.py
"""

import sys
import time
from pathlib import Path
from datetime import datetime

import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

try:
    import yfinance as yf
except ImportError:
    sys.exit("yfinance required: pip install yfinance")

# US equity tickers
US_EQUITY = [
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

CRYPTO = [
    "BTC", "ETH", "BNB", "SOL", "XRP", "ADA", "DOGE", "DOT",
    "USDC", "USDT", "RAY", "HNT", "BONK", "PYTH",
]


def load_lse_tickers() -> list[str]:
    """Load LSE ETF tickers from the pre-built list."""
    for path in [Path("lse_etf_tickers_yahoo.txt"),
                 Path(__file__).parent.parent / "lse_etf_tickers_yahoo.txt"]:
        if path.exists():
            return [l.strip() for l in path.read_text().splitlines() if l.strip()]
    print("WARNING: lse_etf_tickers_yahoo.txt not found — skipping LSE tickers")
    return []


def build_datasets() -> dict:
    """Build DATASETS dict including LSE tickers."""
    lse = load_lse_tickers()
    equity = US_EQUITY + lse
    print(f"Equity tickers: {len(US_EQUITY)} US + {len(lse)} LSE = {len(equity)}")
    return {
        "equity_daily": equity,
        "crypto_daily": CRYPTO,
    }


DATASETS = build_datasets()

# Yahoo ticker mapping (crypto uses {SYMBOL}-USD)
def yahoo_ticker(ticker: str, dataset: str) -> str:
    if dataset == "crypto_daily":
        return f"{ticker}-USD"
    return ticker


def fetch_yahoo_info(yahoo_sym: str) -> dict:
    """Fetch metadata from yfinance .info dict."""
    try:
        t = yf.Ticker(yahoo_sym)
        info = t.info or {}
        # ETF-specific fields (from fundProfile if available)
        fund_profile = info.get("fundProfile", {}) or {}

        return {
            "long_name": info.get("longName") or info.get("shortName", ""),
            "exchange": info.get("exchange", ""),
            "full_exchange": info.get("fullExchangeName", ""),
            "currency": info.get("currency", ""),
            "instrument_type": info.get("quoteType", ""),
            "sector": info.get("sector"),
            "industry": info.get("industry"),
            "country": info.get("country"),
            "market_cap": info.get("marketCap") or info.get("totalAssets"),
            "volume_avg": info.get("averageVolume"),
            "fifty_two_week_high": info.get("fiftyTwoWeekHigh"),
            "fifty_two_week_low": info.get("fiftyTwoWeekLow"),
            # ETF-specific
            "expense_ratio": info.get("annualReportExpenseRatio"),
            "yield_pct": info.get("yield"),
            "category": info.get("category") or info.get("legalType"),
            "fund_family": info.get("fundFamily"),
            "nav_price": info.get("navPrice"),
            "beta_3yr": info.get("beta3Year"),
            "ytd_return": info.get("ytdReturn"),
            "three_yr_return": info.get("threeYearAverageReturn"),
        }
    except Exception as e:
        print(f"    WARN: {yahoo_sym}: {e}")
        return {}


def compute_data_stats(ticker: str, dataset: str, data_dir: Path) -> dict:
    """Compute start_date, end_date, total_obs, missing_pct from existing Parquet."""
    file_map = {
        "equity_daily": "yfinance_equity.parquet",
        "crypto_daily": "crypto_all.parquet",
    }
    fpath = data_dir / file_map.get(dataset, "")
    if not fpath.exists():
        return {}

    df = pq.read_table(fpath, columns=["date", "ticker", "volume"]).to_pandas()
    sub = df[df["ticker"] == ticker]
    if len(sub) == 0:
        return {}

    start = sub["date"].min()
    end = sub["date"].max()
    total = len(sub)

    # Expected trading days (approximate: 252/year for equity, 365 for crypto)
    days_span = (end - start).days
    if dataset == "crypto_daily":
        expected = days_span  # crypto trades every day
    else:
        expected = int(days_span * 252 / 365)  # approximate trading days

    missing_pct = round(100 * (1 - total / max(expected, 1)), 1) if expected > 0 else 0.0

    return {
        "start_date": start,
        "end_date": end,
        "total_obs": total,
        "missing_pct": max(missing_pct, 0.0),
    }


def main():
    data_dir = Path("data/raw")
    output_dir = data_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    total = sum(len(v) for v in DATASETS.values())
    i = 0

    for dataset, tickers in DATASETS.items():
        print(f"\n=== {dataset} ({len(tickers)} tickers) ===")
        for ticker in tickers:
            i += 1
            ysym = yahoo_ticker(ticker, dataset)
            print(f"  [{i}/{total}] {ticker} ({ysym})...", end=" ", flush=True)

            info = fetch_yahoo_info(ysym)
            stats = compute_data_stats(ticker, dataset, data_dir)

            row = {
                "ticker": ticker,
                "dataset": dataset,
                "long_name": info.get("long_name", ""),
                "exchange": info.get("exchange", ""),
                "full_exchange": info.get("full_exchange", ""),
                "currency": info.get("currency", "USD"),
                "instrument_type": info.get("instrument_type", ""),
                "sector": info.get("sector"),
                "industry": info.get("industry"),
                "country": info.get("country"),
                "market_cap": info.get("market_cap"),
                "volume_avg": info.get("volume_avg"),
                "fifty_two_week_high": info.get("fifty_two_week_high"),
                "fifty_two_week_low": info.get("fifty_two_week_low"),
                "expense_ratio": info.get("expense_ratio"),
                "yield_pct": info.get("yield_pct"),
                "category": info.get("category"),
                "fund_family": info.get("fund_family"),
                "nav_price": info.get("nav_price"),
                "beta_3yr": info.get("beta_3yr"),
                "ytd_return": info.get("ytd_return"),
                "three_yr_return": info.get("three_yr_return"),
                "start_date": stats.get("start_date"),
                "end_date": stats.get("end_date"),
                "total_obs": stats.get("total_obs"),
                "missing_pct": stats.get("missing_pct"),
            }
            rows.append(row)
            print(f"{info.get('long_name', '?')[:30]} | {info.get('sector', '-')}")
            time.sleep(0.3)

    df = pd.DataFrame(rows)
    # Ensure date columns are proper dates (not mixed types)
    for col in ["start_date", "end_date"]:
        df[col] = pd.to_datetime(df[col]).dt.date
    # Ensure numeric columns
    for col in ["market_cap", "volume_avg", "fifty_two_week_high", "fifty_two_week_low",
                 "missing_pct", "expense_ratio", "yield_pct", "nav_price",
                 "beta_3yr", "ytd_return", "three_yr_return"]:
        df[col] = pd.to_numeric(df[col], errors="coerce")
    df["total_obs"] = pd.to_numeric(df["total_obs"], errors="coerce").astype("Int64")

    out_path = output_dir / "metadata.parquet"
    pq.write_table(pa.Table.from_pandas(df), out_path, compression="zstd")

    print(f"\n=== Summary ===")
    print(f"Tickers: {len(df)}")
    print(f"Datasets: {df['dataset'].nunique()}")
    print(f"With sector: {df['sector'].notna().sum()}")
    print(f"With market_cap: {df['market_cap'].notna().sum()}")
    print(f"File: {out_path} ({out_path.stat().st_size / 1e3:.0f} KB)")


if __name__ == "__main__":
    main()
