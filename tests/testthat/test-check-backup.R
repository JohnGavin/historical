testthat::local_edition(3)

# scripts/check_backup.sh (RECOVERY.md): exit 0 PASS | 1 FAIL | 2 usage |
# 3 INDETERMINATE. Every test runs against a FIXTURE of `defaults read` output and
# a temporary data folder (HL_BACKUP_PREFS_FILE, HL_BACKUP_DATA_DIR): nothing is read
# from the real machine. macOS only (the script uses BSD `date -j` and `stat -f`).

testthat::skip_if(Sys.info()[["sysname"]] != "Darwin", "check_backup.sh is macOS-only")

.repo <- normalizePath(here::here())
.script <- file.path(.repo, "scripts", "check_backup.sh")
`%||%` <- function(a, b) if (is.null(a)) b else a

# A preferences fixture in the shape `defaults read` prints. The snapshot dates are
# the argument; the attempt date is deliberately newer than every snapshot, so a
# check that counted attempts would pass when it should not. The volume name is a
# marker the output must never repeat.
.prefs <- function(snapshots, env = parent.frame()) {
  f <- withr::local_tempfile(fileext = ".txt", .local_envir = env)
  body <- if (length(snapshots)) {
    c("            SnapshotDates =             (",
      paste0("                \"", snapshots, "\"", c(rep(",", length(snapshots) - 1), "")),
      "            );")
  }
  writeLines(c(
    "{", "    Destinations =     (", "                {",
    "            AttemptDates =             (",
    "                \"2026-12-31 00:00:00 +0000\"", "            );",
    "            LastKnownVolumeName = \"SECRETVOLUME\";",
    body, "        }", "    );", "}"), f)
  f
}

# A data folder with one file whose mtime is `when` (UTC).
.data_dir <- function(when, env = parent.frame()) {
  d <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(d, "perp_ctx_5m"))
  f <- file.path(d, "perp_ctx_5m", "x.parquet")
  writeLines("x", f)
  Sys.setFileTime(f, as.POSIXct(when, tz = "UTC"))
  d
}

.run <- function(prefs, data_dir, args = character()) {
  out <- suppressWarnings(system2(
    "/bin/bash", c(.script, args), stdout = TRUE, stderr = TRUE,
    env = c(paste0("HL_BACKUP_PREFS_FILE=", prefs),
            paste0("HL_BACKUP_DATA_DIR=", data_dir))))
  list(status = attr(out, "status") %||% 0L, text = paste(out, collapse = "\n"))
}

test_that("a snapshot newer than the data is a PASS (exit 0)", {
  r <- .run(.prefs("2026-11-21 08:00:00 +0000"), .data_dir("2026-11-21 06:00:00"))
  expect_equal(r$status, 0L)
  expect_match(r$text, "BACKUP PASS")
})

test_that("a snapshot a little older than the data, inside the tolerance, is a PASS", {
  # 10 h older, default tolerance 24 h
  r <- .run(.prefs("2026-11-21 00:00:00 +0000"), .data_dir("2026-11-21 10:00:00"))
  expect_equal(r$status, 0L)
})

test_that("a snapshot older than the data by more than the tolerance is a FAIL (exit 1) with both times and the gap", {
  r <- .run(.prefs("2026-11-01 00:00:00 +0000"), .data_dir("2026-11-21 06:00:00"))
  expect_equal(r$status, 1L)
  expect_match(r$text, "BACKUP FAIL")
  expect_match(r$text, "2026-11-21T06:00:00Z")          # newest data file
  expect_match(r$text, "2026-11-01T00:00:00Z")          # newest snapshot
  expect_match(r$text, "486 h older")                    # 20 d 6 h
})

test_that("--tolerance-hours moves the line between PASS and FAIL", {
  prefs <- .prefs("2026-11-19 00:00:00 +0000")
  data <- .data_dir("2026-11-20 06:00:00")               # 30 h gap
  expect_equal(.run(prefs, data)$status, 1L)
  expect_equal(.run(prefs, data, "--tolerance-hours=48")$status, 0L)
  expect_equal(.run(prefs, data, "--tolerance-hours=0")$status, 1L)
})

test_that("the newest of several snapshots is the one that counts", {
  r <- .run(.prefs(c("2026-01-01 00:00:00 +0000", "2026-11-21 08:00:00 +0000",
                     "2026-03-01 00:00:00 +0000")),
            .data_dir("2026-11-21 06:00:00"))
  expect_equal(r$status, 0L)
  expect_match(r$text, "of 3 recorded")
})

test_that("an attempt date newer than every snapshot does not count (the fixture has one)", {
  r <- .run(.prefs("2026-01-01 00:00:00 +0000"), .data_dir("2026-11-21 06:00:00"))
  expect_equal(r$status, 1L)
})

test_that("unreadable preferences are INDETERMINATE (exit 3), never PASS, with the reason", {
  r <- .run(file.path(tempdir(), "no-such-prefs-file"), .data_dir("2026-11-21 06:00:00"))
  expect_equal(r$status, 3L)
  expect_match(r$text, "INDETERMINATE")
  expect_match(r$text, "not readable")
  expect_no_match(r$text, "PASS")
})

test_that("preferences that parse to no snapshot dates are INDETERMINATE (exit 3)", {
  r <- .run(.prefs(character()), .data_dir("2026-11-21 06:00:00"))
  expect_equal(r$status, 3L)
  expect_match(r$text, "no snapshot dates")
})

test_that("a snapshot date that does not parse is INDETERMINATE (exit 3)", {
  r <- .run(.prefs("not a date"), .data_dir("2026-11-21 06:00:00"))
  expect_equal(r$status, 3L)
  expect_match(r$text, "did not parse")
})

test_that("a missing or empty data folder is INDETERMINATE (exit 3)", {
  prefs <- .prefs("2026-11-21 08:00:00 +0000")
  r <- .run(prefs, file.path(tempdir(), "no-such-data-dir"))
  expect_equal(r$status, 3L)
  expect_match(r$text, "does not exist")
  r <- .run(prefs, withr::local_tempdir())
  expect_equal(r$status, 3L)
  expect_match(r$text, "no file")
})

test_that("a usage error is exit 2", {
  prefs <- .prefs("2026-11-21 08:00:00 +0000")
  data <- .data_dir("2026-11-21 06:00:00")
  expect_equal(.run(prefs, data, "--bogus")$status, 2L)
  expect_equal(.run(prefs, data, "--tolerance-hours=soon")$status, 2L)
  expect_equal(.run(prefs, data, "--tolerance-hours=")$status, 2L)
})

test_that("the output never carries a volume name", {
  for (snap in c("2026-11-21 08:00:00 +0000", "2026-11-01 00:00:00 +0000")) {
    r <- .run(.prefs(snap), .data_dir("2026-11-21 06:00:00"))
    expect_no_match(r$text, "SECRETVOLUME")
  }
})
