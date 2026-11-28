// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Runs the ticket core on an ordinary server (Node 20+):
//   DEMO=on PORT=8790 DATA_FILE=./data/store.json node src/node.js
// Put it behind a reverse proxy with HTTPS (Caddy, nginx) that sets X-Forwarded-For and X-Forwarded-Proto.
//
//   DEMO            "on" loads the demo data and opens the demo console's helper endpoints. Never in production.
//   DATA_FILE       where the state is kept; without it everything is in memory
//   ADMIN_TOKEN     Publit's own key for approving operators (in demo mode one is made up at start)
//   ROOT_KEY_JWK    the root key that signs the trust list; without it one is created and kept in the store
//   SECRETS_KEY     encrypts what operators hand over (secrets, tokens, signing keys); at least 24 characters.
//                   Keep it outside the data file. In demo mode one is made up at start (and lost at restart).
//   PRIVATE         "on" closes everything, pages included, to anyone without ADMIN_TOKEN: as a Bearer token,
//                   or as the password when the browser asks (any user name). /health stays open.
//   RATE_LIMIT      requests per minute and address (default 240)
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, join, normalize, extname } from "node:path";
import { createApp } from "./app.js";
import { createStore } from "./store.js";

const MAX_BODY = 1024 * 1024;
const here = dirname(fileURLToPath(import.meta.url));
const TYPES = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml", ".png": "image/png", ".json": "application/json", ".webmanifest": "application/manifest+json" };

export function memoryRateLimiter(limit, periodSeconds = 60, now = () => Date.now()) {
  const windows = new Map();
  return (key) => {
    const t = now();
    const w = windows.get(key);
    if (!w || t - w.start >= periodSeconds * 1000) {
      windows.set(key, { start: t, count: 1 });
      if (windows.size > 10000) for (const [k, v] of windows) if (t - v.start >= periodSeconds * 1000) windows.delete(k);
      return true;
    }
    w.count += 1;
    return w.count <= limit;
  };
}

// The demo pages and the shared check code (src/core) are plain files; nothing is built.
async function staticFile(path) {
  const roots = path.startsWith("/core/") ? [join(here, "core"), path.slice(6)] : [join(here, "..", "public"), path === "/" ? "index.html" : path.slice(1)];
  const file = normalize(join(roots[0], roots[1]));
  if (!file.startsWith(roots[0]) || !TYPES[extname(file)]) return null;
  try {
    return { body: await readFile(file), type: TYPES[extname(file)] };
  } catch {
    return null;
  }
}

const same = (a, b) => {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && timingSafeEqual(x, y);
};

/** PRIVATE=on: who may come in. → "header" (send the cookie along), "cookie", or null. */
export function accessBy(headers, token) {
  const pass = createHash("sha256").update(`ptc-access:${token}`).digest("hex");
  const auth = headers.authorization ?? "";
  if (auth.startsWith("Bearer ") && same(auth.slice(7).trim(), token)) return "header";
  if (auth.startsWith("Basic ")) {
    const text = Buffer.from(auth.slice(6), "base64").toString("utf8");
    if (same(text.slice(text.indexOf(":") + 1), token)) return "header";
  }
  // The console sends operator keys in the Authorization header, so the browser's own sign-in rides in a cookie.
  const cookie = /(?:^|;\s*)ptc_access=([a-f0-9]{64})(?:;|$)/.exec(headers.cookie ?? "");
  return cookie && same(cookie[1], pass) ? "cookie" : null;
}

export function createCoreServer(env = process.env, store = createStore(env.DATA_FILE ?? null)) {
  const settings = { ...env };
  const closed = settings.PRIVATE === "on";
  if (closed && (settings.ADMIN_TOKEN ?? "").length < 24) throw new Error("PRIVATE=on needs an ADMIN_TOKEN of at least 24 characters");
  if (settings.DEMO === "on" && !settings.ADMIN_TOKEN) settings.ADMIN_TOKEN = randomBytes(18).toString("base64url");
  if (settings.DEMO === "on" && !settings.SECRETS_KEY) settings.SECRETS_KEY = randomBytes(32).toString("base64url");
  const app = createApp({ store, env: settings });
  const allowed = memoryRateLimiter(Number(settings.RATE_LIMIT ?? 240));
  const server = createServer(async (req, res) => {
    try {
      // The reverse proxy appends the address it saw as the last entry; earlier entries are whatever the
      // client sent and must not decide the rate limit.
      const ip = (req.headers["x-forwarded-for"] ?? req.socket.remoteAddress ?? "unknown").split(",").at(-1).trim();
      const path = new URL(req.url, "http://localhost").pathname;
      if (closed && path !== "/health") {
        if (!allowed(`gate:${ip}`)) { res.writeHead(429).end(); return; }
        const by = accessBy(req.headers, settings.ADMIN_TOKEN);
        if (!by) { res.writeHead(401, { "www-authenticate": 'Basic realm="Publit Ticket Core", charset="UTF-8"', "cache-control": "no-store" }).end("Not authorised"); return; }
        if (by === "header") {
          const secure = (req.headers["x-forwarded-proto"] ?? "").split(",")[0].trim() === "https" ? "; Secure" : "";
          res.setHeader("set-cookie", `ptc_access=${createHash("sha256").update(`ptc-access:${settings.ADMIN_TOKEN}`).digest("hex")}; Path=/; HttpOnly; SameSite=Strict; Max-Age=2592000${secure}`);
        }
      }
      if (req.method === "GET" && !path.startsWith("/v1/") && path !== "/health") {
        const file = await staticFile(path);
        if (!file) { res.writeHead(404).end("Not found"); return; }
        res.writeHead(200, { "content-type": file.type, "cache-control": "no-cache", "x-content-type-options": "nosniff",
          "referrer-policy": "no-referrer", "permissions-policy": "camera=(self)" }).end(file.body);
        return;
      }
      if (!allowed(ip)) { res.writeHead(429, { "content-type": "application/json" }).end('{"error":"rate_limited"}'); return; }
      const chunks = [];
      let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > MAX_BODY) { res.writeHead(413).end(); return; }
        chunks.push(chunk);
      }
      const proto = (req.headers["x-forwarded-proto"] ?? "http").split(",")[0].trim();
      const headers = new Headers();
      for (const [k, v] of Object.entries(req.headers)) if (typeof v === "string") headers.set(k, v);
      const request = new Request(`${proto}://${req.headers.host ?? "localhost"}${req.url}`, {
        method: req.method, headers, body: ["GET", "HEAD", "OPTIONS"].includes(req.method) ? undefined : Buffer.concat(chunks),
      });
      const response = await app(request);
      res.writeHead(response.status, Object.fromEntries(response.headers));
      res.end(Buffer.from(await response.arrayBuffer()));
    } catch (error) {
      console.error(error);
      if (!res.headersSent) res.writeHead(500);
      res.end();
    }
  });
  server.on("close", () => store.flush());
  return server;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const port = Number(process.env.PORT ?? 8790);
  const host = process.env.HOST ?? "127.0.0.1";
  const server = createCoreServer();
  server.listen(port, host, () => console.log(`Publit ticket core on http://${host}:${port}${process.env.DEMO === "on" ? " (demo data)" : ""}`));
  for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => server.close(() => process.exit(0)));
}
