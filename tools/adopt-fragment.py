#!/usr/bin/env python3
"""Move existing APIs onto a Fragment.

For every Tyk OAS API (or the ones named with --api), replace the block at --path with a
reference to the Fragment, and report how each API's own copy differed from the Fragment.
The Dashboard validates each API as it is saved, so an API the Fragment would break is left as it was.

  TYK_DASHBOARD_KEY=... tools/adopt-fragment.py --fragment cors-browser-apps \\
      --path x-tyk-api-gateway.middleware.global.cors [--api payments-api ...] [--dry-run]

Run with --dry-run first: it reports the drift and changes nothing.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from tyk_dashboard import DashboardError, call, oas_api_ids  # noqa: E402


def short(value, limit=40):
    text = "(missing)" if value is None else json.dumps(value, separators=(",", ":"))
    return text if len(text) <= limit else text[: limit - 1] + "…"


def drift(own, shared):
    """Fields where an API's own block differs from the Fragment, with the API's value."""
    if not isinstance(own, dict) or not isinstance(shared, dict):
        return [] if own == shared else [f"value={short(own)}"]
    keys = [k for k in shared] + [k for k in own if k not in shared]
    return [f"{k}={short(own.get(k))}" for k in keys if own.get(k) != shared.get(k)]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fragment", required=True, help="Fragment ID")
    ap.add_argument("--path", required=True, help="dotted path of the block, e.g. x-tyk-api-gateway.upstream.rateLimit")
    ap.add_argument("--api", action="append", help="API ID to move (repeatable). Default: every Tyk OAS API")
    ap.add_argument("--dry-run", action="store_true", help="report only, change nothing")
    a = ap.parse_args()

    try:
        shared = call("GET", f"/api/assets/{a.fragment}")
    except DashboardError as e:
        sys.exit(f"Fragment {a.fragment!r} not found ({e}). Create it first.")
    if shared.get("kind") != "fragment":
        sys.exit(f"{a.fragment!r} is a {shared.get('kind')}, not a fragment.")
    ref = {"$ref": f"fragment://{a.fragment}"}
    *parents, leaf = a.path.split(".")

    print(f"{'Checking' if a.dry_run else 'Moving'} APIs onto fragment {a.fragment}  ({a.path})\n", flush=True)
    moved = drifted = skipped = failed = 0
    for api in a.api or oas_api_ids():
        definition = call("GET", f"/api/apis/oas/{api}")
        node = definition
        for p in parents:
            node = node.get(p) if isinstance(node, dict) else None
        own = node.get(leaf) if isinstance(node, dict) else None
        if own is None:
            print(f"  {api:<24} no {leaf} block, skipped", flush=True)
            skipped += 1
            continue
        if own == ref:
            print(f"  {api:<24} already uses the fragment", flush=True)
            moved += 1
            continue
        diff = drift(own, shared["data"])
        drifted += bool(diff)
        note = "its copy matched" if not diff else "DRIFTED  " + "  ".join(diff[:2]) + (f"  +{len(diff) - 2} more" if len(diff) > 2 else "")
        if a.dry_run:
            print(f"  {api:<24} {note}", flush=True)
            continue
        node[leaf] = ref
        try:
            call("PUT", f"/api/apis/oas/{api}", definition)
            moved += 1
            print(f"  {api:<24} \u2714 references it    {note}", flush=True)
        except DashboardError as e:
            failed += 1
            print(f"  {api:<24} NOT MOVED: {e}", flush=True)

    print()
    if a.dry_run:
        print(f"Dry run: {drifted} of the APIs checked have drifted from {a.fragment}. Nothing was changed.")
    else:
        print(f"{moved} {'API now references' if moved == 1 else 'APIs now reference'} {a.fragment}. {drifted} had drifted from it and now follow it."
              + (f" {failed} could not be moved." if failed else "") + (f" {skipped} skipped." if skipped else ""))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
