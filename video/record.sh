#!/usr/bin/env bash
# Record the walkthrough video against the running demo stack.
# Needs: ffmpeg, python3 with Pillow, Playwright with Chromium (npm i -D playwright && npx playwright install chromium
# in the directory you run this from), and the evidence-video toolkit in EVIDENCE_VIDEO_HOME.
# Writes video/api-fragments-walkthrough.mp4 with .srt and .vtt subtitle files beside it.
# usage: EVIDENCE_VIDEO_HOME=/path/to/tools/evidence-video ./video/record.sh <workdir>
. "$(dirname "$0")/../demo/lib.sh"; need_state; need_fragments
TOOLS="${EVIDENCE_VIDEO_HOME:?set EVIDENCE_VIDEO_HOME to the evidence-video toolkit}"
WORK="${1:?usage: record.sh <workdir>}"; rm -rf "$WORK"; mkdir -p "$WORK"
PARTNER=http://novapay.localhost:5180

# Off camera: put the Fragment back to its starting value and serve the partner page.
dash PUT /api/assets/cors-browser-apps --data-binary "@$ROOT/fragments/cors-browser-apps.json" >/dev/null
serve() {  # serve DIR PORT, detached so this script can exit while the server keeps running
  curl -fsS -o /dev/null "http://127.0.0.1:$2/" 2>/dev/null && return
  nohup python3 -m http.server "$2" --bind 127.0.0.1 --directory "$1" </dev/null >/dev/null 2>&1 &
  disown; sleep 1
}
serve "$ROOT/partner-app" 5180
serve "$ROOT/video/scenes" 5181
"$ROOT/video/scale.sh" up >/dev/null    # the video tells the story with 24 APIs across six teams
wait_until "the Fragment to return to its starting value" '! cors_allows accounts "$PARTNER" && ! cors_allows notifications "$PARTNER"'

# The video is built without subtitle text. Subtitles go to standalone .srt and .vtt files.
python3 "$ROOT/video/assemble.py" strip "$ROOT/video/story.tsv" "$WORK/story.tsv"
DASH_EMAIL=platform@meridian.example DASH_PASSWORD="$(awk '/^Password/{print $2}' "$STATE/login.txt")" \
  node "$TOOLS/record-web.mjs" "$ROOT/video/steps.json" "$WORK"
python3 "$TOOLS/make_video.py" build "$WORK" --no-voice
python3 "$TOOLS/make_video.py" verify "$WORK"

# Join the segments with crossfades, add the subtitle band, and write the .srt and .vtt files.
python3 "$ROOT/video/assemble.py" build "$ROOT/video/story.tsv" "$WORK" "$ROOT/video/api-fragments-walkthrough"
