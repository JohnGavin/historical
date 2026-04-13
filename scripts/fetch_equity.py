"""Fetch equity daily OHLCV via yfinance batch download.

Downloads full history for all tickers in a single yf.download() call
(yfinance handles internal parallelism and rate limiting).

Usage:
    python scripts/fetch_equity.py                    # All US default tickers
    python scripts/fetch_equity.py --lse              # Add ~929 LSE ETFs
    python scripts/fetch_equity.py --lse --batch-size 50  # LSE in batches of 50
    python scripts/fetch_equity.py --sp500             # Add ~500 S&P 500 tickers
    python scripts/fetch_equity.py --stoxx600          # Add ~150 STOXX Europe 600 majors
    python scripts/fetch_equity.py AAPL MSFT GOOGL     # Specific tickers
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

# Major US stocks + ETFs + macro hedge ETFs
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
    # REITs
    "PLD", "AMT",
    # US index ETFs
    "SPY", "QQQ", "IWM", "DIA",
    # Volatility
    "VIXY",
    # === Defense First rotation strategy ETFs ===
    "TLT",   # Long-duration Treasuries (deflation hedge)
    "GLD",   # Gold (monetary instability hedge)
    "DBC",   # Broad commodities (stagflation hedge)
    "UUP",   # US dollar index (global stress hedge)
    # === Extended macro ETFs (cross-checking / alternatives) ===
    "IEF",   # 7-10yr Treasuries (intermediate duration)
    "SHY",   # 1-3yr Treasuries (short duration)
    "TIP",   # TIPS (inflation-protected)
    "IAU",   # Gold (alternative to GLD, lower expense)
    "PDBC",  # Commodities (no K-1 tax form)
    "BIL",   # T-bills (cash proxy)
    "AGG",   # US Aggregate Bond
    "EFA",   # International developed equities
    "EEM",   # Emerging market equities
    # === Factor ETFs (Factor Max strategy) ===
    "VLUE",  # iShares MSCI USA Value Factor (value)
    "MTUM",  # iShares MSCI USA Momentum Factor (momentum)
    "QUAL",  # iShares MSCI USA Quality Factor (quality/profitability)
    "USMV",  # iShares MSCI USA Minimum Volatility (low-vol)
    "SIZE",  # iShares MSCI USA Size Factor (small-cap tilt)
    "VTV",   # Vanguard Value ETF (value, longer history)
    "VUG",   # Vanguard Growth ETF (growth, complement to value)
    "IWD",   # iShares Russell 1000 Value
    "IWF",   # iShares Russell 1000 Growth
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


def load_sp500_tickers() -> list[str]:
    """Load S&P 500 tickers from GitHub datasets repo."""
    import urllib.request, csv, io
    try:
        req = urllib.request.Request(
            "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/main/data/constituents.csv",
            headers={"User-Agent": "Mozilla/5.0"},
        )
        response = urllib.request.urlopen(req, timeout=30)
        reader = csv.DictReader(io.TextIOWrapper(response))
        tickers = [row["Symbol"].replace(".", "-") for row in reader]
        print(f"  Loaded {len(tickers)} S&P 500 tickers from GitHub")
        return tickers
    except Exception as e:
        print(f"  WARNING: Failed to load S&P 500: {e}")
        return []


# Major European stocks with Yahoo Finance exchange suffixes
STOXX600_MAJORS = [
    # Germany (.DE) - DAX 40
    "SAP.DE", "SIE.DE", "ALV.DE", "DTE.DE", "BAS.DE", "MBG.DE", "BMW.DE",
    "MRK.DE", "IFX.DE", "ADS.DE", "MUV2.DE", "HEN3.DE", "BAYN.DE", "VOW3.DE",
    "AIR.DE", "SHL.DE", "DB1.DE", "DPW.DE", "RWE.DE", "FRE.DE", "CON.DE",
    "HEI.DE", "BEI.DE", "ENR.DE", "FME.DE", "SY1.DE", "MTX.DE", "VNA.DE",
    "PUM.DE", "LEG.DE", "QIA.DE", "DTG.DE", "PAH3.DE", "RHM.DE", "DBK.DE", "CBK.DE",
    # France (.PA) - CAC 40
    "MC.PA", "OR.PA", "TTE.PA", "SAN.PA", "AI.PA", "SU.PA", "BN.PA", "CS.PA",
    "AIR.PA", "DG.PA", "BNP.PA", "GLE.PA", "ACA.PA", "CAP.PA", "RI.PA", "DSY.PA",
    "KER.PA", "VIE.PA", "EL.PA", "HO.PA", "EN.PA", "ORA.PA", "SGO.PA", "STM.PA",
    "VIV.PA", "ML.PA", "PUB.PA", "RMS.PA", "LR.PA", "SAF.PA", "CA.PA",
    # Netherlands (.AS)
    "ASML.AS", "SHELL.AS", "UNA.AS", "INGA.AS", "PHIA.AS", "AD.AS", "WKL.AS",
    "HEIA.AS", "ABN.AS", "NN.AS", "RAND.AS", "AKZA.AS", "KPN.AS", "IMCD.AS",
    # Switzerland (.SW)
    "NESN.SW", "ROG.SW", "NOVN.SW", "ZURN.SW", "UBSG.SW", "ABBN.SW", "SREN.SW",
    "GIVN.SW", "LONN.SW", "SGSN.SW", "GEBN.SW", "SLHN.SW", "SCMN.SW", "BALN.SW",
    # Spain (.MC)
    "SAN.MC", "IBE.MC", "ITX.MC", "BBVA.MC", "TEF.MC", "REP.MC", "AMS.MC",
    "FER.MC", "ENG.MC", "IAG.MC",
    # Italy (.MI)
    "ISP.MI", "ENI.MI", "ENEL.MI", "UCG.MI", "G.MI", "STM.MI", "RACE.MI",
    "MONC.MI", "TEN.MI", "MB.MI",
    # Sweden (.ST)
    "VOLV-B.ST", "ERIC-B.ST", "ATCO-A.ST", "SEB-A.ST", "SAND.ST", "ASSA-B.ST",
    "HM-B.ST", "SWED-A.ST", "INVE-B.ST",
    # Denmark (.CO)
    "NOVO-B.CO", "MAERSK-B.CO", "CARL-B.CO", "DSV.CO", "NZYM-B.CO", "VWS.CO",
    "PNDORA.CO", "COLO-B.CO", "ORSTED.CO", "GN.CO",
]


def load_stoxx600_tickers() -> list[str]:
    """Return major STOXX Europe 600 tickers with Yahoo suffixes.

    Covers ~150 of the largest constituents (~70% by market cap).
    Full STOXX 600 constituent list requires a paid data subscription.
    """
    return list(STOXX600_MAJORS)


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

    include_sp500 = False
    include_stoxx600 = False

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--batch-size" and i + 1 < len(args):
            batch_size = int(args[i + 1])
            i += 2
        elif args[i] == "--lse":
            include_lse = True
            i += 1
        elif args[i] == "--sp500":
            include_sp500 = True
            i += 1
        elif args[i] == "--stoxx600":
            include_stoxx600 = True
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
            batch_size = 50

    if include_sp500:
        sp500 = load_sp500_tickers()
        print(f"Adding {len(sp500)} S&P 500 tickers")
        tickers.extend(sp500)
        if batch_size == 0:
            batch_size = 100

    if include_stoxx600:
        stoxx = load_stoxx600_tickers()
        print(f"Adding {len(stoxx)} STOXX 600 tickers")
        tickers.extend(stoxx)
        if batch_size == 0:
            batch_size = 100

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
