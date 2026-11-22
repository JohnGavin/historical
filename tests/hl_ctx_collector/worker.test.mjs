// Tests for cloudflare/hl-ctx-collector/worker.js. No network: `fetch` and the KV
// binding are stubs fed with recorded Hyperliquid replies (tests/testthat/fixtures/
// hl_ctx_collector/). Run: node --test tests/hl_ctx_collector/worker.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, writeFileSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..", "..");
const fx = (name) => readFileSync(join(root, "tests", "testthat", "fixtures", "hl_ctx_collector", name));

// Import the Worker as a module whatever the package's module type is.
const copy = join(mkdtempSync(join(tmpdir(), "hl-worker-")), "worker.mjs");
writeFileSync(copy, readFileSync(join(root, "cloudflare", "hl-ctx-collector", "worker.js")));
const worker = (await import(pathToFileURL(copy).href)).default;

const PERP_DEXS = fx("perpdexs.json"); // [null, xyz, flx]
const XYZ = fx("metaandassetctxs_xyz.json");
const FLX = fx("metaandassetctxs_flx.json");
// The core exchange: not a recorded reply. It carries bytes a re-serialising Worker
// would change (extra whitespace, a multi-byte character) to show bodies pass through.
const MAIN = Buffer.concat([XYZ, Buffer.from("\n  é中 \n")]);

const SCHEDULED = Date.parse("2026-11-22T12:05:00Z");
const event = { scheduledTime: SCHEDULED, cron: "*/5 * * * *" };

// A fetch stub. `routes(body)` returns {status, body} or throws. Records every call
// and the peak number of simultaneous requests.
function stubFetch(routes) {
  const calls = [];
  let live = 0;
  const state = { calls, peak: 0 };
  globalThis.fetch = async (url, init) => {
    assert.equal(url, "https://api.hyperliquid.xyz/info");
    assert.equal(init.method, "POST");
    const body = JSON.parse(init.body);
    calls.push(body);
    live += 1;
    state.peak = Math.max(state.peak, live);
    await new Promise((r) => setTimeout(r, 2));
    live -= 1;
    const r = routes(body);
    return { status: r.status, arrayBuffer: async () => new Uint8Array(r.body).buffer.slice(0) };
  };
  return state;
}

function stubKv() {
  const puts = [];
  return { puts, env: { HL_CTX: { put: async (key, value, opts) => puts.push({ key, value, opts }) } } };
}

// Read a stored value back: header, then bodies by their declared lengths.
function unframe(value) {
  const buf = Buffer.from(value);
  const nl = buf.indexOf(0x0a);
  const header = JSON.parse(buf.subarray(0, nl).toString("utf8"));
  let at = nl + 1;
  const bodies = header.replies.map((r) => {
    const b = buf.subarray(at, at + r.bytes);
    at += r.bytes;
    return b;
  });
  assert.equal(at, buf.length, "no stray bytes after the last body");
  return { header, bodies };
}

const standard = (body) => {
  if (body.type === "perpDexs") return { status: 200, body: PERP_DEXS };
  if (body.dex === undefined) return { status: 200, body: MAIN };
  if (body.dex === "xyz") return { status: 200, body: XYZ };
  if (body.dex === "flx") return { status: 200, body: FLX };
  throw new Error("unexpected request " + JSON.stringify(body));
};

test("the exchange list comes from perpDexs: core exchange without dex, the others by name", async () => {
  const f = stubFetch(standard);
  const kv = stubKv();
  await worker.scheduled(event, kv.env, {});
  assert.deepEqual(f.calls, [
    { type: "perpDexs" },
    { type: "metaAndAssetCtxs" },
    { type: "metaAndAssetCtxs", dex: "xyz" },
    { type: "metaAndAssetCtxs", dex: "flx" },
  ]);
  const { header } = unframe(kv.puts[0].value);
  assert.deepEqual(header.replies.map((r) => r.dex), ["", "xyz", "flx"]);
  assert.equal(header.truncated, false);
});

test("the key and slot come from the scheduled time, not the clock; 10-day expiry", async () => {
  stubFetch(standard);
  const kv = stubKv();
  const realNow = Date.now;
  Date.now = () => Date.parse("2031-01-01T00:00:00Z"); // the run-time clock must not matter
  try {
    await worker.scheduled(event, kv.env, {});
  } finally {
    Date.now = realNow;
  }
  assert.equal(kv.puts.length, 1);
  assert.equal(kv.puts[0].key, "ctx/2026-11-22/1205");
  assert.deepEqual(kv.puts[0].opts, { expirationTtl: 864000 });
  const { header } = unframe(kv.puts[0].value);
  assert.equal(header.slot, "2026-11-22T12:05:00.000Z");
  assert.equal(header.format, "hl-ctx-v1");
  assert.equal(header.collector, "cf-1");
  assert.equal(header.replies[0].fetched_at_us, String(Date.parse("2031-01-01T00:00:00Z") * 1000));
  // midnight edge: 23:55 on one day, 00:00 on the next
  const k2 = stubKv();
  await worker.scheduled({ scheduledTime: Date.parse("2026-11-22T23:55:00Z") }, k2.env, {});
  await worker.scheduled({ scheduledTime: Date.parse("2026-11-23T00:00:00Z") }, k2.env, {});
  assert.deepEqual(k2.puts.map((p) => p.key), ["ctx/2026-11-22/2355", "ctx/2026-11-23/0000"]);
});

