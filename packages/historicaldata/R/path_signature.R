# Level-2 path signatures and Lévy area (#605)
#
# Every rolling statistic we compute elsewhere (roll_mean_safe, roll_sd_safe,
# roll_quantile_safe) is permutation-invariant: shuffle the observations inside
# the window and the answer does not change.  So none of them can tell
# "price moved, then volatility expanded" from "volatility expanded, then price
# moved".  The Lévy area can, and it is the cheapest statistic that can.
#
# ── Why there is no dependency here ────────────────────────────────────────
#
# The path-signature ecosystem is Python-only (iisignature, esig, RoughPy,
# signax); there is no CRAN, r-universe or Bioconductor package for rough
# paths.  For a 2-dimensional path truncated at level 2 that does not matter,
# because the shuffle identities collapse the whole tensor to one new number:
#
#     S(i,i)          = S(i)^2 / 2
#     S(1,2) + S(2,1) = S(1) * S(2)
#
# leaving only the antisymmetric part - the Lévy area - as information beyond
# level 1.  Both identities are pinned by tests.  Reach for reticulate +
# iisignature only if we ever need truncation level >= 3 or dimension >= 4.
#
# Reference: Chevyrev & Kormilitzin (2016), "A Primer on the Signature Method
#   in Machine Learning", arXiv:1603.03788.
# Origin: https://delphicalpha.substack.com/p/path-signatures-does-the-shape-of
#   (the post's trading claims do not survive scrutiny; the feature does).

# ── 1. Level-2 signature ────────────────────────────────────────────────────

#' Level-1 and level-2 signature of a piecewise-linear path
#'
#' Computes the truncated signature of a discretely-sampled path treated as
#' piecewise linear between observations. For increments \eqn{\delta_k} with
#' running total \eqn{A_{k-1}} before step \eqn{k}:
#'
#' \deqn{S(i) = \sum_k \delta_k^i}
#' \deqn{S(i,j) = \sum_k \left[ A_{k-1}^i \delta_k^j
#'   + \tfrac{1}{2}\delta_k^i \delta_k^j \right]}
#'
#' @section What is actually new at level 2:
#' The shuffle identities force \eqn{S(i,i) = S(i)^2/2} and
#' \eqn{S(i,j) + S(j,i) = S(i)S(j)}. Every diagonal term and every symmetric
#' part is therefore a function of level 1. For a 2-D path the only new
#' quantity is the antisymmetric part, \code{\link{hd_levy_area}}. Treating
#' \eqn{S(1,1)} or \eqn{S(2,2)} as an independent "acceleration" feature is a
#' mistake: they are half the square of a level-1 term and are strictly
#' non-negative.
#'
#' @param X Numeric matrix or data frame, one row per observation and one
#'   column per path coordinate. These are path **levels**, not increments —
#'   pass \code{cumsum()} of a return series, not the returns.
#'
#' @return A list with \code{S1} (numeric, length \code{ncol(X)}) and
#'   \code{S2} (numeric matrix, \code{ncol(X)} by \code{ncol(X)}, with
#'   \code{S2[i, j]} holding \eqn{S(i,j)}).
#'
#' @examples
#' X <- cbind(cumsum(stats::rnorm(50)), cumsum(abs(stats::rnorm(50))))
#' s <- hd_path_signature2(X)
#' s$S1
#' # the shuffle identity holds exactly
#' all.equal(diag(s$S2), s$S1^2 / 2)
#'
#' @family path-signature
#' @seealso [hd_levy_area()] for the one level-2 quantity that carries ordering.
#' @export
hd_path_signature2 <- function(X) {
  X <- as.matrix(X)
  if (!is.numeric(X)) {
    cli::cli_abort("{.arg X} must be numeric; got {.cls {class(X)}}.")
  }
  if (nrow(X) < 2L) {
    cli::cli_abort(c(
      "x" = "{.arg X} has {nrow(X)} row{?s}; a path needs at least 2 points.",
      "i" = "Pass path levels (e.g. {.code cumsum(returns)}), one row per observation."
    ))
  }

  dX <- diff(X)
  d <- ncol(X)
  S1 <- colSums(dX)

  # A[, i] is the running total of coordinate i strictly BEFORE each step.
  A <- rbind(0, apply(dX, 2, cumsum))[seq_len(nrow(dX)), , drop = FALSE]

  S2 <- matrix(NA_real_, d, d)
  for (i in seq_len(d)) {
    for (j in seq_len(d)) {
      S2[i, j] <- sum(A[, i] * dX[, j]) + 0.5 * sum(dX[, i] * dX[, j])
    }
  }
  list(S1 = S1, S2 = S2)
}

# ── 2. Lévy area ────────────────────────────────────────────────────────────

