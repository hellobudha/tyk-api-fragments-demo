#!/usr/bin/env python3
"""Put the demo stack into the video's starting state: 24 APIs, no Fragments.

Every API carries its own copy of the CORS, rate limit and security header settings, as teams do
before Fragments exist, and four of the CORS copies have drifted from the bank's standard.
Run ./demo/00-setup.sh afterwards to return to the main walkthrough.
"""
import copy
import csv
import json
import os
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from tyk_dashboard import DashboardError, call, oas_api_ids  # noqa: E402

STANDARD = json.load(open(os.path.join(ROOT, "fragments", "cors-browser-apps.json")))["data"]
# How four teams' copies have drifted from the standard over a year.
DRIFT = {
    "payments": {"allowedOrigins": ["*"], "allowedHeaders": ["*"]},   # widened during an incident, never reverted
    "card-controls": {"allowedOrigins": STANDARD["allowedOrigins"] + ["https://staging.meridian.example"]},
    "mortgages": {"allowedOrigins": ["https://app.meridian.example", "https://www.meridian-legacy.example"]},
    "kyc": {"allowCredentials": False},
}


def quiet(fn, *args):
    try:
        return fn(*args)
    except DashboardError:
        return None


def definition(team, api):
    d = json.load(open(os.path.join(ROOT, "apis", "before", "accounts.json")))   # a correct copy of the baseline
    name = " ".join(w.upper() if w in ("fx", "kyc") else w.capitalize() for w in api.split("-")) + " API"
    d["info"].update(title=name, contact={"name": f"{team} team"})
    d["paths"] = {"/health": {"get": {"operationId": "health", "responses": {"200": {"description": "OK"}}}}}
    g = d["x-tyk-api-gateway"]
    g["info"].update(id=f"{api}-api", name=name)
    g["server"]["listenPath"]["value"] = f"/{api}/"
    g["upstream"]["url"] = f"http://upstream:8080/anything/{api}-service"
    g["middleware"]["global"]["cors"] = dict(copy.deepcopy(STANDARD), **DRIFT.get(api, {}))
    return d


def main():
    teams = [r for r in csv.reader(open(os.path.join(ROOT, "video", "apis.tsv")), delimiter="\t") if r and not r[0].startswith("#")]
    quiet(call, "DELETE", "/api/assets/meridian-api-baseline")
    for api in oas_api_ids():
        call("DELETE", f"/api/apis/oas/{api}")
    for fragment in ("cors-browser-apps", "rate-limit-standard", "security-response-headers"):
        quiet(call, "DELETE", f"/api/assets/{fragment}")
    for team, api, *_ in teams:
        call("POST", "/api/apis/oas", definition(team, api))
    gw = os.environ.get("GATEWAY_URL", "http://localhost:8280")
    for _ in range(120):   # wait until the Gateway serves all of them
        try:
            for _, api, *_ in teams:
                urllib.request.urlopen(f"{gw}/{api}/health", timeout=5).read()
            break
        except Exception:
            time.sleep(0.5)
    else:
        sys.exit("The Gateway did not load the APIs within 60 seconds.")
    print(f"{len(teams)} APIs with their own CORS copies, {len(DRIFT)} drifted, no Fragments.")


if __name__ == "__main__":
    main()