test("framing round-trips: every body comes back byte for byte", async () => {
  stubFetch(standard);
  const kv = stubKv();
  await worker.scheduled(event, kv.env, {});
  const { header, bodies } = unframe(kv.puts[0].value);
  assert.deepEqual(header.replies.map((r) => [r.status, r.ok]), [[200, true], [200, true], [200, true]]);
  assert.ok(bodies[0].equals(MAIN));
  assert.ok(bodies[1].equals(XYZ));
  assert.ok(bodies[2].equals(FLX));
  assert.deepEqual(header.replies.map((r) => r.bytes), [MAIN.length, XYZ.length, FLX.length]);
  assert.ok(header.perp_dexs.ok);
});

test("a 429 HTML body becomes ok:false without breaking the other replies", async () => {
  stubFetch((b) =>
    b.dex === "xyz" ? { status: 429, body: Buffer.from("<html>Too Many Requests</html>") } : standard(b),
  );
  const kv = stubKv();
  await worker.scheduled(event, kv.env, {});
  const { header, bodies } = unframe(kv.puts[0].value);
  assert.deepEqual(header.replies.map((r) => [r.dex, r.status, r.ok, r.bytes === 0]), [
    ["", 200, true, false],
    ["xyz", 429, false, true],
    ["flx", 200, true, false],
  ]);
  assert.ok(bodies[0].equals(MAIN));
  assert.equal(bodies[1].length, 0);
  assert.ok(bodies[2].equals(FLX));
});

test("a request that throws is status 0, ok:false, and the others still arrive", async () => {
  stubFetch((b) => {
    if (b.dex === "flx") throw new Error("network down");
    return standard(b);
  });
  const kv = stubKv();
  await worker.scheduled(event, kv.env, {});
  const { header } = unframe(kv.puts[0].value);
  assert.deepEqual(header.replies.map((r) => [r.dex, r.status, r.ok]), [
    ["", 200, true],
    ["xyz", 200, true],
    ["flx", 0, false],
  ]);
});

test("a perpDexs failure writes a header-only marker and polls nothing else", async () => {
  for (const routes of [
    () => ({ status: 500, body: Buffer.from("oops") }),
    () => {
      throw new Error("network down");
    },
    () => ({ status: 200, body: Buffer.from("not json") }),
    () => ({ status: 200, body: Buffer.from("[]") }),
  ]) {
    const f = stubFetch(routes);
    const kv = stubKv();
    await worker.scheduled(event, kv.env, {});
    assert.equal(f.calls.length, 1);
    assert.equal(kv.puts.length, 1);
    assert.equal(kv.puts[0].key, "ctx/2026-11-22/1205");
    const { header } = unframe(kv.puts[0].value);
    assert.deepEqual(header.replies, []);
    assert.equal(header.perp_dexs.ok, false);
    const text = Buffer.from(kv.puts[0].value).toString("utf8");
    assert.equal(text.indexOf("\n"), text.length - 1, "the marker is the header line alone");
  }
});

test("more than 48 exchanges: the first 48 are polled, truncated is recorded, at most 6 at once", async () => {
  const names = Array.from({ length: 60 }, (_, i) => (i === 0 ? null : { name: "d" + i }));
  const f = stubFetch((b) =>
    b.type === "perpDexs" ? { status: 200, body: Buffer.from(JSON.stringify(names)) } : { status: 200, body: XYZ },
  );
  const kv = stubKv();
  await worker.scheduled(event, kv.env, {});
  assert.equal(f.calls.length, 1 + 48); // inside the 50-subrequest limit
  assert.ok(f.peak <= 6, "peak concurrency " + f.peak);
  const { header } = unframe(kv.puts[0].value);
  assert.equal(header.replies.length, 48);
  assert.equal(header.truncated, true);
  assert.equal(header.replies[0].dex, "");
  assert.equal(header.replies[47].dex, "d47");
});

test("the sha256 recorded in the README is the hash of worker.js", async () => {
  const { createHash } = await import("node:crypto");
  const dir = join(root, "cloudflare", "hl-ctx-collector");
  const actual = createHash("sha256").update(readFileSync(join(dir, "worker.js"))).digest("hex");
  const m = readFileSync(join(dir, "README.md"), "utf8").match(/sha256 of `worker\.js`: `([0-9a-f]{64})`/);
  assert.ok(m, "README has no 'sha256 of `worker.js`: `<hex>`' line");
  assert.equal(m[1], actual);
});
