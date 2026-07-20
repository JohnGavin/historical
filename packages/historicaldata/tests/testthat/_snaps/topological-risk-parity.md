# hrp_weights: weights sum to 1 (5-asset)

    Code
      args(hrp_weights)
    Output
      function (cov_mat, method = "complete") 
      NULL

# hrp_weights: error on non-matrix input

    Code
      hrp_weights(list(a = 1))
    Condition
      Error in `.validate_cov_input()`:
      x `cov_mat` must be a matrix.
      i Got <list>.

# hrp_weights: error on non-square matrix

    Code
      hrp_weights(m)
    Condition
      Error in `.validate_cov_input()`:
      x `cov_mat` must be square.
      i Got 2 x 3.

# hrp_weights: error on unnamed matrix

    Code
      hrp_weights(m)
    Condition
      Error in `.validate_cov_input()`:
      x `cov_mat` must have named rows and columns.
      i Set `rownames(cov_mat)` and `colnames(cov_mat)`.

# hrp_weights: error on mismatched row/col names

    Code
      hrp_weights(m)
    Condition
      Error in `.validate_cov_input()`:
      x Row names and column names of `cov_mat` must be identical.
      i Found mismatched row/column names.

# hrp_weights: error on single-asset matrix

    Code
      hrp_weights(m)
    Condition
      Error in `.validate_cov_input()`:
      x `cov_mat` must have at least 2 assets.
      i Got 1 asset(s).

# trp_weights: error on non-matrix input

    Code
      trp_weights(data.frame(a = 1))
    Condition
      Error in `.validate_cov_input()`:
      x `cov_mat` must be a matrix.
      i Got <data.frame>.

