#' Check if HuggingFace is reachable
#'
#' Returns TRUE if the HF API responds within 5 seconds.
#' Used by tests and examples to fall back to local sample data.
#'
#' @return Logical
#' @keywords internal
hd_is_online <- function() {
  tryCatch({
    con <- url("https://huggingface.co/api/datasets/dsfefvx/finance-historical-data",
               open = "r")
    on.exit(close(con))
    TRUE
  }, error = function(e) FALSE)
}

#' Path to bundled sample data
#'
#' Returns path to small sample Parquet files bundled in the package.
#' Used as fallback when HuggingFace is unreachable (e.g. R CMD check).
#'
#' @param dataset One of "equity", "crypto", "macro", "factors", "metadata"
#' @return File path to sample parquet
#' @keywords internal
hd_sample_path <- function(dataset) {
  file <- switch(dataset,
    equity_daily = "equity_sample.parquet",
    crypto_daily = "crypto_sample.parquet",
    macro_daily = "macro_sample.parquet",
    factors = "factors_sample.parquet",
    metadata = "metadata_sample.parquet",
    cli::cli_abort("No sample data for dataset: {dataset}")
  )
  system.file("extdata", "sample", file, package = "historicaldata", mustWork = TRUE)
}
