import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import forge from "node-forge";
import { signManifest, SignError } from "../src/sign.js";
import worker from "../src/index.js";

function certificate(subject, issuer, keys, signingKey, ca) {
  const cert = forge.pki.createCertificate();
  cert.publicKey = keys.publicKey;
  cert.serialNumber = String(Math.floor(Math.random() * 1e9));
  cert.validity.notBefore = new Date(Date.now() - 86400000);
  cert.validity.notAfter = new Date(Date.now() + 86400000);
  cert.setSubject([{ name: "commonName", value: subject }]);
  cert.setIssuer([{ name: "commonName", value: issuer }]);
  cert.setExtensions([{ name: "basicConstraints", cA: ca }, { name: "keyUsage", digitalSignature: true, keyCertSign: ca }]);
  cert.sign(signingKey, forge.md.sha256.create());
  return cert;
}

const caKeys = forge.pki.rsa.generateKeyPair(1024);
const passKeys = forge.pki.rsa.generateKeyPair(1024);
const ca = certificate("Test WWDR", "Test WWDR", caKeys, caKeys.privateKey, true);
const passCert = certificate("Pass Type ID: pass.test", "Test WWDR", passKeys, caKeys.privateKey, false);
const env = {
  PASS_TYPE_ID: "pass.test",
  TEAM_ID: "ABCDE12345",
  PASS_CERT_PEM: forge.pki.certificateToPem(passCert),
  PASS_KEY_PEM: forge.pki.privateKeyToPem(passKeys.privateKey),
  WWDR_CERT_PEM: forge.pki.certificateToPem(ca),
};

const sha1 = (s) => forge.md.sha1.create().update(s, "raw").digest().toHex();
const b64 = (s) => Buffer.from(s, "utf8").toString("base64");
const passJSON = JSON.stringify({ formatVersion: 1, passTypeIdentifier: "pass.test", teamIdentifier: "ABCDE12345", serialNumber: "abc" });
const manifestJSON = (pass = passJSON, extra = {}) => JSON.stringify({ "pass.json": sha1(pass), "icon.png": "0".repeat(40), ...extra });

test("signs a valid manifest with a detached PKCS #7 signature", () => {
  const manifest = manifestJSON();
  const der = signManifest({ pass: b64(passJSON), manifest: b64(manifest) }, env);
  const p7 = forge.pkcs7.messageFromAsn1(forge.asn1.fromDer(der));
  assert.equal(p7.certificates.length, 2);
  assert.equal(p7.rawCapture.content, undefined, "detached: no embedded content");

  // Cross-check with OpenSSL when it is installed.
  try {
    const dir = mkdtempSync(join(tmpdir(), "signer-"));
    writeFileSync(join(dir, "sig.der"), Buffer.from(der, "binary"));
    writeFileSync(join(dir, "manifest.json"), manifest);
    writeFileSync(join(dir, "ca.pem"), env.WWDR_CERT_PEM);
    execFileSync("openssl", ["smime", "-verify", "-binary", "-inform", "DER", "-in", join(dir, "sig.der"),
      "-content", join(dir, "manifest.json"), "-CAfile", join(dir, "ca.pem"), "-purpose", "any", "-out", "/dev/null"], { stdio: "pipe" });
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
});

test("rejects other pass types, foreign files, hash mismatches and web services", () => {
  const foreign = JSON.stringify({ formatVersion: 1, passTypeIdentifier: "pass.other", teamIdentifier: "ABCDE12345", serialNumber: "x" });
  assert.throws(() => signManifest({ pass: b64(foreign), manifest: b64(manifestJSON(foreign)) }, env), (e) => e instanceof SignError && e.status === 403);
  assert.throws(() => signManifest({ pass: b64(passJSON), manifest: b64(manifestJSON(passJSON, { "evil.js": "0".repeat(40) })) }, env), /not allowed/);
  assert.throws(() => signManifest({ pass: b64(passJSON), manifest: b64(manifestJSON("{}")) }, env), /hash mismatch/);
  const service = JSON.stringify({ formatVersion: 1, passTypeIdentifier: "pass.test", teamIdentifier: "ABCDE12345", serialNumber: "x", webServiceURL: "https://evil.example" });
  assert.throws(() => signManifest({ pass: b64(service), manifest: b64(manifestJSON(service)) }, env), /web service/);
  assert.throws(() => signManifest({ pass: "not base64!", manifest: "x" }, env), /base64/);
});

test("worker answers only POST /sign and returns DER", async () => {
  assert.equal((await worker.fetch(new Request("https://x/other"), env)).status, 404);
  assert.equal((await worker.fetch(new Request("https://x/sign"), env)).status, 405);
  const bad = await worker.fetch(new Request("https://x/sign", { method: "POST", body: "{" }), env);
  assert.equal(bad.status, 400);
  const ok = await worker.fetch(new Request("https://x/sign", {
    method: "POST", body: JSON.stringify({ pass: b64(passJSON), manifest: b64(manifestJSON()) }),
  }), env);
  assert.equal(ok.status, 200);
  assert.equal(ok.headers.get("Content-Type"), "application/pkcs7-signature");
  const bytes = new Uint8Array(await ok.arrayBuffer());
  assert.equal(bytes[0], 0x30);
});
