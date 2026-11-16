#!/usr/bin/env bash
# Act 3: one change to one fragment reaches every API.
. "$(dirname "$0")/lib.sh"; need_state; need_fragments

act "Act 3: Friday, 4pm"
say "Meridian signs NovaPay, a partner whose web app must call Meridian APIs from the browser.
Launch is Monday. NovaPay's origin has to be allowed on every API.

The old way: one ticket per API team, three reviews, three deploys, and hope nobody mistypes it.
At 140 APIs the launch moves to next quarter."
pause

say "Before the change, NovaPay is blocked everywhere:"
audit "${APIS[@]}"
pause

say "Priya adds one origin to one fragment."
jq --arg o "$PARTNER_ORIGIN" '.data.allowedOrigins += [$o] | .data.allowedOrigins |= unique' \
  "$ROOT/fragments/cors-browser-apps.json" > "$STATE/cors-with-partner.json"
show "curl -X PUT $DASH/api/assets/cors-browser-apps -d '{... \"allowedOrigins\": [\"$APP_ORIGIN\", \"$PARTNER_ORIGIN\"] ...}'"
dash PUT /api/assets/cors-browser-apps --data-binary "@$STATE/cors-with-partner.json" | jq -c '{Status, Message}'
[ "$(status)" = 200 ] || exit 1
for api in "${APIS[@]}"; do wait_until "$api to allow the partner" "cors_allows $api $PARTNER_ORIGIN"; done
pause

say "One request. Tyk checked every API that uses the fragment, saved it, and reloaded the Gateway."
audit "${APIS[@]}"
pause

say "And the question nobody could answer in Act 1 is now a lookup: which APIs get this setting?"
show "curl $DASH/api/assets/cors-browser-apps/apis"
dash GET /api/assets/cors-browser-apps/apis | jq -r '.apis[] | "  \(.api_id)  (\(.name))"'

say "Next: ${B}./demo/04-guardrails.sh${N}"
