#!/usr/bin/env python3
"""NovaUI helper: turns pictures and videos into things the library can use without any download.

  convert  VIDEO [--out intro.webm] [--height 540] [--bitrate 1M] [--fps N] [--map] [--force]
      Makes a video Roblox can play: WebM (VP8), no sound, at most 540 px tall. Put the result in
      workspace/NovaUI/backgrounds. Add --map to also write the colour map file next to it.

  anim     VIDEO [--fps 8] [--width 256] [--max-seconds 12] [--map] [--force]
      Roblox often refuses video files that come from the executor's folder. This turns the video into
      pictures (sprite sheets) that NovaUI flips through like a video. It writes  <name>.anim.txt  and
      <name>.anim1.jpg, <name>.anim2.jpg ...  Put them all in workspace/NovaUI/backgrounds and pick
      <name>.anim.txt. Add --map for Match colours.

  colormap VIDEO_OR_PICTURE [--cols 12 --rows 8 --fps 2 --max-seconds 60] [--out file.lua] [--sidecar]
      Samples the colours of every part of the picture over time, for "Match colours [beta]".
      --sidecar writes  <name>.map.txt  next to the file: put both in workspace/NovaUI/backgrounds and
      NovaUI picks the map up by itself. Without --sidecar the output is a Lua table (ColorMap = ...).
      Roblox cannot read pixels from a video itself, so this one-time conversion is what makes it possible.

  pixels   PICTURE  [--size 32] [--bg 1a1a24] [--out file.lua]
      A small embedded picture. Use it as  Image = <table>  for the login logo, or
      Background = { Pixels = <table> }  (colour matching then works with no extra files).

Needs only ffmpeg and ffprobe on your PATH (https://ffmpeg.org). Output is plain text.
"""
import argparse
import os
import re
import subprocess
import sys

MAX_SIDE = 64
MAX_FRAMES = 4000  # the library refuses maps with more frames
MAX_MAP_TEXT = 2000000  # ... and text map files over 2 MB
SIDECAR_SUFFIX = ".map.txt"
NAME_OK = re.compile(r"^[A-Za-z0-9\-._ ()]+$")  # the characters NovaUI accepts in a folder file name
NAME_BAD = re.compile(r"[^A-Za-z0-9\-._ ()]")


def run(cmd):
    try:
        return subprocess.run(cmd, check=True, capture_output=True).stdout
    except FileNotFoundError:
        sys.exit("ffmpeg/ffprobe not found. Install ffmpeg and make sure it is on your PATH.")
    except subprocess.CalledProcessError as e:
        sys.exit("ffmpeg could not read that file:\n" + e.stderr.decode("utf-8", "replace")[-400:])


def warn(text):
    sys.stderr.write("warning: " + text + "\n")


def probe_size(path):
    out = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
               "-of", "csv=p=0:s=x", path]).decode().strip()
    try:
        w, h = out.split("x")[:2]
        return int(w), int(h)
    except ValueError:
        sys.exit("could not read the size of " + path)


def probe_duration(path):
    """Seconds, or None when the file does not say (pictures, odd containers)."""
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                             check=True, capture_output=True).stdout.decode().strip()
        value = float(out)
        return value if value > 0 else None
    except (FileNotFoundError, subprocess.CalledProcessError, ValueError):
        return None


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


def sidecar_path(media_path):
    """intro.webm -> intro.map.txt (same folder)."""
    return os.path.splitext(media_path)[0] + SIDECAR_SUFFIX


def check_name(path):
    """NovaUI lists and loads only file names with letters, digits, space and - . _ ( )"""
    name = os.path.basename(path)
    if not NAME_OK.match(name):
        warn("NovaUI only accepts file names with letters, digits, space and - . _ ( ). "
             "Rename '%s' (for example '%s') or it will not show up in the file picker." % (name, NAME_BAD.sub("_", name)))


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


def sample_frames(path, cols, rows, fps, max_seconds):
    """One 'rrggbb' string per cell (row by row) for every sampled moment. Returns (frames, total_frames_seen)."""
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
    for f in range(min(n, MAX_FRAMES)):
        chunk = raw[f * frame_bytes:(f + 1) * frame_bytes]
        frames.append("".join(hexpx(chunk[i], chunk[i + 1], chunk[i + 2]) for i in range(0, frame_bytes, 3)))
    return frames, n


def lua_map(frames, cols, rows, fps):
    lines = ",\n".join('    "%s"' % fr for fr in frames)
    return "{ Cols = %d, Rows = %d, Interval = %.4f,\n  Frames = {\n%s,\n  } }" % (cols, rows, 1.0 / float(fps), lines)


