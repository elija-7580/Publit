#!/usr/bin/env python3
"""0.1.0 resubmission: wait for build 65, attach it to version 0.1.0, add review notes, resubmit for App Review."""
import os, time, jwt, requests
KEY_ID, ISSUER, P8 = os.environ["KEY_ID"], os.environ["ISSUER_ID"], os.environ["P8"]
API = "https://api.appstoreconnect.apple.com"; BUNDLE = "io.github.elija7580.publit"; BUILD_NO = "65"
NOTES = """Build 65 resolves the review of submission e5ab7187-ad86-496a-9469-1de860f209bd:

Guideline 5.1.1(iv): The location explanation in onboarding now has a single "Continue" button that always leads to the system location permission request. The "Not now" button was removed; swiping on also leads to the request.

Guideline 2.5.1: Publit reads only the Walking Speed type from Apple Health (read only, nothing is written), so routes plan walks at the user's pace. Where: Settings > Smart routing > "Use my walking speed". The switch shows the Apple Health heart icon and "From Apple Health". Turning it on shows the Apple Health permission sheet."""
out = []
def log(*a):
    s = " ".join(str(x) for x in a); print(s, flush=True); out.append(s)
def tok():
    n = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": n, "exp": n + 1100, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def call(m, p, body=None, quiet=False):
    r = requests.request(m, p if p.startswith("http") else API + p, json=body, headers={"Authorization": "Bearer " + tok()}, timeout=60)
    if not r.ok:
        if not quiet: log(f"!! {m} {p.split('?')[0]} -> {r.status_code}: {r.text[:3000]}")
        return None
    return r.json() if r.content else {}
try:
    APP = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]["id"]
    BUILD = None
    for i in range(80):
        d = call("GET", f"/v1/builds?filter[app]={APP}&filter[version]={BUILD_NO}")
        if d and d["data"]:
            a = d["data"][0]["attributes"]
            if a.get("processingState") == "VALID": BUILD = d["data"][0]["id"]; break
            if i % 5 == 0: log("build", BUILD_NO, a.get("processingState"))
        elif i % 5 == 0: log("build", BUILD_NO, "not visible yet")
        time.sleep(30)
    if not BUILD: raise SystemExit("build 65 not processed in time")
    log("build", BUILD_NO, "VALID", BUILD)
    call("PATCH", f"/v1/builds/{BUILD}", {"data": {"type": "builds", "id": BUILD, "attributes": {"usesNonExemptEncryption": False}}}, quiet=True)
    for g in call("GET", f"/v1/apps/{APP}/betaGroups?limit=50")["data"]:
        if not g["attributes"].get("hasAccessToAllBuilds"):
            r = call("POST", f"/v1/betaGroups/{g['id']}/relationships/builds", {"data": [{"type": "builds", "id": BUILD}]}, quiet=True)
            log("beta group", g["attributes"]["name"], "build added", r is not None)
    v = call("GET", f"/v1/apps/{APP}/appStoreVersions?filter[versionString]=0.1.0&filter[platform]=IOS")["data"][0]
    VER = v["id"]; log("version 0.1.0", v["attributes"].get("appStoreState"), v["attributes"].get("appVersionState"))
    r = call("PATCH", f"/v1/appStoreVersions/{VER}/relationships/build", {"data": {"type": "builds", "id": BUILD}})
    log("build 65 attached to 0.1.0", r is not None)
    rd = call("GET", f"/v1/appStoreVersions/{VER}/appStoreReviewDetail")["data"]
    old = (rd["attributes"].get("notes") or "").split("Build 65 resolves")[0].strip()
    notes = (NOTES + ("\n\n" + old if old else ""))[:3990]
    r = call("PATCH", f"/v1/appStoreReviewDetails/{rd['id']}", {"data": {"type": "appStoreReviewDetails", "id": rd["id"], "attributes": {"notes": notes}}})
    log("review notes updated", r is not None)
    S = "e5ab7187-ad86-496a-9469-1de860f209bd"
    for s in call("GET", f"/v1/reviewSubmissions?filter[app]={APP}&filter[platform]=IOS&limit=20")["data"]:
        st = s["attributes"].get("state"); log("submission", s["id"], st)
        if s["id"] != S and st == "READY_FOR_REVIEW":
            items = (call("GET", f"/v1/reviewSubmissions/{s['id']}/items", quiet=True) or {}).get("data", [])
            if not items:
                r = call("PATCH", f"/v1/reviewSubmissions/{s['id']}", {"data": {"type": "reviewSubmissions", "id": s["id"], "attributes": {"canceled": True}}})
                log("  empty submission canceled", r is not None)
    done = False
    for attempt in range(12):
        r = call("PATCH", f"/v1/reviewSubmissions/{S}", {"data": {"type": "reviewSubmissions", "id": S, "attributes": {"submitted": True}}}, quiet=attempt < 11)
        if r is not None:
            done = True; log("resubmit", S, "->", r["data"]["attributes"].get("state")); break
        log("attempt", attempt + 1, "not ready yet, waiting 3 min"); time.sleep(180)
    log("SUBMITTED for App Review" if done else "!! submit failed")
except BaseException as e:
    log("!! exception", repr(e))
open("asc-report.txt", "w").write("\n".join(out) + "\n")
