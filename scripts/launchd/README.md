# launchd job templates (Hyperliquid, #1080)

These are templates. Nothing in the repo installs or loads them; the owner does.

| Template | Runs | Log |
|---|---|---|
| `io.github.johngavin.historical.hyperliquid-weekly.plist` | `scripts/run_hyperliquid_weekly.sh` (the candle fetch, then the market reference step), Sunday 03:00 local, and at load | `~/Library/Logs/historical/hyperliquid_weekly.log` |
| `io.github.johngavin.historical.hyperliquid-ctx-poll.plist` | `scripts/run_hyperliquid_ctx_poll.sh` (every exchange, one run), every 300 s, and at load | `~/Library/Logs/historical/hyperliquid_ctx_poll.log` |

The plists call the wrappers with no arguments. Changing what a wrapper runs
(#1084: the poller covers all exchanges by default, the weekly wrapper adds the
market reference step) therefore needs no reinstall: launchd starts the wrapper
file in the checkout, so the new behaviour applies from the next run. Only a change
to a plist (schedule, arguments, paths) needs `install_jobs.sh --apply`.

## Install (owner)

Run from the main checkout (the rendered plists point at the checkout the script
lives in):

```sh
scripts/launchd/install_jobs.sh            # dry run (the default): prints, changes nothing
scripts/launchd/install_jobs.sh --apply    # does it
```

For each template it renders `__REPO__` to this checkout's absolute path, lints
the result, copies it (a copy, not a symlink) to `~/Library/LaunchAgents/`,
runs `launchctl bootout` first if the job is already loaded, then
`launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/<label>.plist`. It
refuses to bootstrap from any path outside `~/Library/LaunchAgents`: a job
bootstrapped from the repo path is gone after the next logout or reboot.

By hand (the same steps): `sed "s|__REPO__|$REPO|g" <template> > ~/Library/LaunchAgents/<label>.plist`,
then `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/<label>.plist`.

Uninstall: `launchctl bootout gui/$(id -u)/<label>` (then delete the copy in
`~/Library/LaunchAgents/`).

Status: `launchctl print gui/$(id -u)/<label>`, or `scripts/launchd/check_jobs.sh`
(read-only). It reports loaded / NOT LOADED, FAILs a job loaded from a path
outside `~/Library/LaunchAgents` ("will not survive reboot"), FAILs an installed
copy that differs from the rendered repo template ("stale install"), and flags a
log STALE when the poller log is older than 15 minutes or the weekly log older
than 8 days. Exit 0 fine, 1 a finding, 3 cannot tell (not loaded, a log missing).

`RunAtLoad` is true for both jobs. The poller records once as soon as it loads.
The weekly fetch (it already uses `--resume`) runs at login, so a run missed
while the Mac was off happens then; installing it therefore starts a long fetch
immediately. Neither sets `KeepAlive`.

## Why these intervals

- **Weekly fetch.** The API keeps the last 5000 bars per interval: about 208 days
  of hourly bars and about 52 days of 15-minute bars. A weekly run loses nothing.
  The wrapper passes `--resume`, so an interrupted run continues where it stopped.
- **5-minute context poll.** `metaAndAssetCtxs` has no history; only the current
  snapshot exists, so the only way to have mid and oracle prices later is to
  record them now. Each run polls every exchange (the core one and every add-on
  exchange): one `perpDexs` request lists them, then one `metaAndAssetCtxs`
  request each, 12 requests today. The API allows 1200 weight per minute per IP
  and each of these requests weighs 20 ([rate limits](https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/api/rate-limits-and-user-limits)),
  so a run costs 240, once every 5 minutes. The weekly fetch is paced at 900 per
  minute, so a poll in the same minute still totals 1140, under 1200. The run takes
  a few seconds against the 200 s budget; the poller starts no request without
  25 s of budget left.
- **Weekly market reference step.** After the candle fetch,
  `scripts/fetch_hl_market_reference.R` writes `data/dist/perp_markets.parquet`
  (long names, categories, definitions and source pages; see
  `docs/DATA_SOURCES.md`). The exchange table `perp_dexs.parquet` comes from the
  candle fetch itself.

