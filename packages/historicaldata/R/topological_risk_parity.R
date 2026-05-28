# Topological Risk Parity (TRP) — HRP baseline + MST topological extension
#
# Implements Lopez de Prado (2016) Hierarchical Risk Parity using only base R
# stats (stats::dist, stats::hclust). The topological extension layers on a
# Minimum Spanning Tree (MST) built from the correlation distance matrix to
# derive cluster membership before the recursive bisection step.
#
# Deferred (out of scope for #114): full TDA (persistent homology) extension
# from VertoxQuant. That requires the TDA or TDAstats package; flagged for
# a separate issue.

# ── Internal helpers ───────────────────────────────────────────────────────────

#' Correlation-distance matrix from a covariance matrix
#' @param cov_mat Symmetric positive-semidefinite covariance matrix.
#' @return Numeric matrix of pairwise correlation distances in
#'   the range \code{[0, sqrt(2)]}. Distance formula:
#'   sqrt(0.5 * (1 - rho_ij)) from Lopez de Prado (2016).
#' @noRd
.cov_to_corr_dist <- function(cov_mat) {
  d <- diag(cov_mat)
  if (any(d <= 0)) {
    cli::cli_abort(c(
      "x" = "Covariance matrix has non-positive diagonal elements.",
      "i" = "Check for zero-variance assets or degenerate columns."
    ))
  }
  sds <- sqrt(d)
  corr_mat <- cov_mat / outer(sds, sds)
  # Clip to [-1, 1] for numerical safety
  corr_mat <- pmax(pmin(corr_mat, 1), -1)
  dist_mat <- sqrt(0.5 * (1 - corr_mat))
  rownames(dist_mat) <- rownames(cov_mat)
  colnames(dist_mat) <- colnames(cov_mat)
  dist_mat
}

#' Build a Minimum Spanning Tree from a distance matrix using Prim's algorithm
#'
#' Pure base-R Prim's. No igraph dependency.
#'
#' @param dist_mat Symmetric numeric distance matrix (n x n).
#' @return Data frame with columns `from`, `to`, `weight` — the n-1 MST edges.
#' @noRd
.build_mst_prim <- function(dist_mat) {
  n <- nrow(dist_mat)
  nms <- rownames(dist_mat)
  if (is.null(nms)) nms <- as.character(seq_len(n))

  in_tree <- logical(n)
  key     <- rep(Inf, n)    # cheapest edge connecting each vertex to tree
  parent  <- rep(NA_integer_, n)

  key[1L] <- 0
  edges <- data.frame(
    from   = character(0),
    to     = character(0),
    weight = numeric(0),
    stringsAsFactors = FALSE
  )

  for (iter in seq_len(n)) {
    # Pick the not-yet-in-tree vertex with minimum key
    u <- which(!in_tree)[which.min(key[!in_tree])]
    in_tree[u] <- TRUE

    if (!is.na(parent[u])) {
      edges <- rbind(edges, data.frame(
        from   = nms[parent[u]],
        to     = nms[u],
        weight = dist_mat[parent[u], u],
        stringsAsFactors = FALSE
      ))
    }

    # Update keys for neighbours of u
    for (v in seq_len(n)) {
      if (!in_tree[v] && dist_mat[u, v] < key[v]) {
        key[v]    <- dist_mat[u, v]
        parent[v] <- u
      }
    }
  }
  edges
}

#' Quasi-diagonalise a covariance matrix via dendrogram leaf ordering
#'
#' @param cov_mat Symmetric covariance matrix (n x n), named.
#' @param hclust_obj Object from stats::hclust.
#' @return Integer vector of column indices in the new quasi-diagonal order.
#' @noRd
.quasi_diag_order <- function(cov_mat, hclust_obj) {
  # stats::order.dendrogram gives leaf order from left to right
  stats::order.dendrogram(stats::as.dendrogram(hclust_obj))
}

