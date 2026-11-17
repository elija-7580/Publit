#!/usr/bin/env python3
"""App Store release helper (App Store Connect API).

MODE=status  : prints versions, builds, review submissions, screenshot states, "What's new" texts.
MODE=prepare : for MARKETING_VERSION from project.yml, makes sure an editable iOS (and watchOS)
               App Store version with that version string exists (renames the editable one if
               needed), attaches the newest valid build of that version, sets "What's new"
               (release_notes.json) for every locale. Never submits for review.
MODE=submit  : submits the prepared version for review (manual release by default).
env: KEY_ID, ISSUER_ID, P8. Writes report.txt.
"""
import json, os, re, time
import jwt, requests
KEY_ID, ISSUER, P8 = os.environ["KEY_ID"], os.environ["ISSUER_ID"], os.environ["P8"]
MODE = os.environ.get("MODE", "status")
API = "https://api.appstoreconnect.apple.com"
out = []
def log(*a):
    s = " ".join(str(x) for x in a); print(s, flush=True); out.append(s)
def tok():
    now = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def call(m, p, b=None, quiet=False):
    r = requests.request(m, API + p, json=b, headers={"Authorization": "Bearer " + tok()}, timeout=60)
    if r.status_code >= 300 and not quiet: log("!!", m, p, r.status_code, r.text[:800])
    return r
def get(p): 
    r = call("GET", p); return r.json() if r.status_code < 300 else {"data": []}
def rel(t, i): return {"data": {"type": t, "id": i}}

