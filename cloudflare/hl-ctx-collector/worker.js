// Hyperliquid 5-minute context collector (Cloudflare Worker, cron trigger).
//
// Every 5 minutes: ask `perpDexs` which exchanges exist, ask `metaAndAssetCtxs`
// for the core exchange ("") and every listed exchange, and store ALL the reply
// bytes, unparsed, in ONE Workers KV value. Nothing is parsed except the
// `perpDexs` reply (its names are the only thing needed), nothing is compressed,
// nothing is dropped. The daily drain (scripts/drain_hl_ctx_kv.R) reads these
// values, parses them with the project's own R code and publishes the day.
//
// Stored value (format "hl-ctx-v1"): ONE header line of JSON, a newline, then the
// reply bodies as raw bytes, back to back, in the header's `replies` order. Each
// body's length is `bytes` in the header, so one bad body (an HTML rate-limit
// page, say) cannot corrupt the others. A failed or non-200 reply has ok:false,
// bytes:0 and no body. If `perpDexs` itself fails the value is the header alone.
//
// Key `ctx/<YYYY-MM-DD>/<HHMM>` comes from the cron event's scheduled time (UTC),
// never from the clock at run time, so a late start still files under its slot.
// The value expires by itself after 10 days; there is no delete job.
// Binding: HL_CTX (a Workers KV namespace). No secret: the info API is public.

const INFO_URL = "https://api.hyperliquid.xyz/info";
const MAX_EXCHANGES = 48; // 50 subrequests per run, minus `perpDexs` (1) and a margin (1)
const PARALLEL = 6; // simultaneous connections allowed per invocation
const TTL_SECONDS = 864000; // 10 days
const encoder = new TextEncoder();

// One info request. Never throws: a network failure is status 0, ok false.
async function info(body) {
  try {
    const res = await fetch(INFO_URL, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    });
    const bytes = new Uint8Array(await res.arrayBuffer());
    return { status: res.status, ok: res.status === 200, bytes, at: Date.now() };
  } catch (err) {
    return { status: 0, ok: false, bytes: new Uint8Array(0), at: Date.now() };
  }
}

// perpDexs -> exchange names, "" for the core exchange (its entry is null).
function exchangeNames(reply) {
  if (!reply.ok) return null;
  try {
    const list = JSON.parse(new TextDecoder().decode(reply.bytes));
    if (!Array.isArray(list) || list.length === 0) return null;
    const names = list.map((d) => (d === null ? "" : String(d.name)));
    return [...new Set(names)];
  } catch (err) {
    return null;
  }
}

function frame(header, bodies) {
  const head = encoder.encode(JSON.stringify(header) + "\n");
  const out = new Uint8Array(head.length + bodies.reduce((n, b) => n + b.length, 0));
  out.set(head, 0);
  let at = head.length;
  for (const b of bodies) {
    out.set(b, at);
    at += b.length;
  }
  return out;
}

export default {
  async scheduled(event, env, ctx) {
    const slot = new Date(event.scheduledTime).toISOString();
    const key = `ctx/${slot.slice(0, 10)}/${slot.slice(11, 13)}${slot.slice(14, 16)}`;
    const header = { format: "hl-ctx-v1", collector: "cf-1", slot, replies: [] };

    const listed = await info({ type: "perpDexs" });
    header.perp_dexs = { status: listed.status, ok: listed.ok, fetched_at_us: String(listed.at * 1000) };
    const names = exchangeNames(listed);
    const bodies = [];
    if (names === null) {
      header.perp_dexs.ok = false; // a 200 that is not a usable list is a failure too
    } else {
      header.truncated = names.length > MAX_EXCHANGES;
      const todo = names.slice(0, MAX_EXCHANGES);
      for (let i = 0; i < todo.length; i += PARALLEL) {
        const batch = todo.slice(i, i + PARALLEL);
        const got = await Promise.all(
          batch.map((dex) => info(dex === "" ? { type: "metaAndAssetCtxs" } : { type: "metaAndAssetCtxs", dex })),
        );
        got.forEach((r, j) => {
          const body = r.ok ? r.bytes : new Uint8Array(0);
          header.replies.push({
            dex: batch[j],
            fetched_at_us: String(r.at * 1000),
            status: r.status,
            ok: r.ok,
            bytes: body.length,
          });
          bodies.push(body);
        });
      }
    }
    await env.HL_CTX.put(key, frame(header, bodies), { expirationTtl: TTL_SECONDS });
  },
};