def text_map(frames, cols, rows, fps):
    """The sidecar format: a header line, then one line of hex per frame. Read by NovaUI without loadstring."""
    return "NVMAP1 cols=%d rows=%d interval=%.4f\n%s\n" % (cols, rows, 1.0 / float(fps), "\n".join(frames))


def make_map(path, cols, rows, fps, max_seconds):
    """Samples the file and warns when the map does not cover the whole video. Returns (frames, cols, rows)."""
    cols, rows = max(1, min(cols, MAX_SIDE)), max(1, min(rows, MAX_SIDE))
    frames, seen = sample_frames(path, cols, rows, fps, max_seconds)
    if seen > MAX_FRAMES:
        warn("the video needs %d frames but NovaUI reads at most %d, so the map stops after %.0f s. "
             "Use a lower --fps." % (seen, MAX_FRAMES, MAX_FRAMES / float(fps)))
    duration = probe_duration(path)
    if duration and max_seconds and duration > max_seconds + 0.5:
        warn("the video is %.0f s long but the map covers only the first %s s, so the colours after that will not "
             "follow the video. Use --max-seconds %d (or 0 for no limit)." % (duration, max_seconds, int(duration) + 1))
    return frames, cols, rows


def write_text(path, body):
    # newline="\n": the same bytes on every system (NovaUI also copes with Windows line endings)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(body)


