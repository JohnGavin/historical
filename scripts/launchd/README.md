# launchd job templates (Hyperliquid, #1080)

These are templates. Nothing in the repo installs or loads them; the owner does.

| Template | Runs | Log |
|---|---|---|
| `io.github.johngavin.historical.hyperliquid-weekly.plist` | `scripts/run_hyperliquid_weekly.sh`, Sunday 03:00 local, and at load | `~/Library/Logs/historical/hyperliquid_weekly.log` |
| `io.github.johngavin.historical.hyperliquid-ctx-poll.plist` | `scripts/run_hyperliquid_ctx_poll.sh`, every 300 s, and at load | `~/Library/Logs/historical/hyperliquid_ctx_poll.log` |

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
  record them now.

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
429, stamps `fetched_at` after the reply arrives, and records a `collector`
column (the host name) so a second collector can be merged by slot later.

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
