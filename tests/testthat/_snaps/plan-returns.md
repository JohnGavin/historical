# plan_returns: function signature is stable (API drift guard)

    Code
      args(plan_returns)
    Output
      function () 
      NULL

# cov_annual: structure snapshot with canonical 4-asset universe

    Code
      list(dim = dim(Sigma), rownames = rownames(Sigma), colnames = colnames(Sigma),
      diag_sign = sign(diag(Sigma)), is_matrix = is.matrix(Sigma))
    Output
      $dim
      [1] 4 4
      
      $rownames
      [1] "SPY" "TLT" "GLD" "DBC"
      
      $colnames
      [1] "SPY" "TLT" "GLD" "DBC"
      
      $diag_sign
      SPY TLT GLD DBC 
        1   1   1   1 
      
      $is_matrix
      [1] TRUE
      

