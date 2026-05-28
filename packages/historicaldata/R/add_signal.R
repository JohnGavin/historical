# Anomaly-Driven Demand (ADD) Signal
#
# Implements the ADD signal from:
#   Kjær, M.M. & Posselt, A.M. (2025). "Anomaly-Driven Demand."
#   Aarhus University / Danish Finance Institute working paper, Nov 2025.
#
# Construction logic (from knowledge/wiki/anomaly-driven-demand.md):
#
#   For each stock j and anomaly k at time t:
#     1. Count net inclusions:
#          NET_{j,k,t} = 1[j in long_leg_{k,t}] - 1[j in short_leg_{k,t}]
#          (0 if neither, +1 if only long, -1 if only short)
#     2. Take the first difference:
#          ADD_{j,k,t} = NET_{j,k,t} - NET_{j,k,t-1}
#
#   High ADD = stock entered more long legs this month (coordinated buying
#   pressure incoming).  Low ADD = stock entered more short legs.
#
# Input data (from Chen-Zimmermann quintile assignments):
#   Quintile 1 = short leg, quintile 5 = long leg (standard convention).
#   Quintiles 2-4 = neither leg.
#
# Look-ahead safety:
#   ADD_{j,k,t} uses quintile assignments from t and t-1 ONLY.
#   The forward return test (is high-ADD predictive?) uses returns from t+1
#   onward.  hd_compute_add() forms ADD at time t from lagged quintiles —
#   the consumer is responsible for matching ADD_t to returns_{t+1}.
#
# Related issues:  #279 (ADD scaffold), #160 (K_eff_strat budget)

# ── Helpers ──────────────────────────────────────────────────────────────────

.is_long_leg  <- function(q) !is.na(q) & q == 5L
.is_short_leg <- function(q) !is.na(q) & q == 1L

# ── Core computation ─────────────────────────────────────────────────────────

#' Compute per-stock per-anomaly Anomaly-Driven Demand (ADD)
#'
#' Given a tidy tibble of monthly quintile assignments across multiple anomaly
#' signals, computes ADD as the month-over-month change in net long-minus-short
#' leg inclusions.
#'
#' Formally, for stock *j*, anomaly *k*, and month *t*:
#'
#' \deqn{
#'   \text{NET}_{j,k,t} = \mathbf{1}[j \in \text{long}_{k,t}]
#'                      - \mathbf{1}[j \in \text{short}_{k,t}]
#' }
#' \deqn{
#'   \text{ADD}_{j,k,t} = \text{NET}_{j,k,t} - \text{NET}_{j,k,t-1}
#' }
#'
#' where long leg = quintile 5 and short leg = quintile 1 (standard
#' Chen-Zimmermann convention; quintiles 2-4 contribute 0 to NET).
#'
#' **Look-ahead safety**: ADD at time *t* is computed from quintile assignments
#' at *t* and *t-1*.  It predicts returns starting from *t+1*; the caller is
#' responsible for this shift.
#'
#' @param quintile_assignments A tibble (or data frame) with columns:
#'   \describe{
#'     \item{stock}{Character stock identifier (e.g., permno or ticker).}
#'     \item{date}{Date (first day of each month, or any consistent monthly
#'       anchor).}
#'     \item{anomaly_id}{Character or factor identifying the anomaly.}
#'     \item{quintile}{Integer 1-5; quintile assignment for (stock, date,
#'       anomaly_id).  \code{NA} means the stock was not ranked (not covered)
#'       in this anomaly this month.}
#'   }
#'   Every (stock, date, anomaly_id) combination should appear at most once.
#'
#' @return A tibble with the same (stock, date, anomaly_id) key and an
#'   additional column:
#'   \describe{
#'     \item{add}{Integer ADD value in \{-2, -1, 0, 1, 2\}.  \code{NA} on
#'       the first month a (stock, anomaly_id) pair is observed (no prior
#'       quintile available).}
#'   }
#'   Rows are ordered by stock, anomaly_id, date (ascending).
#'
#' @examples
#' \dontrun{
#' # Minimal synthetic example (3 stocks x 3 months x 2 anomalies)
#' tbl <- tibble::tibble(
#'   stock      = rep(c("A", "B", "C"), times = 6),
#'   date       = rep(rep(as.Date(c("2023-01-01", "2023-02-01", "2023-03-01")),
#'                        each = 3), 2),
#'   anomaly_id = rep(c("val", "mom"), each = 9),
#'   quintile   = c(1L, 3L, 5L, 5L, 3L, 1L, 5L, 3L, 1L,   # val
#'                  3L, 5L, 3L, 5L, 1L, 3L, 1L, 5L, 3L)    # mom
#' )
#' hd_compute_add(tbl)
#' }
#'
#' @family add
#' @export
hd_compute_add <- function(quintile_assignments) {
  # ── Input validation ────────────────────────────────────────────────────────
  if (!is.data.frame(quintile_assignments)) {
    cli::cli_abort(c(
      "x" = "{.arg quintile_assignments} must be a data frame or tibble.",
      "i" = "Got {.cls {class(quintile_assignments)}}."
    ))
  }

  required_cols <- c("stock", "date", "anomaly_id", "quintile")
  missing_cols  <- setdiff(required_cols, names(quintile_assignments))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg quintile_assignments} is missing required columns: {.field {missing_cols}}.",
      "i" = "Found columns: {.field {names(quintile_assignments)}}."
    ))
  }

  if (nrow(quintile_assignments) == 0L) {
    cli::cli_abort(c(
      "x" = "{.arg quintile_assignments} must not be empty.",
      "i" = "Pass a tibble with at least one row."
    ))
  }

  if (!inherits(quintile_assignments$date, c("Date", "POSIXct"))) {
    cli::cli_abort(c(
      "x" = "Column {.field date} must be a {.cls Date} or {.cls POSIXct}.",
      "i" = "Got {.cls {class(quintile_assignments$date)}}."
    ))
  }

  quintile_vals <- quintile_assignments$quintile
  valid_quintiles <- quintile_vals[!is.na(quintile_vals)]
  if (length(valid_quintiles) > 0L && (!is.numeric(valid_quintiles) ||
      any(valid_quintiles < 1L | valid_quintiles > 5L))) {
    cli::cli_abort(c(
      "x" = "Column {.field quintile} must contain integers in 1-5 or NA.",
      "i" = "Got values outside [1, 5]."
    ))
  }

  # ── Computation ─────────────────────────────────────────────────────────────
  quintile_assignments |>
    dplyr::arrange(stock, anomaly_id, date) |>
    dplyr::group_by(stock, anomaly_id) |>
    dplyr::mutate(
      # NET at t: +1 if in long leg (Q5), -1 if in short leg (Q1), 0 otherwise
      net = dplyr::case_when(
        .is_long_leg(quintile)  ~  1L,
        .is_short_leg(quintile) ~ -1L,
        TRUE                    ~  0L
      ),
      # ADD at t = NET_t - NET_{t-1}; NA on first observation per group
      add = net - dplyr::lag(net, n = 1L, default = NA_integer_)
    ) |>
    dplyr::ungroup() |>
    dplyr::select(stock, date, anomaly_id, quintile, add)
}


