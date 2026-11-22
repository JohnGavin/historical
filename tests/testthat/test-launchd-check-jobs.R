testthat::local_edition(3)

# scripts/launchd/check_jobs.sh (#1080), run against a STUB `launchctl` on PATH:
# no job is loaded, nothing is read from the real launchd. macOS only (the script
# uses BSD `stat -f`).

testthat::skip_if(Sys.info()[["sysname"]] != "Darwin", "check_jobs.sh is macOS-only")

.repo <- normalizePath(here::here())
.script <- file.path(.repo, "scripts", "launchd", "check_jobs.sh")
.labels <- c("io.github.johngavin.historical.hyperliquid-ctx-poll",
             "io.github.johngavin.historical.hyperliquid-weekly")

# Build a sandbox: stub launchctl, an "agents" dir and a log dir.
.sandbox <- function(env = parent.frame()) {
  root <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(root, "bin")); dir.create(file.path(root, "agents"))
  dir.create(file.path(root, "logs"))
  stub <- file.path(root, "bin", "launchctl")
  writeLines(c(
    "#!/bin/bash",
    "# stub: launchctl print gui/<uid>/<label>",
    "label=\"${2##*/}\"",
    "case \"$STUB_MODE\" in",
    "  missing) echo 'Could not find service \"'$label'\" in domain for user gui: 501'; exit 113 ;;",
    "  repo)    printf 'x = {\\n\\tpath = %s/scripts/launchd/%s.plist\\n}\\n' \"$STUB_REPO\" \"$label\" ;;",
    "  *)       printf 'x = {\\n\\tpath = %s/%s.plist\\n}\\n' \"$STUB_AGENTS\" \"$label\" ;;",
    "esac"), stub)
  Sys.chmod(stub, "0755")
  # installed copies == rendered repo templates; fresh logs
  for (l in .labels) {
    tpl <- readLines(file.path(.repo, "scripts", "launchd", paste0(l, ".plist")))
    writeLines(gsub("__REPO__", .repo, tpl, fixed = TRUE),
               file.path(root, "agents", paste0(l, ".plist")))
  }
  file.create(file.path(root, "logs", c("hyperliquid_ctx_poll.log", "hyperliquid_weekly.log")))
  root
}

.run_check <- function(root, mode) {
  out <- suppressWarnings(system2(
    "/bin/bash", .script, stdout = TRUE, stderr = TRUE,
    env = c(paste0("PATH=", file.path(root, "bin"), ":", Sys.getenv("PATH")),
            paste0("STUB_MODE=", mode), paste0("STUB_REPO=", .repo),
            paste0("STUB_AGENTS=", file.path(root, "agents")),
            paste0("HL_LAUNCH_AGENTS_DIR=", file.path(root, "agents")),
            paste0("HL_LOG_DIR=", file.path(root, "logs")))))
  list(status = attr(out, "status") %||% 0L, text = paste(out, collapse = "\n"))
}
`%||%` <- function(a, b) if (is.null(a)) b else a

test_that("a job loaded from ~/Library/LaunchAgents with a matching copy is fine (exit 0)", {
  r <- .run_check(.sandbox(), "good")
  expect_equal(r$status, 0L)
  expect_match(r$text, "loaded")
  expect_no_match(r$text, "FAIL|STALE|NOT LOADED")
})

test_that("a job loaded from the repo path is a FAIL: will not survive reboot (exit 1)", {
  r <- .run_check(.sandbox(), "repo")
  expect_equal(r$status, 1L)
  expect_match(r$text, "will not survive reboot")
  expect_match(r$text, "loaded from .*/scripts/launchd/")
})

test_that("a label launchd does not know is 'cannot tell' (exit 3)", {
  r <- .run_check(.sandbox(), "missing")
  expect_equal(r$status, 3L)
  expect_match(r$text, "NOT LOADED")
})

test_that("a stale installed copy is a FAIL (exit 1)", {
  root <- .sandbox()
  p <- file.path(root, "agents", paste0(.labels[1], ".plist"))
  writeLines(c(readLines(p), "<!-- edited after install -->"), p)
  r <- .run_check(root, "good")
  expect_equal(r$status, 1L)
  expect_match(r$text, "stale install")
})

test_that("a poller log older than 15 minutes is STALE (exit 1); the weekly log allows 8 days", {
  root <- .sandbox()
  old <- Sys.time() - 20 * 60
  Sys.setFileTime(file.path(root, "logs", "hyperliquid_ctx_poll.log"), old)
  Sys.setFileTime(file.path(root, "logs", "hyperliquid_weekly.log"), Sys.time() - 3 * 86400)
  r <- .run_check(root, "good")
  expect_equal(r$status, 1L)
  expect_match(r$text, "STALE")
  # Red/green: the same 3-day-old weekly log alone is not stale
  Sys.setFileTime(file.path(root, "logs", "hyperliquid_ctx_poll.log"), Sys.time())
  expect_equal(.run_check(root, "good")$status, 0L)
})

test_that("a missing log is 'cannot tell' (exit 3), never fine", {
  root <- .sandbox()
  unlink(file.path(root, "logs", "hyperliquid_weekly.log"))
  expect_equal(.run_check(root, "good")$status, 3L)
})
