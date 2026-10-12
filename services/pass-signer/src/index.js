import { signManifest, SignError } from "./sign.js";

const MAX_BODY = 100 * 1024;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/sign") return new Response("Not found", { status: 404 });
    if (request.method !== "POST") return new Response("Method not allowed", { status: 405, headers: { Allow: "POST" } });
    if (env.RATE_LIMITER) {
      const { success } = await env.RATE_LIMITER.limit({ key: request.headers.get("CF-Connecting-IP") ?? "unknown" });
      if (!success) return new Response("Too many requests", { status: 429 });
    }
    const length = Number(request.headers.get("Content-Length") ?? "0");
    if (length > MAX_BODY) return new Response("Payload too large", { status: 413 });
    const text = await request.text();
    if (text.length > MAX_BODY) return new Response("Payload too large", { status: 413 });

    let body;
    try {
      body = JSON.parse(text);
    } catch {
      return new Response("Invalid JSON", { status: 400 });
    }
    try {
      const der = signManifest(body ?? {}, env);
      const bytes = Uint8Array.from(der, (c) => c.charCodeAt(0));
      return new Response(bytes, {
        headers: { "Content-Type": "application/pkcs7-signature", "Cache-Control": "no-store" },
      });
    } catch (error) {
      const status = error instanceof SignError ? error.status : 500;
      // Never echo certificates or keys; messages are fixed strings.
      return new Response(status === 500 ? "Signing failed" : error.message, { status });
    }
  },
};
