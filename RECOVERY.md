# RECOVERY.md — Non-Reproducible State

This file documents state in this project that **cannot be regenerated** from
`git` history plus a deterministic pipeline (`tar_make`, `nix develop`, etc.).
See the `backup-architecture` rule for the design rationale.

---

## 1. Research-Log Parquet Store

### What it is

An append-only typed parquet store recording the full lineage of research
experiments: hypotheses, implementations, results, critiques, and robustness
panels.  Each row represents a discrete experiment step and carries a UUID,
parent UUID, git commit SHA, and environment hash.

This log is the single source of truth for _why_ particular strategies were
tested, what parameters were used, what the results were, and what critiques
were raised.  It cannot be regenerated from code: the rows are written once
during live research sessions and the historical sequence of decisions is not
reproducible.

### Location

```
packages/historicaldata/inst/extdata/research_log/
  hypotheses/          one parquet file per append call
  implementations/
  results/
  critiques/
  robustness/
```

### Format

Apache Parquet, `compression = "zstd"`.  One file per `hd_rlog_append()` call,
named `<uuid>_<timestamp>.parquet`.  Append-only; rows are never updated
in-place.

### Failure domain

The parquet files live **inside the git repository** (`inst/extdata/`), so the
primary recovery path is git history.  For additional protection, maintain a
copy in a **different failure domain** (different machine or cloud storage
account).  Do not rely on the same disk or git remote as the sole backup.

### RPO / RTO

| Metric | Target |
|--------|--------|
| RPO (Recovery Point Objective) | Last git commit (git-tracked) |
| RTO (Recovery Time Objective) | Minutes (git clone + `hd_rlog_query`) |

### Backup copies

| Copy | Location | Retention |
|------|----------|-----------|
| Primary | `inst/extdata/research_log/` in the git repo | Indefinite |
| Cross-domain | [TO BE CONFIGURED — e.g. external drive or cloud storage outside this git remote] | [TO BE CONFIGURED] |

Update this table when a cross-domain backup destination is established.

### Restore steps

1. Confirm you have a complete clone of the repository:

   ```bash
   git -C <repo> log --oneline -5
   ```

2. Verify the research-log directory exists:

   ```bash
   ls <repo>/packages/historicaldata/inst/extdata/research_log/
   ```

3. If the directory is missing or corrupted, restore from git:

   ```bash
   git -C <repo> checkout HEAD -- packages/historicaldata/inst/extdata/research_log/
   ```

4. If files are missing beyond HEAD (e.g. accidental `git rm`), find the
   last commit that touched them and restore:

   ```bash
   git -C <repo> log --all -- "packages/historicaldata/inst/extdata/research_log/**"
   git -C <repo> checkout <commit-sha> -- packages/historicaldata/inst/extdata/research_log/
   ```

5. If recovering from a cross-domain backup copy, place the files under
   `packages/historicaldata/inst/extdata/research_log/<table>/` and
   verify each table loads:

   ```r
   # In R with the package loaded:
   hd_rlog_query("hypotheses")
   hd_rlog_query("implementations")
   hd_rlog_query("results")
   hd_rlog_query("critiques")
   hd_rlog_query("robustness")
   ```

### Verification step

After restore, confirm row counts are plausible and no errors are raised:

```r
for (tbl in hd_rlog_tables()) {
  rows <- hd_rlog_query(tbl)
  message(tbl, ": ", nrow(rows), " rows")
}
```

Compare output against the last known row counts from `CHANGELOG.md` or
previous research notes.

### Owner and last drill date

| Field | Value |
|-------|-------|
| Owner | John Gavin |
| Last restore drill | [NOT YET DRILLED] |

---

## 2. Results Database Parquet Store

### What it is

Strategy back-test results written by `hd_results_append()`.  Stored under
`packages/historicaldata/inst/extdata/results/`.  One parquet file per day,
deduped on `(strategy_id, partition)`.

### Reproducibility

Results are **partially reproducible** if the strategy code and data are
intact.  However, re-running back-tests is time-consuming and the exact
market data snapshots may drift.  Treat as non-reproducible for recovery
planning purposes.

### Recovery

Same as the research-log store above: restore from git history or a
cross-domain backup copy, then verify with `hd_results_query()`.

---

*No secrets in this file.  Credentials are stored in `.Renviron` (gitignored).*
