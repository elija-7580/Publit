import hashlib, io, json, os, time, urllib.request
import jwt, requests
from PIL import Image
KEY_ID, ISSUER, P8 = os.environ["KEY_ID"], os.environ["ISSUER_ID"], os.environ["P8"]
API = "https://api.appstoreconnect.apple.com"
SRC = {"de-DE": "de", "en-GB": "en", "en-US": "en"}
OK = {(1398, 2034), (2034, 1398), (2007, 2853), (2853, 2007)}
out = []
def log(*a):
    s = " ".join(str(x) for x in a); print(s, flush=True); out.append(s)
def tok():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def call(m, p, b=None):
    r = requests.request(m, API + p, json=b, headers={"Authorization": "Bearer " + tok()}, timeout=60)
    if r.status_code >= 300: log("!!", m, p, r.status_code, r.text[:600])
    return r
def rel(t, i): return {"data": {"type": t, "id": i}}
def image(path):
    im = Image.open(path).convert("RGB")
    assert im.size in OK, im.size
    b = io.BytesIO(); im.save(b, "PNG"); return b.getvalue()
try:
    app = call("GET", "/v1/apps?filter[bundleId]=io.github.elija7580.publit").json()["data"][0]["id"]
    ver = call("GET", f"/v1/apps/{app}/appStoreVersions?filter[platform]=IOS&limit=5").json()["data"][0]["id"]
    locs = {l["attributes"]["locale"]: l["id"] for l in call("GET", f"/v1/appStoreVersions/{ver}/appStoreVersionLocalizations").json()["data"]}
    log("locales", list(locs))
    for loc, lang in SRC.items():
        FILES = sorted(f for f in os.listdir(f'composed/{lang}') if f.endswith('.png'))
        if loc not in locs: log("missing locale", loc); continue
        lid = locs[loc]
        sets = {s["attributes"]["screenshotDisplayType"]: s["id"] for s in call("GET", f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets").json()["data"]}
        if "APP_IPHONE_DUO" not in sets:
            r = call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": "APP_IPHONE_DUO"},
                "relationships": {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", lid)}}})
            sets["APP_IPHONE_DUO"] = r.json()["data"]["id"]
        sid = sets["APP_IPHONE_DUO"]
        for s in call("GET", f"/v1/appScreenshotSets/{sid}/appScreenshots").json()["data"]:
            call("DELETE", f"/v1/appScreenshots/{s['id']}")
        n = 0
        for i, name in enumerate(FILES, 1):
            data = image(f'composed/{lang}/{name}')
            fn = name
            r = call("POST", "/v1/appScreenshots", {"data": {"type": "appScreenshots", "attributes": {"fileName": fn, "fileSize": len(data)},
                "relationships": {"appScreenshotSet": rel("appScreenshotSets", sid)}}})
            if r.status_code >= 300: continue
            sh = r.json()["data"]
            for op in sh["attributes"]["uploadOperations"]:
                h = {x["name"]: x["value"] for x in op.get("requestHeaders", [])}
                requests.request(op["method"], op["url"], headers=h, data=data[op["offset"]:op["offset"] + op["length"]], timeout=120).raise_for_status()
            r = call("PATCH", f"/v1/appScreenshots/{sh['id']}", {"data": {"type": "appScreenshots", "id": sh["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
            if r.status_code < 300: n += 1
        log("uploaded", loc, n, "/", len(FILES), FILES)
    time.sleep(25)
    for loc, lid in locs.items():
        d = call("GET", f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets?include=appScreenshots").json()
        for s in d.get("data", []):
            if s["attributes"]["screenshotDisplayType"] != "APP_IPHONE_DUO": continue
            inc = [x for x in d.get("included", []) if x["id"] in [y["id"] for y in s["relationships"]["appScreenshots"]["data"]]]
            log("check", loc, [(x["attributes"]["fileName"], (x["attributes"].get("assetDeliveryState") or {}).get("state")) for x in inc])
except Exception as e:
    log("ERROR", repr(e))
open("report.txt", "w").write("\n".join(out) + "\n")
