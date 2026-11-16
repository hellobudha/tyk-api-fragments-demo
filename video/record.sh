#!/usr/bin/env bash
# Record the walkthrough video against the running demo stack.
#
# The video starts where most teams are today: 24 APIs, each with its own copy of the CORS rules, and
# no Fragments. It creates the Fragment, moves the APIs onto it, and makes the partner launch one edit.
#
# Needs ffmpeg, and Playwright with Chromium installed in the directory you run this from:
#   npm i -D playwright && npx playwright install chromium
# usage: ./video/record.sh <workdir>
# Writes video/api-fragments-walkthrough.mp4 with .srt and .vtt subtitle files beside it.
# Afterwards, run ./demo/00-setup.sh to return to the main walkthrough.
. "$(dirname "$0")/../demo/lib.sh"; need_state
WORK="${1:?usage: record.sh <workdir>}"; rm -rf "$WORK"; mkdir -p "$WORK"
command -v ffmpeg >/dev/null || { bad "This needs ffmpeg."; exit 1; }
PARTNER=http://novapay.localhost:5180
export TYK_DASHBOARD_URL="$DASH" TYK_DASHBOARD_KEY="$DASH_KEY"

# Off camera: the starting state, and the two local pages the video visits.
python3 "$ROOT/video/prepare.py"
serve() {  # serve NAME PORT COMMAND..., detached so this script can exit while the server keeps running
  local name=$1 port=$2; shift 2
  curl -fsS -o /dev/null "http://127.0.0.1:$port/$name" 2>/dev/null && return
  curl -fsS -o /dev/null "http://127.0.0.1:$port/" 2>/dev/null && { bad "Port $port is busy with something else."; exit 1; }
  nohup "$@" </dev/null >/dev/null 2>&1 & disown
  wait_until "the server on port $port" "curl -fsS -o /dev/null http://127.0.0.1:$port/$name"
}
serve index.html 5180 python3 -m http.server 5180 --bind 127.0.0.1 --directory "$ROOT/partner-app"
serve health 5181 python3 "$ROOT/video/scenes/server.py"
wait_until "the starting state at the Gateway" '! cors_allows accounts "$PARTNER" && cors_allows payments "$PARTNER"'

DASH_EMAIL=platform@meridian.example DASH_PASSWORD="$(awk '/^Password/{print $2}' "$STATE/login.txt")" \
  node "$ROOT/video/record-web.mjs" "$ROOT/video/steps.json" "$WORK"
python3 "$ROOT/video/assemble.py" "$ROOT/video/story.tsv" "$WORK" "$ROOT/video/api-fragments-walkthrough"
note "The stack now holds the video's end state. Run ./demo/00-setup.sh to return to the main walkthrough."
