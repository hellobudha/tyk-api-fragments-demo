#!/usr/bin/env bash
# Record the walkthrough video against the running demo stack.
# Needs: ffmpeg, python3 with Pillow, Playwright with Chromium (npm i -D playwright && npx playwright install chromium
# in the directory you run this from), and the evidence-video toolkit in EVIDENCE_VIDEO_HOME.
# Writes video/api-fragments-walkthrough.mp4 with .srt and .vtt subtitle files beside it.
# usage: EVIDENCE_VIDEO_HOME=/path/to/tools/evidence-video ./video/record.sh <workdir>
. "$(dirname "$0")/../demo/lib.sh"; need_state
TOOLS="${EVIDENCE_VIDEO_HOME:?set EVIDENCE_VIDEO_HOME to the evidence-video toolkit}"
WORK="${1:?usage: record.sh <workdir>}"; rm -rf "$WORK"; mkdir -p "$WORK"
PARTNER=http://novapay.localhost:5180

# Off camera: put the Fragment back to its starting value and serve the partner page.
dash PUT /api/assets/cors-browser-apps --data-binary "@$ROOT/fragments/cors-browser-apps.json" >/dev/null
curl -fsS -o /dev/null "$PARTNER/" 2>/dev/null || { (cd "$ROOT/partner-app" && python3 -m http.server 5180 --bind 127.0.0.1 >/dev/null 2>&1 &); sleep 1; }
while cors_allows accounts "$PARTNER"; do sleep 0.5; done

# The video is built without subtitle text. Subtitles go to standalone .srt and .vtt files.
python3 "$ROOT/video/subtitles.py" strip "$ROOT/video/story.tsv" "$WORK/story.tsv"
DASH_EMAIL=platform@meridian.example DASH_PASSWORD="$(awk '/^Password/{print $2}' "$STATE/login.txt")" \
  node "$TOOLS/record-web.mjs" "$ROOT/video/steps.json" "$WORK"
python3 "$TOOLS/make_video.py" build "$WORK" --no-voice
python3 "$TOOLS/make_video.py" verify "$WORK"

# Add an empty band under the picture. Players draw subtitles near the bottom of the frame,
# so they land on the band and never cover the Dashboard.
OUT="$ROOT/video/api-fragments-walkthrough"
ffmpeg -loglevel error -y -i "$WORK/out/final.mp4" -vf "pad=1280:860:0:0:color=0x111318" \
  -c:v libx264 -crf 20 -pix_fmt yuv420p -an "$OUT.mp4"
python3 "$ROOT/video/subtitles.py" write "$ROOT/video/story.tsv" "$WORK/out/segments.tsv" "$OUT"
