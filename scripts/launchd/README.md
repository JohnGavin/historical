# launchd job templates (Hyperliquid, #1080)

These are templates. Nothing in the repo installs or loads them; the owner does.

| Template | Runs | Log |
|---|---|---|
| `io.github.johngavin.historical.hyperliquid-weekly.plist` | `scripts/run_hyperliquid_weekly.sh`, Sunday 03:00 local | `~/Library/Logs/historical/hyperliquid_weekly.log` |
| `io.github.johngavin.historical.hyperliquid-ctx-poll.plist` | `scripts/run_hyperliquid_ctx_poll.sh`, every 300 s | `~/Library/Logs/historical/hyperliquid_ctx_poll.log` |

## One-time install (owner)

Each template holds `__REPO__`, a placeholder for the absolute path of the main
checkout. Copy (do not symlink) each plist into `~/Library/LaunchAgents/`,
substituting the path, then bootstrap it from there. A plist bootstrapped from
anywhere else lasts only until logout or reboot.

```sh
REPO=/absolute/path/to/historical
for j in hyperliquid-weekly hyperliquid-ctx-poll; do
  sed "s|__REPO__|$REPO|g" "$REPO/scripts/launchd/io.github.johngavin.historical.$j.plist" \
    > ~/Library/LaunchAgents/io.github.johngavin.historical.$j.plist
  plutil -lint ~/Library/LaunchAgents/io.github.johngavin.historical.$j.plist
  launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/io.github.johngavin.historical.$j.plist
done
```

Uninstall: `launchctl bootout gui/$(id -u)/io.github.johngavin.historical.<name>`
(then delete the copy in `~/Library/LaunchAgents/`).

Status: `launchctl print gui/$(id -u)/io.github.johngavin.historical.<name>`, or
run `scripts/launchd/check_jobs.sh` (read-only; reports loaded / not loaded and
the age of each log, flags STALE if the poller log is older than 15 minutes or
the weekly log older than 8 days; exit 0 fine, 1 a finding, 3 cannot tell).

`RunAtLoad` is false for the weekly job and true for the poller (it records once
as soon as it is loaded). Neither sets `KeepAlive`.

## Why these intervals

- **Weekly fetch.** The API keeps the last 5000 bars per interval: about 208 days
  of hourly bars and about 52 days of 15-minute bars. A weekly run loses nothing.
  The wrapper passes `--resume`, so an interrupted run continues where it stopped.
- **5-minute context poll.** `metaAndAssetCtxs` has no history; only the current
  snapshot exists, so the only way to have mid and oracle prices later is to
  record them now. `nix develop` starts in about 13 s when warm, so a 300 s
  interval is comfortable.

## Gaps are expected

launchd does not run jobs while the Mac sleeps, and `StartInterval` does not
catch up afterwards. The poller therefore leaves holes (laptop asleep, lid
closed). Nothing imputes them: `fetched_at` is the true request time and `slot`
is its 5-minute floor, so a later study finds the gaps as missing slots.

## Reboots, sleep and upgrades

- LaunchAgents run only while the owner is logged in.
- `StartInterval` ticks missed during sleep are not replayed.
- A `StartCalendarInterval` run missed during sleep fires once on wake, but one
  missed while the Mac is powered off does not.
- macOS may list the jobs under System Settings > General > Login Items &
  Extensions > "Allow in the Background", where they can be switched off.
- An installed copy does not update when the repo copy changes: re-copy and
  re-bootstrap (`bootout` first) after editing.

## Exit codes

Both wrappers pass the script's exit code through unchanged: 0 ok, 1 partial
(weekly fetch only), 2 usage or could not start, 3 INDETERMINATE (source
unreachable, rate-limited, or an empty result). 3 is never reported as 0.
