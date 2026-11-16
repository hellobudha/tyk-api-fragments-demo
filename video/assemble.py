#!/usr/bin/env python3
"""Cut the recording into the finished video and its standalone subtitle files.

  assemble.py <story.tsv> <workdir> <basename>

Reads <workdir>/raw.mp4 and <workdir>/beats.tsv from video/record-web.mjs. Each beat in story.tsv
runs from its marker to the next marker, so frames after a "cut" marker (page loads) are left out.
Beats filmed back to back are joined as filmed; other joins get a short crossfade.

The result is 1920x1080. The picture sits in the upper part of the frame with an empty band under
it, where players draw the subtitles, so subtitles never cover the screen. Writes <basename>.mp4,
<basename>.srt and <basename>.vtt.
"""
import csv
import subprocess
import sys

FPS = 30
FADE = 0.4            # seconds of crossfade between two shots
FRAME = (1920, 1080)  # size of the finished video
PICTURE = (1600, 900) # the recorded screen inside it, leaving a band underneath for subtitles
TOP = 24              # pixels above the picture
BACKDROP = "0x03031C"


def rows(path):
    with open(path, newline="") as f:
        for r in csv.reader(f, delimiter="\t"):
            if r and not r[0].startswith("#"):
                yield r


def stamp(t, sep):
    ms = round(t * 1000)
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d}{sep}{ms % 1000:03d}"


def main(story, work, base):
    markers = [(float(t), name) for t, name in rows(f"{work}/beats.tsv")]
    at = {name: t for t, name in markers}
    beats = [(r + [""] * 6)[:6] for r in rows(story)]
    graph = [f"[0:v]fps={FPS},split={len(beats)}" + "".join(f"[r{i}]" for i in range(len(beats)))]
    cues, last, total, prev = [], None, 0.0, None
    for i, (kind, name, _, l1, l2, _) in enumerate(beats):
        if kind != "beat" or name not in at:
            sys.exit(f"story beat {name!r} was not recorded (recorded: {', '.join(n for _, n in markers)})")
        t0 = at[name]
        nxt = min((t for t, _ in markers if t > t0), default=None)
        if nxt is None:
            sys.exit(f"beat {name!r} has no end marker")
        a, b = round(t0 * FPS), round(nxt * FPS)
        dur = (b - a) / FPS
        graph.append(f"[r{i}]trim=start_frame={a}:end_frame={b},setpts=PTS-STARTPTS[s{i}]")
        continuous = prev is not None and at.get(prev) is not None and min(t for t, _ in markers if t > at[prev]) == t0
        if last is None:
            start, total, last = 0.0, dur, f"s{i}"
        elif continuous:
            graph.append(f"[{last}][s{i}]concat=n=2:v=1:a=0,fps={FPS}[j{i}]")
            start, total, last = total, total + dur, f"j{i}"
        else:
            graph.append(f"[{last}][s{i}]xfade=transition=fade:duration={FADE}:offset={total - FADE:.4f}[j{i}]")
            start, total, last = total - FADE, total + dur - FADE, f"j{i}"
        text = [x for x in (l1, l2) if x]
        if text:
            cues.append((start + FADE + 0.1, start + dur - FADE - 0.1, text))
        prev = name
    graph.append(f"[{last}]fade=t=in:d=0.6,fade=t=out:st={total - 0.8:.3f}:d=0.8,"
                 f"scale={PICTURE[0]}:{PICTURE[1]}:flags=lanczos,"
                 f"pad={FRAME[0]}:{FRAME[1]}:{(FRAME[0] - PICTURE[0]) // 2}:{TOP}:color={BACKDROP},format=yuv420p[out]")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", f"{work}/raw.mp4", "-filter_complex", ";".join(graph),
                    "-map", "[out]", "-c:v", "libx264", "-crf", "18", "-preset", "medium", "-movflags", "+faststart",
                    "-an", base + ".mp4"], check=True)
    with open(base + ".srt", "w") as f:
        for n, (a, b, lines) in enumerate(cues, 1):
            f.write(f"{n}\n{stamp(a, ',')} --> {stamp(b, ',')}\n" + "\n".join(lines) + "\n\n")
    with open(base + ".vtt", "w") as f:
        f.write("WEBVTT\n\n")
        for a, b, lines in cues:
            f.write(f"{stamp(a, '.')} --> {stamp(b, '.')}\n" + "\n".join(lines) + "\n\n")
    print(f"{base}.mp4: {FRAME[0]}x{FRAME[1]}, {len(beats)} shots, {total:.1f}s, {len(cues)} subtitle cues in .srt and .vtt")


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    main(*sys.argv[1:])
