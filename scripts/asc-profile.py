#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 Elija Samuel Friedrich-Ulrich
"""Fetches (or creates) an App Store provisioning profile for one bundle ID with the App Store Connect API.

Used by testflight.yml for targets added after the profile secrets were set up (the watch complications):
registers the bundle ID if needed, reuses an active profile of the same name or creates one with every
distribution certificate of the team, and writes it to <out>. No packages needed: the JWT is signed with
openssl. Exits non-zero on any failure; the caller then ships the build without that target.

Usage: asc-profile.py <key id> <issuer id> <key.p8> <bundle id> <profile name> <out.mobileprovision>
"""
import base64, json, subprocess, sys, tempfile, time, urllib.parse, urllib.request

key_id, issuer, key_path, bundle_id, name, out = sys.argv[1:7]
API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der):
    """ECDSA signature: DER SEQUENCE(r, s) from openssl to the 64-byte r||s a JWT wants."""
    assert der[0] == 0x30
    i = 2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)
    parts = []
    for _ in range(2):
        assert der[i] == 0x02
        n = der[i + 1]
        parts.append(der[i + 2:i + 2 + n].lstrip(b"\x00").rjust(32, b"\x00"))
        i += 2 + n
    return parts[0] + parts[1]


def token():
    header = b64url(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64url(json.dumps({"iss": issuer, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"}).encode())
    msg = f"{header}.{payload}".encode()
    with tempfile.NamedTemporaryFile() as f:
        f.write(msg)
        f.flush()
        der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", key_path, f.name],
                             check=True, capture_output=True).stdout
    return f"{header}.{payload}.{b64url(der_to_raw(der))}"


TOKEN = token()


def call(method, path, body=None, query=None):
    url = API + path + ("?" + urllib.parse.urlencode(query) if query else "")
    req = urllib.request.Request(url, method=method, data=json.dumps(body).encode() if body else None,
                                 headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read() or b"{}")


bundles = call("GET", "/bundleIds", query={"filter[identifier]": bundle_id, "limit": "5"})["data"]
bundle = next((b for b in bundles if b["attributes"]["identifier"] == bundle_id), None)
if bundle is None:
    bundle = call("POST", "/bundleIds", {"data": {"type": "bundleIds", "attributes": {
        "identifier": bundle_id, "name": name, "platform": "IOS"}}})["data"]
    print("registered", bundle_id)

profiles = call("GET", "/profiles", query={"filter[name]": name, "limit": "10"})["data"]
active = [p for p in profiles if p["attributes"].get("profileState") == "ACTIVE"
          and p["attributes"].get("profileType") == "IOS_APP_STORE"]
if active:
    content = active[0]["attributes"]["profileContent"]
    print("reusing profile", name)
else:
    certs = [c for c in call("GET", "/certificates", query={"limit": "50"})["data"]
             if c["attributes"].get("certificateType") in ("DISTRIBUTION", "IOS_DISTRIBUTION")]
    if not certs:
        sys.exit("no distribution certificate")
    created = call("POST", "/profiles", {"data": {
        "type": "profiles",
        "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
        "relationships": {
            "bundleId": {"data": {"type": "bundleIds", "id": bundle["id"]}},
            "certificates": {"data": [{"type": "certificates", "id": c["id"]} for c in certs]},
        }}})["data"]
    content = created["attributes"]["profileContent"]
    print("created profile", name)
open(out, "wb").write(base64.b64decode(content))
