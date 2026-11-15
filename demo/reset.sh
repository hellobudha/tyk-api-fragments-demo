#!/usr/bin/env bash
# Throw the demo stack away, including its data. Run 00-setup.sh to start again.
. "$(dirname "$0")/lib.sh"
(cd "$ROOT" && docker compose down -v)
rm -rf "$STATE"
ok "Demo stack removed"
