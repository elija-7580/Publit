import forge from "node-forge";

const MAX_PASS_BYTES = 64 * 1024;
const MAX_MANIFEST_BYTES = 8 * 1024;
const ALLOWED_FILES = new Set([
  "pass.json",
  "icon.png", "icon@2x.png", "icon@3x.png",
  "logo.png", "logo@2x.png", "logo@3x.png",
  "strip.png", "strip@2x.png", "strip@3x.png",
  "thumbnail.png", "thumbnail@2x.png", "thumbnail@3x.png",
]);

export class SignError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function decodeBase64(value, limit, name) {
  if (typeof value !== "string" || value.length === 0 || value.length > Math.ceil(limit / 3) * 4 + 4) {
    throw new SignError(400, `${name} missing or too large`);
  }
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(value)) throw new SignError(400, `${name} is not base64`);
  return forge.util.decode64(value);
}

function sha1Hex(binary) {
  const md = forge.md.sha1.create();
  md.update(binary, "raw");
  return md.digest().toHex();
}

/**
 * Checks that the manifest belongs to a pass for this Pass Type ID and Team ID, then returns the
 * detached PKCS #7 signature (DER, as a binary string). Only pass.json and the manifest are sent,
 * never the ticket document.
 */
export function signManifest({ pass, manifest }, env, now = new Date()) {
  const passJSON = decodeBase64(pass, MAX_PASS_BYTES, "pass");
  const manifestJSON = decodeBase64(manifest, MAX_MANIFEST_BYTES, "manifest");

  let passObject, manifestObject;
  try {
    passObject = JSON.parse(forge.util.decodeUtf8(passJSON));
    manifestObject = JSON.parse(forge.util.decodeUtf8(manifestJSON));
  } catch {
    throw new SignError(400, "invalid JSON");
  }
  if (passObject.passTypeIdentifier !== env.PASS_TYPE_ID || passObject.teamIdentifier !== env.TEAM_ID) {
    throw new SignError(403, "pass type or team does not match");
  }
  if (passObject.formatVersion !== 1 || typeof passObject.serialNumber !== "string" || passObject.serialNumber.length > 64) {
    throw new SignError(400, "invalid pass");
  }
  // No web service: passes from this signer cannot be updated or pushed to remotely.
  if ("webServiceURL" in passObject || "authenticationToken" in passObject) {
    throw new SignError(400, "web service fields are not allowed");
  }
  const entries = Object.entries(manifestObject);
  if (entries.length === 0 || entries.length > ALLOWED_FILES.size) throw new SignError(400, "invalid manifest");
  for (const [file, hash] of entries) {
    if (!ALLOWED_FILES.has(file) || typeof hash !== "string" || !/^[0-9a-f]{40}$/.test(hash)) {
      throw new SignError(400, `file not allowed: ${file}`);
    }
  }
  if (manifestObject["pass.json"] !== sha1Hex(passJSON)) throw new SignError(400, "pass.json hash mismatch");
  if (!manifestObject["icon.png"]) throw new SignError(400, "icon.png missing");

  const certificate = forge.pki.certificateFromPem(env.PASS_CERT_PEM);
  const wwdr = forge.pki.certificateFromPem(env.WWDR_CERT_PEM);
  const key = env.PASS_KEY_PASSPHRASE
    ? forge.pki.decryptRsaPrivateKey(env.PASS_KEY_PEM, env.PASS_KEY_PASSPHRASE)
    : forge.pki.privateKeyFromPem(env.PASS_KEY_PEM);
  if (!key) throw new SignError(500, "signing key unavailable");

  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(manifestJSON, "raw");
  p7.addCertificate(certificate);
  p7.addCertificate(wwdr);
  p7.addSigner({
    key,
    certificate,
    digestAlgorithm: forge.pki.oids.sha256,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      { type: forge.pki.oids.signingTime, value: now },
    ],
  });
  p7.sign({ detached: true });
  return forge.asn1.toDer(p7.toAsn1()).getBytes();
}