def sidecar_for(path, cols, rows, fps, max_seconds, check=True):
    """Writes <path minus extension>.map.txt. Returns (map file, frame count)."""
    frames, cols, rows = make_map(path, cols, rows, fps, max_seconds)
    body = text_map(frames, cols, rows, fps)
    if len(body) > MAX_MAP_TEXT:
        sys.exit("the colour map would be %d KB; NovaUI reads at most 2000 KB. Use a lower --fps, fewer "
                 "--cols/--rows or a shorter --max-seconds." % (len(body) // 1000))
    if check:
        check_name(path)
    out = sidecar_path(path)
    write_text(out, body)
    return out, len(frames)


def safe_stem(path):
    stem = os.path.splitext(os.path.basename(path))[0]
    cleaned = NAME_BAD.sub("_", stem).strip(" .") or "background"
    return cleaned, cleaned != stem


def convert(path, out, height, bitrate, fps, force):
    if not os.path.isfile(path):
        sys.exit("file not found: " + path)
    if not re.match(r"^\d+(\.\d+)?[kKmM]?$", bitrate):
        sys.exit("--bitrate must look like 800k or 1M")
    if height < 2 or height > 2160:
        sys.exit("--height must be between 2 and 2160 (Roblox plays up to 720)")
    if height > 720:
        warn("Roblox plays videos up to 720p. A taller video may stay blank.")
    if fps is not None and not 0 < fps <= 60:
        sys.exit("--fps must be above 0 and at most 60")
    if out is None:
        stem, changed = safe_stem(path)
        out = os.path.join(os.path.dirname(os.path.abspath(path)), stem + ".webm")
        if os.path.abspath(out) == os.path.abspath(path):
            out = os.path.join(os.path.dirname(out), stem + "_nova.webm")
        if changed:
            sys.stderr.write("note: the name was cleaned to '%s' (NovaUI accepts only letters, digits, space and - . _ ( )).\n"
                             % os.path.basename(out))
    else:
        check_name(out)
    if os.path.abspath(out) == os.path.abspath(path):
        sys.exit("the output would overwrite the original. Pick another --out.")
    if os.path.exists(out) and not force:
        sys.exit("%s already exists. Use --force to replace it, or pick another --out." % out)
    # never upscale: min(wanted height, real height); -2 keeps the width even and the shape right
    vf = "scale=-2:'min(%d,ih)'" % height
    if fps is not None:
        vf = "fps=%s,%s" % (fps, vf)
    run(["ffmpeg", "-v", "error", "-y" if force else "-n", "-i", path, "-map", "0:v:0", "-c:v", "libvpx",
         "-b:v", bitrate, "-vf", vf, "-pix_fmt", "yuv420p", "-an", out])
    size = os.path.getsize(out)
    w, h = probe_size(out)
    duration = probe_duration(out)
    sys.stderr.write("wrote %s  (%dx%d, %s, %.1f MB, WebM VP8, no sound)\n"
                     % (out, w, h, "%.0f s" % duration if duration else "length unknown", size / 1e6))
    if size > 40e6:
        warn("over 40 MB. Roblox and the executor may refuse it. Use a lower --bitrate, --height or --fps.")
    elif size > 10e6:
        warn("over 10 MB: loading will be slow. A lower --bitrate (like 600k) or --height 360 makes it smaller.")
    return out


MAX_ANIM_FRAMES = 240  # the library refuses longer animations
ANIM_SHEET_PX = 1024  # Roblox shrinks bigger pictures, so a sheet never goes past this


def anim_frame_count(path, fps, max_seconds):
    """How many frames the fps filter really produces (counted, not guessed)."""
    cmd = ["ffmpeg", "-v", "error", "-i", path]
    if max_seconds:
        cmd += ["-t", str(max_seconds)]
    cmd += ["-vf", "fps=%s,scale=2:2,format=gray" % fps, "-f", "rawvideo", "-pix_fmt", "gray", "-"]
    return len(run(cmd)) // 4


def anim(path, fps, width, cols, rows, max_seconds, quality, make_map_file, force):
    if not os.path.isfile(path):
        sys.exit("file not found: " + path)
    if not 0 < fps <= 30:
        sys.exit("--fps must be above 0 and at most 30")
    if not 32 <= width <= ANIM_SHEET_PX:
        sys.exit("--width must be between 32 and %d" % ANIM_SHEET_PX)
    if not 2 <= quality <= 31:
        sys.exit("--quality must be between 2 (best) and 31 (smallest)")
    w, h = probe_size(path)
    fw = width
    fh = max(2, int(round(width * h / float(w) / 2.0)) * 2)
    if fh > ANIM_SHEET_PX:
        sys.exit("that picture is too tall for a frame; use a smaller --width")
    cols = cols or max(1, ANIM_SHEET_PX // fw)
    rows = rows or max(1, ANIM_SHEET_PX // fh)
    if cols * fw > ANIM_SHEET_PX or rows * fh > ANIM_SHEET_PX:
        sys.exit("%d x %d frames of %dx%d is over %d px. Use fewer --cols/--rows or a smaller --width."
                 % (cols, rows, fw, fh, ANIM_SHEET_PX))
    stem, changed = safe_stem(path)
    if changed:
        sys.stderr.write("note: the name was cleaned to '%s'.\n" % stem)
    folder = os.path.dirname(os.path.abspath(path))
    manifest = os.path.join(folder, stem + ".anim.txt")
    if os.path.exists(manifest) and not force:
        sys.exit("%s already exists. Use --force to replace it." % manifest)
    frames = anim_frame_count(path, fps, max_seconds)
    if frames < 1:
        sys.exit("no frames could be read")
    if frames > MAX_ANIM_FRAMES:
        warn("the video gives %d frames; NovaUI plays at most %d, so only the first %.0f s are used. "
             "Use a lower --fps or --max-seconds." % (frames, MAX_ANIM_FRAMES, MAX_ANIM_FRAMES / float(fps)))
        frames = MAX_ANIM_FRAMES
        max_seconds = MAX_ANIM_FRAMES / float(fps)
    per = cols * rows
    sheets = -(-frames // per)
    for old in os.listdir(folder):  # sheets of an older, longer run must not linger
        if re.match(r"^%s\.anim\d+\.jpg$" % re.escape(stem), old):
            os.remove(os.path.join(folder, old))
    pattern = os.path.join(folder, stem + ".anim%d.jpg")
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", path]
    if max_seconds:
        cmd += ["-t", str(max_seconds)]
    cmd += ["-vf", "fps=%s,scale=%d:%d:flags=lanczos,tile=%dx%d" % (fps, fw, fh, cols, rows),
            "-frames:v", str(sheets), "-q:v", str(quality), "-start_number", "1", pattern]
    run(cmd)
    made = [f for f in (pattern % (i + 1) for i in range(sheets)) if os.path.isfile(f)]
    if len(made) != sheets:
        sys.exit("expected %d sheet(s) but ffmpeg wrote %d" % (sheets, len(made)))
    write_text(manifest, "NVANIM1 cols=%d rows=%d fw=%d fh=%d fps=%s frames=%d\n" % (cols, rows, fw, fh, ("%g" % fps), frames))
    total = sum(os.path.getsize(f) for f in made)
    sys.stderr.write("wrote %s + %d sheet(s) (%d frames of %dx%d, %.1f s, %.2f MB)\n"
                     % (manifest, sheets, frames, fw, fh, frames / float(fps), total / 1e6))
    if total > 8e6:
        warn("over 8 MB of pictures: loading will be slow. Use a lower --fps, --width or a higher --quality number.")
    if make_map_file:
        mf = os.path.join(folder, stem + ".map.txt")
        body_frames, mc, mr = make_map(path, 12, 8, 2.0, max_seconds or 0)
        write_text(mf, text_map(body_frames, mc, mr, 2.0))
        sys.stderr.write("wrote %s  (%d colour frame(s))\n" % (mf, len(body_frames)))
    sys.stderr.write("Put all of these in workspace/NovaUI/backgrounds, then pick %s.\n" % os.path.basename(manifest))
    return manifest


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
    c.add_argument("--max-seconds", type=float, default=60.0, help="how much of the video to sample (0 = all of it)")
    c.add_argument("--out")
    c.add_argument("--sidecar", action="store_true",
                   help="write <file name>.map.txt next to the file (NovaUI finds it by itself)")
    a = sub.add_parser("anim")
    a.add_argument("file")
    a.add_argument("--fps", type=float, default=8.0, help="frames per second (default 8; more = smoother but bigger)")
    a.add_argument("--width", type=int, default=256, help="width of one frame in pixels (default 256)")
    a.add_argument("--cols", type=int, help="frames per row on a sheet (default: fill 1024 px)")
    a.add_argument("--rows", type=int, help="rows per sheet (default: fill 1024 px)")
    a.add_argument("--max-seconds", type=float, default=12.0, help="how much of the video to use (0 = all, default 12)")
    a.add_argument("--quality", type=int, default=5, help="JPEG quality number, 2 best .. 31 smallest (default 5)")
    a.add_argument("--map", action="store_true", help="also write the colour map file (Match colours)")
    a.add_argument("--force", action="store_true", help="replace an earlier result")
    v = sub.add_parser("convert")
    v.add_argument("file")
    v.add_argument("--out", help="default: <name>.webm next to the original")
    v.add_argument("--height", type=int, default=540, help="largest height in pixels, never upscaled (default 540)")
    v.add_argument("--bitrate", default="1M", help="video bitrate, like 800k or 1M (default 1M)")
    v.add_argument("--fps", type=float, help="limit the frame rate (default: keep the original)")
    v.add_argument("--map", action="store_true", help="also write the colour map file next to the result")
    v.add_argument("--force", action="store_true", help="replace the output if it exists")
    args = ap.parse_args()

    if args.cmd == "pixels":
        text, w, h = pixels(args.file, args.size, parse_bg(args.bg))
        note = "-- NovaUI pixels picture %dx%d\n" % (w, h)
    elif args.cmd == "anim":
        anim(args.file, args.fps, args.width, args.cols, args.rows, args.max_seconds, args.quality, args.map, args.force)
        return
    elif args.cmd == "convert":
        out = convert(args.file, args.out, args.height, args.bitrate, args.fps, args.force)
        if args.map:
            map_file, n = sidecar_for(out, 12, 8, 2.0, 0, check=False)
            sys.stderr.write("wrote %s  (%d colour frame(s)). Put both files in workspace/NovaUI/backgrounds.\n" % (map_file, n))
        return
    else:
        if args.fps <= 0:
            sys.exit("--fps must be above 0")
        if args.max_seconds < 0:
            sys.exit("--max-seconds can not be negative")
        if args.sidecar:
            if args.out:
                sys.exit("use either --sidecar or --out, not both")
            map_file, n = sidecar_for(args.file, args.cols, args.rows, args.fps, args.max_seconds)
            sys.stderr.write("wrote %s  (%d frame(s), one every %.2f s). Keep it next to %s in workspace/NovaUI/backgrounds.\n"
                             % (map_file, n, 1.0 / args.fps, os.path.basename(args.file)))
            return
        frames, cols, rows = make_map(args.file, args.cols, args.rows, args.fps, args.max_seconds)
        text = lua_map(frames, cols, rows, args.fps)
        n = len(frames)
        note = "-- NovaUI colour map: %d frame(s) of %dx%d, one every %.2fs\n" % (n, cols, rows, 1.0 / args.fps)
        if n * cols * rows * 6 > 400000:
            sys.stderr.write("warning: large map (%d KB). Lower --fps, --cols/--rows or --max-seconds.\n" % (n * cols * rows * 6 // 1000))
    body = note + "return " + text + "\n"
    if args.out:
        write_text(args.out, body)
        sys.stderr.write("wrote %s (%d bytes)\n" % (args.out, len(body)))
    else:
        sys.stdout.write(body)


if __name__ == "__main__":
    main()
