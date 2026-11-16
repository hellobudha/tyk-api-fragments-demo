"""A small Tyk Dashboard API client for the scripts in this repository.

Reads TYK_DASHBOARD_URL (default http://localhost:3100) and TYK_DASHBOARD_KEY from the environment.
The key is a Dashboard user's API access key. It is sent as a header and never printed.
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ.get("TYK_DASHBOARD_URL", "http://localhost:3100").rstrip("/")
KEY = os.environ.get("TYK_DASHBOARD_KEY", "")


class DashboardError(Exception):
    def __init__(self, status, body):
        try:
            message = json.loads(body).get("Message", body)
        except (ValueError, AttributeError):
            message = body
        super().__init__(f"HTTP {status}: {message}")
        self.status = status


def call(method, path, body=None):
    if not KEY:
        sys.exit("Set TYK_DASHBOARD_KEY to a Tyk Dashboard user's API access key.")
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(URL + path, data=data, method=method,
                                 headers={"Authorization": KEY, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            raw = res.read().decode()
            return json.loads(raw) if raw.strip() else None
    except urllib.error.HTTPError as e:
        raise DashboardError(e.code, e.read().decode()) from None


def oas_api_ids():
    """IDs of every Tyk OAS API in the organisation."""
    listing = call("GET", "/api/apis?p=-1")
    return sorted(a["api_definition"]["api_id"] for a in listing.get("apis") or [] if a["api_definition"].get("is_oas"))