#' Aggregate per-anomaly ADD into a per-stock-per-month composite score
#'
#' Collapses the per-(stock, date, anomaly_id) ADD values produced by
#' [hd_compute_add()] into a single composite ADD score per stock per month,
#' summing across all anomalies.  The resulting value equals the number of
#' anomaly long legs newly entered by the stock this month minus the number of
#' anomaly short legs newly entered (net of reversals in both directions).
#'
#' @param add_tbl A tibble returned by [hd_compute_add()] with columns
#'   \code{stock}, \code{date}, \code{anomaly_id}, \code{quintile}, \code{add}.
#' @param by Aggregation granularity.  Currently only \code{"stock_date"} is
#'   supported (sum across anomalies within each stock-month).
#'
#' @return A tibble with columns:
#'   \describe{
#'     \item{stock}{Stock identifier.}
#'     \item{date}{Month date (same anchor as input).}
#'     \item{add_sum}{Integer sum of ADD across all anomalies for this
#'       (stock, date) pair.  \code{NA} rows (first month per anomaly) are
#'       excluded from the sum via \code{na.rm = TRUE}; if ALL anomalies are
#'       NA for a given stock-month, \code{add_sum} is \code{NA}.}
#'     \item{n_anomalies_valid}{Number of anomalies contributing a non-NA ADD
#'       value for this stock-month (integer).}
#'   }
#'
#' @family add
#' @export
hd_aggregate_add <- function(add_tbl, by = "stock_date") {
  # ── Input validation ─────────────────────────────────────────────────────
  if (!is.data.frame(add_tbl)) {
    cli::cli_abort(c(
      "x" = "{.arg add_tbl} must be a data frame or tibble.",
      "i" = "Got {.cls {class(add_tbl)}}."
    ))
  }

  required_cols <- c("stock", "date", "anomaly_id", "add")
  missing_cols  <- setdiff(required_cols, names(add_tbl))
  if (length(missing_cols) > 0L) {
    cli::cli_abort(c(
      "x" = "{.arg add_tbl} is missing required columns: {.field {missing_cols}}.",
      "i" = "These are produced by {.fn hd_compute_add}."
    ))
  }

  if (!identical(by, "stock_date")) {
    cli::cli_abort(c(
      "x" = "Only {.val stock_date} is supported for {.arg by}.",
      "i" = "Got {.val {by}}."
    ))
  }

  if (nrow(add_tbl) == 0L) {
    cli::cli_abort(c(
      "x" = "{.arg add_tbl} must not be empty."
    ))
  }

  # ── Aggregation ───────────────────────────────────────────────────────────
  add_tbl |>
    dplyr::group_by(stock, date) |>
    dplyr::summarise(
      add_sum          = if (all(is.na(add))) NA_integer_
                         else sum(add, na.rm = TRUE),
      n_anomalies_valid = sum(!is.na(add)),
      .groups = "drop"
    ) |>
    dplyr::arrange(stock, date)
}
