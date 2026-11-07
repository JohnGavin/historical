#!/usr/bin/env Rscript
# scripts/olmar_survivorship_977.R -- size of the OLMAR-1 survivorship bias (#977)
#
# QUESTION. The 20-ticker OLMAR-1 universe (R/plan_olmar.R, olmar_params$tickers)
# was written 2026-05-23, after the whole 2010-2026 test window, from today's
# mega-caps; equity_daily records no delistings. How much does that flatter
# OLMAR-1 (and its equal-weight benchmark)?
#
# METHOD (hindsight-free comparison universe, same data, same functions).
#   1. Membership: the S&P 500 constituents on the first trading day of the
#      window, from a free machine-readable file (fja05680/sp500 on GitHub;
#      DATA only -- no code from that repository is used). Parsed by
#      .osv_parse_membership() below, never typed in.
#   2. Rank the members that exist in equity_daily by median daily dollar volume
#      (close * volume) over the six calendar months BEFORE the window starts.
#      Dollar volume is a liquidity proxy for size, NOT market cap: the repo has
#      no point-in-time shares outstanding (#150). The ranking uses only data
#      dated before the first trading day, so it is hindsight-free.
#   3. Alternative universe = the same non-stock core as the current list (the
#      instruments that never appear in the S&P 500 history, i.e. index ETFs)
#      plus the top-k members by that rank, k = the current list's stock count.
#   4. Run olmar_backtest() (packages/historicaldata/R/olmar.R, NOT reimplemented)
#      with olmar_params evaluated from R/plan_olmar.R itself (one home for the
#      hyperparameters), and the equal-weight benchmark = the same function with
#      leverage = 0, on (a) the current list and (b) the alternative, plus
#      n_draws random same-size alternatives drawn from the eligible members.
#   5. Count the 2010 members that equity_daily cannot supply (delisted, acquired,
#      renamed, never ingested). Those names are INVISIBLE to every comparison
#      above, so the computed delta is a LOWER bound on the bias if failed names
#      are the ones missing; the sign of the part we cannot see is unknown.
#
# EXIT CODES (checks-must-distinguish-unknown):
#   0  a numeric estimate was produced
#   1  the run completed but the data cannot yield an estimate (fewer eligible
#      members than the current list has stocks)
#   2  usage error
#   3  INDETERMINATE: an input is missing, unreadable or too thin to trust
#
# USAGE
#   Rscript scripts/olmar_survivorship_977.R --equity=PATH --factors=PATH \
#     (--membership=CSV | --download-to=DIR) [--draws=200] [--to=YYYY-MM-DD] \
#     [--out=DIR]

.osv_membership_url <- paste0(
  "https://raw.githubusercontent.com/fja05680/sp500/master/",
  "S%26P%20500%20Historical%20Components%20%26%20Changes.csv"
)

# Guards against trusting a thin input (verification-before-completion: a gate
# that passes on thin inputs is worse than none). Overridable in tests only.
.osv_default_cfg <- list(
  min_equity_tickers = 500L,   # equity_daily holds 1622 distinct tickers
  min_snapshot_tokens = 400L,  # an S&P 500 snapshot has ~500
  min_rank_days = 60L,         # ~half a year of trading days with price+volume
  start_gate_days = 7L,        # series must start within 7 days of window start
  n_draws = 200L,
  seed = 977L
)

# sharpe_ratio_rf lives in the repo-root R/ (the function plan_olmar.R uses); it
# is sourced lazily into a private env so this script stays sourceable in tests.
.osv_env <- new.env(parent = globalenv())
.osv_sharpe <- function(...) {
  if (is.null(.osv_env$sharpe_ratio_rf)) {
    root <- if (is.null(.osv_env$root)) here::here() else .osv_env$root
    sys.source(file.path(root, "R", "utils_metrics.R"), envir = .osv_env)
  }
  .osv_env$sharpe_ratio_rf(...)
}

# ---------------------------------------------------------------------------
# Membership parsing
# ---------------------------------------------------------------------------

