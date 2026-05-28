# Chen-Zimmermann "Open Asset Pricing" dataset registration
#
# Source:
#   Chen, Andrew Y. and Zimmermann, Tom (2022). "Open Source Cross-Sectional
#   Asset Pricing." Critical Finance Review, 11(2), 207-264.
#   DOI: 10.1561/104.00000112
#   Dataset portal: https://www.openassetpricing.com/
#
# The dataset covers 209 anomaly signals for US common stocks (NYSE, AMEX,
# NASDAQ) 1990-2023.  The anomaly data is free to download; the portal
# provides CSV downloads for both the sorted-portfolio returns and the
# underlying characteristic quintile assignments.
#
# Characteristic/quintile CSV download note (2026-05):
#   The underlying per-stock quintile assignments needed to compute ADD are
#   available from the "Signals" section at openassetpricing.com.
#   TODO: confirm whether the direct download URL requires an authenticated
#   session or is openly accessible at a stable canonical URL.  As of the
#   wiki compilation on 2026-05-25 (knowledge/wiki/anomaly-driven-demand.md)
#   the site was accessible without login.  The exact download path is:
#     https://www.openassetpricing.com/                (landing page)
#     → "Data" → "Signals" → annual/monthly CSV bundles
#   Do NOT hard-code a URL until confirmed stable; fill in hd_add_quintile_url()
#   once a stable canonical path is verified.
#
# References:
#   Kjær, M.M. & Posselt, A.M. (2025). "Anomaly-Driven Demand."
#   Aarhus University / Danish Finance Institute working paper, Nov 2025.
#   Presented at Cavalcade Asia-Pacific 2025.
#   See knowledge/wiki/anomaly-driven-demand.md for digest.
#
# Related issues:
#   #279 — ADD crowding / candidate signal
#   #160 — effective number of tested strategies (K_eff_strat) — must budget
#          ADD against existing correlated-strategy count before deployment

#' Register the Chen-Zimmermann Open Asset Pricing dataset source
#'
#' Returns a named list describing the Chen & Zimmermann (2022) "Open Source
#' Cross-Sectional Asset Pricing" dataset used to construct Anomaly-Driven
#' Demand (ADD) signals.  This is a *registration* function only — it does
#' **not** download any data.  Use the returned metadata to locate and
#' retrieve the data when the pipeline is ready for a full download step.
#'
#' The dataset contains per-stock anomaly characteristic values and
#' quintile-portfolio assignments for 209 anomalies spanning US common
#' stocks (NYSE, AMEX, NASDAQ) from January 1990 to December 2023.
#'
#' ADD construction requires the monthly quintile-assignment file — a tidy
#' long table with columns (stock, date, anomaly_id, quintile) indicating
#' which quintile each stock was assigned to for each anomaly in each month.
#' See [hd_compute_add()] for the computation step.
#'
#' @return A named list with fields:
#'   \describe{
#'     \item{source_name}{Human-readable name of the data source.}
#'     \item{portal_url}{URL of the data portal (no authentication required
#'       as of 2026-05).}
#'     \item{download_url}{Canonical direct download URL for the monthly
#'       quintile CSV bundle, or \code{NA_character_} if not yet confirmed
#'       stable.}
#'     \item{expected_schema}{Character vector of expected column names in
#'       the quintile-assignment table.}
#'     \item{frequency}{Rebalancing frequency of the anomaly portfolios.}
#'     \item{universe}{Description of the stock universe covered.}
#'     \item{sample_start}{Start of the data sample (character "YYYY-MM").}
#'     \item{sample_end}{End of the data sample (character "YYYY-MM").}
#'     \item{n_anomalies}{Number of anomaly signals in the dataset (integer).}
#'     \item{citation}{Full citation string for the dataset.}
#'     \item{related_issues}{Character vector of GitHub issue numbers
#'       relevant to this dataset.}
#'   }
#' @family add
#' @export
hd_register_add_dataset <- function() {
  list(
    source_name    = "Chen-Zimmermann Open Asset Pricing (2022)",
    portal_url     = "https://www.openassetpricing.com/",
    # TODO: replace NA with the stable direct-download URL once confirmed.
    # The portal hosts CSV bundles for sorted-portfolio returns and per-stock
    # quintile assignments under the "Signals" section.  As of 2026-05-25
    # no stable canonical URL has been verified to be authentication-free.
    download_url   = NA_character_,
    expected_schema = c("permno", "date", "anomaly_id", "quintile"),
    frequency      = "monthly",
    universe       = paste0(
      "US common stocks on NYSE, AMEX, NASDAQ. ",
      "Only post-publication anomalies counted at each point in time ",
      "(look-ahead-safe by construction)."
    ),
    sample_start   = "1990-01",
    sample_end     = "2023-12",
    n_anomalies    = 209L,
    citation       = paste0(
      "Chen, A.Y. and Zimmermann, T. (2022). ",
      "'Open Source Cross-Sectional Asset Pricing.' ",
      "Critical Finance Review, 11(2), 207-264. ",
      "DOI: 10.1561/104.00000112. ",
      "Dataset: https://www.openassetpricing.com/"
    ),
    related_issues = c("#279", "#160")
  )
}
