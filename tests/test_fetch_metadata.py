"""Regression tests for fetch_metadata._yield_fields().

Covers the trailingAnnualDividendYield = 0.0 edge case (historical#233):
truthiness checks (`if yield_value:`) treat 0.0 as absent; the fix requires
`is not None` so that a genuine zero trailing yield is preserved and tagged
correctly as "trailing" rather than falling through to the raw `yield` field.
"""

import sys
from pathlib import Path

# Allow running from repo root or from tests/
sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from fetch_metadata import _yield_fields


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