marketing = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', open("project.yml").read()).group(1)
build_no = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', open("project.yml").read()).group(1)
try:
    app = get("/v1/apps?filter[bundleId]=io.github.elija7580.publit")["data"][0]
    aid = app["id"]; log("app", app["attributes"].get("name"), aid, "project", marketing, build_no)
    vers = get(f"/v1/apps/{aid}/appStoreVersions?limit=20&include=build")
    builds_by_id = {b["id"]: b for b in vers.get("included", []) if b["type"] == "builds"}
    for v in vers["data"]:
        a = v["attributes"]; b = (v["relationships"].get("build") or {}).get("data")
        bn = builds_by_id.get(b["id"], {}).get("attributes", {}).get("version") if b else None
        log("version", a.get("platform"), a.get("versionString"), a.get("appStoreState"), "release", a.get("releaseType"), "build", bn, "created", a.get("createdDate"))
    builds = get(f"/v1/builds?filter[app]={aid}&sort=-uploadedDate&limit=8&include=preReleaseVersion")
    pre = {p["id"]: p["attributes"] for p in builds.get("included", [])}
    for b in builds["data"]:
        a = b["attributes"]; pv = pre.get(b["relationships"]["preReleaseVersion"]["data"]["id"], {})
        log("build", pv.get("platform"), pv.get("version"), a.get("version"), a.get("processingState"), "expired" if a.get("expired") else "", a.get("uploadedDate"), "encryption", a.get("usesNonExemptEncryption"))
    subs = get(f"/v1/reviewSubmissions?filter[app]={aid}&limit=10")
    for s in subs["data"]:
        a = s["attributes"]; log("reviewSubmission", s["id"], a.get("platform"), a.get("state"), a.get("submittedDate"))
        items = get(f"/v1/reviewSubmissions/{s['id']}/items?include=appStoreVersion,appCustomProductPageVersion,appEvent,appStoreVersionExperiment")
        for it in items.get("data", []):
            r = {k: (v.get("data") or {}).get("type") + ":" + (v.get("data") or {}).get("id", "")[:8] for k, v in it.get("relationships", {}).items() if isinstance(v, dict) and v.get("data")}
            log("   item", it["attributes"].get("state"), r)
        for inc in items.get("included", []):
            log("   incl", inc["type"], {k: inc["attributes"].get(k) for k in ("versionString", "appStoreState", "state", "referenceName", "eventState", "name") if k in inc["attributes"]})
    for pp in get(f"/v1/apps/{aid}/appCustomProductPages?limit=10")["data"]:
        log("customProductPage", pp["attributes"].get("name"), pp["attributes"].get("visible"))
    for ev in get(f"/v1/apps/{aid}/appEvents?limit=10")["data"]:
        log("appEvent", ev["attributes"].get("referenceName"), ev["attributes"].get("eventState"))
    editable = [v for v in vers["data"] if v["attributes"]["appStoreState"] in ("READY_FOR_SALE", "PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE")]
    for v in editable:
        locs = get(f"/v1/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]
        for l in locs:
            wn = (l["attributes"].get("whatsNew") or "").replace("\n", " / ")
            log("  loc", v["attributes"]["platform"], l["attributes"]["locale"], "whatsNew:", wn[:160] or "-")
            for s in get(f"/v1/appStoreVersionLocalizations/{l['id']}/appScreenshotSets")["data"]:
                shots = get(f"/v1/appScreenshotSets/{s['id']}/appScreenshots")["data"]
                states = sorted({(x["attributes"].get("assetDeliveryState") or {}).get("state") for x in shots})
                log("    shots", s["attributes"]["screenshotDisplayType"], len(shots), states)

    if MODE in ("prepare", "submit"):
        notes = json.load(open("tools/appstore/release_notes.json"))
        for platform in ("IOS", "WATCH_OS"):
            ed = [v for v in vers["data"] if v["attributes"]["platform"] == platform and v["attributes"]["appStoreState"] in ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED")]
            if not ed:
                if platform == "WATCH_OS": continue
                r = call("POST", "/v1/appStoreVersions", {"data": {"type": "appStoreVersions", "attributes": {"platform": platform, "versionString": marketing, "releaseType": "MANUAL"},
                    "relationships": {"app": rel("apps", aid)}}})
                if r.status_code >= 300: continue
                v = r.json()["data"]; log("created version", platform, marketing)
            else:
                v = ed[0]
                if v["attributes"]["versionString"] != marketing:
                    r = call("PATCH", f"/v1/appStoreVersions/{v['id']}", {"data": {"type": "appStoreVersions", "id": v["id"], "attributes": {"versionString": marketing}}})
                    log("renamed version", platform, v["attributes"]["versionString"], "->", marketing, r.status_code)
            vid = v["id"]
            # Newest valid build of this marketing version.
            bl = get(f"/v1/builds?filter[app]={aid}&filter[version]={build_no}&filter[preReleaseVersion.version]={marketing}&filter[preReleaseVersion.platform]={platform}&limit=5")["data"]
            if platform == "IOS":
                if bl and bl[0]["attributes"].get("processingState") == "VALID":
                    r = call("PATCH", f"/v1/appStoreVersions/{vid}/relationships/build", rel("builds", bl[0]["id"]))
                    log("attached build", platform, marketing, build_no, r.status_code)
                else:
                    log("build not ready", platform, marketing, build_no, [b["attributes"].get("processingState") for b in bl])
            locs = get(f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
            for l in locs:
                loc = l["attributes"]["locale"]; text = notes.get(loc) or notes.get(loc.split("-")[0]) or notes["en"]
                r = call("PATCH", f"/v1/appStoreVersionLocalizations/{l['id']}", {"data": {"type": "appStoreVersionLocalizations", "id": l["id"], "attributes": {"whatsNew": text}}})
                log("whatsNew", platform, loc, r.status_code)
            if MODE == "submit" and platform == "IOS":
                r = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"}, "relationships": {"app": rel("apps", aid)}}})
                if r.status_code < 300:
                    sid = r.json()["data"]["id"]
                    call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {"reviewSubmission": rel("reviewSubmissions", sid), "appStoreVersion": rel("appStoreVersions", vid)}}})
                    r = call("PATCH", f"/v1/reviewSubmissions/{sid}", {"data": {"type": "reviewSubmissions", "id": sid, "attributes": {"submitted": True}}})
                    log("submitted for review", r.status_code)
finally:
    open("report.txt", "w").write("\n".join(out) + "\n")
