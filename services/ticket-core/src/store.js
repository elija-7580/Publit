// SPDX-License-Identifier: AGPL-3.0-only
// SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich

// The prototype keeps everything in one JSON file (or only in memory when no file is given). The rest of the
// code touches `store.data` and calls `store.save()`; a real deployment swaps this file for Postgres and moves
// the private keys into a key service.
import { readFileSync, writeFileSync, renameSync, mkdirSync } from "node:fs";
import { dirname } from "node:path";

export function emptyData() {
  return { root: null, operators: {}, products: {}, orders: {}, tickets: {}, revoked: {}, inspections: [], demo: null };
}

export function createStore(file = null) {
  let data = emptyData();
  if (file) {
    try {
      data = { ...emptyData(), ...JSON.parse(readFileSync(file, "utf8")) };
    } catch (error) {
      if (error.code !== "ENOENT") throw error;
    }
  }
  let timer = null;
  const write = () => {
    timer = null;
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(`${file}.tmp`, JSON.stringify(store.data), { mode: 0o600 });
    renameSync(`${file}.tmp`, file);
  };
  const store = {
    data,
    save() {
      if (file && !timer) timer = setTimeout(write, 200);
    },
    flush() {
      if (file && timer) { clearTimeout(timer); write(); }
    },
    reset() {
      store.data = emptyData();
      store.save();
    },
  };
  return store;
}
