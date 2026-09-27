/**
 * Cloudflare Worker for the BRICK / BAS browser build.
 *
 * It is deployed from this repo on its own (`npm run deploy`) and has no public
 * URL of its own: the personal site forwards robboborben.xyz/demos/brick-bas/*
 * here through a service binding, so the game keeps that address (and players'
 * browser saves) while shipping independently of the site.
 */
import { brickBasEngine, PREFIX, type AssetBinding } from "./engine.ts";

type Env = { ASSETS: AssetBinding };

const worker = {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/" || url.pathname === PREFIX) {
      url.pathname = PREFIX + "/";
      return Response.redirect(url.href, 308);
    }
    if (!url.pathname.startsWith(PREFIX + "/")) {
      return new Response("Not found", { status: 404 });
    }
    if (url.pathname === PREFIX + "/index.wasm") return brickBasEngine(request, env.ASSETS);
    return env.ASSETS.fetch(request);
  },
};

export default worker;
