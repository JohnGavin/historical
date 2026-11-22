# hl-ctx-collector: Hyperliquid 5-minute snapshots on Cloudflare (#1088)

A Cloudflare Worker (a small program that Cloudflare runs for you) with a cron
trigger. Every 5 minutes it fetches the Hyperliquid `metaAndAssetCtxs` reply of
every exchange and stores the raw bytes in one Workers KV value. Nothing runs on
the laptop. A daily GitHub Actions job (`.github/workflows/hl-ctx-drain.yml`,
script `scripts/drain_hl_ctx_kv.R`) turns those values into the public dataset
on Hugging Face (prefix `hyperliquid/`). KV is only a 10-day buffer.

- `worker.js`: the whole Worker, plain JavaScript, no dependencies, about 100 lines.
- Stored value, key `ctx/<YYYY-MM-DD>/<HHMM>` (UTC slot of the cron event): one JSON
  header line (`format`, `collector` = `cf-1`, `slot`, one entry per reply with
  `dex`, `fetched_at_us`, `status`, `ok`, `bytes`), a newline, then the reply bodies
  as raw bytes in header order. A failed reply is `ok:false` with no body. If
  `perpDexs` fails the value is the header alone, so a failed fetch is told apart from
  a missing run.
- Expiry: 10 days (`expirationTtl` 864000), so there is no delete job.
- Test: `node --test tests/hl_ctx_collector/worker.test.mjs` (also run by the R test
  suite, `tests/testthat/test-hl-ctx-collector.R`). It stubs `fetch` and the KV binding
  with recorded replies.

## Free-plan limits this stays inside

Cloudflare docs, read 2026-11-22: 100,000 Worker requests a day (we use 288); 50
subrequests per run (we use at most 49: `perpDexs` plus 48 exchanges; more than 48
exchanges are cut off and `truncated:true` is recorded); 1,000 KV writes a day to
different keys (we use 288); 1 GB KV storage (10 days is about 0.7 GB); 10 ms CPU per
cron run (the Worker only moves bytes). Reading values through the REST API is limited
to 1,200 requests per 5 minutes; the drain paces itself under that.

## Owner steps (cannot be scripted)

1. Create a free Cloudflare account that is used for nothing else, so the API token
   in step 6 can reach nothing but this data. No card is needed for the free Workers
   plan (confirm at sign-up).
2. Create a KV namespace (Workers & Pages, KV, Create). Note its ID.
3. Create a Worker, open its code editor, replace the code with the contents of
   `worker.js`, and deploy. Menu names move; the docs for the dashboard editor are at
   <https://developers.cloudflare.com/workers/get-started/dashboard/>.
4. In the Worker's settings add a KV namespace binding named exactly `HL_CTX`, pointing
   at the namespace from step 2.
5. In the Worker's settings add a Cron Trigger with the expression `*/5 * * * *`.
6. Create an API token with the single permission Account, Workers KV Storage, Read
   (account level; it cannot be limited to one namespace). Note the account ID.
7. Add three repository secrets on the GitHub repository: `CF_ACCOUNT_ID`,
   `CF_KV_NAMESPACE_ID`, `CF_API_TOKEN`. (`HF_TOKEN` already exists for the other
   workflows and needs write access to the dataset.)
8. Confirm the pasted code is the committed code: the dashboard editor shows the text;
   copy it into a file and compare its hash with the one below.

## Committed file hash

sha256 of `worker.js`: `83cac43d9b7e818daad1798987a1ab2df613eaa0b73563973ef38d0ebd6e710a`

Recompute after any edit (macOS; on Linux use `sha256sum`) and update the line above:

```sh
shasum -a 256 cloudflare/hl-ctx-collector/worker.js
```

The test fails when this line and the file disagree.
