#' Get the local cache directory path
#'
#' Uses `tools::R_user_dir()` for platform-appropriate caching.
#'
#' @return Path to cache directory
#' @family infrastructure
#' @export
hd_cache_path <- function() {
  path <- Sys.getenv("HD_CACHE_DIR", unset = "")
  if (nzchar(path)) return(path)
  tools::R_user_dir("historicaldata", "cache")
}

#' Download dataset(s) to local cache
#'
#' Downloads Parquet files from HF for offline use.
#'
#' @param dataset Dataset name(s). If NULL, downloads all registered datasets.
#' @param force If TRUE, re-download even if cached file exists.
#' @return Invisibly, paths to cached files.
#' @family infrastructure
#' @export
hd_download <- function(dataset = NULL, force = FALSE) {
  cache_dir <- hd_cache_path()
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

  if (is.null(dataset)) {
    dataset <- names(hd_datasets())
  }

  paths <- character(length(dataset))
  names(paths) <- dataset

  for (ds_name in dataset) {
    ds <- hd_datasets()[[ds_name]]
    if (is.null(ds)) {
      cli::cli_warn("Unknown dataset: {ds_name}, skipping.")
      next
    }

    local_path <- file.path(cache_dir, paste0(ds_name, ".parquet"))
    paths[ds_name] <- local_path

    if (file.exists(local_path) && !force) {
      cli::cli_inform("Cache hit: {ds_name} ({local_path})")
      next
    }

    cli::cli_inform("Downloading {ds_name} from HF...")
    tryCatch(
      utils::download.file(ds$url, local_path, mode = "wb", quiet = TRUE),
      error = function(e) {
        cli::cli_warn("Failed to download {ds_name}: {conditionMessage(e)}")
      }
    )

    if (file.exists(local_path)) {
      size_mb <- round(file.info(local_path)$size / 1e6, 1)
      cli::cli_inform(c("v" = "Cached {ds_name}: {size_mb} MB"))
    }
  }

  invisible(paths)
}

#' Clear the local cache
#'
#' @param dataset If NULL, clears all cached datasets.
#' @family infrastructure
#' @export
hd_cache_clear <- function(dataset = NULL) {
  cache_dir <- hd_cache_path()

  if (is.null(dataset)) {
    files <- list.files(cache_dir, full.names = TRUE)
  } else {
    files <- file.path(cache_dir, paste0(dataset, ".parquet"))
    files <- files[file.exists(files)]
  }

  if (length(files) == 0) {
    cli::cli_inform("Cache is empty.")
    return(invisible())
  }

  file.remove(files)
  cli::cli_inform(c("v" = "Removed {length(files)} cached file{?s}."))
  invisible()
}