#' Recursive bisection: allocate inverse-variance weights per cluster
#'
#' @param cov_mat Named covariance matrix.
#' @param sorted_assets Character vector of asset names in quasi-diagonal order.
#' @return Named numeric vector of portfolio weights summing to 1.
#' @noRd
.recursive_bisect <- function(cov_mat, sorted_assets) {
  n <- length(sorted_assets)
  weights <- setNames(rep(1, n), sorted_assets)

  # Stack holds index ranges [lo, hi] of sorted_assets to split
  stack <- list(c(1L, n))

  while (length(stack) > 0L) {
    item  <- stack[[length(stack)]]
    stack <- stack[-length(stack)]

    lo <- item[1L]
    hi <- item[2L]
    if (lo >= hi) next  # single asset — no split needed

    mid <- floor((lo + hi) / 2L)

    left_assets  <- sorted_assets[lo:mid]
    right_assets <- sorted_assets[(mid + 1L):hi]

    # Inverse-variance contribution of each sub-cluster
    iv_left  <- .cluster_inv_var(cov_mat, left_assets)
    iv_right <- .cluster_inv_var(cov_mat, right_assets)

    total <- iv_left + iv_right
    alpha_left  <- iv_left  / total   # fraction to left sub-cluster
    alpha_right <- iv_right / total   # fraction to right sub-cluster

    weights[left_assets]  <- weights[left_assets]  * alpha_left
    weights[right_assets] <- weights[right_assets] * alpha_right

    stack[[length(stack) + 1L]] <- c(lo, mid)
    stack[[length(stack) + 1L]] <- c(mid + 1L, hi)
  }
  weights
}

#' Cluster inverse-variance (scalar)
#'
#' For a sub-cluster of assets, returns 1 / Var(inverse-variance-weight portfolio).
#' Uses inverse-variance (IVP) weights as required by Lopez de Prado (2016) HRP
#' recursive bisection. Equal-weight was incorrect: when cluster variances differ,
#' it produced wrong capital splits between sub-clusters.
#'
#' @param cov_mat Full covariance matrix (named).
#' @param assets Character vector of asset names in this sub-cluster.
#' @return Scalar: inverse of the IVP sub-cluster portfolio variance.
#' @noRd
.cluster_inv_var <- function(cov_mat, assets) {
  sub <- cov_mat[assets, assets, drop = FALSE]
  diag_var <- diag(sub)
  # Inverse-variance portfolio weights (Lopez de Prado 2016)
  ivp <- (1 / diag_var) / sum(1 / diag_var)
  # portfolio variance = w' Sigma w
  pvar <- as.numeric(t(ivp) %*% sub %*% ivp)
  if (!is.finite(pvar) || pvar <= 0) return(1e-12)
  1 / pvar
}

# ── Exported functions ─────────────────────────────────────────────────────────

#' Hierarchical Risk Parity (HRP) portfolio weights
#'
#' Implements the Lopez de Prado (2016) HRP algorithm using only base-R
#' clustering (`stats::hclust`, `stats::dist`). No external optimiser or
#' portfolio package is required.
#'
#' The three steps are:
#' 1. **Tree clustering** — hierarchical agglomerative clustering on the
#'    correlation-distance matrix (complete linkage by default).
#' 2. **Quasi-diagonalisation** — reorder assets by dendrogram leaf order so
#'    correlated assets are adjacent.
#' 3. **Recursive bisection** — split portfolio allocation top-down using the
#'    inverse-variance of each sub-cluster.
#'
#' @param cov_mat Numeric matrix. Named, symmetric, positive-semi-definite
#'   covariance matrix (n x n). Row and column names must be the same and
#'   identify the assets.
#' @param method Character scalar. Linkage method passed to [stats::hclust].
#'   Default `"complete"` is most common for HRP. Other valid values:
#'   `"single"`, `"average"`, `"ward.D2"`.
#'
#' @return Named numeric vector of portfolio weights summing to 1. All weights
#'   are strictly positive (inverse-variance allocation assigns positive weight
#'   to every asset).
#'
#' @references
#' Lopez de Prado, M. (2016). Building diversified portfolios that outperform
#' out-of-sample. *Journal of Portfolio Management*, 42(4), 59–69.
#'
#' @family topological_risk_parity
#' @export
#'
#' @examples
#' set.seed(42)
#' n <- 5
#' R <- matrix(c(1,.8,.1,.1,.0,
#'               .8,1,.1,.1,.0,
#'               .1,.1,1,.7,.2,
#'               .1,.1,.7,1,.2,
#'               .0,.0,.2,.2,1), nrow = n)
#' sds <- c(.02,.03,.015,.025,.02)
#' cov_mat <- diag(sds) %*% R %*% diag(sds)
#' rownames(cov_mat) <- colnames(cov_mat) <- paste0("A", seq_len(n))
#' w <- hrp_weights(cov_mat)
#' stopifnot(abs(sum(w) - 1) < 1e-10, all(w > 0))
hrp_weights <- function(cov_mat, method = "complete") {
  .validate_cov_input(cov_mat)

  dist_mat  <- .cov_to_corr_dist(cov_mat)
  dist_obj  <- stats::as.dist(dist_mat)
  hclust_obj <- stats::hclust(dist_obj, method = method)

  asset_order   <- .quasi_diag_order(cov_mat, hclust_obj)
  sorted_assets <- colnames(cov_mat)[asset_order]

  w <- .recursive_bisect(cov_mat, sorted_assets)
  w / sum(w)
}

