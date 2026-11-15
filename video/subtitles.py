#!/usr/bin/env python3
"""Keep subtitles out of the picture.

  subtitles.py strip <story.tsv> <out.tsv>
      Copy the storyboard with the beat subtitle text removed, so the video is built clean.
  subtitles.py write <story.tsv> <segments.tsv> <basename>
      Write <basename>.srt and <basename>.vtt, timed from the measured segments of the built video.

Title cards keep their text: they are full-screen slides, not subtitles.
"""
import csv
import sys


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


def write(story, segments, base):
    text = {name: [x for x in (l1, l2) if x] for kind, name, _, l1, l2, _ in rows(story) if kind == "beat"}
    cues = []
    for seg, start, dur in ((r[0], float(r[1]), float(r[2])) for r in rows(segments) if r[0] != "TOTAL"):
        _, kind, name = seg.split("-", 2)  # e.g. 04-beat-usage
        if kind == "beat" and text.get(name):
            cues.append((start + 0.3, start + dur - 0.2, text[name]))
    with open(base + ".srt", "w") as f:
        for i, (a, b, lines) in enumerate(cues, 1):
            f.write(f"{i}\n{stamp(a, ',')} --> {stamp(b, ',')}\n" + "\n".join(lines) + "\n\n")
    with open(base + ".vtt", "w") as f:
        f.write("WEBVTT\n\n")
        for a, b, lines in cues:
            f.write(f"{stamp(a, '.')} --> {stamp(b, '.')}\n" + "\n".join(lines) + "\n\n")
    print(f"wrote {len(cues)} cues to {base}.srt and {base}.vtt")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "strip":
        strip(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 5 and sys.argv[1] == "write":
        write(*sys.argv[2:])
    else:
        sys.exit(__doc__)
