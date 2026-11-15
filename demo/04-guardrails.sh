#!/usr/bin/env bash
# Act 4: one change reaching every API is also one mistake reaching every API. Tyk checks first.
. "$(dirname "$0")/lib.sh"; need_state

act "Act 4: What if the one change is wrong?"
say "Shared configuration has an obvious risk. If one edit reaches every API, one typo breaks every API.
Tyk Dashboard validates every API that uses a fragment before it saves the fragment."
pause

say "${B}1. A typo.${N} Priya pastes the origins as a string and forgets the list brackets."
jq '.data.allowedOrigins = "https://app.meridian.example"' "$ROOT/fragments/cors-browser-apps.json" > "$STATE/bad.json"
show "curl -X PUT $DASH/api/assets/cors-browser-apps -d '{... \"allowedOrigins\": \"https://app.meridian.example\" ...}'"
dash PUT /api/assets/cors-browser-apps --data-binary "@$STATE/bad.json" > /dev/null
bad "HTTP $(status): $(jq -r '.Message | split(":")[0]' "$STATE/body")"
jq -r '.Errors[] | "    " + (split(": validating resolved document: ") | .[0] + "\n      " + .[1])' "$STATE/body"
if cors_allows accounts "$APP_ORIGIN"; then ok "Nothing was saved. The APIs still serve the last good configuration."; fi
pause

say "${B}2. A clean-up.${N} Someone decides rate-limit-standard looks unused and deletes it."
show "curl -X DELETE $DASH/api/assets/rate-limit-standard"
dash DELETE /api/assets/rate-limit-standard > /dev/null
bad "HTTP $(status): $(jq -r .Message "$STATE/body")"
pause

say "${B}3. A quiet opt-out.${N} The Payments team wants its wildcard back and adds it next to the reference."
jq '."x-tyk-api-gateway".middleware.global.cors += {allowedOrigins:["*"]}' "$ROOT/apis/after/payments.json" > "$STATE/optout.json"
show "\"cors\": { \"\$ref\": \"fragment://cors-browser-apps\", \"allowedOrigins\": [\"*\"] }"
dash PUT /api/apis/oas/payments-api --data-binary "@$STATE/optout.json" > /dev/null
bad "HTTP $(status): $(jq -r .Message "$STATE/body")"
note "A reference is all or nothing. A team can still replace it with its own block, but then the API
drops off the fragment's usage list, where the platform team can see it."
pause

say "Three attempts, no outage."
audit "${APIS[@]}"

say "Next: ${B}./demo/05-new-team.sh${N}"