## How the poller wrapper protects a run

`scripts/run_hyperliquid_ctx_poll.sh` waits up to 45 s for the API host to
resolve (a wake from sleep often has no network yet; else exit 3), runs under a
hard 240 s deadline (a timed-out run exits 3, and runs never overlap), and
avoids evaluating the flake each run: `nix print-dev-env --profile` is built
once per `flake.nix` / `flake.lock` content into `~/Library/Caches/historical/`
(the profile is a GC root) and sourced afterwards (about 2 s against about 13 s
for a warm `nix develop`). If that cache is missing, unbuildable or its store
paths were collected, the wrapper falls back to plain `nix develop`. Old cache
files from earlier flake contents are not removed automatically. In R the poller
retries a non-429 error (3 attempts, about 60 s at most), never retries HTTP
429, stamps `fetched_at` after each reply arrives, and records a `collector`
column so a second collector can be merged by slot later. The collector is a
configured label, not the host name: the environment variable `HL_POLL_COLLECTOR`,
default `laptop-1` (a launchd job does not need it set, so the plist is unchanged).
It also stores each market's `is_delisted` flag (rows from before #1084 have NA
there).

**Where the poller writes (#1082).** One parquet file per UTC day and collector,
`data/dist/perp_ctx_5m/date=YYYY-MM-DD/<collector>.parquet`, so a run rewrites only
today's file and its cost does not grow with the history (the single file it
replaces was rewritten whole every 5 minutes). Read it with `hl_ctx_read(out_dir)`
or `hl_ctx_open(out_dir)` (`scripts/poll_hyperliquid_ctx.R`). The raw replies go to
`data/raw/hyperliquid/ctx_poll/<UTC date>/<collector>_<HHMMSS>.json.gz`: one
gzipped file per run (288 a day) with every reply and its `fetched_at`, which
`hl_ctx_replay_day()` can rebuild a day's parquet from. The weekly fetch's own raw
files (`data/raw/hyperliquid/<UTC date>/*.json`) are unchanged. After pulling this
change run `Rscript scripts/migrate_hl_ctx_to_daily.R` (a dry run; `--apply` to
write) once to split the old single file; no job needs reinstalling.

A **partial run** (some exchanges polled, some failed, not reached or
rate-limited) writes the rows of the exchanges that worked and exits 3, never 0:
the failed exchanges are named in the log and the next run is the retry. If the
exchange list itself cannot be read, the exchanges of the last
`perp_dexs.parquet` (else the core exchange alone) are polled and the run is
still 3. A rate limit stops the run: the remaining exchanges are not attempted.

## Gaps are expected

launchd does not run jobs while the Mac sleeps, and `StartInterval` does not
catch up afterwards. The poller therefore leaves holes (laptop asleep, lid
closed). Nothing imputes them: `slot` is `fetched_at` floored to 5 minutes, so a
later study finds the gaps as missing slots.

## Reboots, sleep and upgrades

- LaunchAgents run only while the owner is logged in.
- `StartInterval` ticks missed during sleep are not replayed.
- A `StartCalendarInterval` run missed during sleep fires once on wake, but one
  missed while the Mac is powered off does not. That is why the weekly job also
  has `RunAtLoad` true: after a power-off it runs at the next login, and
  `--resume` makes a repeat harmless.
- macOS may list the jobs under System Settings > General > Login Items &
  Extensions > "Allow in the Background", where they can be switched off.
- An installed copy does not update when the repo copy changes: re-run
  `install_jobs.sh --apply` (it boots the job out first). `check_jobs.sh` reports
  a "stale install" when they differ.

## Exit codes

Both wrappers pass the script's exit code through unchanged: 0 ok, 1 partial
(weekly fetch only), 2 usage or could not start, 3 INDETERMINATE (source
unreachable, rate-limited, DNS never resolved, deadline hit, or an empty result).
3 is never reported as 0.
