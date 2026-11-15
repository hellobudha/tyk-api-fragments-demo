#!/usr/bin/env bash
# Act 5: a new API starts with the baseline and stays on it.
. "$(dirname "$0")/lib.sh"; need_state

act "Act 5: The fourth team"
say "The Loans team ships its first API. A year ago they would have copied a block from the wiki,
and the drift from Act 1 would start again.

Priya publishes an API Template that carries the three references."
show "curl -X PUT $DASH/api/assets/meridian-api-baseline -d @templates/meridian-api-baseline.json"
dash PUT /api/assets/meridian-api-baseline --data-binary "@$ROOT/templates/meridian-api-baseline.json" | jq -c '{Status, Message}'
pause

say "The Loans team writes only what is theirs: a name, a listen path and an upstream."
show "jq '.\"x-tyk-api-gateway\"' apis/new/loans.json"
jq -c '."x-tyk-api-gateway"' "$ROOT/apis/new/loans.json"
dash GET /api/apis/oas/loans-api >/dev/null
if [ "$(status)" != 200 ]; then
  show "curl -X POST '$DASH/api/apis/oas?templateID=meridian-api-baseline' -d @apis/new/loans.json"
  dash POST "/api/apis/oas?templateID=meridian-api-baseline" --data-binary "@$ROOT/apis/new/loans.json" | jq -c '{Status, Message}'
fi
wait_for curl -fsS "$GW/loans/health"
until [ "$(security_headers loans)" = 3 ]; do sleep 0.5; done
pause

say "The new API holds references, not copies, so it follows the platform team from its first request.
It already allows NovaPay, which was added before the Loans API existed."
show "curl $DASH/api/apis/oas/loans-api/fragments"
dash GET /api/apis/oas/loans-api/fragments | jq -r 'to_entries[] | "  \(.key)  ->  \(.value.id)"'
audit "${APIS[@]}" loans

act "Where Meridian ended up"
say "  Before   3 APIs, 9 pasted blocks, 2 of 3 APIs out of line, no way to see it.
  After    4 APIs, 3 fragments, 0 pasted blocks. A baseline change is one request.

Platform team owns the fragments. API teams own everything else in their definitions.
Open the Dashboard (login in .demo/login.txt) and look under ${B}Assets > Fragments${N}.
Open any API in the designer to see the ${B}Shared configuration${N} badge on the fields a fragment sets.

Start again from the beginning with ${B}./demo/reset.sh${N}"
