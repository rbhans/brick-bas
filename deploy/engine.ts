/** Shared by deploy/worker.ts and its tests (the Worker's entry module may only export handlers). */
export type AssetBinding = { fetch(request: Request): Promise<Response> };

export const PREFIX = "/demos/brick-bas";

/** Serve the unchanged Godot engine from a precompressed static asset. */
export async function brickBasEngine(request: Request, assets: AssetBinding): Promise<Response> {
  if (!["GET", "HEAD"].includes(request.method)) {
    return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
  }
  const url = new URL(request.url);
  url.pathname = PREFIX + "/index.wasm.gz";
  const requestHeaders = new Headers(request.headers);
  // Ranges over compressed bytes are not ranges over the decoded WASM.
  requestHeaders.delete("range");
  requestHeaders.delete("if-range");
  requestHeaders.set("accept-encoding", "identity");
  const asset = await assets.fetch(new Request(url, { method: request.method, headers: requestHeaders }));
  if (!asset.ok && asset.status !== 304) return asset;
  const headers = new Headers(asset.headers);
  headers.set("Content-Type", "application/wasm");
  headers.set("Cache-Control", "public, max-age=0, must-revalidate");
  headers.set("Vary", "Accept-Encoding");
  headers.delete("Accept-Ranges");
  const acceptsGzip = (request.headers.get("accept-encoding") ?? "").split(",").some((entry) => {
    const [coding, ...parameters] = entry.trim().toLowerCase().split(";");
    const quality = parameters.map((value) => value.trim()).find((value) => value.startsWith("q="));
    return coding === "gzip" && (!quality || Number(quality.slice(2)) > 0);
  });
  if (headers.has("etag") && !headers.get("etag")!.startsWith("W/")) headers.set("etag", `W/${headers.get("etag")}`);
  const noBody = request.method === "HEAD" || asset.status === 304;
  if (acceptsGzip) {
    headers.set("Content-Encoding", "gzip");
    const init: ResponseInit & { encodeBody: "manual" } = { status: asset.status, headers, encodeBody: "manual" };
    return new Response(noBody ? null : asset.body, init);
  }
  headers.delete("Content-Encoding");
  headers.delete("Content-Length");
  return new Response(noBody ? null : asset.body?.pipeThrough(new DecompressionStream("gzip")), { status: asset.status, headers });
}
