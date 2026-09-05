# mu: must be a single non-missing number

    Code
      hd_first_passage(mu = "x", sigma = 0.02, upper = 0.1)
    Condition
      Error in `hd_first_passage()`:
      x `mu` must be a single non-missing number.
      i Got "x".

---

    Code
      hd_first_passage(mu = NA_real_, sigma = 0.02, upper = 0.1)
    Condition
      Error in `hd_first_passage()`:
      x `mu` must be a single non-missing number.
      i Got NA.

---

    Code
      hd_first_passage(mu = c(0.001, 0.002), sigma = 0.02, upper = 0.1)
    Condition
      Error in `hd_first_passage()`:
      x `mu` must be a single non-missing number.
      i Got 0.001 and 0.002.

# sigma: must be a single positive number

    Code
      hd_first_passage(mu = 0.001, sigma = -0.02, upper = 0.1)
    Condition
      Error in `hd_first_passage()`:
      x `sigma` must be a single positive number.
      i Got -0.02.

---

    Code
      hd_first_passage(mu = 0.001, sigma = 0, upper = 0.1)
    Condition
      Error in `hd_first_passage()`:
      x `sigma` must be a single positive number.
      i Got 0.

# upper: must be a single positive number

    Code
      hd_first_passage(mu = 0.001, sigma = 0.02, upper = -0.1)
    Condition
      Error in `hd_first_passage()`:
      x `upper` must be a single positive number.
      i Got -0.1.

---

    Code
      hd_first_passage(mu = 0.001, sigma = 0.02, upper = 0)
    Condition
      Error in `hd_first_passage()`:
      x `upper` must be a single positive number.
      i Got 0.

# lower: must be a single positive number

    Code
      hd_first_passage(mu = 0.001, sigma = 0.02, upper = 0.1, lower = -0.05)
    Condition
      Error in `hd_first_passage()`:
      x `lower` must be a single positive number.
      i Got -0.05.

# function signature is stable (catches API drift)

    Code
      args(hd_first_passage)
    Output
      function (mu, sigma, upper, lower = upper) 
      NULL

