#!/usr/bin/env python3
"""Sets the App Store version to 0.1.0, attaches build 64, prints a readiness report. Never submits."""
import os, time, jwt, requests
KEY_ID, ISSUER, P8 = os.environ["KEY_ID"], os.environ["ISSUER_ID"], os.environ["P8"]
API = "https://api.appstoreconnect.apple.com"; BUNDLE = "io.github.elija7580.publit"
VERSION, BUILD = "0.1.0", "64"
out = []
def log(*a):
    s = " ".join(str(x) for x in a); print(s, flush=True); out.append(s)
def tok():
    n = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": n, "exp": n + 1100, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def call(m, p, body=None):
    r = requests.request(m, p if p.startswith("http") else API + p, json=body, headers={"Authorization": "Bearer " + tok()}, timeout=60)
    if not r.ok: log(f"!! {m} {p} -> {r.status_code}: {r.text[:600]}"); return None
    return r.json() if r.content else {}
try:
    APP = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]["id"]
    vs = call("GET", f"/v1/apps/{APP}/appStoreVersions?limit=20")["data"]
    for v in vs: log("version", v["id"], v["attributes"]["platform"], v["attributes"]["versionString"], v["attributes"].get("appStoreState"))
    ver = next(v for v in vs if v["attributes"]["platform"] == "IOS" and v["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"))
    VER = ver["id"]
    if ver["attributes"]["versionString"] != VERSION:
        r = call("PATCH", f"/v1/appStoreVersions/{VER}", {"data": {"type": "appStoreVersions", "id": VER, "attributes": {"versionString": VERSION}}})
        log("versionString ->", VERSION, "ok" if r is not None else "FAILED")
    b = None
    for i in range(80):
        d = call("GET", f"/v1/builds?filter[app]={APP}&filter[version]={BUILD}&filter[preReleaseVersion.version]={VERSION}")
        b = d["data"][0] if d and d["data"] else None
        st = b and b["attributes"].get("processingState")
        if st == "VALID": break
        log("build", BUILD, "state", st, "waiting"); time.sleep(45)
    if b and b["attributes"].get("processingState") == "VALID":
        if b["attributes"].get("usesNonExemptEncryption") is None:
            call("PATCH", f"/v1/builds/{b['id']}", {"data": {"type": "builds", "id": b["id"], "attributes": {"usesNonExemptEncryption": False}}})
            log("export compliance: no non-exempt encryption")
        r = call("PATCH", f"/v1/appStoreVersions/{VER}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
        log("build", BUILD, "attached" if r is not None else "NOT attached")
    else:
        log("!! build", BUILD, "not ready")
    OLD = "https://elija-7580.github.io/publit-site/"
    fix = lambda t: t.replace(OLD, "https://publit.eu/") if t else t
    for loc in call("GET", f"/v1/appStoreVersions/{VER}/appStoreVersionLocalizations")["data"]:
        la = loc["attributes"]; ch = {}
        for k in ("marketingUrl", "description", "promotionalText", "supportUrl"):
            if la.get(k) and OLD in la[k]: ch[k] = fix(la[k])
        if ch:
            r = call("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": ch}})
            log("links", la["locale"], list(ch), "ok" if r is not None else "FAILED")
    for info in call("GET", f"/v1/apps/{APP}/appInfos")["data"]:
        for l in call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]:
            ch = {k: fix(l["attributes"][k]) for k in ("privacyPolicyUrl", "privacyChoicesUrl") if l["attributes"].get(k) and OLD in l["attributes"][k]}
            if ch:
                r = call("PATCH", f"/v1/appInfoLocalizations/{l['id']}", {"data": {"type": "appInfoLocalizations", "id": l["id"], "attributes": ch}})
                log("privacy", l["attributes"]["locale"], "ok" if r is not None else "FAILED")
    v = call("GET", f"/v1/appStoreVersions/{VER}?include=build,appStoreReviewDetail")
    a = v["data"]["attributes"]; log("now:", a["versionString"], a.get("appStoreState"), "copyright", a.get("copyright"))
    rels = v["data"]["relationships"]
    log("build linked:", bool(rels["build"]["data"]), "review detail:", bool(rels.get("appStoreReviewDetail", {}).get("data")))
    for loc in call("GET", f"/v1/appStoreVersions/{VER}/appStoreVersionLocalizations")["data"]:
        la = loc["attributes"]
        sets = call("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets?include=appScreenshots")
        cnt = {s["attributes"]["screenshotDisplayType"]: len(s["relationships"]["appScreenshots"]["data"]) for s in sets["data"]}
        log("loc", la["locale"], "desc", len(la.get("description") or ""), "kw", len(la.get("keywords") or ""), "support", la.get("supportUrl"), "marketing", la.get("marketingUrl"), "whatsNew", bool(la.get("whatsNew")), cnt)
    for info in call("GET", f"/v1/apps/{APP}/appInfos")["data"]:
        for l in call("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"]:
            log("info", info["attributes"].get("appStoreState"), l["attributes"]["locale"], "privacy", l["attributes"].get("privacyPolicyUrl"))
except Exception as e:
    log("!! exception", repr(e))
open("asc-report.txt", "w").write("\n".join(out) + "\n")