#' Signed area enclosed between two increment series
#'
#' The Lévy area of the 2-D path traced by the running totals of \code{x} and
#' \code{y}. It is the only part of the level-2 signature not determined by
#' level 1, and the only statistic here that is sensitive to **ordering**:
#'
#' \deqn{A = \tfrac{1}{2}\sum_k \left( X_{k-1}\, \delta_k^y
#'   - Y_{k-1}\, \delta_k^x \right)}
#'
#' @section Sign convention:
#' **Positive means \code{x} leads \code{y}.** With \code{x} a return series
#' and \code{y} a volatility series, a positive value means directional moves
#' systematically precede volatility expansion; negative means volatility
#' expands first. Two windows with identical endpoints and identical totals
#' differ in this number whenever they differ in order.
#'
#' @section Scaling:
#' The raw statistic is bilinear — it scales with the product of the two
#' series' scales — so cross-asset or cross-period comparison needs
#' normalisation. With \code{scale = TRUE} each series is divided by its own
#' standard deviation **computed inside the window**. Scaling by a full-sample
#' standard deviation would leak each window's future into itself, which is
#' `look-ahead-bias-prevention` type-2 leakage and is not offered here.
#'
#' @section Missing values:
#' Any \code{NA} in either series yields \code{NA_real_}. Unlike a rolling
#' mean, a path functional cannot drop interior points: removing one splices
#' two non-adjacent observations into a single step and silently changes the
#' geometry — the defect behind issue #603. There is deliberately no
#' \code{min_frac} escape hatch.
#'
#' @param x,y Numeric vectors of equal length, holding **increments** (returns,
#'   range changes), not levels. The path is formed by their running totals.
#' @param scale Logical. Divide each series by its within-window standard
#'   deviation before computing. Default \code{TRUE}. Returns \code{NA_real_}
#'   if either series is constant.
#'
#' @return A single numeric value, or \code{NA_real_}.
#'
#' @examples
#' # x moves first, then y: positive
#' hd_levy_area(c(1, 0), c(0, 1), scale = FALSE)
#'
#' # reverse the order: same totals, opposite sign
#' hd_levy_area(c(0, 1), c(1, 0), scale = FALSE)
#'
#' @family path-signature
#' @export
hd_levy_area <- function(x, y, scale = TRUE) {
  x <- as.numeric(x)
  y <- as.numeric(y)

  if (length(x) != length(y)) {
    cli::cli_abort(c(
      "x" = "{.arg x} and {.arg y} must be the same length.",
      "i" = "Got {length(x)} and {length(y)}."
    ))
  }
  if (length(x) < 2L) {
    cli::cli_abort(c(
      "x" = "Need at least 2 increments to enclose an area; got {length(x)}.",
      "i" = "A single step traces a straight line, which encloses nothing."
    ))
  }
  # No splicing: a hole in the path means the geometry is unknown, not that
  # the surviving points are adjacent.
  if (anyNA(x) || anyNA(y)) return(NA_real_)

  if (isTRUE(scale)) {
    sx <- stats::sd(x)
    sy <- stats::sd(y)
    if (!is.finite(sx) || !is.finite(sy) || sx <= 0 || sy <= 0) return(NA_real_)
    x <- x / sx
    y <- y / sy
  }

  # Running totals strictly before each step.
  cx <- cumsum(x) - x
  cy <- cumsum(y) - y
  0.5 * sum(cx * y - cy * x)
}

# ── 3. Rolling Lévy area ────────────────────────────────────────────────────

#' Rolling Lévy area over a trailing window
#'
#' Length-preserving trailing-window version of [hd_levy_area()]. The first
#' \code{n - 1} positions are \code{NA} (warm-up), and any window containing an
#' \code{NA} is \code{NA} — see the missing-value note in [hd_levy_area()].
#'
#' @param x,y Numeric vectors of equal length holding increments.
#' @param n Integer window length in observations. Must be at least 2.
#' @param scale Logical, passed to [hd_levy_area()]. Default \code{TRUE}, so
#'   each window is normalised by its own standard deviations.
#'
#' @return Numeric vector the same length as \code{x}.
#'
#' @examples
#' r <- stats::rnorm(100, 0, 0.01)
#' v <- abs(stats::rnorm(100, 0.012, 0.004))
#' head(hd_roll_levy_area(r, v, n = 20L), 25)
#'
#' @family path-signature
#' @export
hd_roll_levy_area <- function(x, y, n, scale = TRUE) {
  x <- as.numeric(x)
  y <- as.numeric(y)

  if (length(x) != length(y)) {
    cli::cli_abort(c(
      "x" = "{.arg x} and {.arg y} must be the same length.",
      "i" = "Got {length(x)} and {length(y)}."
    ))
  }
  n <- as.integer(n)
  if (is.na(n) || n < 2L) {
    cli::cli_abort(c(
      "x" = "{.arg n} must be at least 2; got {n}.",
      "i" = "A window of one step traces a straight line and encloses no area."
    ))
  }

  slider::slide2_dbl(
    x, y,
    function(xw, yw) {
      if (length(xw) < n) return(NA_real_)   # warm-up
      hd_levy_area(xw, yw, scale = scale)
    },
    .before = n - 1L, .complete = FALSE
  )
}
