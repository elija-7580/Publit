#!/usr/bin/env python3
"""Beta groups: report testers, add build 64 to every group, submit for beta review if external; then submit 0.1.0 for App Review."""
import os, time, jwt, requests
KEY_ID, ISSUER, P8 = os.environ["KEY_ID"], os.environ["ISSUER_ID"], os.environ["P8"]
API = "https://api.appstoreconnect.apple.com"; BUNDLE = "io.github.elija7580.publit"
out = []
def log(*a):
    s = " ".join(str(x) for x in a); print(s, flush=True); out.append(s)
def tok():
    n = int(time.time())
    return jwt.encode({"iss": ISSUER, "iat": n, "exp": n + 1100, "aud": "appstoreconnect-v1"}, P8, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
def call(m, p, body=None, quiet=False):
    r = requests.request(m, p if p.startswith("http") else API + p, json=body, headers={"Authorization": "Bearer " + tok()}, timeout=60)
    if not r.ok:
        if not quiet: log(f"!! {m} {p.split('?')[0]} -> {r.status_code}: {r.text[:5000]}")
        return None
    return r.json() if r.content else {}
def mask(e): return (e or "?")[:3] + "…@" + (e or "@?").split("@")[-1]
try:
    APP = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE}")["data"][0]["id"]
    b = call("GET", f"/v1/builds?filter[app]={APP}&filter[version]=64&include=buildBetaDetail")
    BUILD = b["data"][0]["id"]; log("build 64", b["data"][0]["attributes"].get("processingState"), "expired", b["data"][0]["attributes"].get("expired"))
    for inc in b.get("included", []): log("beta detail", inc["attributes"])
    for u in call("GET", "/v1/users?limit=50")["data"]:
        log("team user", mask(u["attributes"].get("username")), u["attributes"].get("roles"), "allApps", u["attributes"].get("allAppsVisible"))
    for g in call("GET", f"/v1/apps/{APP}/betaGroups?limit=50")["data"]:
        a = g["attributes"]; G = g["id"]
        testers = call("GET", f"/v1/betaGroups/{G}/betaTesters?limit=200")["data"]
        log("group", a["name"], "internal", a.get("isInternalGroup"), "allBuilds", a.get("hasAccessToAllBuilds"), "publicLink", a.get("publicLinkEnabled"), "testers", len(testers))
        for t in testers: log("   tester", mask(t["attributes"].get("email")), t["attributes"].get("state"), t["attributes"].get("inviteType"))
        gb = [x["id"] for x in call("GET", f"/v1/betaGroups/{G}/builds?limit=200")["data"]]
        if BUILD in gb: log("   build 64 already in group")
        elif not a.get("hasAccessToAllBuilds"):
            r = call("POST", f"/v1/betaGroups/{G}/relationships/builds", {"data": [{"type": "builds", "id": BUILD}]})
            log("   build 64 added", r is not None)
    if any(not g["attributes"].get("isInternalGroup") for g in call("GET", f"/v1/apps/{APP}/betaGroups")["data"]):
        r = call("POST", "/v1/betaAppReviewSubmissions", {"data": {"type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": BUILD}}}}}, quiet=True)
        log("beta app review submitted", r is not None)
    if os.environ.get("SUBMIT") == "1":
        VER = call("GET", f"/v1/apps/{APP}/appStoreVersions?filter[versionString]=0.1.0&filter[platform]=IOS")["data"][0]["id"]
        s = call("POST", "/v1/reviewSubmissions", {"data": {"type": "reviewSubmissions", "attributes": {"platform": "IOS"}, "relationships": {"app": {"data": {"type": "apps", "id": APP}}}}})
        if s is None:
            ex = call("GET", f"/v1/reviewSubmissions?filter[app]={APP}&filter[state]=READY_FOR_REVIEW")["data"]
            S = ex[0]["id"] if ex else None
        else: S = s["data"]["id"]
        log("review submission", S)
        call("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {"reviewSubmission": {"data": {"type": "reviewSubmissions", "id": S}}, "appStoreVersion": {"data": {"type": "appStoreVersions", "id": VER}}}}})
        r = call("PATCH", f"/v1/reviewSubmissions/{S}", {"data": {"type": "reviewSubmissions", "id": S, "attributes": {"submitted": True}}})
        log("SUBMITTED for App Review" if r is not None else "!! submit failed", r and r["data"]["attributes"].get("state"))
except Exception as e:
    log("!! exception", repr(e))
open("asc-report.txt", "w").write("\n".join(out) + "\n")
