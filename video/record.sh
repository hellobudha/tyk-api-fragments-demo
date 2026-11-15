#!/usr/bin/env bash
# Record the walkthrough video against the running demo stack.
# Needs: ffmpeg, python3 with Pillow, Playwright with Chromium (npm i -D playwright && npx playwright install chromium
# in the directory you run this from), and the evidence-video toolkit in EVIDENCE_VIDEO_HOME.
# usage: EVIDENCE_VIDEO_HOME=/path/to/tools/evidence-video ./video/record.sh <workdir>
. "$(dirname "$0")/../demo/lib.sh"; need_state
TOOLS="${EVIDENCE_VIDEO_HOME:?set EVIDENCE_VIDEO_HOME to the evidence-video toolkit}"
WORK="${1:?usage: record.sh <workdir>}"; rm -rf "$WORK"; mkdir -p "$WORK"
PARTNER=http://novapay.localhost:5180

# Off camera: put the Fragment back to its starting value and serve the partner page.
dash PUT /api/assets/cors-browser-apps --data-binary "@$ROOT/fragments/cors-browser-apps.json" >/dev/null
curl -fsS -o /dev/null "$PARTNER/" 2>/dev/null || { (cd "$ROOT/partner-app" && python3 -m http.server 5180 --bind 127.0.0.1 >/dev/null 2>&1 &); sleep 1; }
while cors_allows accounts "$PARTNER"; do sleep 0.5; done

cp "$ROOT/video/story.tsv" "$WORK/story.tsv"
DASH_EMAIL=platform@meridian.example DASH_PASSWORD="$(awk '/^Password/{print $2}' "$STATE/login.txt")" \
  node "$TOOLS/record-web.mjs" "$ROOT/video/steps.json" "$WORK"
python3 "$TOOLS/make_video.py" build "$WORK" --no-voice
python3 "$TOOLS/make_video.py" verify "$WORK"