#' Parse the constituents-history CSV: one row per change date, a `tickers`
#' cell holding the comma-separated membership AFTER that change. A token
#' `SYM-YYYYMM` means the source records SYM as removed in that month (legacy
#' file layout only; the validated reader is the package's
#' hd_sp500_read_snapshots(), which does not touch tokens).
#' @noRd
.osv_parse_membership <- function(path) {
  # One home (#816): the validated reader lives in the package
  # (historicaldata::hd_sp500_read_snapshots). Load the package lazily so this
  # script stays sourceable in tests, like .osv_sharpe() above.
  if (!"historicaldata" %in% loadedNamespaces()) {
    root <- if (is.null(.osv_env$root)) here::here() else .osv_env$root
    suppressPackageStartupMessages(pkgload::load_all(
      file.path(root, "packages", "historicaldata"), quiet = TRUE))
  }
  historicaldata::hd_sp500_read_snapshots(path)
}

#' Tokens of the last snapshot dated on or before `asof`.
#' @noRd
.osv_members_asof <- function(m, asof) {
  asof <- as.Date(asof)
  ok <- which(m$date <= asof)
  if (length(ok) == 0L) {
    cli::cli_abort(
      "no membership snapshot on or before {asof}.", call = NULL)
  }
  row <- m[max(ok), , drop = FALSE]
  tok <- trimws(strsplit(row$tickers, ",", fixed = TRUE)[[1L]])
  list(snapshot_date = row$date, tokens = tok[nzchar(tok)])
}

#' Split tokens into base symbol + removal marker.
#' @noRd
.osv_split_tokens <- function(tokens) {
  hit <- grepl("^.+-[0-9]{6}$", tokens)
  data.frame(
    token = tokens,
    symbol = ifelse(hit, sub("-[0-9]{6}$", "", tokens), tokens),
    suffixed = hit,
    stringsAsFactors = FALSE
  )
}

#' Every base symbol that appears anywhere in the history.
#' @noRd
.osv_all_symbols <- function(m) {
  tok <- unlist(strsplit(m$tickers, ",", fixed = TRUE))
  unique(.osv_split_tokens(trimws(tok))$symbol)
}

#' Classify each snapshot token against what equity_daily can supply.
#' @param tok_df output of .osv_split_tokens()
#' @param eq_summary data.frame(ticker, first_date, last_date) for tickers
#'   present in equity_daily
#' @param first_day first trading day of the window
#' @noRd
.osv_classify <- function(tok_df, eq_summary, first_day, start_gate_days) {
  first_day <- as.Date(first_day)
  idx <- match(tok_df$symbol, eq_summary$ticker)
  present <- !is.na(idx)
  first_seen <- as.Date(rep(NA_character_, nrow(tok_df)))
  first_seen[present] <- as.Date(eq_summary$first_date[idx[present]])
  cls <- ifelse(
    tok_df$suffixed, "delisted_per_source",
    ifelse(!present, "absent_from_equity_daily",
      ifelse(first_seen > first_day + start_gate_days,
             "no_history_at_start", "usable")))
  out <- tok_df
  out$class <- cls
  # A suffixed token whose base symbol IS in equity_daily is symbol reuse by a
  # different company: it must never be used as the delisted firm's series.
  out$base_symbol_reused <- tok_df$suffixed & present
  out
}

# ---------------------------------------------------------------------------
# Ranking and selection
# ---------------------------------------------------------------------------

