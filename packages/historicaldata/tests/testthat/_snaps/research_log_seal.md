# re-sealing an already-sealed row is refused by default

    Code
      reseal <- hd_rlog_seal(sealed, sealed_at = FIXED_TIME)
    Message
      i 1 row already sealed; leaving untouched.
      i Pass `overwrite = TRUE` only if you intend to break the existing commitment.

# sealing refuses rows missing a claim field

    Code
      hd_rlog_seal(h)
    Condition
      Error in `hd_rlog_seal()`:
      x Cannot seal: missing field null_hypothesis.
      i Sealing requires all of: uuid, economic_claim, dependent_var, predictor, sample_spec, and null_hypothesis.

# verification detects a reworded claim

    Code
      res <- hd_rlog_seal_verify(sealed)
    Condition
      Warning:
      x 1 sealed hypothesis no longer matches its hash.
      i First mismatch: uuid "uuid-02".
      i A claim was edited after sealing. Recover the original from git history rather than resealing.

# strict verification aborts on mismatch

    Code
      hd_rlog_seal_verify(sealed, strict = TRUE)
    Condition
      Error in `hd_rlog_seal_verify()`:
      x 1 sealed hypothesis no longer matches its hash.
      i First mismatch: uuid "uuid-01".
      i A claim was edited after sealing. Recover the original from git history rather than resealing.

# verification refuses rows with no commit_hash column

    Code
      hd_rlog_seal_verify(rows)
    Condition
      Error in `hd_rlog_seal_verify()`:
      x No commit_hash column — these rows were never sealed.
      i Seal them with `hd_rlog_seal()` before verifying.

# sealing function signatures are stable

    Code
      args(hd_rlog_seal)
    Output
      function (rows, method = "sha256-v1", sealed_at = Sys.time(), 
          overwrite = FALSE) 
      NULL

---

    Code
      args(hd_rlog_seal_verify)
    Output
      function (rows, strict = FALSE) 
      NULL

---

    Code
      args(hd_rlog_seal_export)
    Output
      function (base_dir = NULL, out_path = file.path(tempdir(), "hypothesis_seals.parquet"), 
          repo_id = "JohnGavin/historical-research-log") 
      NULL

