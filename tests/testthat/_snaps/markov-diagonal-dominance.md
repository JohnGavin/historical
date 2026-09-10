# check_markov_diagonal_dominance throws when a state persists no better than chance

    Code
      check_markov_diagonal_dominance(noisy)
    Condition
      Error in `check_markov_diagonal_dominance()`:
      x 3 state(s) in noisy show no better persistence than a 1/3 random baseline (0.333) -- the classifier is not detecting real persistence for these state(s) (S32, #838):
      i  benign -- p_stay = 0.000 (baseline = 0.333, n_from = 10)
      i  cautious -- p_stay = 0.000 (baseline = 0.333, n_from = 10)
      i  hostile -- p_stay = 0.000 (baseline = 0.333, n_from = 9)

