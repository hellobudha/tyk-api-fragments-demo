#!/usr/bin/env bash
# Run the whole walkthrough without pauses.
cd "$(dirname "$0")"
export DEMO_AUTO=1
for s in 00-setup 01-the-drift 02-extract 03-one-change 04-guardrails 05-new-team; do ./$s.sh; done
