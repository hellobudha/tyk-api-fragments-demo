#!/usr/bin/env bash
# Start the stack, create an organisation and an admin user, and load the three "before" APIs.
. "$(dirname "$0")/lib.sh"
mkdir -p "$STATE"
ADMIN_SECRET=admin-secret

act "Starting Tyk ${DASHBOARD_VERSION:-v5.16.0} (Dashboard $DASH, Gateway $GW)"
(cd "$ROOT" && docker compose up -d --wait dashboard redis postgres upstream && docker compose up -d gateway)
wait_for curl -fsS "$DASH/hello"

if [ ! -f "$STATE/dashboard.env" ]; then
  org=$(curl -fsS "$DASH/admin/organisations" -H "admin-auth: $ADMIN_SECRET" \
    -d '{"owner_name":"Meridian Bank","cname_enabled":false}' | jq -r .Meta)
  pass="Mb-$(openssl rand -hex 12)"
  user=$(curl -fsS "$DASH/admin/users" -H "admin-auth: $ADMIN_SECRET" -d "$(jq -n --arg o "$org" --arg p "$pass" \
    '{first_name:"Priya",last_name:"Platform",email_address:"platform@meridian.example",password:$p,active:true,org_id:$o,user_permissions:{IsAdmin:"admin"}}')")
  key=$(jq -r .Meta.access_key <<<"$user"); uid=$(jq -r .Meta.id <<<"$user")
  curl -fsS "$DASH/api/users/$uid/actions/reset" -H "Authorization: $key" \
    -d "$(jq -n --arg p "$pass" '{new_password:$p,user_permissions:{IsAdmin:"admin"}}')" >/dev/null
  umask 077
  printf 'DASH_KEY=%s\nORG_ID=%s\n' "$key" "$org" > "$STATE/dashboard.env"
  printf 'Dashboard: %s\nEmail:     platform@meridian.example\nPassword:  %s\n' "$DASH" "$pass" > "$STATE/login.txt"
  ok "Organisation and admin user created"
fi
need_state

act "Loading the three APIs as each team wrote them"
for api in "${APIS[@]}"; do
  dash GET "/api/apis/oas/$api-api" >/dev/null
  if [ "$(status)" = 200 ]; then
    dash PUT "/api/apis/oas/$api-api" --data-binary "@$ROOT/apis/before/$api.json" >/dev/null
  else
    dash POST "/api/apis/oas" --data-binary "@$ROOT/apis/before/$api.json" >/dev/null
  fi
  [ "$(status)" = 200 ] || { bad "$api: HTTP $(status) $(cat "$STATE/body")"; exit 1; }
  ok "$api-api"
done
# Running setup again rewinds the story: remove what the later acts created.
dash DELETE /api/apis/oas/loans-api >/dev/null
[ -x "$ROOT/video/scale.sh" ] && "$ROOT/video/scale.sh" down >/dev/null
for asset in meridian-api-baseline cors-browser-apps rate-limit-standard security-response-headers; do
  dash DELETE "/api/assets/$asset" >/dev/null
done
for api in "${APIS[@]}"; do wait_for curl -fsS "$GW/$api/health"; done
until cors_allows payments "$ROGUE_ORIGIN" && [ "$(security_headers cards)" = 0 ] && ! curl -fsS -o /dev/null "$GW/loans/health"; do sleep 0.5; done

say "Ready. Dashboard login is in ${B}.demo/login.txt${N}. Next: ${B}./demo/01-the-drift.sh${N}"
