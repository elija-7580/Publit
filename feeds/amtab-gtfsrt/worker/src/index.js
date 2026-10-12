// Cloudflare Worker: serves AMTAB Bari real-time data as GTFS-Realtime protobuf.
//   /trip-updates.pb  /vehicle-positions.pb  /health
import { tripUpdates, vehiclePositions } from "./gtfsrt.js";

const SOURCE = "https://avl.amtab.it/WSExportGTFS_RT/api/gtfs";
const CACHE_SECONDS = 20;

async function upstream(env, path) {
  const res = await fetch(`${env.AMTAB_BASE || SOURCE}/${path}`, {
    headers: { "User-Agent": env.USER_AGENT || "Publit-AMTAB-GTFSRT/0.2 (+https://github.com/elija-7580/Publit-)", Accept: "application/json" },
    cf: { cacheTtl: CACHE_SECONDS, cacheEverything: true },
  });
  if (!res.ok) throw new Error(`upstream ${path}: HTTP ${res.status}`);
  return res.json();
}

function reply(body, type, status = 200) {
  return new Response(body, {
    status,
    headers: { "Content-Type": type, "Cache-Control": `public, max-age=${CACHE_SECONDS}`, "Access-Control-Allow-Origin": "*" },
  });
}

export async function handle(request, env = {}, load = upstream) {
  const path = new URL(request.url).pathname.replace(/\/$/, "");
  if (!["/trip-updates.pb", "/vehicle-positions.pb", "/health"].includes(path)) return reply("not found", "text/plain", 404);
  try {
    const vp = await load(env, "VechiclePosition"); // sic: AMTAB's endpoint spelling
    if (path === "/vehicle-positions.pb") return reply(vehiclePositions(vp).bytes, "application/x-protobuf");
    const tu = await load(env, "TripUpdates");
    const out = tripUpdates(tu, vp);
    if (path === "/trip-updates.pb") return reply(out.bytes, "application/x-protobuf");
    return reply(JSON.stringify({ ok: true, trip_updates: out.count, vehicles: vehiclePositions(vp).count, feed_timestamp: out.timestamp }), "application/json");
  } catch (err) {
    return reply(path === "/health" ? JSON.stringify({ ok: false, error: String(err.message || err) }) : "upstream unavailable",
      path === "/health" ? "application/json" : "text/plain", 503);
  }
}

export default {
  async fetch(request, env, ctx) {
    const cache = caches.default;
    const hit = await cache.match(request);
    if (hit) return hit;
    const res = await handle(request, env);
    if (res.ok) ctx.waitUntil(cache.put(request, res.clone()));
    return res;
  },
};
