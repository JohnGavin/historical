# hd_structural_breaks: non-numeric input aborts with structured cli message

    Code
      hd_structural_breaks("not_a_vector")
    Condition
      Error in `hd_structural_breaks()`:
      x `returns` must be a numeric vector.
      i Got <character>, not numeric.

# hd_structural_breaks: NA values abort with structured cli message

    Code
      hd_structural_breaks(c(0.01, NA_real_, 0.02))
    Condition
      Error in `hd_structural_breaks()`:
      x `returns` must not contain `NA` values.
      i Strip NAs before calling: `returns[!is.na(returns)]`.
      i Found 1 NA in a vector of length 3.

# hd_structural_breaks: alpha out of (0,1) aborts with structured cli message

    Code
      hd_structural_breaks(r, alpha = 1.5)
    Condition
      Error in `hd_structural_breaks()`:
      x `alpha` must be a single numeric value in (0, 1).
      i Typical values: 0.01, 0.05, 0.10.

# hd_structural_breaks: non-positive min_years aborts

    Code
      hd_structural_breaks(r, min_years = 0)
    Condition
      Error in `hd_structural_breaks()`:
      x `min_years` must be a positive numeric scalar.
      i Got 0.

# hd_structural_breaks: multiple_testing_note is a non-empty string

    Code
      cat(result$multiple_testing_note)
    Output
      Scanning all candidate split dates inflates the false-break rate above the nominal alpha (0.01). Treat breaks as evidence requiring further investigation, not as grounds for immediate re-estimation (see resulting-prohibition rule).

# structural_breaks_caption: format is stable (snapshot)

    Code
      cat(caption)
    Output
      Structural break analysis (Carver 2026): 1 of 7 strategies show at least one structural break at the 1% significance level. 0 show a material post-break Sharpe divergence (>25% from whole-history Sharpe). Breaks are detected using an iterative forward-split t-test on vol-normalised returns with a minimum segment of 5 years. Per the resulting-prohibition rule, a detected break is evidence requiring investigation — not a signal to revise strategy allocation. Per Carver's own finding, 'no break' often wins OOS: break-splitting is a guard against over-splitting, not an always-on re-estimator. Multiple-testing note: scanning all candidate split dates inflates the false-break rate above the nominal 1% level.

