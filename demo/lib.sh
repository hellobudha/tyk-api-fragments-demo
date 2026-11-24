#!/usr/bin/env bash
# Shared helpers for the walkthrough scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -f "$ROOT/.env" ] && set -a && . "$ROOT/.env" && set +a
DASH="http://localhost:${DASHBOARD_PORT:-3100}"
GW="http://localhost:${GATEWAY_PORT:-8280}"
STATE="$ROOT/.demo"
APIS=(accounts payments cards)

if [ -t 1 ]; then
  B=$'\033[1m'; D=$'\033[2m'; R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'; N=$'\033[0m'
else
  B=; D=; R=; G=; Y=; C=; N=
fi

act()  { printf '\n%s━━ %s ━━%s\n' "$B$C" "$*" "$N"; }
say()  { printf '\n%s\n' "$*"; }
note() { printf '%s%s%s\n' "$D" "$*" "$N"; }
ok()   { printf '%s✔ %s%s\n' "$G" "$*" "$N"; }
bad()  { printf '%s✘ %s%s\n' "$R" "$*" "$N"; }
# Show the command about to run, the way a presenter would type it.
show() { printf '%s$ %s%s\n' "$Y" "$*" "$N"; }
pause() { [ "${DEMO_AUTO:-}" = 1 ] || { printf '\n%s[enter to continue]%s' "$D" "$N"; read -r _; }; }

need_state() {
  [ -f "$STATE/dashboard.env" ] || { bad "Run ./demo/00-setup.sh first."; exit 1; }
  . "$STATE/dashboard.env"
  curl -fsS -o /dev/null "$DASH/hello" 2>/dev/null || { bad "Tyk Dashboard is not answering at $DASH. Run ./demo/00-setup.sh."; exit 1; }
}

# dash METHOD PATH [curl args...] -> body on stdout, HTTP status in $STATE/status
dash() {
  local method=$1 path=$2; shift 2
  curl -sS -X "$method" "$DASH$path" -H "Authorization: $DASH_KEY" \
    -H 'Content-Type: application/json' -o "$STATE/body" -w '%{http_code}' "$@" > "$STATE/status"
  cat "$STATE/body"
}
status() { cat "$STATE/status"; }

# The Gateway reloads a moment after the Dashboard saves. Wait until a probe passes.
wait_for() {
  local tries=0
  until "$@" >/dev/null 2>&1; do
    tries=$((tries + 1)); [ $tries -gt 120 ] && { bad "Timed out after 60s waiting for: $*"; exit 1; }
    sleep 0.5
  done
}
# wait_until "what we are waiting for" 'shell condition' -> gives up after 60 seconds instead of hanging
wait_until() {
  local tries=0
  until eval "$2" >/dev/null 2>&1; do
    tries=$((tries + 1))
    [ $tries -gt 120 ] && { bad "Timed out after 60s waiting for $1. Check: docker compose logs gateway dashboard"; exit 1; }
    sleep 0.5
  done
}

need_tools() {
  local t
  for t in docker curl jq openssl; do command -v "$t" >/dev/null || { bad "This walkthrough needs '$t' on your PATH."; exit 1; }; done
  docker info >/dev/null 2>&1 || { bad "Docker is not running."; exit 1; }
}
# Acts 3 to 5 build on Act 2: the APIs must already reference the Fragments.
need_fragments() {
  [ "$(shared_blocks accounts 2>/dev/null)" = 3 ] || { bad "The APIs do not use Fragments yet. Run ./demo/02-extract.sh first."; exit 1; }
}

APP_ORIGIN=https://app.meridian.example
ROGUE_ORIGIN=https://evil.example
PARTNER_ORIGIN=https://app.novapay.example

# cors_allows API ORIGIN -> true when the Gateway answers a preflight by allowing that origin
cors_allows() {
  curl -s -o /dev/null -D - -X OPTIONS "$GW/$1/$1" -H "Origin: $2" -H 'Access-Control-Request-Method: GET' \
    | grep -qi '^access-control-allow-origin:'
}
security_headers() {
  curl -s -o /dev/null -D - "$GW/$1/$1" | grep -ciE '^(strict-transport-security|x-content-type-options|cache-control: no-store)' || true
}
rate_limit() {
  dash GET "/api/apis/oas/$1-api?resolved=true" | jq -r '."x-tyk-api-gateway".upstream.rateLimit | "\(.rate) per \(.per)"'
}
shared_blocks() { dash GET "/api/apis/oas/$1-api/fragments" | jq 'length'; }

# cell COLOUR WIDTH TEXT -> padded, then coloured, so columns line up with or without a terminal
cell() { printf '%s%-*s%s ' "$1" "$2" "$3" "$N"; }

# The audit asks the running Gateway how each API behaves, so it reports what callers get.
audit() {
  local api h
  printf '\n%s%-9s %-9s %-11s %-9s %-9s %-12s %s%s\n' "$B" API "our app" "rogue site" NovaPay "sec hdrs" "rate limit" "from fragments" "$N"
  for api in "$@"; do
    printf '%-9s ' "$api"
    if cors_allows "$api" "$APP_ORIGIN"; then cell "$G" 9 allowed; else cell "$R" 9 BLOCKED; fi
    if cors_allows "$api" "$ROGUE_ORIGIN"; then cell "$R" 11 ALLOWED; else cell "$G" 11 blocked; fi
    if cors_allows "$api" "$PARTNER_ORIGIN"; then cell "$G" 9 allowed; else cell "$Y" 9 blocked; fi
    h=$(security_headers "$api"); if [ "$h" = 3 ]; then cell "$G" 9 "3 of 3"; else cell "$R" 9 "$h of 3"; fi
    printf '%-12s %s of 3 blocks\n' "$(rate_limit "$api")" "$(shared_blocks "$api")"
  done
  note "The three browser columns are live CORS preflights through the Gateway at $GW."
}

# burst API N -> how many of N quick requests the Gateway served
burst() {
  local n=0 i
  for i in $(seq "$2"); do [ "$(curl -s -o /dev/null -w '%{http_code}' "$GW/$1/health")" = 200 ] && n=$((n + 1)); done
  echo "$n"
  # Let the rate-limit window clear so later checks are not answered with 429.
  wait_until "the rate-limit window to clear" "curl -fsS -o /dev/null $GW/$1/health"
}
