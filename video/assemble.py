#!/usr/bin/env python3
"""Turn the recorded segments into the finished video and its standalone subtitle files.

  assemble.py strip <story.tsv> <out.tsv>
      Copy the storyboard with the subtitle text removed, so no text is drawn into the picture.
  assemble.py build <story.tsv> <workdir> <basename>
      Join <workdir>/out/seg/*.mp4 with short crossfades, add an empty band under the picture
      (players draw subtitles there, so they never cover the screen), and write <basename>.mp4,
      <basename>.srt and <basename>.vtt with cues timed to the joined video.
"""
import csv
import os
import subprocess
import sys

FADE = 0.4            # seconds of crossfade between two segments
LEAD_IN = 0.2         # seconds each segment starts before its beat (set by the recording toolkit)
BAND = 140            # pixels of empty band under the 1280x720 picture
BAND_COLOUR = "0x03031C"


def rows(path):
    with open(path, newline="") as f:
        for r in csv.reader(f, delimiter="\t"):
            if r and not r[0].startswith("#"):
                yield (r + [""] * 6)[:6]


def stamp(t, sep):
    ms = round(t * 1000)
    return f"{ms // 3600000:02d}:{ms // 60000 % 60:02d}:{ms // 1000 % 60:02d}{sep}{ms % 1000:03d}"


def strip(story, out):
    with open(out, "w", newline="") as f:
        w = csv.writer(f, delimiter="\t", lineterminator="\n")
        for kind, name, secs, l1, l2, spoken in rows(story):
            w.writerow([kind, name, secs, l1, l2, spoken] if kind == "card" else [kind, name, secs, "", "", spoken])


def build(story, work, base):
    text = {name: [x for x in (l1, l2) if x] for kind, name, _, l1, l2, _ in rows(story) if kind == "beat"}
    segs = [(r[0], float(r[2])) for r in rows(os.path.join(work, "out", "segments.tsv")) if r[0] != "TOTAL"]
    # Two beats are continuous footage when the recorder logged them back to back, with no cut
    # marker between them. Continuous beats are joined as they were filmed; a cut gets a crossfade.
    recorded = [r[1] for r in rows(os.path.join(work, "beats.tsv"))]
    follows = {b: a for a, b in zip(recorded, recorded[1:])}
    cmd, graph, cues = ["ffmpeg", "-loglevel", "error", "-y"], [], []
    total, last, prev = 0.0, None, None            # total: length of the joined video so far
    for i, (seg, dur) in enumerate(segs):
        name = seg.split("-", 2)[2]                # e.g. 04-beat-usage
        cmd += ["-i", os.path.join(work, "out", "seg", seg + ".mp4")]
        continuous = prev is not None and follows.get(name) == prev
        lead = LEAD_IN if continuous else 0.0      # drop the frames the previous beat already showed
        graph.append(f"[{i}:v]trim=start={lead},setpts=PTS-STARTPTS,fps=30,format=yuv420p[s{i}]")
        dur -= lead
        if last is None:
            start, total = 0.0, dur
            last = f"s{i}"
        elif continuous:
            graph.append(f"[{last}][s{i}]concat=n=2:v=1:a=0,fps=30[j{i}]")
            start, total = total, total + dur
            last = f"j{i}"
        else:
            graph.append(f"[{last}][s{i}]xfade=transition=fade:duration={FADE}:offset={total - FADE:.3f}[j{i}]")
            start, total = total - FADE, total + dur - FADE
            last = f"j{i}"
        if text.get(name):
            cues.append((start + FADE + 0.1, start + dur - FADE - 0.1, text[name]))
        prev = name
    graph.append(f"[{last}]pad=1280:{720 + BAND}:0:0:color={BAND_COLOUR},format=yuv420p[out]")
    cmd += ["-filter_complex", ";".join(graph), "-map", "[out]", "-c:v", "libx264", "-crf", "20", "-an", base + ".mp4"]
    subprocess.run(cmd, check=True)
    with open(base + ".srt", "w") as f:
        for i, (a, b, lines) in enumerate(cues, 1):
            f.write(f"{i}\n{stamp(a, ',')} --> {stamp(b, ',')}\n" + "\n".join(lines) + "\n\n")
    with open(base + ".vtt", "w") as f:
        f.write("WEBVTT\n\n")
        for a, b, lines in cues:
            f.write(f"{stamp(a, '.')} --> {stamp(b, '.')}\n" + "\n".join(lines) + "\n\n")
    print(f"{base}.mp4: {len(segs)} segments, {total:.1f}s, {len(cues)} subtitle cues in .srt and .vtt")


if __name__ == "__main__":
    a = sys.argv[1:]
    if len(a) == 3 and a[0] == "strip":
        strip(a[1], a[2])
    elif len(a) == 4 and a[0] == "build":
        build(a[1], a[2], a[3])
    else:
        sys.exit(__doc__)
