// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createCoreServer, memoryRateLimiter } from "../src/node.js";
import { createStore } from "../src/store.js";

async function withServer(env, run, store) {
  const server = createCoreServer(env, store);
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  try {
    await run(`http://127.0.0.1:${server.address().port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test("server: demo pages, the shared check code and the API come from one process", async () => {
  await withServer({ DEMO: "on" }, async (base) => {
    const page = await fetch(`${base}/`);
    assert.equal(page.status, 200);
    assert.match(await page.text(), /Publit Ticket Core/);
    assert.match(await (await fetch(`${base}/core/validate.js`)).text(), /checkTicket/);
    assert.equal((await fetch(`${base}/app.js`)).headers.get("content-type"), "text/javascript; charset=utf-8");
    for (const path of ["/core/../node.js", "/core/%2e%2e/node.js", "/../package.json", "/core/..%2f..%2fpackage.json", "/nothing.html", "/core/secret.txt"]) {
      const response = await fetch(`${base}${path}`);
      assert.equal(response.status, 404, path);
    }
    const demo = await (await fetch(`${base}/v1/demo`)).json();
    assert.equal(typeof demo.adminToken, "string");
    const order = await (await fetch(`${base}/v1/orders`, { method: "POST", body: JSON.stringify({ productId: "alpenland-bus.24-stunden-netzticket" }) })).json();
    const paid = await (await fetch(`${base}/v1/orders/${order.order.id}/pay`, { method: "POST", body: JSON.stringify({ secret: order.order.secret }) })).json();
    assert.match(paid.ticket.token, /^PT1\./);
    assert.equal((await fetch(`${base}/v1/orders`, { method: "POST", body: "x".repeat(1100000) })).status, 413);
  });
});

test("server: the state survives a restart, private keys stay in a file only the owner can read", async () => {
  const file = join(mkdtempSync(join(tmpdir(), "ticket-core-")), "store.json");
  let token;
  await withServer({ DEMO: "on", DATA_FILE: file }, async (base) => {
    const order = await (await fetch(`${base}/v1/orders`, { method: "POST", body: JSON.stringify({ productId: "alpenland-bus.24-stunden-netzticket" }) })).json();
    token = (await (await fetch(`${base}/v1/orders/${order.order.id}/pay`, { method: "POST", body: JSON.stringify({ secret: order.order.secret }) })).json()).ticket.token;
  }, createStore(file));
  assert.equal(Object.keys(JSON.parse(readFileSync(file, "utf8")).tickets).length, 1);
  await withServer({ DEMO: "on", DATA_FILE: file }, async (base) => {
    const checked = await (await fetch(`${base}/v1/validate`, { method: "POST", body: JSON.stringify({ code: token }) })).json();
    assert.equal(checked.level, "valid");
  }, createStore(file));
});

test("server: rate limit per address and minute", () => {
  let now = 0;
  const allowed = memoryRateLimiter(2, 60, () => now);
  assert.deepEqual([allowed("a"), allowed("a"), allowed("a"), allowed("b")], [true, true, false, true]);
  now = 61000;
  assert.equal(allowed("a"), true);
});
