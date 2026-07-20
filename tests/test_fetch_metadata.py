"""Regression tests for fetch_metadata._yield_fields() and related helpers.

Covers the trailingAnnualDividendYield = 0.0 edge case (historical#233):
truthiness checks (`if yield_value:`) treat 0.0 as absent; the fix requires
`is not None` so that a genuine zero trailing yield is preserved and tagged
correctly as "trailing" rather than falling through to the raw `yield` field.

Also covers _expected_trading_days() / _missing_pct() (historical#569): the
old missing_pct calculation used a hand-entered 252/365 ratio to approximate
trading days; the fix derives the expected calendar from the dataset itself.
"""

import sys
from datetime import date
from pathlib import Path

# Allow running from repo root or from tests/
# Import from the dep-free helper module so pytest collection does not trigger
# pandas/pyarrow/yfinance imports or the DATASETS = build_datasets() side
# effect that lives at the top level of fetch_metadata.py.
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from metadata_helpers import _expected_trading_days, _missing_pct, _yield_fields


class TestYieldFields:
    """Regression tests for _yield_fields() (historical#233)."""

    # --- trailingAnnualDividendYield present ---

    def test_trailing_nonzero_returns_trailing_type(self):
        """Normal non-zero trailing yield — canonical happy path."""
        result = _yield_fields({"trailingAnnualDividendYield": 0.025})
        assert result["yield_pct"] == 0.025
        assert result["yield_type"] == "trailing"

    def test_trailing_zero_returns_trailing_type(self):
        """Zero trailing yield must be treated as present, not absent (closes #233).

        Before the fix, `if trailing:` evaluated False for 0.0, causing
        fall-through to the raw `yield` branch and an inconsistent yield_type.
        """
        result = _yield_fields({"trailingAnnualDividendYield": 0.0})
        assert result["yield_pct"] == 0.0
        assert result["yield_type"] == "trailing"

    def test_trailing_zero_overrides_raw_yield(self):
        """When trailing=0.0 is present, raw yield must be ignored.

        Confirms yield_pct and yield_type remain consistent with each other
        rather than yield_pct=0.0 (trailing) and yield_type='reported'|'synthetic'
        (from raw yield branch).
        """
        result = _yield_fields({
            "trailingAnnualDividendYield": 0.0,
            "yield": 0.25,
        })
        assert result["yield_pct"] == 0.0, "trailing=0.0 must take precedence over raw yield"
        assert result["yield_type"] == "trailing", "yield_type must match the chosen source"

    # --- only raw yield present ---

    def test_raw_yield_reported(self):
        """Raw yield <= 0.20 is classified as 'reported'."""
        result = _yield_fields({"yield": 0.05})
        assert result["yield_pct"] == 0.05
        assert result["yield_type"] == "reported"

    def test_raw_yield_synthetic(self):
        """Raw yield > 0.20 is classified as 'synthetic'."""
        result = _yield_fields({"yield": 0.21})
        assert result["yield_pct"] == 0.21
        assert result["yield_type"] == "synthetic"

    def test_raw_yield_zero_returns_reported_type(self):
        """Zero raw yield (no trailing present) is classified as 'reported'."""
        result = _yield_fields({"yield": 0.0})
        assert result["yield_pct"] == 0.0
        assert result["yield_type"] == "reported"

    # --- neither present ---

    def test_no_yield_fields_returns_none(self):
        """Empty info dict returns both fields as None."""
        result = _yield_fields({})
        assert result["yield_pct"] is None
        assert result["yield_type"] is None

    def test_none_trailing_falls_through_to_raw(self):
        """Explicit None for trailing must fall through to raw yield."""
        result = _yield_fields({
            "trailingAnnualDividendYield": None,
            "yield": 0.03,
        })
        assert result["yield_pct"] == 0.03
        assert result["yield_type"] == "reported"


class TestExpectedTradingDays:
    """Regression tests for _expected_trading_days() (historical#569).

    Replaces the old hand-entered 252/365 ratio with a calendar derived from
    the dataset's own observed dates.
    """

    def test_multi_ticker_uses_union_calendar(self):
        """Expected days = distinct dates across ALL tickers within [start, end].

        Ticker A trades Jan 2-4; ticker B additionally trades Jan 5. The
        union calendar for the window Jan2-Jan5 is 4 distinct days, even
        though any single ticker only contributes 3 observations.
        """
        all_dates = [
            date(2024, 1, 2), date(2024, 1, 3), date(2024, 1, 4),  # ticker A
            date(2024, 1, 2), date(2024, 1, 3), date(2024, 1, 4), date(2024, 1, 5),  # ticker B
        ]
        result = _expected_trading_days(
            "equity_daily", all_dates, date(2024, 1, 2), date(2024, 1, 5), days_span=3
        )
        assert result == 4

    def test_single_ticker_dataset_equals_own_dates(self):
        """LIMITATION: with only one ticker in the dataset, the union calendar
        reduces to that ticker's own dates, so missing_pct is 0 by
        construction — a real gap (Jan 4 missing here) is invisible.
        """
        own_dates = [date(2024, 1, 2), date(2024, 1, 3), date(2024, 1, 5)]  # gap on Jan 4
        result = _expected_trading_days(
            "equity_daily", own_dates, date(2024, 1, 2), date(2024, 1, 5), days_span=3
        )
        assert result == len(own_dates) == 3

    def test_empty_calendar_returns_zero(self):
        """No dates at all (e.g. empty dataset) yields an expected count of 0."""
        result = _expected_trading_days(
            "equity_daily", [], date(2024, 1, 2), date(2024, 1, 5), days_span=3
        )
        assert result == 0

    def test_zero_span_single_observation(self):
        """A single-observation ticker (start == end, days_span == 0) still
        counts its own date within the window."""
        all_dates = [date(2024, 1, 2)]
        result = _expected_trading_days(
            "equity_daily", all_dates, date(2024, 1, 2), date(2024, 1, 2), days_span=0
        )
        assert result == 1

    def test_crypto_branch_uses_days_span_ignoring_calendar(self):
        """Crypto trades every calendar day: expected == days_span regardless
        of what all_dates contains (deliberately mismatched here)."""
        result = _expected_trading_days(
            "crypto_daily", [], date(2024, 1, 1), date(2024, 1, 11), days_span=10
        )
        assert result == 10

    def test_crypto_zero_span_returns_zero(self):
        """Crypto with a zero-day span returns 0 (single observation)."""
        result = _expected_trading_days(
            "crypto_daily", [], date(2024, 1, 2), date(2024, 1, 2), days_span=0
        )
        assert result == 0


class TestMissingPct:
    """Regression tests for _missing_pct() (historical#569)."""

    def test_normal_case(self):
        assert _missing_pct(total=18, expected=20) == 10.0

    def test_no_missing_days(self):
        assert _missing_pct(total=20, expected=20) == 0.0

    def test_zero_expected_returns_zero_not_error(self):
        """expected <= 0 (e.g. zero-length calendar) must not raise
        ZeroDivisionError; it is treated as 'cannot estimate' → 0.0."""
        assert _missing_pct(total=5, expected=0) == 0.0

    def test_negative_expected_returns_zero(self):
        assert _missing_pct(total=5, expected=-1) == 0.0

    def test_floors_at_zero_when_total_exceeds_expected(self):
        """A ticker cannot have negative missing_pct even if its own total
        exceeds the union-calendar expected count (e.g. duplicate rows)."""
        assert _missing_pct(total=25, expected=20) == 0.0
