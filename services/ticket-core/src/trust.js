// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// The trust list: every active issuer's public keys, the published scope of every product and the revoked
// tickets, signed with the root key. A checking device downloads it when it has network and then needs none.
// Only the root's public key is built into the checking app.

import { generateKeyPair, signText } from "./core/token.js";

const VALID_HOURS = 72; // a device that has not synced for three days must sync before it checks again

export async function rootKey(store, env = {}) {
  if (env.ROOT_KEY_JWK) {
    const privateJwk = JSON.parse(env.ROOT_KEY_JWK);
    return { kid: "root-env", privateJwk, publicJwk: { kty: privateJwk.kty, crv: privateJwk.crv, x: privateJwk.x, y: privateJwk.y } };
  }
  if (!store.data.root) {
    store.data.root = { kid: "root-1", ...(await generateKeyPair()) };
    store.save();
  }
  return store.data.root;
}

export function trustList(store, now = Date.now()) {
  const operators = Object.values(store.data.operators);
  const products = {};
  for (const product of Object.values(store.data.products)) {
    for (const version of product.versions) {
      if (version.status === "draft") continue;
      products[`${product.id}@${version.version}`] = { operatorId: product.operatorId, name: version.name, validity: version.validity, hash: version.hash };
    }
  }
  return {
    version: 1,
    issuedAt: Math.floor(now / 1000),
    validUntil: Math.floor(now / 1000) + VALID_HOURS * 3600,
    issuers: operators.filter((o) => o.keys.length > 0 && (o.status === "active" || o.status === "suspended")).map((o) => ({
      id: o.id, name: o.name, country: o.country, status: o.status,
      keys: o.keys.map((k) => ({ kid: k.kid, jwk: k.jwk, from: k.from, until: k.until, status: k.status })),
    })),
    operators: operators.map((o) => ({ id: o.id, name: o.name, aliases: o.aliases })),
    products,
    revoked: Object.keys(store.data.revoked),
  };
}

export async function signedTrustList(store, env = {}, now = Date.now()) {
  const root = await rootKey(store, env);
  const list = JSON.stringify(trustList(store, now));
  return { list, signature: await signText(list, root.privateJwk), rootKid: root.kid };
}
