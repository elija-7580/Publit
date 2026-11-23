// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import test from "node:test";
import assert from "node:assert/strict";
import { createShopServer, memoryRateLimiter } from "../src/node.js";

test("rate limiter allows the limit per window, then blocks until the window ends", async () => {
  let t = 0;
  const limiter = memoryRateLimiter(2, 60, () => t);
  assert.equal((await limiter.limit({ key: "a" })).success, true);
  assert.equal((await limiter.limit({ key: "a" })).success, true);
  assert.equal((await limiter.limit({ key: "a" })).success, false);
  assert.equal((await limiter.limit({ key: "b" })).success, true);
  t = 60_000;
  assert.equal((await limiter.limit({ key: "a" })).success, true);
});

test("server hands requests to the shop with the client IP and returns its response", async () => {
  let seen;
  const handler = { async fetch(request) {
    seen = { url: request.url, ip: request.headers.get("CF-Connecting-IP"), body: await request.text() };
    return new Response('{"ok":true}', { status: 201, headers: { "Content-Type": "application/json" } });
  } };
  const server = createShopServer({}, handler).listen(0);
  await new Promise((r) => server.once("listening", r));
  const { port } = server.address();
  const res = await fetch(`http://127.0.0.1:${port}/v1/offers`, {
    method: "POST", body: '{"legs":[]}', headers: { "X-Forwarded-For": "203.0.113.7", "X-Forwarded-Proto": "https" },
  });
  server.close();
  assert.equal(res.status, 201);
  assert.deepEqual(await res.json(), { ok: true });
  assert.equal(seen.ip, "203.0.113.7");
  assert.equal(seen.body, '{"legs":[]}');
  assert.ok(seen.url.startsWith("https://"));
});

test("return redirect works through the server", async () => {
  const server = createShopServer({ TOKEN_SECRET: "x".repeat(32) }).listen(0);
  await new Promise((r) => server.once("listening", r));
  const res = await fetch(`http://127.0.0.1:${server.address().port}/v1/return?session_id=cs_test_abcdefgh123`, { redirect: "manual" });
  server.close();
  assert.equal(res.status, 302);
  assert.equal(res.headers.get("location"), "publit://shop/return?order=cs_test_abcdefgh123");
});
