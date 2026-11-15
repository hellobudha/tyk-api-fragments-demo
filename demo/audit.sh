#!/usr/bin/env bash
# Report how every demo API behaves at the Gateway right now.
. "$(dirname "$0")/lib.sh"; need_state
apis=("${APIS[@]}")
dash GET /api/apis/oas/loans-api >/dev/null; [ "$(status)" = 200 ] && apis+=(loans)
audit "${apis[@]}"
