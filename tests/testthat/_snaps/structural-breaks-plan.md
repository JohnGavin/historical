# structural_breaks_caption: format is stable (snapshot)

    Code
      cat(caption)
    Output
      Structural break analysis (Carver 2026): 1 of 7 strategies show at least one structural break at the 1% significance level. 0 show a material post-break Sharpe divergence (>25% from whole-history Sharpe). Breaks are detected using an iterative forward-split t-test on vol-normalised returns with a minimum segment of 5 years. Per the resulting-prohibition rule, a detected break is evidence requiring investigation — not a signal to revise strategy allocation. Per Carver's own finding, 'no break' often wins OOS: break-splitting is a guard against over-splitting, not an always-on re-estimator. Multiple-testing note: scanning all candidate split dates inflates the false-break rate above the nominal 1% level.

