testthat::local_edition(3)

# scripts/hf_upload_commit.sh (#1088). NO network: `hf` and `curl` are stubs on PATH.
# The stub `hf upload` copies the folder into a folder standing in for the dataset;
# `hf download` copies a file back out. STUB_DROP makes the upload silently skip a
# file, which is the "uploaded but not there" failure the read-back must catch.

.script <- here::here("scripts", "hf_upload_commit.sh")

.stub_hf <- '#!/usr/bin/env bash
cmd="$1"; shift
case "$cmd" in
  upload)
    echo "upload $*" >> "$STUB_LOG"
    [ -n "${STUB_UPLOAD_FAIL:-}" ] && exit 1
    folder="$2"
    (cd "$folder" && find . -type f) | while read -r f; do
      rel="${f#./}"
      [ "$rel" = "${STUB_DROP:-__none__}" ] && continue
      mkdir -p "$STUB_REMOTE/$(dirname "$rel")"
      cp "$folder/$rel" "$STUB_REMOTE/$rel"
      [ "$rel" = "${STUB_CORRUPT:-__none__}" ] && echo "x" >> "$STUB_REMOTE/$rel"
    done
    exit 0 ;;
  download)
    rel="$2"; shift 2
    while [ $# -gt 0 ]; do
      case "$1" in --local-dir) dir="$2"; shift ;; esac
      shift
    done
    [ -f "$STUB_REMOTE/$rel" ] || exit 1
    mkdir -p "$dir/$(dirname "$rel")"
    cp "$STUB_REMOTE/$rel" "$dir/$rel"
    exit 0 ;;
esac
exit 1
'
.stub_curl <- '#!/usr/bin/env bash
echo "${STUB_CURL_CODE:-200}"
'

# A PATH holding the stubs and ONLY the basic tools the script needs (so "hf absent" is real).
.setup <- function(with_hf = TRUE, env = parent.frame()) {
  bin <- withr::local_tempdir(.local_envir = env)
  w <- function(name, body) { p <- file.path(bin, name); writeLines(body, p); Sys.chmod(p, "0755") }
  if (with_hf) w("hf", strsplit(.stub_hf, "\n", fixed = TRUE)[[1]])
  w("curl", strsplit(.stub_curl, "\n", fixed = TRUE)[[1]])
  for (t in c("bash", "env", "find", "sort", "date", "cmp", "mktemp", "sleep", "dirname", "cp", "mkdir")) {
    file.symlink(Sys.which(t), file.path(bin, t))
  }
  remote <- withr::local_tempdir(.local_envir = env)
  log <- withr::local_tempfile(.local_envir = env)
  file.create(log)
  withr::local_envvar(PATH = bin, STUB_REMOTE = remote, STUB_LOG = log, HF_TOKEN = "stub-token-value",
                      HD_HF_REPO_VISIBILITY = "public", HD_HF_REPO = NA, HD_HF_READBACK_SLEEP = "0",
                      STUB_DROP = NA, STUB_CORRUPT = NA, STUB_UPLOAD_FAIL = NA, STUB_CURL_CODE = NA,
                      .local_envir = env)
  list(remote = remote, log = log)
}

.stage <- function(files = c("hyperliquid/perp_ctx_5m/date=2026-11-22/cf-1.parquet",
                             "hyperliquid/raw/ctx_poll/date=2026-11-22/cf-1.jsonl.gz")) {
  d <- withr::local_tempdir(.local_envir = parent.frame())
  for (f in files) {
    dir.create(dirname(file.path(d, f)), recursive = TRUE, showWarnings = FALSE)
    writeLines(paste("content of", f), file.path(d, f))
  }
  d
}

.run <- function(dir, ...) {
  out <- suppressWarnings(system2("bash", c(shQuote(.script), shQuote(dir), ...), stdout = TRUE, stderr = TRUE))
  list(status = attr(out, "status") %||% 0L, out = paste(out, collapse = "\n"))
}
.uploads <- function(s) sum(grepl("^upload ", readLines(s$log)))