#' Topological Risk Parity (TRP) portfolio weights
#'
#' Extends HRP with a Minimum Spanning Tree (MST) step that groups assets by
#' network topology before hierarchical clustering. The MST is constructed from
#' the same correlation-distance matrix used by HRP. Assets connected in the
#' same MST component receive cluster membership, which biases the quasi-
#' diagonal ordering to respect topological proximity.
#'
#' **Algorithm:**
#' 1. Build correlation-distance matrix from `cov_mat`.
#' 2. Extract the MST (Prim's algorithm, base R, no external graph package).
#' 3. Derive MST-based asset ordering from a depth-first traversal of the tree.
#' 4. Apply recursive bisection (as in HRP) using this ordering.
#'
#' **Deferred:** Full TDA (persistent homology / Betti numbers) extension from
#' VertoxQuant (2024). Requires the TDA/TDAstats package and is out of scope
#' for the #114 first cut. Flagged for a follow-up issue.
#'
#' @param cov_mat Numeric matrix. Named, symmetric, positive-semi-definite
#'   covariance matrix (n x n). Row and column names must match.
#' @param fallback_to_hrp Logical. If `TRUE` (default), fall back to
#'   `hrp_weights()` if the MST ordering step fails. If `FALSE`, error on
#'   failure.
#'
#' @return Named numeric vector of portfolio weights summing to 1. All weights
#'   are strictly positive.
#'
#' @references
#' VertoxQuant (2024). *Topological Risk Parity*.
#' \url{https://www.vertoxquant.com/p/topological-risk-parity}
#'
#' Lopez de Prado, M. (2016). Building diversified portfolios that outperform
#' out-of-sample. *Journal of Portfolio Management*, 42(4), 59–69.
#'
#' @family topological_risk_parity
#' @export
#'
#' @examples
#' set.seed(42)
#' n <- 5
#' R <- matrix(c(1,.8,.1,.1,.0,
#'               .8,1,.1,.1,.0,
#'               .1,.1,1,.7,.2,
#'               .1,.1,.7,1,.2,
#'               .0,.0,.2,.2,1), nrow = n)
#' sds <- c(.02,.03,.015,.025,.02)
#' cov_mat <- diag(sds) %*% R %*% diag(sds)
#' rownames(cov_mat) <- colnames(cov_mat) <- paste0("A", seq_len(n))
#' w <- trp_weights(cov_mat)
#' stopifnot(abs(sum(w) - 1) < 1e-10, all(w > 0))
trp_weights <- function(cov_mat, fallback_to_hrp = TRUE) {
  .validate_cov_input(cov_mat)

  dist_mat <- .cov_to_corr_dist(cov_mat)

  sorted_assets <- tryCatch({
    mst_edges  <- .build_mst_prim(dist_mat)
    .mst_dfs_order(colnames(cov_mat), mst_edges)
  }, error = function(e) {
    if (fallback_to_hrp) {
      cli::cli_warn(c(
        "!" = "TRP MST ordering failed; falling back to HRP.",
        "i" = conditionMessage(e)
      ))
      NULL
    } else {
      cli::cli_abort(c(
        "x" = "TRP MST ordering failed.",
        "i" = conditionMessage(e)
      ))
    }
  })

  if (is.null(sorted_assets)) {
    return(hrp_weights(cov_mat))
  }

  w <- .recursive_bisect(cov_mat, sorted_assets)
  w / sum(w)
}

