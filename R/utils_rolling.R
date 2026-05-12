#' Length-preserving rolling mean with minimum-coverage gate
#'
#' Wraps `slider::slide_dbl()` to compute a right-aligned rolling mean that
#' tolerates scattered NAs but returns NA where the window has too few
#' observations. Use this in place of `RcppRoll::roll_mean(x, n, fill = NA)`
#' on any series sourced from external providers (HuggingFace parquet, FRED,
#' joined tables) where sparse NAs are expected.
#'
#' @param x Numeric vector.
#' @param n Window size (right-aligned, includes current observation).
#' @param min_frac Minimum fraction of non-NA values required in the window;
#'   below this, returns NA. Default 0.5. For `sd` use 0.7; for extreme
#'   quantiles (e.g. 0.95) use 0.9.
#' @return Numeric vector the same length as `x`.
#' @seealso [roll_sd_safe()], [roll_quantile_safe()]
#' @export
roll_mean_safe <- function(x, n, min_frac = 0.5) {
  .validate_rolling_args(x, n, min_frac)
  min_obs <- ceiling(min_frac * n)
  slider::slide_dbl(
    x,
    function(w) {
      n_obs <- sum(!is.na(w))
      if (n_obs < min_obs) NA_real_ else mean(w, na.rm = TRUE)
    },
    .before = n - 1L,
    .complete = FALSE
  )
}

#' Length-preserving rolling SD with minimum-coverage gate
#'
#' @inheritParams roll_mean_safe
#' @param min_frac Default 0.7 (variance estimates degrade faster than means).
#' @return Numeric vector the same length as `x`.
#' @seealso [roll_mean_safe()], [roll_quantile_safe()]
#' @export
roll_sd_safe <- function(x, n, min_frac = 0.7) {
  .validate_rolling_args(x, n, min_frac)
  min_obs <- ceiling(min_frac * n)
  slider::slide_dbl(
    x,
    function(w) {
      n_obs <- sum(!is.na(w))
      if (n_obs < min_obs) NA_real_ else stats::sd(w, na.rm = TRUE)
    },
    .before = n - 1L,
    .complete = FALSE
  )
}

#' Length-preserving rolling quantile with minimum-coverage gate
#'
#' @inheritParams roll_mean_safe
#' @param probs Single probability in [0, 1].
#' @param min_frac Default 0.9 (extreme quantiles need near-full coverage).
#' @return Numeric vector the same length as `x`.
#' @seealso [roll_mean_safe()], [roll_sd_safe()]
#' @export
roll_quantile_safe <- function(x, n, probs, min_frac = 0.9) {
  .validate_rolling_args(x, n, min_frac)
  if (!is.numeric(probs) || length(probs) != 1L || probs < 0 || probs > 1) {
    cli::cli_abort(c(
      "x" = "{.arg probs} must be a single numeric value in [0, 1].",
      "i" = "Received: {.val {probs}}"
    ))
  }
  min_obs <- ceiling(min_frac * n)
  slider::slide_dbl(
    x,
    function(w) {
      n_obs <- sum(!is.na(w))
      if (n_obs < min_obs) NA_real_ else {
        stats::quantile(w, probs = probs, na.rm = TRUE, names = FALSE, type = 7)
      }
    },
    .before = n - 1L,
    .complete = FALSE
  )
}

# Shared input validation — called by all three exported helpers.
# A positive integer n is required: non-integer positives are accepted
# (n = 5.0 is fine) but n = 5.5 would be misleading since .before uses
# integer arithmetic; we coerce and warn below the integer check.
.validate_rolling_args <- function(x, n, min_frac) {
  if (!is.numeric(x)) {
    cli::cli_abort(c(
      "x" = "{.arg x} must be a numeric vector.",
      "i" = "Received class: {.cls {class(x)}}"
    ))
  }
  if (!is.numeric(n) || length(n) != 1L || is.na(n) || n < 1 || n != as.integer(n)) {
    cli::cli_abort(c(
      "x" = "{.arg n} must be a single positive integer.",
      "i" = "Received: {.val {n}}"
    ))
  }
  if (!is.numeric(min_frac) || length(min_frac) != 1L || is.na(min_frac) ||
      min_frac <= 0 || min_frac > 1) {
    cli::cli_abort(c(
      "x" = "{.arg min_frac} must be a single numeric value in (0, 1].",
      "i" = "Received: {.val {min_frac}}"
    ))
  }
}
