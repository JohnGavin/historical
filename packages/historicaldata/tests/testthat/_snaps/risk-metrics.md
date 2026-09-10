# hd_cdap: non-numeric inputs abort with an informative message

    Code
      hd_cdap("not_numeric", -0.1)
    Condition
      Error in `hd_cdap()`:
      x `r` must be a numeric vector.
      i Got <character>.

---

    Code
      hd_cdap(0.1, "not_numeric")
    Condition
      Error in `hd_cdap()`:
      x `d` must be a numeric vector.
      i Got <character>.

# hd_cdap: mismatched vector lengths abort

    Code
      hd_cdap(c(0.1, 0.2, 0.3), c(-0.1, -0.2))
    Condition
      Error in `hd_cdap()`:
      x `r` and `d` must be the same length (or length 1).
      i Got length 3 and 2.

# hd_cdap: sign-behaviour snapshot pins the coherent ordering (#588)

    Code
      cat(paste(sprintf("r=%.2f d=%.2f -> cdap=%s", grid$r, grid$d, out), collapse = "\n"))
    Output
      r=-0.20 d=-0.05 -> cdap=-0.01
      r=-0.10 d=-0.05 -> cdap=-0.005
      r=0.00 d=-0.05 -> cdap=0
      r=0.10 d=-0.05 -> cdap=2
      r=0.20 d=-0.05 -> cdap=4
      r=-0.20 d=-0.10 -> cdap=-0.02
      r=-0.10 d=-0.10 -> cdap=-0.01
      r=0.00 d=-0.10 -> cdap=0
      r=0.10 d=-0.10 -> cdap=1
      r=0.20 d=-0.10 -> cdap=2
      r=-0.20 d=-0.20 -> cdap=-0.04
      r=-0.10 d=-0.20 -> cdap=-0.02
      r=0.00 d=-0.20 -> cdap=0
      r=0.10 d=-0.20 -> cdap=0.5
      r=0.20 d=-0.20 -> cdap=1
      r=-0.20 d=-0.40 -> cdap=-0.08
      r=-0.10 d=-0.40 -> cdap=-0.04
      r=0.00 d=-0.40 -> cdap=0
      r=0.10 d=-0.40 -> cdap=0.25
      r=0.20 d=-0.40 -> cdap=0.5

