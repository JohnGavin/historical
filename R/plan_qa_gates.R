# QA gate targets — look-ahead bias prevention
#
# Mandatory follow-up from PR #181 (2026-05-16) per look-ahead-bias-prevention rule.
# Every tar_make() runs these checks. Any match aborts the pipeline with a file:line
# report so the developer knows exactly where to fix.
#
# Opt-out: append `# look-ahead-safe` to any line that intentionally uses one of
# the forbidden patterns (e.g. lead(ym) to build a join key that is NOT itself
# a return or price series). Document why the pattern is safe in that comment.

# ---- helpers ----

#' Scan files for lead(ym) used for month-key construction (S1)
#'
#' @param files Character vector of absolute .R file paths to scan.
#' @return A tibble with columns file, line, code. Zero rows = no hits.
check_no_lead_ym <- function(files) {
  results <- purrr::map(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m <- grep("\\blead\\s*\\(\\s*ym\\b", lines)
    # Exclude comment lines (#' docstrings and # comments) — they describe
    # the forbidden pattern but don't execute it.
    m <- m[!grepl("^\\s*#", lines[m])]
    # Exclude lines that carry the explicit opt-out marker
    m <- m[!grepl("# look-ahead-safe", lines[m], fixed = TRUE)]
    if (length(m) == 0L) return(NULL)
    tibble::tibble(file = f, line = m, code = lines[m])
  })
  dplyr::bind_rows(results)
}

#' Scan files for slider forward-window without a lead-shifted input (S2)
#'
#' Pattern: slide_dbl(...) with .before = 0 on a variable that is NOT already
#' lead-shifted (i.e. the variable name does NOT end in _lead).
#'
#' Opt-out: append `# look-ahead-safe` to the slide_dbl() call line when the
#' input is genuinely forward-looking (e.g. a forecast series).
#'
#' @param files Character vector of absolute .R file paths to scan.
#' @return A tibble with columns file, line, code. Zero rows = no hits.
check_no_unleaded_slider <- function(files) {
  results <- purrr::map(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m <- grep("slide_dbl\\s*\\(", lines)
    bad <- m[vapply(m, function(i) {
      # Look ahead up to 5 lines for the .before argument
      block <- paste(lines[i:min(length(lines), i + 5L)], collapse = " ")
      has_before_zero <- grepl("\\.before\\s*=\\s*0\\b", block)
      input_is_lead   <- grepl("_lead\\b", block)
      has_opt_out     <- grepl("# look-ahead-safe", block, fixed = TRUE)
      has_before_zero && !input_is_lead && !has_opt_out
    }, logical(1L))]
    if (length(bad) == 0L) return(NULL)
    tibble::tibble(file = f, line = bad, code = lines[bad])
  })
  dplyr::bind_rows(results)
}

#' Scan files for zoo::na.approx (look-ahead via linear interpolation) (S3)
#'
#' zoo::na.approx uses tomorrow's value to fill today's NA — this is look-ahead
#' bias in any backtest feature. See na-propagation-rolling-stats rule.
#'
#' @param files Character vector of absolute .R file paths to scan.
#' @return A tibble with columns file, line, code. Zero rows = no hits.
check_no_na_approx <- function(files) {
  results <- purrr::map(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m <- grep("(zoo::)?na\\.approx\\s*\\(", lines)
    m <- m[!grepl("^\\s*#", lines[m])]                                     # skip comments
    m <- m[!grepl("# look-ahead-safe", lines[m], fixed = TRUE)]            # explicit opt-out
    if (length(m) == 0L) return(NULL)
    tibble::tibble(file = f, line = m, code = lines[m])
  })
  dplyr::bind_rows(results)
}

#' Scan files for cumulative products/sums of forward_* variables (S4)
#'
#' Accumulating forward returns at time T into a series indexed by T uses
#' information not available at T. Opt-out: append `# look-ahead-safe`.
#'
#' @param files Character vector of absolute .R file paths to scan.
#' @return A tibble with columns file, line, code. Zero rows = no hits.
check_no_forward_cumulative <- function(files) {
  results <- purrr::map(files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m <- grep("(cumprod|cumsum)\\s*\\([^)]*\\bforward_", lines)
    m <- m[!grepl("^\\s*#", lines[m])]                                     # skip comments
    m <- m[!grepl("# look-ahead-safe", lines[m], fixed = TRUE)]
    if (length(m) == 0L) return(NULL)
    tibble::tibble(file = f, line = m, code = lines[m])
  })
  dplyr::bind_rows(results)
}

# ---- QA gate plan ----

plan_qa_gates <- function() {
  list(
    # QA gate: look-ahead bias — 4 forbidden patterns
    #
    # Runs on EVERY tar_make() via cue = "always". Aborts the pipeline on any
    # match, printing file:line:code for each violation.
    #
    # Opt-out for legitimate uses: add `# look-ahead-safe` to the offending line
    # and document why the pattern is safe (e.g. join-key construction where
    # the lead-shifted column is never used as a return series).
    targets::tar_target(
      qa_look_ahead_bias,
      command = {
        files <- list.files(here::here("R"), pattern = "\\.R$",
                            full.names = TRUE, recursive = TRUE)
        files <- files[basename(files) != "plan_qa_gates.R"]

        s1 <- check_no_lead_ym(files)
        s2 <- check_no_unleaded_slider(files)
        s3 <- check_no_na_approx(files)
        s4 <- check_no_forward_cumulative(files)

        all_hits <- dplyr::bind_rows(
          if (nrow(s1) > 0L) dplyr::mutate(s1, check = "S1: lead(ym)") else NULL,
          if (nrow(s2) > 0L) dplyr::mutate(s2, check = "S2: slide_dbl forward without _lead") else NULL,
          if (nrow(s3) > 0L) dplyr::mutate(s3, check = "S3: na.approx (forbidden)") else NULL,
          if (nrow(s4) > 0L) dplyr::mutate(s4, check = "S4: cumulative of forward_*") else NULL
        )

        if (nrow(all_hits) > 0L) {
          msgs <- purrr::pmap_chr(
            all_hits[, c("check", "file", "line", "code")],
            function(check, file, line, code) {
              sprintf("  %s -- %s:%d -- %s", check, basename(file), line, trimws(code))
            }
          )
          cli::cli_abort(c(
            "x" = "Look-ahead bias patterns detected in {nrow(all_hits)} place(s):",
            setNames(msgs, rep("i", length(msgs)))
          ))
        }

        cli::cli_inform(c("v" = "qa_look_ahead_bias: all 4 checks passed (0 patterns detected)"))
        nrow(all_hits)  # 0 on success; downstream gates can depend on this value target
      },
      cue = targets::tar_cue(mode = "always")
    )
  )
}
