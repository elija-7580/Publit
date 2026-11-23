// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// Runs the ticket shop on an ordinary server (Node 20+), without Cloudflare:
//   PORT=8787 TOKEN_SECRET=… STRIPE_SECRET_KEY=sk_test_… DEMO_PROVIDER=on node src/node.js
// Put it behind a reverse proxy with HTTPS (Caddy, nginx) that sets X-Forwarded-For and X-Forwarded-Proto.
import { createServer } from "node:http";
import worker from "./index.js";

const MAX_BODY = 64 * 1024;

/** Fixed-window limit per client IP, like the Cloudflare binding: `limit` requests per `periodSeconds`. */
export function memoryRateLimiter(limit = 30, periodSeconds = 60, now = () => Date.now()) {
  const windows = new Map();
  return {
    async limit({ key }) {
      const t = now();
      const w = windows.get(key);
      if (!w || t - w.start >= periodSeconds * 1000) {
        windows.set(key, { start: t, count: 1 });
        if (windows.size > 10000) for (const [k, v] of windows) if (t - v.start >= periodSeconds * 1000) windows.delete(k);
        return { success: true };
      }
      w.count += 1;
      return { success: w.count <= limit };
    },
  };
}

export function envFromProcess(source = process.env) {
  return {
    TOKEN_SECRET: source.TOKEN_SECRET,
    STRIPE_SECRET_KEY: source.STRIPE_SECRET_KEY,
    DISTRIBUSION_API_KEY: source.DISTRIBUSION_API_KEY,
    DISTRIBUSION_BASE_URL: source.DISTRIBUSION_BASE_URL ?? "https://api.demo.distribusion.com/retailers/v4",
    DEMO_PROVIDER: source.DEMO_PROVIDER ?? "off",
    DEMO_PAYMENTS: source.DEMO_PAYMENTS ?? "off",
    RATE_LIMITER: memoryRateLimiter(Number(source.RATE_LIMIT ?? 30), 60),
  };
}

export function createShopServer(env = envFromProcess(), handler = worker) {
  return createServer(async (req, res) => {
    try {
      const chunks = [];
      let size = 0;
      for await (const chunk of req) {
        size += chunk.length;
        if (size > MAX_BODY) { res.writeHead(413).end(); return; }
        chunks.push(chunk);
      }
      const proto = (req.headers["x-forwarded-proto"] ?? "http").split(",")[0].trim();
      const url = `${proto}://${req.headers.host ?? "localhost"}${req.url}`;
      const ip = (req.headers["x-forwarded-for"] ?? req.socket.remoteAddress ?? "unknown").split(",")[0].trim();
      const headers = new Headers();
      for (const [k, v] of Object.entries(req.headers)) if (typeof v === "string") headers.set(k, v);
      headers.set("CF-Connecting-IP", ip);
      const body = chunks.length && req.method !== "GET" && req.method !== "HEAD" ? Buffer.concat(chunks) : undefined;
      const response = await handler.fetch(new Request(url, { method: req.method, headers, body }), env, {});
      res.writeHead(response.status, Object.fromEntries(response.headers));
      res.end(Buffer.from(await response.arrayBuffer()));
    } catch {
      if (!res.headersSent) res.writeHead(500, { "Content-Type": "application/json" });
      res.end('{"error":"internal","message":"Internal error"}');
    }
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const port = Number(process.env.PORT ?? 8787);
  createShopServer().listen(port, process.env.HOST ?? "127.0.0.1", () => console.log(`Ticket shop on port ${port}`));
}
