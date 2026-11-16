#!/usr/bin/env bash
# Act 2: the platform team stores each shared block once, and the APIs point at it.
. "$(dirname "$0")/lib.sh"; need_state

act "Act 2: Store it once"
say "Priya on the platform team takes the three blocks that must be identical everywhere
and saves each one as a Fragment: a named piece of API configuration held in Tyk Dashboard."
pause

for f in cors-browser-apps rate-limit-standard security-response-headers; do
  show "curl -X PUT $DASH/api/assets/$f -d @fragments/$f.json"
  dash PUT "/api/assets/$f" --data-binary "@$ROOT/fragments/$f.json" >/dev/null
  case "$(status)" in 200|201) ok "$f  $(jq -c .data "$ROOT/fragments/$f.json" | cut -c1-90)";; *) bad "$f: $(cat "$STATE/body")"; exit 1;; esac
done
pause

say "Now each API swaps its own copy for a reference. This is the whole change to the Payments API:"
show "diff apis/before/payments.json apis/after/payments.json"
diff <(jq -S '."x-tyk-api-gateway" | {upstream, middleware}' "$ROOT/apis/before/payments.json") \
     <(jq -S '."x-tyk-api-gateway" | {upstream, middleware}' "$ROOT/apis/after/payments.json") | sed 's/^/  /' || true
pause

for api in "${APIS[@]}"; do
  show "curl -X PUT $DASH/api/apis/oas/$api-api -d @apis/after/$api.json"
  dash PUT "/api/apis/oas/$api-api" --data-binary "@$ROOT/apis/after/$api.json" >/dev/null
  [ "$(status)" = 200 ] && ok "$api-api now references 3 fragments" || { bad "$api: $(cat "$STATE/body")"; exit 1; }
done
wait_until "the Gateway to reload the APIs" '[ "$(security_headers cards)" = 3 ] && ! cors_allows payments "$ROGUE_ORIGIN"'
pause

say "The Dashboard stores the reference. The Gateway never sees one: it receives the finished definition."
show "curl $DASH/api/apis/oas/cards-api                  # what is stored"
dash GET /api/apis/oas/cards-api | jq -c '."x-tyk-api-gateway".upstream.rateLimit'
show "curl $DASH/api/apis/oas/cards-api?resolved=true    # what the Gateway runs"
dash GET "/api/apis/oas/cards-api?resolved=true" | jq -c '."x-tyk-api-gateway".upstream.rateLimit'
pause

say "Same audit as before. No team redeployed anything."
show "./demo/audit.sh"
audit "${APIS[@]}"
say "The Cards limit dropped from 200 to 20 per 10 seconds. Thirty quick requests prove it at the Gateway:"
show "for i in \$(seq 30); do curl $GW/cards/health; done"
ok "Cards API served $(burst cards 30) of 30, then answered 429"

say "Next: ${B}./demo/03-one-change.sh${N}"
