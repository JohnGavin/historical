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

#' Scan rendered HTML for diagram click URLs that lack a line anchor (S5)
#'
#' Matches GitHub blob URLs pointing to repo R files that do NOT end in
#' `#L<digits>`. Any hit means diagram_node_links.R has a missing or NA line.
#'
#' @param html_dir Character. Directory to scan for *.html files.
#' @param repo Character. GitHub owner/repo slug (used to scope the pattern).
#' @return A tibble with columns file, line, url. Zero rows = no hits.
check_no_bare_diagram_urls <- function(html_dir,
                                        repo = "JohnGavin/historical") {
  html_files <- list.files(html_dir, pattern = "\\.html$",
                            full.names = TRUE, recursive = TRUE)
  # Pattern: a github.com blob URL for a .R file with NO trailing #L<n>
  pat <- sprintf(
    "https://github\\.com/%s/blob/[^\"' ]+\\.R(?!#L[0-9])",
    gsub("/", "\\\\/", repo)
  )
  results <- purrr::map(html_files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m     <- grep(pat, lines, perl = TRUE)
    if (length(m) == 0L) return(NULL)
    # Extract matching URLs for reporting
    urls <- regmatches(lines[m],
                       gregexpr(pat, lines[m], perl = TRUE))
    tibble::tibble(
      file = f,
      line = rep(m, lengths(urls)),
      url  = unlist(urls)
    )
  })
  dplyr::bind_rows(results)
}

#' Verify that every #L<n> anchor is within the target file's line count (S6)
#'
#' Reads each R file referenced by a `#L<n>` URL and checks that `<n>` does
#' not exceed the file's actual line count.
#'
#' @param html_dir Character. Directory to scan for *.html files.
#' @param repo_root Character. Absolute path to the repository root.
#' @param repo Character. GitHub owner/repo slug (used to scope the pattern).
#' @return A tibble with columns file, line, url, anchor_line, max_line. Zero rows = no violations.
check_anchor_in_range <- function(html_dir,
                                   repo_root,
                                   repo = "JohnGavin/historical") {
  html_files <- list.files(html_dir, pattern = "\\.html$",
                            full.names = TRUE, recursive = TRUE)
  # Pattern: a github.com blob URL for a .R file with a #L<n> anchor
  pat <- sprintf(
    "https://github\\.com/%s/blob/[^\"' ]+\\.R#L([0-9]+)",
    gsub("/", "\\\\/", repo)
  )
  results <- purrr::map(html_files, function(f) {
    lines <- readLines(f, warn = FALSE)
    m     <- grep(pat, lines, perl = TRUE)
    if (length(m) == 0L) return(NULL)
    url_matches <- regmatches(lines[m], gregexpr(pat, lines[m], perl = TRUE))
    purrr::map2_dfr(m, url_matches, function(ln, urls) {
      purrr::map_dfr(urls, function(url) {
        # Extract relative file path from URL (everything after /blob/<ref>/)
        rel_path   <- sub(sprintf("https://github\\.com/%s/blob/[^/]+/", repo), "", url)
        rel_path   <- sub("#L[0-9]+$", "", rel_path)
        anchor_n   <- as.integer(sub(".*#L", "", url))
        abs_path   <- file.path(repo_root, rel_path)
        if (!file.exists(abs_path)) return(NULL)
        max_ln     <- length(readLines(abs_path, warn = FALSE))
        if (anchor_n > max_ln) {
          tibble::tibble(file = f, line = ln, url = url,
                         anchor_line = anchor_n, max_line = max_ln)
        } else NULL
      })
    })
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
    ),

    # QA gate: diagram click URLs must have #L<n> anchors (S5)
    #
    # Runs whenever docs/ HTML changes. Aborts if any GitHub blob URL for
    # a .R file lacks a #L<n> anchor — which means diagram_node_links.R
    # has a missing or NA line number entry.
    targets::tar_target(
      qa_no_bare_diagram_urls,
      command = {
        html_dir <- here::here("docs")
        hits <- check_no_bare_diagram_urls(html_dir)
        if (nrow(hits) > 0L) {
          msgs <- purrr::pmap_chr(
            hits[, c("file", "line", "url")],
            function(file, line, url) {
              sprintf("  S5: %s:%d -- %s", basename(file), line, url)
            }
          )
          cli::cli_abort(c(
            "x" = "Diagram click URLs without #L<n> anchors in {nrow(hits)} place(s):",
            "i" = "Add line numbers to R/diagram_node_links.R for each node.",
            setNames(msgs, rep("i", length(msgs)))
          ))
        }
        cli::cli_inform(c("v" = "qa_no_bare_diagram_urls: S5 passed (0 bare URLs detected)"))
        nrow(hits)
      },
      cue = targets::tar_cue(mode = "always")
    ),

    # QA gate: every #L<n> anchor must be within the target file's line count (S6)
    #
    # Catches stale line numbers after code edits. Aborts if any anchor points
    # beyond the file's actual line count.
    targets::tar_target(
      qa_anchor_in_range,
      command = {
        html_dir  <- here::here("docs")
        repo_root <- here::here()
        hits <- check_anchor_in_range(html_dir, repo_root)
        if (nrow(hits) > 0L) {
          msgs <- purrr::pmap_chr(
            hits[, c("file", "line", "url", "anchor_line", "max_line")],
            function(file, line, url, anchor_line, max_line) {
              sprintf("  S6: %s:%d -- #L%d exceeds file max %d -- %s",
                      basename(file), line, anchor_line, max_line, url)
            }
          )
          cli::cli_abort(c(
            "x" = "Stale #L<n> anchors in {nrow(hits)} place(s):",
            "i" = "Update line numbers in R/diagram_node_links.R.",
            setNames(msgs, rep("i", length(msgs)))
          ))
        }
        cli::cli_inform(c("v" = "qa_anchor_in_range: S6 passed (all anchors in range)"))
        nrow(hits)
      },
      cue = targets::tar_cue(mode = "always")
    )
  )
}
