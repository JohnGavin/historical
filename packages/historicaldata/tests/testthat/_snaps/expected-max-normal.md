# invalid K aborts with an informative message

    Code
      hd_expected_max_normal(0.5)
    Condition
      Error in `hd_expected_max_normal()`:
      x `K` must be at least 1.
      i Got 0.5.

---

    Code
      hd_expected_max_normal(0)
    Condition
      Error in `hd_expected_max_normal()`:
      x `K` must be at least 1.
      i Got 0.

---

    Code
      hd_expected_max_normal(NA_real_)
    Condition
      Error in `hd_expected_max_normal()`:
      x `K` must be a single finite number.
      i Got NA.

---

    Code
      hd_expected_max_normal(Inf)
    Condition
      Error in `hd_expected_max_normal()`:
      x `K` must be a single finite number.
      i Got Inf.

---

    Code
      hd_expected_max_normal("10")
    Condition
      Error in `hd_expected_max_normal()`:
      x `K` must be a single finite number.
      i Got "10".

---

    Code
      hd_expected_max_normal(c(2, 3))
    Condition
      Error in `hd_expected_max_normal()`:
      x `K` must be a single finite number.
      i Got 2 and 3.

# function signature is stable

    Code
      args(hd_expected_max_normal)
    Output
      function (K) 
      NULL

