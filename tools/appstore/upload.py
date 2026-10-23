#!/usr/bin/env python3
"""Replace the App Store screenshots of the current iOS version with docs/appstore/mockups/<device>/<lang>/*.png.

env: KEY_ID, ISSUER_ID, P8 (App Store Connect API key), DEVICES (default: all). Writes report.txt.
"""
import hashlib, io, os, time
import jwt, requests
from PIL import Image
KEY_ID, ISSUER, P8 = os.environ["KEY_ID"], os.environ["ISSUER_ID"], os.environ["P8"]
API = "https://api.appstoreconnect.apple.com"
ROOT = "docs/appstore/mockups"
SRC = {"de-DE": "de", "en-GB": "en", "en-US": "en"}
TYPE = {"iphone": "APP_IPHONE_67", "ipad": "APP_IPAD_PRO_3GEN_129", "duo": "APP_IPHONE_DUO", "watch": "APP_WATCH_ULTRA"}
DEVICES = os.environ.get("DEVICES", "iphone ipad duo watch").split()
out = []
def log(*a):
    s = " ".join(str(x) for x in a); print(s, flush=True); out.append(s)
def tok():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def call(m, p, b=None):
    r = requests.request(m, API + p, json=b, headers={"Authorization": "Bearer " + tok()}, timeout=60)
    if r.status_code >= 300: log("!!", m, p, r.status_code, r.text[:500])
    return r
def rel(t, i): return {"data": {"type": t, "id": i}}
def png(path):
    b = io.BytesIO(); Image.open(path).convert("RGB").save(b, "PNG"); return b.getvalue()
try:
    app = call("GET", "/v1/apps?filter[bundleId]=io.github.elija7580.publit").json()["data"][0]["id"]
    vers = call("GET", f"/v1/apps/{app}/appStoreVersions?filter[platform]=IOS&limit=5").json()["data"]
    ver = vers[0]["id"]; log("version", vers[0]["attributes"].get("versionString"), vers[0]["attributes"].get("appStoreState"))
    locs = {l["attributes"]["locale"]: l["id"] for l in call("GET", f"/v1/appStoreVersions/{ver}/appStoreVersionLocalizations").json()["data"]}
    log("locales", list(locs))
    for dev in DEVICES:
        dtype = TYPE[dev]
        for loc, lang in SRC.items():
            d = f"{ROOT}/{dev}/{lang}"
            if loc not in locs or not os.path.isdir(d): log("skip", dev, loc); continue
            files = sorted(f for f in os.listdir(d) if f.endswith(".png"))[:10]
            lid = locs[loc]
            sets = {s["attributes"]["screenshotDisplayType"]: s["id"] for s in call("GET", f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets").json()["data"]}
            if dtype not in sets:
                r = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": dtype},
                    "relationships": {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", lid)}}})
                if r.status_code >= 300: log("no set", dev, loc); continue
                sets[dtype] = r.json()["data"]["id"]
            sid = sets[dtype]
            for s in call("GET", f"/v1/appScreenshotSets/{sid}/appScreenshots").json()["data"]:
                call("DELETE", f"/v1/appScreenshots/{s['id']}")
            n = 0
            for name in files:
                data = png(f"{d}/{name}")
                r = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": name, "fileSize": len(data)},
                    "relationships": {"appScreenshotSet": rel("appScreenshotSets", sid)}}})
                if r.status_code >= 300: continue
                sh = r.json()["data"]
                for op in sh["attributes"]["uploadOperations"]:
                    h = {x["name"]: x["value"] for x in op.get("requestHeaders", [])}
                    requests.request(op["method"], op["url"], headers=h, data=data[op["offset"]:op["offset"] + op["length"]], timeout=120).raise_for_status()
                r = call("PATCH", f"/v1/appScreenshots/{sh['id']}", {"data": {"type": "appScreenshots", "id": sh["id"],
                    "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
                if r.status_code < 300: n += 1
            log("uploaded", dev, loc, n, "/", len(files))
    time.sleep(30)
    for loc, lid in locs.items():
        d = call("GET", f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets?include=appScreenshots&limit[appScreenshots]=50").json()
        inc = {x["id"]: x for x in d.get("included", [])}
        for s in d.get("data", []):
            states = [(inc[y["id"]]["attributes"].get("assetDeliveryState") or {}).get("state") for y in s["relationships"]["appScreenshots"]["data"] if y["id"] in inc]
            log("check", loc, s["attributes"]["screenshotDisplayType"], len(states), sorted(set(map(str, states))))
except Exception as e:
    log("ERROR", repr(e))
open("report.txt", "w").write("\n".join(out) + "\n")