test_that("a good folder is uploaded as ONE commit and read back identical", {
  s <- .setup()
  d <- .stage()
  r <- .run(d)
  expect_equal(r$status, 0L, info = r$out)
  expect_match(r$out, "PASS: 2 file(s) uploaded in one commit", fixed = TRUE)
  expect_equal(.uploads(s), 1L)                                          # one `hf upload` for both files
  expect_match(readLines(s$log)[1], "^upload JohnGavin/finance-data \\S+ \\. --repo-type dataset --commit-message ")
  for (f in c("hyperliquid/perp_ctx_5m/date=2026-11-22/cf-1.parquet", "hyperliquid/raw/ctx_poll/date=2026-11-22/cf-1.jsonl.gz")) {
    expect_identical(readLines(file.path(s$remote, f)), readLines(file.path(d, f)))
  }
})

test_that("falsification: a file the hub did not take makes it exit 1, naming the file", {
  s <- .setup()
  d <- .stage()
  withr::local_envvar(STUB_DROP = "hyperliquid/raw/ctx_poll/date=2026-11-22/cf-1.jsonl.gz")
  r <- .run(d)
  expect_equal(r$status, 1L, info = r$out)
  expect_match(r$out, "MISSING or different after commit: hyperliquid/raw/ctx_poll/date=2026-11-22/cf-1.jsonl.gz", fixed = TRUE)
  expect_match(r$out, "FAIL: 1 of 2", fixed = TRUE)
  # and a file that arrived changed is caught too
  s2 <- .setup()
  withr::local_envvar(STUB_DROP = NA, STUB_CORRUPT = "hyperliquid/perp_ctx_5m/date=2026-11-22/cf-1.parquet")
  r2 <- .run(d)
  expect_equal(r2$status, 1L, info = r2$out)
})

test_that("it fails closed: wrong repo, undeclared visibility, a file outside hyperliquid/, symlinks, temp files", {
  s <- .setup()
  d <- .stage()
  withr::local_envvar(HD_HF_REPO = "SomeoneElse/other-data")
  r1 <- .run(d)
  expect_equal(r1$status, 1L)
  expect_match(r1$out, "REFUSED: repo")
  withr::local_envvar(HD_HF_REPO = NA, HD_HF_REPO_VISIBILITY = "")
  expect_equal(.run(d)$status, 1L)
  withr::local_envvar(HD_HF_REPO_VISIBILITY = "private")
  expect_equal(.run(d)$status, 1L)
  withr::local_envvar(HD_HF_REPO_VISIBILITY = "public")
  d2 <- .stage(c("hyperliquid/a.parquet", "other/b.parquet"))
  r2 <- .run(d2)
  expect_equal(r2$status, 1L)
  expect_match(r2$out, "'other/b.parquet' is not under hyperliquid/", fixed = TRUE)
  d3 <- .stage(c("hyperliquid/a.parquet.tmp"))
  expect_equal(.run(d3)$status, 1L)
  d4 <- .stage(c("hyperliquid/a.parquet"))
  file.symlink("/etc/hosts", file.path(d4, "hyperliquid", "link.parquet"))
  expect_equal(.run(d4)$status, 1L)
  expect_equal(.uploads(s), 0L)                                          # none of those uploaded anything
})

test_that("a private or unreachable dataset is not published to", {
  s <- .setup()
  d <- .stage()
  withr::local_envvar(STUB_CURL_CODE = "404")
  expect_equal(.run(d)$status, 1L)
  withr::local_envvar(STUB_CURL_CODE = "401")
  expect_equal(.run(d)$status, 1L)
  withr::local_envvar(STUB_CURL_CODE = "000")
  r <- .run(d)
  expect_equal(r$status, 3L)
  expect_equal(.uploads(s), 0L)
})

test_that("missing hf CLI or token is exit 3 (never 0); a failed upload is 1; usage is 2", {
  s <- .setup(with_hf = FALSE)
  d <- .stage()
  r <- .run(d)
  expect_equal(r$status, 3L)
  expect_match(r$out, "'hf' CLI is not on PATH", fixed = TRUE)
  s2 <- .setup()
  withr::local_envvar(HF_TOKEN = NA)
  r2 <- .run(d)
  expect_equal(r2$status, 3L)
  expect_match(r2$out, "HF_TOKEN is not set", fixed = TRUE)
  expect_false(grepl("stub-token-value", r2$out, fixed = TRUE))
  s3 <- .setup()
  withr::local_envvar(STUB_UPLOAD_FAIL = "1")
  expect_equal(.run(d)$status, 1L)
  expect_equal(.run(file.path(d, "no-such-folder"))$status, 2L)
  empty <- withr::local_tempdir()
  expect_equal(.run(empty)$status, 2L)
})
