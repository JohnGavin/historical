# Shared builders for the Cloudflare-collector tests (#1088): KV values framed exactly as
# cloudflare/hl-ctx-collector/worker.js writes them, and a fake client (KV store + a
# folder standing in for the Hugging Face dataset). No network anywhere.

.hlfx_path <- function(name) {
  here::here("tests", "testthat", "fixtures", "hl_ctx_collector", name)
}
.hlfx <- function(name) {
  p <- .hlfx_path(name)
  readBin(p, "raw", file.size(p))
}

# "2026-11-22/1205" or an ISO string -> microseconds since the epoch, plus an offset.
.hl_us <- function(slot_id, offset_s = 0) {
  t <- as.POSIXct(paste0(substr(slot_id, 1L, 10L), " ", substr(slot_id, 12L, 13L), ":",
                         substr(slot_id, 14L, 15L), ":00"), tz = "UTC")
  sprintf("%.0f", (as.numeric(t) + offset_s) * 1e6)
}
.hl_iso <- function(slot_id) {
  sprintf("%sT%s:%s:00.000Z", substr(slot_id, 1L, 10L), substr(slot_id, 12L, 13L), substr(slot_id, 14L, 15L))
}

# One Worker value. `replies` = list(list(dex, status, body (raw), offset_s)).
.hl_kv_value <- function(slot_id, replies, perp_ok = TRUE, collector = "cf-1") {
  hdr <- list(
    format = "hl-ctx-v1", collector = collector, slot = .hl_iso(slot_id),
    replies = lapply(replies, function(r) {
      body <- if (r$status == 200L) r$body else raw(0)
      list(dex = r$dex, fetched_at_us = .hl_us(slot_id, r$offset_s %||% 1), status = r$status,
           ok = r$status == 200L, bytes = length(body))
    }),
    perp_dexs = list(status = if (perp_ok) 200L else 500L, ok = perp_ok, fetched_at_us = .hl_us(slot_id)),
    truncated = FALSE)
  bodies <- unlist(lapply(replies, function(r) if (r$status == 200L) r$body else raw(0)))
  c(charToRaw(paste0(jsonlite::toJSON(hdr, auto_unbox = TRUE), "\n")), bodies)
}

# The usual slot: two exchanges answer with the recorded replies.
.hl_ok_replies <- function() {
  list(list(dex = "xyz", status = 200L, body = .hlfx("metaandassetctxs_xyz.json"), offset_s = 1),
       list(dex = "flx", status = 200L, body = .hlfx("metaandassetctxs_flx.json"), offset_s = 2))
}

# A KV store: `entries` is a named list of list(status, body, expiration).
.hl_fake_client <- function(entries, remote, now_s = as.numeric(as.POSIXct("2026-11-22 14:00:00", tz = "UTC"))) {
  state <- new.env()
  state$gets <- character()
  state$hf_lists <- character()
  state$hf_fail <- character()           # day strings whose HF listing errors
  client <- list(
    kv_list = function(prefix) {
      data.frame(name = as.character(names(entries)),
                 expiration = vapply(entries, function(e) e$expiration %||% (now_s + 10 * 86400), numeric(1)),
                 stringsAsFactors = FALSE, row.names = NULL)
    },
    kv_get = function(name) {
      state$gets <- c(state$gets, name)
      e <- entries[[name]]
      if (is.null(e)) return(list(status = 404L, body = raw(0)))
      if (identical(e$error, TRUE)) stop("connection reset")
      list(status = e$status %||% 200L, body = e$body %||% raw(0))
    },
    hf_list = function(path) {
      state$hf_lists <- c(state$hf_lists, path)
      if (any(vapply(state$hf_fail, grepl, logical(1), x = path, fixed = TRUE))) stop("HF unavailable")
      d <- file.path(remote, path)
      if (!dir.exists(d)) return(character())
      paste0(path, "/", list.files(d))
    },
    hf_download = function(path, dest) {
      dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
      stopifnot(file.copy(file.path(remote, path), dest, overwrite = TRUE))
      invisible(TRUE)
    }
  )
  attr(client, "state") <- state
  client
}

# Standing in for the upload: copy a staging folder into the fake HF folder.
.hl_publish <- function(stage, remote) {
  file.copy(list.files(stage, full.names = TRUE), remote, recursive = TRUE, overwrite = TRUE)
  invisible(remote)
}
