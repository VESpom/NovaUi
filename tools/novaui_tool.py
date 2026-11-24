#!/usr/bin/env python3
"""NovaUI helper: turns pictures and videos into things the library can use without any download.

  pixels   PICTURE  [--size 32] [--bg 1a1a24] [--out file.lua]
      A small embedded picture. Use it as  Image = <table>  for the login logo, or
      Background = { Pixels = <table> }  (colour matching then works with no extra files).

  colormap VIDEO_OR_PICTURE [--cols 12 --rows 8 --fps 2 --max-seconds 60] [--out file.lua]
      Samples the colours of every part of the picture over time. Pass it as ColorMap = <table> next to
      Video = ... / Image = ... and turn on "Match colours [beta]". Roblox cannot read pixels from a
      video itself, so this one-time conversion is what makes colour matching possible.

Needs only ffmpeg and ffprobe on your PATH (https://ffmpeg.org). Output is plain Lua text.
"""
import argparse
import subprocess
import sys

MAX_SIDE = 64


def run(cmd):
    try:
        return subprocess.run(cmd, check=True, capture_output=True).stdout
    except FileNotFoundError:
        sys.exit("ffmpeg/ffprobe not found. Install ffmpeg and make sure it is on your PATH.")
    except subprocess.CalledProcessError as e:
        sys.exit("ffmpeg could not read that file:\n" + e.stderr.decode("utf-8", "replace")[-400:])


def probe_size(path):
    out = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
               "-of", "csv=p=0:s=x", path]).decode().strip()
    try:
        w, h = out.split("x")[:2]
        return int(w), int(h)
    except ValueError:
        sys.exit("could not read the size of " + path)


def parse_bg(text):
    text = text.lstrip("#")
    if len(text) != 6:
        sys.exit("--bg must be 6 hex digits, like 1a1a24")
    try:
        return tuple(int(text[i:i + 2], 16) for i in (0, 2, 4))
    except ValueError:
        sys.exit("--bg must be 6 hex digits, like 1a1a24")


def hexpx(r, g, b):
    return "%02x%02x%02x" % (r, g, b)


def pixels(path, size, bg):
    size = max(1, min(size, MAX_SIDE))
    w, h = probe_size(path)
    scale = size / max(w, h)
    tw, th = max(1, round(w * scale)), max(1, round(h * scale))
    raw = run(["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1", "-vf",
               "scale=%d:%d:flags=lanczos,format=rgba" % (tw, th), "-f", "rawvideo", "-pix_fmt", "rgba", "-"])
    if len(raw) < tw * th * 4:
        sys.exit("no picture data came out of ffmpeg")
    out = []
    for i in range(tw * th):
        r, g, b, a = raw[i * 4:i * 4 + 4]
        k = a / 255.0  # transparent parts are flattened onto --bg
        out.append(hexpx(round(r * k + bg[0] * (1 - k)), round(g * k + bg[1] * (1 - k)), round(b * k + bg[2] * (1 - k))))
    data = "".join(out)
    return "{ W = %d, H = %d,\n  Data = \"%s\" }" % (tw, th, data), tw, th


def colormap(path, cols, rows, fps, max_seconds):
    cols, rows = max(1, min(cols, MAX_SIDE)), max(1, min(rows, MAX_SIDE))
    cmd = ["ffmpeg", "-v", "error", "-i", path]
    if max_seconds:
        cmd += ["-t", str(max_seconds)]
    cmd += ["-vf", "fps=%s,scale=%d:%d:flags=area,format=rgb24" % (fps, cols, rows), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
    raw = run(cmd)
    frame_bytes = cols * rows * 3
    n = len(raw) // frame_bytes
    if n < 1:
        # still pictures can come out with zero frames at fps filters; take one frame instead
        raw = run(["ffmpeg", "-v", "error", "-i", path, "-frames:v", "1", "-vf",
                   "scale=%d:%d:flags=area,format=rgb24" % (cols, rows), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"])
        n = len(raw) // frame_bytes
        if n < 1:
            sys.exit("no frames could be read")
    frames = []
    for f in range(min(n, 4000)):
        chunk = raw[f * frame_bytes:(f + 1) * frame_bytes]
        frames.append("".join(hexpx(chunk[i], chunk[i + 1], chunk[i + 2]) for i in range(0, frame_bytes, 3)))
    lines = ",\n".join('    "%s"' % fr for fr in frames)
    interval = 1.0 / float(fps)
    text = "{ Cols = %d, Rows = %d, Interval = %.4f,\n  Frames = {\n%s,\n  } }" % (cols, rows, interval, lines)
    return text, len(frames)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("pixels")
    p.add_argument("file")
    p.add_argument("--size", type=int, default=32, help="longest side in pixels (max 64)")
    p.add_argument("--bg", default="1a1a24", help="colour behind transparent areas")
    p.add_argument("--out")
    c = sub.add_parser("colormap")
    c.add_argument("file")
    c.add_argument("--cols", type=int, default=12)
    c.add_argument("--rows", type=int, default=8)
    c.add_argument("--fps", type=float, default=2.0, help="samples per second of video")
    c.add_argument("--max-seconds", type=float, default=60.0)
    c.add_argument("--out")
    args = ap.parse_args()

    if args.cmd == "pixels":
        text, w, h = pixels(args.file, args.size, parse_bg(args.bg))
        note = "-- NovaUI pixels picture %dx%d\n" % (w, h)
    else:
        if args.fps <= 0:
            sys.exit("--fps must be above 0")
        text, n = colormap(args.file, args.cols, args.rows, args.fps, args.max_seconds)
        note = "-- NovaUI colour map: %d frame(s) of %dx%d, one every %.2fs\n" % (n, args.cols, args.rows, 1.0 / args.fps)
        if n * args.cols * args.rows * 6 > 400000:
            sys.stderr.write("warning: large map (%d KB). Lower --fps, --cols/--rows or --max-seconds.\n" % (n * args.cols * args.rows * 6 // 1000))
    body = note + "return " + text + "\n"
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(body)
        sys.stderr.write("wrote %s (%d bytes)\n" % (args.out, len(body)))
    else:
        sys.stdout.write(body)


if __name__ == "__main__":
    main()
