import json, os, time, jwt, requests
KEY_ID, ISSUER, P8 = os.environ["KEY_ID"], os.environ["ISSUER_ID"], os.environ["P8"]
API = "https://api.appstoreconnect.apple.com"
out = []
def log(*a):
    s = " ".join(str(x) for x in a); print(s, flush=True); out.append(s)
def tok():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def call(m, p, b=None):
    return requests.request(m, API + p, json=b, headers={"Authorization": "Bearer " + tok()}, timeout=60)
def rel(t, i): return {"data": {"type": t, "id": i}}
try:
    app = call("GET", "/v1/apps?filter[bundleId]=io.github.elija7580.publit").json()["data"][0]["id"]
    vs = call("GET", f"/v1/apps/{app}/appStoreVersions?filter[platform]=IOS&limit=5").json()["data"]
    ver = vs[0]["id"]; log("version", ver, vs[0]["attributes"].get("versionString"))
    locs = call("GET", f"/v1/appStoreVersions/{ver}/appStoreVersionLocalizations").json()["data"]
    lid = next(l["id"] for l in locs if l["attributes"]["locale"] == "en-GB")
    sets = call("GET", f"/v1/appStoreVersionLocalizations/{lid}/appScreenshotSets").json()["data"]
    log("existing sets", [s["attributes"]["screenshotDisplayType"] for s in sets])
    def mk(kind):
        return call("POST", "/v1/appScreenshotSets", {"data": {"type": "appScreenshotSets", "attributes": {"screenshotDisplayType": kind},
            "relationships": {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", lid)}}})
    r = mk("NOT_A_REAL_TYPE"); log("invalid ->", r.status_code, r.text[:3000])
    for k in ["APP_IPHONE_DUO", "APP_IPHONE_DUO_INNER", "APP_IPHONE_DUO_OUTER", "APP_IPHONE_FOLDABLE", "APP_IPHONE_69", "APP_IPHONE_PRO_MAX"]:
        r = mk(k); log(k, "->", r.status_code, r.text[:300])
        if r.status_code in (200, 201):
            call("DELETE", f"/v1/appScreenshotSets/{r.json()['data']['id']}")
except Exception as e:
    log("ERROR", repr(e))
open("report.txt", "w").write("\n".join(out) + "\n")