#' Median daily dollar volume (close * volume) per ticker in [from, to].
#' NA when fewer than `min_days` days have both price and volume.
#' @noRd
.osv_dollar_volume <- function(px, from, to, min_days) {
  w <- px[px$date >= as.Date(from) & px$date <= as.Date(to) &
            !is.na(px$close) & !is.na(px$volume), , drop = FALSE]
  if (nrow(w) == 0L) {
    return(data.frame(ticker = character(), dollar_volume = numeric(),
                      n_days = integer(), stringsAsFactors = FALSE))
  }
  w$dv <- w$close * w$volume
  parts <- lapply(split(w, w$ticker), function(g) {
    data.frame(ticker = g$ticker[1L],
               dollar_volume = if (nrow(g) >= min_days) stats::median(g$dv) else NA_real_,
               n_days = nrow(g), stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}

#' Top-n tickers by dollar volume, ties broken alphabetically; NA never ranks.
#' @noRd
.osv_select_top <- function(dv, n, exclude = character()) {
  d <- dv[!is.na(dv$dollar_volume) & !(dv$ticker %in% exclude), , drop = FALSE]
  d <- d[order(-d$dollar_volume, d$ticker), , drop = FALSE]
  d$rank <- seq_len(nrow(d))
  utils::head(d, n)
}

# ---------------------------------------------------------------------------
# Parameters: evaluated from the plan files, never retyped
# ---------------------------------------------------------------------------

#' Return the command expression of `tar_target(<target>, <command>)` found
#' anywhere in the parsed `file`, without evaluating the file.
#' @noRd
.osv_target_command <- function(file, target) {
  walk <- function(e) {
    if (is.call(e)) {
      parts <- as.list(e)
      if (length(parts) >= 3L &&
          identical(parts[[1L]], quote(targets::tar_target)) &&
          identical(parts[[2L]], as.name(target))) {
        return(parts[[3L]])
      }
      for (i in seq_along(parts)) {
        if (identical(parts[[i]], quote(expr = ))) next
        r <- walk(parts[[i]])
        if (!is.null(r)) return(r)
      }
    }
    NULL
  }
  for (ex in as.list(parse(file))) {
    r <- walk(ex)
    if (!is.null(r)) return(r)
  }
  cli::cli_abort("no tar_target named {.val {target}} in {.path {file}}.",
                 call = NULL)
}

#' Evaluate olmar_params and bt_partitions straight from the plan files.
#' @noRd
.osv_load_params <- function(root) {
  bt <- eval(.osv_target_command(file.path(root, "R", "plan_partitions.R"),
                                 "bt_partitions"), envir = baseenv())
  env <- list2env(list(bt_partitions = bt), parent = baseenv())
  p <- eval(.osv_target_command(file.path(root, "R", "plan_olmar.R"),
                                "olmar_params"), envir = env)
  needed <- c("window", "epsilon", "leverage", "cost_bps", "start_date",
              "test_start", "test_end", "tickers")
  miss <- setdiff(needed, names(p))
  if (length(miss) > 0L) {
    cli::cli_abort("olmar_params lacks {.field {miss}}.", call = NULL)
  }
  p
}

# ---------------------------------------------------------------------------
# Backtest wrapper (olmar_backtest itself is reused, not reimplemented)
# ---------------------------------------------------------------------------

#' Wide adjusted-close matrix (date + one column per ticker) from long rows.
#' @noRd
.osv_wide <- function(px, tickers, from) {
  d <- px[px$ticker %in% tickers & px$date >= as.Date(from) &
            !is.na(px$adjusted), c("date", "ticker", "adjusted"), drop = FALSE]
  if (nrow(d) == 0L) return(NULL)
  w <- tidyr::pivot_wider(d, names_from = "ticker", values_from = "adjusted")
  w <- w[order(w$date), , drop = FALSE]
  as.data.frame(w[, c("date", intersect(tickers, names(w))), drop = FALSE])
}

#' Metrics for one daily return series, mirroring olmar_metrics' calc().
#' @noRd
.osv_metrics_one <- function(d, label) {
  d <- d[!is.na(d$net_ret) & !is.na(d$rf_ret), , drop = FALSE]
  n <- nrow(d)
  if (n < 20L) {
    return(data.frame(period = label, days = n, cagr = NA_real_, vol = NA_real_,
                      sharpe = NA_real_, max_dd = NA_real_))
  }
  sr <- .osv_sharpe(d$net_ret, d$rf_ret, periods_per_year = 252L, na.rm = TRUE)
  eq <- cumprod(1 + d$net_ret)
  data.frame(period = label, days = n,
             cagr = sr$ann_ret * 100, vol = sr$ann_vol * 100,
             sharpe = sr$sharpe,
             max_dd = min((eq - cummax(eq)) / cummax(eq)) * 100)
}

#' Run OLMAR-1 and the equal-weight benchmark (leverage = 0) on one price
#' matrix; return Training / Testing / Full Period rows for each.
#' @param rf data.frame(date, rf_ret)
#' @param max_rf_missing fraction of portfolio dates allowed to lack rf
#' @noRd
.osv_run <- function(prices, rf, params, max_rf_missing = 0.01) {
  prices <- prices[rowSums(!is.na(prices[, -1L, drop = FALSE])) >= 2L, , drop = FALSE]
  one <- function(strategy, leverage) {
    port <- olmar_backtest(prices, window = params$window, epsilon = params$epsilon,
                           leverage = leverage, cost_bps = params$cost_bps)
    port$date <- as.Date(port$date)
    port$rf_ret <- rf$rf_ret[match(port$date, rf$date)]
    miss <- mean(is.na(port$rf_ret))
    if (miss > max_rf_missing) {
      cli::cli_abort(c(
        "x" = "risk-free series missing on {round(100 * miss, 1)}% of portfolio dates.",
        "i" = "A missing rf is never treated as zero (fail-loud-not-null)."
      ), call = NULL)
    }
    ts <- as.Date(params$test_start); te <- as.Date(params$test_end)
    out <- rbind(
      .osv_metrics_one(port[port$date < ts, , drop = FALSE], "Training"),
      .osv_metrics_one(port[port$date >= ts & port$date <= te, , drop = FALSE], "Testing"),
      .osv_metrics_one(port, "Full Period"))
    cbind(strategy = strategy, out, stringsAsFactors = FALSE)
  }
  rbind(one("OLMAR-1", params$leverage), one("EqualWeight", 0))
}

# ---------------------------------------------------------------------------
# I/O
# ---------------------------------------------------------------------------

.osv_download <- function(url, dest) {
  dir.create(dirname(dest), showWarnings = FALSE, recursive = TRUE)
  ok <- tryCatch({
    suppressWarnings(utils::download.file(url, dest, quiet = TRUE, mode = "wb"))
    file.exists(dest) && file.size(dest) > 1000
  }, error = function(e) FALSE)
  ok
}

.osv_query <- function(con, sql) DBI::dbGetQuery(con, sql)

.osv_args <- function(argv) {
  kv <- regmatches(argv, regexec("^--([a-z-]+)=(.*)$", argv))
  bad <- argv[lengths(kv) == 0L]
  if (length(bad) > 0L) return(list(error = paste("bad argument:", bad[1L])))
  vals <- stats::setNames(lapply(kv, `[`, 3L), vapply(kv, `[`, "", 2L))
  known <- c("equity", "factors", "membership", "download-to", "draws", "to", "out")
  unk <- setdiff(names(vals), known)
  if (length(unk) > 0L) return(list(error = paste("unknown argument:", unk[1L])))
  vals
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

#' @return integer exit status (0 / 1 / 2 / 3)
#' @noRd
.osv_main <- function(argv, root = here::here(), cfg = list()) {
  cfg <- utils::modifyList(.osv_default_cfg, cfg)
  a <- .osv_args(argv)
  if (!is.null(a$error)) {
    message("USAGE ERROR: ", a$error)
    return(2L)
  }
  indet <- function(why) {
    message("INDETERMINATE: ", why)
    cat("RESULT: INDETERMINATE -- ", why, "\n", sep = "")
    3L
  }
  for (k in c("equity", "factors")) {
    if (is.null(a[[k]]) || !file.exists(a[[k]])) {
      return(indet(sprintf("--%s parquet missing or not found", k)))
    }
  }
  if (!is.null(a$draws)) cfg$n_draws <- as.integer(a$draws)
  if (is.na(cfg$n_draws) || cfg$n_draws < 0L) {
    message("USAGE ERROR: --draws must be a non-negative integer")
    return(2L)
  }

  # -- membership file -------------------------------------------------------
  mem_path <- a$membership
  mem_source <- "local file"
  if (is.null(mem_path)) {
    if (is.null(a[["download-to"]])) {
      return(indet("no --membership file and no --download-to directory given"))
    }
    mem_path <- file.path(a[["download-to"]], "sp500_historical_components.csv")
    if (!.osv_download(.osv_membership_url, mem_path)) {
      return(indet("membership download failed (no network or source moved)"))
    }
    mem_source <- paste("downloaded", format(Sys.Date()), "from", .osv_membership_url)
  } else if (!file.exists(mem_path)) {
    return(indet(sprintf("--membership file not found: %s", mem_path)))
  }
  mem <- tryCatch(.osv_parse_membership(mem_path),
                  error = function(e) e)
  if (inherits(mem, "error")) {
    return(indet(paste("membership file unusable:", conditionMessage(mem))))
  }
  mem_md5 <- unname(tools::md5sum(mem_path))

  # -- parameters from the plan files ---------------------------------------
  params <- .osv_load_params(root)
  suppressPackageStartupMessages(pkgload::load_all(
    file.path(root, "packages", "historicaldata"), quiet = TRUE))
  .osv_env$root <- root

  # -- equity_daily ----------------------------------------------------------
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  eq <- a$equity
  q_eq <- sprintf("read_parquet(%s)", DBI::dbQuoteString(con, eq))
  n_eq <- .osv_query(con, sprintf(
    "SELECT count(DISTINCT ticker) AS n FROM %s", q_eq))$n
  if (n_eq < cfg$min_equity_tickers) {
    return(indet(sprintf("equity_daily has %d distinct tickers (< %d): too thin",
                         n_eq, cfg$min_equity_tickers)))
  }
  end_cap <- if (is.null(a$to)) as.Date("2100-01-01") else as.Date(a$to)

  spy_first <- .osv_query(con, sprintf(
    "SELECT min(CAST(date AS DATE)) AS d FROM %s WHERE ticker = 'SPY' AND CAST(date AS DATE) >= DATE %s",
    q_eq, DBI::dbQuoteString(con, as.character(params$start_date))))$d
  if (length(spy_first) != 1L || is.na(spy_first)) {
    return(indet("cannot determine the first trading day (no SPY rows in the window)"))
  }
  first_day <- as.Date(spy_first)
  snap <- .osv_members_asof(mem, first_day)
  if (length(snap$tokens) < cfg$min_snapshot_tokens) {
    return(indet(sprintf("membership snapshot %s has %d tokens (< %d): too thin",
                         snap$snapshot_date, length(snap$tokens), cfg$min_snapshot_tokens)))
  }
  tok <- .osv_split_tokens(snap$tokens)

  rank_to <- first_day - 1L
  rank_from <- rank_to - 183L
  cur_all <- params$tickers
  syms <- unique(c(tok$symbol, cur_all))
  in_list <- paste(DBI::dbQuoteString(con, syms), collapse = ",")
  px <- .osv_query(con, sprintf(
    "SELECT ticker, CAST(date AS DATE) AS date, close, adjusted, volume FROM %s
       WHERE ticker IN (%s) AND CAST(date AS DATE) >= DATE %s AND CAST(date AS DATE) <= DATE %s",
    q_eq, in_list, DBI::dbQuoteString(con, as.character(rank_from)),
    DBI::dbQuoteString(con, as.character(end_cap))))
  px$date <- as.Date(px$date)
  eq_summary <- .osv_query(con, sprintf(
    "SELECT ticker, min(CAST(date AS DATE)) AS first_date, max(CAST(date AS DATE)) AS last_date
       FROM %s WHERE ticker IN (%s) GROUP BY ticker", q_eq, in_list))

  rf <- .osv_query(con, sprintf(
    "SELECT CAST(date AS DATE) AS date, value / 100.0 AS rf_ret FROM read_parquet(%s)
       WHERE factor_name = 'RF' AND dataset = 'FF3' AND frequency = 'daily'",
    DBI::dbQuoteString(con, a$factors)))
  rf$date <- as.Date(rf$date)
  if (nrow(rf) == 0L || anyNA(rf$rf_ret)) {
    return(indet("factors parquet has no (or NA) FF3 daily RF series"))
  }

  # -- classify the 2010 members --------------------------------------------
  cls <- .osv_classify(tok, eq_summary, first_day, cfg$start_gate_days)
  cls_counts <- as.data.frame(table(class = factor(cls$class, levels = c(
    "usable", "no_history_at_start", "absent_from_equity_daily",
    "delisted_per_source"))), responseName = "n")
  n_members <- nrow(cls)
  n_missing <- sum(cls$class %in% c("absent_from_equity_daily", "delisted_per_source"))

  # -- current universe, split into non-stock core and hindsight stocks ------
  hist_syms <- .osv_all_symbols(mem)
  cur_present <- intersect(cur_all, eq_summary$ticker)
  cur_absent <- setdiff(cur_all, eq_summary$ticker)
  # Non-stock core: never in the S&P 500 history AND already trading at the
  # window start. A ticker that did not exist yet (META, listed 2012) is a
  # hindsight inclusion, not a core instrument, even if the history file lists
  # it under its then-symbol (FB).
  existed <- eq_summary$ticker[as.Date(eq_summary$first_date) <=
                                 first_day + cfg$start_gate_days]
  core <- cur_present[!(cur_present %in% hist_syms) & cur_present %in% existed]
  cur_stocks <- setdiff(cur_present, core)
  cur_stocks_in_2010 <- intersect(cur_stocks, cls$symbol[cls$class == "usable"])
  k <- length(cur_stocks)

  dv <- .osv_dollar_volume(px, rank_from, rank_to, cfg$min_rank_days)
  eligible <- cls$symbol[cls$class == "usable"]
  dv_elig <- dv[dv$ticker %in% eligible, , drop = FALSE]
  ranked_all <- .osv_select_top(dv_elig, Inf, exclude = core)
  if (nrow(ranked_all) < k || k == 0L) {
    cat(sprintf("RESULT: NONE -- %d eligible 2010 members with a dollar-volume rank, need %d\n",
                nrow(ranked_all), k))
    return(1L)
  }
  top <- utils::head(ranked_all, k)
  cur_rank <- ranked_all$rank[match(cur_stocks, ranked_all$ticker)]

  # -- backtests -------------------------------------------------------------
  w_cur <- .osv_wide(px, cur_present, params$start_date)
  w_alt <- .osv_wide(px, c(core, top$ticker), params$start_date)
  m_cur <- cbind(universe = "current", .osv_run(w_cur, rf, params))
  m_alt <- cbind(universe = "alt_top_by_2009H2_dollar_volume", .osv_run(w_alt, rf, params))
  results <- rbind(m_cur, m_alt)

  draws <- NULL
  if (cfg$n_draws > 0L) {
    set.seed(cfg$seed)
    pool <- setdiff(ranked_all$ticker, core)
    w_pool <- .osv_wide(px, c(core, pool), params$start_date)
    draws <- do.call(rbind, lapply(seq_len(cfg$n_draws), function(i) {
      pick <- sample(pool, k)
      r <- .osv_run(w_pool[, c("date", core, pick), drop = FALSE], rf, params)
      r <- r[r$period == "Full Period", , drop = FALSE]
      cbind(draw = i, r)
    }))
  }

  # -- report ----------------------------------------------------------------
  cat("\n=== OLMAR-1 survivorship (#977) ===\n")
  cat(sprintf("window start (first trading day): %s | end of data used: %s\n",
              first_day, max(w_cur$date)))
  cat(sprintf("membership snapshot: %s (%d tokens) | file md5 %s | %s\n",
              snap$snapshot_date, n_members, mem_md5, mem_source))
  cat(sprintf("rank window: %s .. %s | metric: median close*volume\n", rank_from, rank_to))
  cat("\n-- 2010 members vs what equity_daily can supply --\n")
  print(cls_counts, row.names = FALSE)
  cat(sprintf("members equity_daily cannot supply: %d of %d (%.1f%%)\n",
              n_missing, n_members, 100 * n_missing / n_members))
  cat(sprintf("delisted-per-source tokens whose base symbol is reused in equity_daily (excluded): %d\n",
              sum(cls$base_symbol_reused)))
  cat("\n-- current list --\n")
  cat(sprintf("declared %d, present in equity_daily %d, absent: %s\n",
              length(cur_all), length(cur_present),
              if (length(cur_absent)) paste(cur_absent, collapse = " ") else "none"))
  cat(sprintf("non-stock core (never in S&P 500 history, trading at window start): %s\n", paste(core, collapse = " ")))
  cat(sprintf("hindsight stocks k = %d; were in the 2010 snapshot and usable: %d (%s)\n",
              k, length(cur_stocks_in_2010), paste(cur_stocks_in_2010, collapse = " ")))
  cat(sprintf("their 2009H2 dollar-volume rank among %d eligible members: %s\n",
              nrow(ranked_all),
              paste(sprintf("%s=%s", cur_stocks, ifelse(is.na(cur_rank), "n/a", cur_rank)),
                    collapse = " ")))
  cat("\n-- alternative (hindsight-free) stocks --\n")
  cat(paste(top$ticker, collapse = " "), "\n")
  cat("\n-- metrics (percent; Sharpe is rf-adjusted, net of costs) --\n")
  print(results, row.names = FALSE, digits = 4)

  full <- results[results$period == "Full Period", ]
  g <- function(u, s, col) full[[col]][full$universe == u & full$strategy == s]
  u2 <- "alt_top_by_2009H2_dollar_volume"
  delta <- data.frame(
    strategy = c("OLMAR-1", "EqualWeight", "OLMAR-minus-EW"),
    d_sharpe = c(g("current", "OLMAR-1", "sharpe") - g(u2, "OLMAR-1", "sharpe"),
                 g("current", "EqualWeight", "sharpe") - g(u2, "EqualWeight", "sharpe"),
                 (g("current", "OLMAR-1", "sharpe") - g("current", "EqualWeight", "sharpe")) -
                   (g(u2, "OLMAR-1", "sharpe") - g(u2, "EqualWeight", "sharpe"))),
    d_cagr_pp = c(g("current", "OLMAR-1", "cagr") - g(u2, "OLMAR-1", "cagr"),
                  g("current", "EqualWeight", "cagr") - g(u2, "EqualWeight", "cagr"),
                  (g("current", "OLMAR-1", "cagr") - g("current", "EqualWeight", "cagr")) -
                    (g(u2, "OLMAR-1", "cagr") - g(u2, "EqualWeight", "cagr"))))
  cat("\n-- delta = current minus hindsight-free alternative, Full Period --\n")
  print(delta, row.names = FALSE, digits = 4)

  if (!is.null(draws)) {
    cat(sprintf("\n-- %d random same-size alternatives (seed %d), Full Period --\n",
                cfg$n_draws, cfg$seed))
    for (s in c("OLMAR-1", "EqualWeight")) {
      d <- draws[draws$strategy == s, ]
      cur_sh <- g("current", s, "sharpe"); cur_cg <- g("current", s, "cagr")
      cat(sprintf(
        "%-12s Sharpe p05/median/p95 = %.3f / %.3f / %.3f | CAGR %% = %.2f / %.2f / %.2f | current Sharpe %.3f ranks above %.0f%% of draws, CAGR %.2f above %.0f%%\n",
        s, stats::quantile(d$sharpe, .05), stats::median(d$sharpe), stats::quantile(d$sharpe, .95),
        stats::quantile(d$cagr, .05), stats::median(d$cagr), stats::quantile(d$cagr, .95),
        cur_sh, 100 * mean(d$sharpe < cur_sh), cur_cg, 100 * mean(d$cagr < cur_cg)))
    }
  }
  cat(sprintf(
    "\nRESULT: ESTIMATE -- %d of %d 2010 members are invisible to equity_daily; the deltas above are a LOWER bound on the bias if failed names are the ones missing (sign of the unseen part is unknown).\n",
    n_missing, n_members))

  if (!is.null(a$out)) {
    dir.create(a$out, showWarnings = FALSE, recursive = TRUE)
    utils::write.csv(results, file.path(a$out, "results.csv"), row.names = FALSE)
    utils::write.csv(delta, file.path(a$out, "deltas.csv"), row.names = FALSE)
    utils::write.csv(cls_counts, file.path(a$out, "membership_classes.csv"), row.names = FALSE)
    utils::write.csv(cbind(top[, c("rank", "ticker", "dollar_volume")]),
                     file.path(a$out, "alt_stocks.csv"), row.names = FALSE)
    if (!is.null(draws)) {
      utils::write.csv(draws, file.path(a$out, "draws.csv"), row.names = FALSE)
    }
  }
  0L
}

# Run only as the Rscript entry point (sys.nframe() == 0), like
# scripts/check_pipeline_errors.R, so tests can source() the functions.
if (sys.nframe() == 0L) {
  suppressPackageStartupMessages(library(DBI))
  file_arg <- grep("^--file=", commandArgs(), value = TRUE)[1L]
  root <- normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), ".."))
  status <- tryCatch(
    .osv_main(commandArgs(trailingOnly = TRUE), root = root),
    error = function(e) {
      message("INDETERMINATE (unhandled error): ", conditionMessage(e))
      3L
    })
  quit(status = status, save = "no")
}