#' Depth-first traversal order of MST assets
#'
#' Produces a linear ordering of all assets by traversing the MST depth-first
#' starting from the root (asset with highest degree = most connections).
#'
#' @param assets Character vector of all asset names.
#' @param mst_edges Data frame with columns `from`, `to` (character).
#' @return Character vector of all assets in DFS order.
#' @noRd
.mst_dfs_order <- function(assets, mst_edges) {
  n <- length(assets)

  # Build adjacency list from undirected MST edges
  adj <- setNames(vector("list", n), assets)
  for (a in assets) adj[[a]] <- character(0)

  for (i in seq_len(nrow(mst_edges))) {
    f <- mst_edges$from[i]
    t <- mst_edges$to[i]
    adj[[f]] <- c(adj[[f]], t)
    adj[[t]] <- c(adj[[t]], f)
  }

  # Root: asset with highest degree (most connections in MST)
  degrees <- vapply(adj, length, integer(1L))
  root    <- assets[which.max(degrees)]

  # Iterative DFS
  visited <- character(0)
  stack   <- root
  while (length(stack) > 0L) {
    node  <- stack[length(stack)]
    stack <- stack[-length(stack)]
    if (node %in% visited) next
    visited <- c(visited, node)
    neighbours <- setdiff(adj[[node]], visited)
    # Push in reverse so we visit smallest-distance neighbour first
    stack <- c(stack, rev(neighbours))
  }

  # Any isolated assets (shouldn't happen with a valid MST) go at the end
  remaining <- setdiff(assets, visited)
  c(visited, remaining)
}

#' Validate covariance matrix input
#'
#' @param cov_mat Object to validate.
#' @return Invisibly `TRUE` if valid; calls [cli::cli_abort()] otherwise.
#' @noRd
.validate_cov_input <- function(cov_mat) {
  if (!is.matrix(cov_mat)) {
    cli::cli_abort(c(
      "x" = "{.arg cov_mat} must be a matrix.",
      "i" = "Got {.cls {class(cov_mat)}}."
    ))
  }
  if (nrow(cov_mat) != ncol(cov_mat)) {
    cli::cli_abort(c(
      "x" = "{.arg cov_mat} must be square.",
      "i" = "Got {nrow(cov_mat)} x {ncol(cov_mat)}."
    ))
  }
  if (is.null(colnames(cov_mat)) || is.null(rownames(cov_mat))) {
    cli::cli_abort(c(
      "x" = "{.arg cov_mat} must have named rows and columns.",
      "i" = "Set {.code rownames(cov_mat)} and {.code colnames(cov_mat)}."
    ))
  }
  if (!identical(rownames(cov_mat), colnames(cov_mat))) {
    cli::cli_abort(c(
      "x" = "Row names and column names of {.arg cov_mat} must be identical.",
      "i" = "Found mismatched row/column names."
    ))
  }
  if (nrow(cov_mat) < 2L) {
    cli::cli_abort(c(
      "x" = "{.arg cov_mat} must have at least 2 assets.",
      "i" = "Got {nrow(cov_mat)} asset(s)."
    ))
  }
  if (!is.numeric(cov_mat)) {
    cli::cli_abort(c(
      "x" = "{.arg cov_mat} must be numeric.",
      "i" = "Got storage mode {.val {storage.mode(cov_mat)}}."
    ))
  }
  if (anyNA(cov_mat) || any(!is.finite(cov_mat))) {
    cli::cli_abort(c(
      "x" = "{.arg cov_mat} must contain only finite, non-NA values.",
      "i" = "Found {sum(!is.finite(cov_mat) | is.na(cov_mat))} non-finite or NA element(s)."
    ))
  }
  # Symmetry check (tolerance-based to handle floating-point rounding)
  if (max(abs(cov_mat - t(cov_mat))) > sqrt(.Machine$double.eps) * max(abs(cov_mat))) {
    cli::cli_abort(c(
      "x" = "{.arg cov_mat} must be symmetric.",
      "i" = "Maximum asymmetry: {.val {max(abs(cov_mat - t(cov_mat)))}}."
    ))
  }
  invisible(TRUE)
}
