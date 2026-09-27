import assert from "node:assert/strict";
import { readFile, access } from "node:fs/promises";
import test from "node:test";
import { gzipSync, gunzipSync } from "node:zlib";
import { createHash } from "node:crypto";
import worker from "./worker.ts";
import { brickBasEngine } from "./engine.ts";

const bundleDir = new URL("../dist/site/demos/brick-bas/", import.meta.url);

test("routes only the game's own paths", async () => {
  const seen = [];
  const env = { ASSETS: { fetch: async (request) => { seen.push(new URL(request.url).pathname); return new Response("ok"); } } };
  for (const path of ["/", "/demos/brick-bas"]) {
    const response = await worker.fetch(new Request("https://robboborben.xyz" + path + "?starter=school"), env);
    assert.equal(response.status, 308);
    assert.equal(response.headers.get("location"), "https://robboborben.xyz/demos/brick-bas/?starter=school");
  }
  assert.equal((await worker.fetch(new Request("https://robboborben.xyz/blog"), env)).status, 404);
  assert.equal((await worker.fetch(new Request("https://robboborben.xyz/demos/brick-bas/index.pck"), env)).status, 200);
  assert.deepEqual(seen, ["/demos/brick-bas/index.pck"]);
});

test("game engine delivery handles gzip, identity, HEAD, 304 and errors", async () => {
  const original = new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0]);
  const compressed = gzipSync(original);
  let requested;
  const assets = { fetch: async (request) => {
    requested = request;
    return new Response(request.method === "HEAD" ? null : compressed, { headers: { etag: '"test"', "content-type": "application/gzip", "content-length": String(compressed.length) } });
  } };
  const url = "https://robboborben.xyz/demos/brick-bas/index.wasm?v=1";
  const zipped = await worker.fetch(new Request(url, { headers: { "accept-encoding": "gzip, br", range: "bytes=0-4" } }), { ASSETS: assets });
  assert.equal(new URL(requested.url).pathname, "/demos/brick-bas/index.wasm.gz");
  assert.equal(new URL(requested.url).search, "?v=1");
  assert.equal(requested.headers.get("range"), null);
  assert.equal(zipped.headers.get("content-type"), "application/wasm");
  assert.equal(zipped.headers.get("content-encoding"), "gzip");
  assert.equal(zipped.headers.get("vary"), "Accept-Encoding");
  assert.deepEqual(new Uint8Array(gunzipSync(await zipped.arrayBuffer())), original);
  for (const encoding of ["identity", "gzip;q=0, br", ""]) {
    const response = await brickBasEngine(new Request(url, { headers: { "accept-encoding": encoding } }), assets);
    assert.equal(response.headers.get("content-encoding"), null);
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), original);
  }
  const head = await brickBasEngine(new Request(url, { method: "HEAD", headers: { "accept-encoding": "gzip" } }), assets);
  assert.equal(head.body, null);
  assert.equal(head.headers.get("content-encoding"), "gzip");
  const cached = await brickBasEngine(new Request(url), { fetch: async () => new Response(null, { status: 304 }) });
  assert.equal(cached.status, 304);
  assert.equal(cached.body, null);
  const missing = await brickBasEngine(new Request(url), { fetch: async () => new Response("Missing", { status: 404 }) });
  assert.equal(missing.status, 404);
  assert.equal(missing.headers.get("content-encoding"), null);
  const rejected = await brickBasEngine(new Request(url, { method: "POST" }), assets);
  assert.equal(rejected.status, 405);
});

test("the site bundle matches its manifest (run npm run site:bundle first)", async (t) => {
  try { await access(new URL("bundle.json", bundleDir)); } catch { t.skip("no dist/site bundle yet"); return; }
  const bundle = JSON.parse(await readFile(new URL("bundle.json", bundleDir), "utf8"));
  for (const entry of Object.values(bundle.files)) {
    const data = await readFile(new URL(entry.file, bundleDir));
    assert.equal(data.length, entry.storedBytes);
    assert.ok(data.length <= 25 * 1024 * 1024, `${entry.file} fits the 25 MiB asset limit`);
    const decoded = entry.file.endsWith(".gz") ? gunzipSync(data) : data;
    assert.equal(decoded.length, entry.bytes);
    assert.equal(createHash("sha256").update(decoded).digest("hex"), entry.sha256);
  }
  const game = await readFile(new URL("index.html", bundleDir), "utf8");
  assert.match(game, /Saves stay in this browser/);
  assert.match(game, /"executable":"index"/);
});
