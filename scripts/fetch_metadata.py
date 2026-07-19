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

# Ensure metadata_helpers is importable regardless of invocation mode:
#   python scripts/fetch_metadata.py   → scripts/ not on sys.path by default
#   python -m scripts.fetch_metadata   → relative import would fail at top-level
# Inserting the script's own directory supports both modes.
_scripts_dir = str(Path(__file__).parent)
if _scripts_dir not in sys.path:
    sys.path.insert(0, _scripts_dir)

from metadata_helpers import (  # noqa: E402
    _expected_trading_days,
    _missing_pct,
    _yield_fields,
    first_present,
)

# US equity tickers
# SYNC NOTE: when fetch_equity.py DEFAULT_TICKERS changes, update this list too.
# Missing tickers caught by qa_metadata_sync (issue #489).
US_EQUITY = [
    "AAPL", "MSFT", "GOOGL", "AMZN", "META", "NVDA", "TSLA",
    "AMD", "INTC", "AVGO", "QCOM",
    "CRM", "ORCL", "ADBE", "NOW",
    "JPM", "BAC", "GS", "MS", "V", "MA",
    "JNJ", "UNH", "PFE", "ABBV", "MRK",
    "WMT", "COST", "HD", "MCD", "KO", "PEP",
    "CAT", "BA", "GE", "HON", "UPS",
    # Energy — APA added to match equity parquet (#489)
    "XOM", "CVX", "COP", "APA",
    "DIS", "NFLX", "CMCSA", "T",
    "PLD", "AMT",
    "SPY", "QQQ", "IWM", "DIA",
    "VIXY",
    # Healthcare — BDX added to match equity parquet (#489)
    "BDX",
    # Technology — CDW added to match equity parquet (#489)
    "CDW",
    # Industrials — ETN added to match equity parquet (#489)
    "ETN",
]

# European equities present in equity_daily parquet but NOT in LSE ETF list.
# These come from fetch_equity.py --stoxx600 runs. Add here to keep metadata
# in sync with OHLCV (#489). Note: volume for these tickers is unreliable in
# yfinance (non-US exchange suffixes) and is nulled on read by hd_ohlcv()
# and hd_unreliable_volume_ticker().
EUROPEAN_EQUITIES = [
    "GN.CO",    # GN Group — Nasdaq Copenhagen (Denmark)
    "SEB-A.ST", # SEB Bank — Nasdaq Stockholm (Sweden)
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
    """Build DATASETS dict including LSE tickers and European equities."""
    lse = load_lse_tickers()
    equity = US_EQUITY + lse + EUROPEAN_EQUITIES
    print(
        f"Equity tickers: {len(US_EQUITY)} US + {len(lse)} LSE"
        f" + {len(EUROPEAN_EQUITIES)} European = {len(equity)}"
    )
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
            # Yield: trailingAnnualDividendYield wins when present (including 0.0);
            # only fall through to `yield` when trailing is None (#646 #667 #3113).
            # yield_type is derived from the same source as yield_pct so the two
            # fields always agree — 0.20 threshold for "synthetic" only applies
            # when `yield` is the chosen source, never when trailing is present.
            **_yield_fields(info),
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
    """Compute start_date, end_date, total_obs, missing_pct from existing Parquet.

    missing_pct means: "of the dates on which some ticker in this dataset has
    an observation between this ticker's own start and end date, what
    fraction is this ticker missing?" It is a data-derived proxy for the true
    exchange trading calendar (see _expected_trading_days() in
    metadata_helpers.py, historical#569), not a fixed 252/365 ratio.

    LIMITATION: for a single-ticker dataset, missing_pct is 0 for every
    ticker by construction (there is no other ticker's calendar to compare
    against) — see _expected_trading_days() docstring.
    """
    file_map = {
        "equity_daily": "yfinance_equity.parquet",
        "crypto_daily": "crypto_all.parquet",
    }
    fpath = data_dir / file_map.get(dataset, "")
    if not fpath.exists():
        return {}

    # Empty parquet (0 rows total) falls through to the len(sub) == 0 check
    # below via an empty `sub`, same as a missing/unmatched ticker.
    df = pq.read_table(fpath, columns=["date", "ticker", "volume"]).to_pandas()
    sub = df[df["ticker"] == ticker]
    if len(sub) == 0:
        return {}

    start = sub["date"].min()
    end = sub["date"].max()
    total = len(sub)
    days_span = (end - start).days  # may be 0 for a single-observation ticker

    expected = _expected_trading_days(dataset, df["date"], start, end, days_span)
    missing_pct = _missing_pct(total, expected)

    return {
        "start_date": start,
        "end_date": end,
        "total_obs": total,
        "missing_pct": missing_pct,
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
                "yield_type": info.get("yield_type"),
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
