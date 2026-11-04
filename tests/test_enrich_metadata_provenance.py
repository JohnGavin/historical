"""Tests for the #865 provenance helpers used by enrich_metadata.py.

enrich_metadata.py merges computed returns onto the CURRENT metadata snapshot
with ``on="ticker"`` alone. Tickers are recycled (#865), so the amendments
log must say which snapshot the join used and that the key has no cik; a
ticker occurring twice in the snapshot is the symptom and must be reported.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from metadata_helpers import duplicated_tickers, with_snapshot_provenance


class TestWithSnapshotProvenance:
    def test_appends_key_and_as_of_to_method(self):
        out = with_snapshot_provenance("beta=cov/var", "2026-11-04")
        assert out.startswith("beta=cov/var")
        assert "join_key=ticker (no cik)" in out
        assert "metadata_snapshot_as_of=2026-11-04" in out
        assert "#865" in out and "#816" in out

    def test_empty_method_still_carries_provenance(self):
        out = with_snapshot_provenance("", "2026-11-04")
        assert "metadata_snapshot_as_of=2026-11-04" in out

    def test_rejects_malformed_as_of(self):
        for bad in ["", "04/11/2026", "2026-13-40", None]:
            try:
                with_snapshot_provenance("m", bad)
            except ValueError as e:
                assert "as_of" in str(e)
            else:
                raise AssertionError(f"accepted bad as_of {bad!r}")


class TestDuplicatedTickers:
    def test_none_when_unique(self):
        assert duplicated_tickers(["AAA", "BBB", "CCC"]) == []

    def test_reports_each_duplicate_once_sorted(self):
        assert duplicated_tickers(["BBB", "AAA", "BBB", "AAA", "BBB", "CCC"]) == ["AAA", "BBB"]

    def test_empty(self):
        assert duplicated_tickers([]) == []
