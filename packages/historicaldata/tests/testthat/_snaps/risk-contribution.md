# non-square cov_mat aborts with informative error

    Code
      hd_risk_contribution(c(0.5, 0.5), matrix(1:6, nrow = 2))
    Condition
      Error in `hd_risk_contribution()`:
      ! `cov_mat` must be square.
      x Got 2 rows and 3 columns.

# asymmetric cov_mat aborts with informative error

    Code
      hd_risk_contribution(c(0.5, 0.5), Sigma)
    Condition
      Error in `hd_risk_contribution()`:
      ! `cov_mat` must be symmetric.
      x Max asymmetry: 0.03.

# dimension mismatch between w and cov_mat aborts with informative error

    Code
      hd_risk_contribution(c(0.5, 0.3, 0.2), Sigma)
    Condition
      Error in `hd_risk_contribution()`:
      ! `cov_mat` dimensions must match `w`.
      x `w` has length 3; `cov_mat` is 2 x 2.

# disagreeing names between w and cov_mat abort with informative error

    Code
      hd_risk_contribution(w, Sigma)
    Condition
      Error in `hd_risk_contribution()`:
      ! `w` and `cov_mat` names disagree.
      x `names(w)`: "X" and "Y".
      x `colnames(cov_mat)`: "A" and "B".
      i Reorder upstream so the two agree; this function will not guess the correct alignment.

# NA in w aborts with informative error

    Code
      hd_risk_contribution(c(0.5, NA_real_), Sigma)
    Condition
      Error in `hd_risk_contribution()`:
      ! `w` must not contain "NA" or "NaN".
      i Found 1 missing value at position 2.
      i Resolve missingness upstream; `hd_risk_contribution()` does not `na.rm`.

# function signature is stable (catches API drift)

    Code
      args(hd_risk_contribution)
    Output
      function (w, cov_mat) 
      NULL

