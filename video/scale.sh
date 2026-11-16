#!/usr/bin/env bash
# Grow the demo from 4 APIs to the 24 in video/apis.tsv, or shrink it back.
# Every added API is created from the baseline Template, so it references the three Fragments.
# Run the main walkthrough through Act 5 first. usage: ./video/scale.sh up|down
. "$(dirname "$0")/../demo/lib.sh"; need_state
title() { awk -F- '{for(i=1;i<=NF;i++) $i=($i=="fx"||$i=="kyc") ? toupper($i) : toupper(substr($i,1,1)) substr($i,2)} 1' OFS=' ' <<<"$1"; }
grep -v '^#' "$ROOT/video/apis.tsv" | while IFS=$'\t' read -r team api _; do
  case "$api" in accounts|payments|cards|loans) continue;; esac
  dash GET "/api/apis/oas/$api-api" >/dev/null; exists=$(status)
  if [ "${1:-}" = up ] && [ "$exists" != 200 ]; then
    name="$(title "$api") API"
    jq -n --arg id "$api-api" --arg n "$name" --arg p "/$api/" --arg u "http://upstream:8080/anything/$api-service" --arg team "$team" \
      '{openapi:"3.0.3",info:{title:$n,version:"1.0.0",contact:{name:($team+" team")}},
        paths:{"/health":{get:{operationId:"health",responses:{"200":{description:"OK"}}}}},
        "x-tyk-api-gateway":{info:{id:$id,name:$n,state:{active:true}},server:{listenPath:{value:$p,strip:true}},upstream:{url:$u}}}' > "$STATE/scale.json"
    dash POST "/api/apis/oas?templateID=meridian-api-baseline" --data-binary "@$STATE/scale.json" >/dev/null
    [ "$(status)" = 200 ] && ok "$api-api ($team)" || { bad "$api: $(cat "$STATE/body")"; exit 1; }
  elif [ "${1:-}" = down ] && [ "$exists" = 200 ]; then
    dash DELETE "/api/apis/oas/$api-api" >/dev/null && ok "removed $api-api"
  fi
done
[ "${1:-}" = up ] && wait_for curl -fsS "$GW/notifications/health"
dash GET /api/assets/cors-browser-apps/apis | jq -r '"APIs using cors-browser-apps: \(.total_count)"'
