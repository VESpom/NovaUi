#!/usr/bin/env python3
"""Tests for tools/novaui_tool.py (needs ffmpeg). Run: python3 test/test_tool.py"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(os.path.dirname(HERE), "tools", "novaui_tool.py")
fails = 0


def check(cond, msg):
    global fails
    if not cond:
        fails += 1
        print("FAIL", msg)


def tool(*args):
    return subprocess.run([sys.executable, TOOL, *args], capture_output=True, text=True)


def ff(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


def near(hexs, rgb, tol=6):
    got = [int(hexs[i:i + 2], 16) for i in (0, 2, 4)]
    return all(abs(a - b) <= tol for a, b in zip(got, rgb))


with tempfile.TemporaryDirectory() as d:
    red = os.path.join(d, "red.png")
    ff("-f", "lavfi", "-i", "color=c=red:s=100x50", "-frames:v", "1", red)
    r = tool("pixels", red, "--size", "10")
    check(r.returncode == 0, "pixels runs: " + r.stderr)
    m = re.search(r"W = (\d+), H = (\d+),\s+Data = \"([0-9a-f]+)\"", r.stdout)
    check(m is not None, "pixels output shape")
    w, h, data = int(m.group(1)), int(m.group(2)), m.group(3)
    check((w, h) == (10, 5), "aspect kept: %sx%s" % (w, h))
    check(len(data) == w * h * 6, "data length")
    check(all(near(data[i:i + 6], (255, 0, 0)) for i in range(0, len(data), 6)), "all red")

    big = tool("pixels", red, "--size", "500")
    check(re.search(r"W = 64,", big.stdout) is not None, "capped at 64")

    # transparent areas are flattened onto --bg
    clear = os.path.join(d, "clear.png")
    ff("-f", "lavfi", "-i", "color=c=0x00000000:s=8x8,format=rgba", "-frames:v", "1", clear)
    t = tool("pixels", clear, "--size", "2", "--bg", "336699")
    check('"336699336699336699336699"' in t.stdout.replace("\n", "").replace(" ", "").replace("Data=", "") or "336699" in t.stdout, "transparent -> bg colour")

    vid = os.path.join(d, "two.mp4")
    ff("-f", "lavfi", "-i", "color=c=red:s=64x64:d=1", "-f", "lavfi", "-i", "color=c=blue:s=64x64:d=1",
       "-filter_complex", "[0][1]concat=n=2:v=1:a=0", "-r", "10", vid)
    c = tool("colormap", vid, "--cols", "2", "--rows", "2", "--fps", "1")
    check(c.returncode == 0, "colormap runs: " + c.stderr)
    frames = re.findall(r'"([0-9a-f]{24})"', c.stdout)
    check(len(frames) == 2, "two frames, got %d" % len(frames))
    check(frames and near(frames[0][:6], (255, 0, 0)) and near(frames[-1][:6], (0, 0, 255)), "red then blue")
    check("Interval = 1.0000" in c.stdout, "interval")

    lim = tool("colormap", vid, "--cols", "1", "--rows", "1", "--fps", "1", "--max-seconds", "1")
    check(len(re.findall(r'"[0-9a-f]{6}"', lim.stdout)) == 1, "max-seconds limits frames")

    still = tool("colormap", red, "--cols", "3", "--rows", "1")
    check(len(re.findall(r'"[0-9a-f]{18}"', still.stdout)) == 1, "still picture -> one frame")

    out = os.path.join(d, "o.lua")
    tool("pixels", red, "--size", "4", "--out", out)
    check(os.path.exists(out) and open(out).read().startswith("-- NovaUI pixels"), "--out writes a file")

    # errors are readable, not tracebacks
    for args in (["pixels", os.path.join(d, "missing.png")], ["pixels", red, "--bg", "zzz"], ["colormap", vid, "--fps", "0"]):
        e = tool(*args)
        check(e.returncode != 0 and "Traceback" not in e.stderr, "clean error for %s" % args[1:])
        check(e.stderr.strip() != "", "error message for %s" % args[1:])

def probe(path, entries):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", entries, "-of", "json", path],
                         capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def read_sidecar(path):
    """An independent, strict reader of the NVMAP1 format (what NovaUI's Lua parser also accepts)."""
    lines = open(path, encoding="utf-8", newline="").read().split("\n")
    head = re.fullmatch(r"NVMAP1 cols=(\d+) rows=(\d+) interval=(\d+\.\d{4})", lines[0])
    if not head:
        return None
    cols, rows, interval = int(head.group(1)), int(head.group(2)), float(head.group(3))
    frames = [ln for ln in lines[1:] if ln != ""]
    if any(len(f) != cols * rows * 6 or not re.fullmatch(r"[0-9a-f]+", f) for f in frames):
        return None
    return cols, rows, interval, frames


with tempfile.TemporaryDirectory() as d:
    # --- colormap --sidecar ----------------------------------------------------------------------
    vid = os.path.join(d, "two.mp4")
    ff("-f", "lavfi", "-i", "color=c=red:s=64x64:d=1", "-f", "lavfi", "-i", "color=c=blue:s=64x64:d=1",
       "-filter_complex", "[0][1]concat=n=2:v=1:a=0", "-r", "10", vid)
    r = tool("colormap", vid, "--cols", "2", "--rows", "1", "--fps", "1", "--sidecar")
    side = os.path.join(d, "two.map.txt")
    check(r.returncode == 0 and os.path.exists(side), "sidecar written next to the video: " + r.stderr)
    check(r.stdout == "", "nothing printed to stdout in sidecar mode")
    got = read_sidecar(side)
    check(got is not None, "sidecar has the NVMAP1 shape")
    if got:
        cols, rows, interval, frames = got
        check((cols, rows, interval, len(frames)) == (2, 1, 1.0, 2), "sidecar numbers: %s" % ((cols, rows, interval, len(frames)),))
        check(near(frames[0][:6], (255, 0, 0)) and near(frames[1][6:], (0, 0, 255)), "sidecar colours: red then blue")
    # the same frames as the Lua format
    lua = tool("colormap", vid, "--cols", "2", "--rows", "1", "--fps", "1")
    check(got is not None and re.findall(r'"([0-9a-f]{12})"', lua.stdout) == got[3], "text and Lua formats carry the same frames")
    check(b"\r" not in open(side, "rb").read(), "plain \\n line endings")

    both = tool("colormap", vid, "--sidecar", "--out", os.path.join(d, "x.txt"))
    check(both.returncode != 0 and "Traceback" not in both.stderr and "either --sidecar or --out" in both.stderr, "sidecar and out together are refused")

    short = tool("colormap", vid, "--cols", "1", "--rows", "1", "--fps", "1", "--max-seconds", "1", "--sidecar")
    check("covers only the first 1.0 s" in short.stderr or "covers only the first 1 s" in short.stderr, "short coverage is warned: " + short.stderr)

    many = tool("colormap", vid, "--cols", "1", "--rows", "1", "--fps", "5000", "--max-seconds", "1", "--sidecar")
    check("at most 4000" in many.stderr, "more than 4000 frames is warned: " + many.stderr[-200:])
    got = read_sidecar(side)
    check(got is not None and len(got[3]) == 4000, "and cut at 4000")

    huge = tool("colormap", vid, "--cols", "64", "--rows", "64", "--fps", "200", "--max-seconds", "0", "--sidecar")
    check(huge.returncode != 0 and "2000 KB" in huge.stderr and "Traceback" not in huge.stderr, "a map over 2 MB is refused: " + huge.stderr[-200:])

    # a picture gets a one-frame map next to it
    pic = os.path.join(d, "wall.png")
    ff("-f", "lavfi", "-i", "color=c=red:s=64x64", "-frames:v", "1", pic)
    tool("colormap", pic, "--cols", "2", "--rows", "2", "--sidecar")
    pgot = read_sidecar(os.path.join(d, "wall.map.txt"))
    check(pgot is not None and len(pgot[3]) == 1, "picture -> one frame")

    # odd names are warned about (NovaUI would not list them)
    odd = os.path.join(d, "my;clip.mp4")
    shutil.copy(vid, odd)
    w = tool("colormap", odd, "--cols", "1", "--rows", "1", "--fps", "1", "--sidecar")
    check("only accepts file names" in w.stderr and os.path.exists(os.path.join(d, "my;clip.map.txt")), "odd name warned: " + w.stderr)

with tempfile.TemporaryDirectory() as d:
    # --- convert ----------------------------------------------------------------------------------
    src = os.path.join(d, "my clip.mp4")
    ff("-f", "lavfi", "-i", "testsrc2=s=1280x720:d=2:r=30", "-f", "lavfi", "-i", "sine=f=440:d=2",
       "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", src)
    r = tool("convert", src)
    out = os.path.join(d, "my clip.webm")
    check(r.returncode == 0 and os.path.exists(out), "convert writes <name>.webm next to the original: " + r.stderr)
    info = probe(out, "stream=codec_name,codec_type,width,height")["streams"]
    check([s["codec_type"] for s in info] == ["video"], "no audio stream is left: %s" % info)
    check(info[0]["codec_name"] == "vp8", "VP8, which Roblox plays: %s" % info[0]["codec_name"])
    check((info[0]["width"], info[0]["height"]) == (960, 540), "scaled to 960x540: %sx%s" % (info[0]["width"], info[0]["height"]))
    check(os.path.exists(src) and os.path.getsize(src) > 0, "the original is untouched")
    check("MB" in r.stderr and "VP8" in r.stderr, "summary printed")

    again = tool("convert", src)
    check(again.returncode != 0 and "already exists" in again.stderr and "Traceback" not in again.stderr, "no silent overwrite")
    before = os.path.getmtime(out)
    forced = tool("convert", src, "--force", "--height", "360")
    check(forced.returncode == 0 and probe(out, "stream=height")["streams"][0]["height"] == 360, "--force replaces it, --height respected")
    check(os.path.getmtime(out) >= before, "file was rewritten")

    # never upscaled, odd sizes still produce a playable file, the frame rate can be limited
    small = os.path.join(d, "tiny!.mp4")
    ff("-f", "lavfi", "-i", "color=c=green:s=101x75:d=2:r=10", "-c:v", "libx264", "-pix_fmt", "yuv420p", small)
    s = tool("convert", small, "--fps", "5")
    cleaned = os.path.join(d, "tiny_.webm")
    check(s.returncode == 0 and os.path.exists(cleaned), "unsafe characters in the name are cleaned: " + s.stderr)
    check("name was cleaned" in s.stderr, "and the user is told")
    sinfo = probe(cleaned, "stream=width,height,r_frame_rate")["streams"][0]
    check(sinfo["height"] <= 75 and sinfo["width"] <= 101, "never upscaled: %sx%s" % (sinfo["width"], sinfo["height"]))
    check(sinfo["r_frame_rate"] == "5/1", "--fps limits the frame rate: %s" % sinfo["r_frame_rate"])

    # a .webm input never overwrites itself
    n = tool("convert", cleaned)
    check(n.returncode == 0 and os.path.exists(os.path.join(d, "tiny__nova.webm")), "webm in -> _nova.webm out: " + n.stderr)
    same = tool("convert", cleaned, "--out", cleaned, "--force")
    check(same.returncode != 0 and "overwrite the original" in same.stderr, "--out equal to the input is refused")

    # --map writes the colour map file beside the result, covering the whole clip
    m = tool("convert", src, "--force", "--map")
    mp = os.path.join(d, "my clip.map.txt")
    check(m.returncode == 0 and os.path.exists(mp), "--map writes my clip.map.txt: " + m.stderr)
    got = read_sidecar(mp)
    check(got is not None and (got[0], got[1], got[2]) == (12, 8, 0.5), "map shape 12x8 every 0.5 s")
    check(got is not None and len(got[3]) == 4, "2 s clip -> 4 frames, whole clip covered: %s" % (got and len(got[3])))

    # explicit odd --out names only warn
    o = tool("convert", small, "--out", os.path.join(d, "bad;name.webm"))
    check(o.returncode == 0 and "only accepts file names" in o.stderr, "explicit odd name warned")

    # readable errors, never tracebacks
    for args, part in ((["convert", os.path.join(d, "nope.mp4")], "file not found"),
                       (["convert", src, "--bitrate", "lots", "--out", os.path.join(d, "e1.webm")], "--bitrate"),
                       (["convert", src, "--height", "9999", "--out", os.path.join(d, "e2.webm")], "--height"),
                       (["convert", src, "--height", "1", "--out", os.path.join(d, "e2.webm")], "--height"),
                       (["convert", src, "--fps", "0", "--out", os.path.join(d, "e3.webm")], "--fps"),
                       (["convert", src, "--fps", "120", "--out", os.path.join(d, "e3.webm")], "--fps")):
        e = tool(*args)
        check(e.returncode != 0 and "Traceback" not in e.stderr and part in e.stderr, "clean error for %s: %s" % (args[1:], e.stderr[-120:]))
    fake = os.path.join(d, "fake.mp4")
    open(fake, "w").write("not a video")
    f = tool("convert", fake)
    check(f.returncode != 0 and "Traceback" not in f.stderr and f.stderr.strip() != "", "a file that is not a video is a readable error")
    check(not os.path.exists(os.path.join(d, "fake.webm")), "and leaves no half file")

    # anim: sprite sheets + NVANIM1 manifest (red for 1 s, then blue for 1 s)
    ad = os.path.join(d, "anim")
    os.makedirs(ad)
    av = os.path.join(ad, "my clip.mp4")
    ff("-f", "lavfi", "-i", "color=c=red:s=64x48:d=1", "-f", "lavfi", "-i", "color=c=blue:s=64x48:d=1",
       "-filter_complex", "[0][1]concat=n=2:v=1:a=0", "-r", "10", av)
    a = tool("anim", av, "--fps", "4", "--width", "64", "--cols", "2", "--rows", "2", "--map")
    check(a.returncode == 0, "anim runs: " + a.stderr)
    man = os.path.join(ad, "my clip.anim.txt")
    check(os.path.isfile(man), "manifest written (a space in the name is allowed)")
    head = open(man).read() if os.path.isfile(man) else ""
    check(head == "NVANIM1 cols=2 rows=2 fw=64 fh=48 fps=4 frames=9\n", "manifest exact: %r" % head)
    s1, s2 = os.path.join(ad, "my clip.anim1.jpg"), os.path.join(ad, "my clip.anim2.jpg")
    s3 = os.path.join(ad, "my clip.anim3.jpg")  # the test video is 2.2 s long, so 9 frames at 4 fps: 4 + 4 + 1
    check(os.path.isfile(s1) and os.path.isfile(s2) and os.path.isfile(s3) and not os.path.exists(os.path.join(ad, "my clip.anim4.jpg")), "3 sheets for 9 frames of 4")
    if os.path.isfile(s1):
        wh = probe(s1, "stream=width,height")["streams"][0]
        check((wh["width"], wh["height"]) == (128, 96), "sheet is 2x2 cells: %s" % wh)

    def cell_colour(path, col, row):
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", "crop=8:8:%d:%d,scale=1:1" % (col * 64 + 28, row * 48 + 20),
                              "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
        return tuple(raw[:3])
    if os.path.isfile(s1) and os.path.isfile(s2):
        r1 = cell_colour(s1, 0, 0)
        check(r1[0] > 200 and r1[2] < 60, "first frame is red: %s" % (r1,))
        b2 = cell_colour(s2, 0, 1)
        check(b2[2] > 200 and b2[0] < 60, "frame 7 (sheet 2, row 2) is blue: %s" % (b2,))
    mp = os.path.join(ad, "my clip.map.txt")
    check(os.path.isfile(mp) and read_sidecar(mp) is not None, "--map writes the colour map next to it")
    again = tool("anim", av, "--fps", "4", "--width", "64", "--cols", "2", "--rows", "2")
    check(again.returncode != 0 and "--force" in again.stderr, "no silent overwrite")
    # a shorter run with --force removes the old second sheet
    short = tool("anim", av, "--fps", "1", "--width", "64", "--cols", "2", "--rows", "2", "--force")
    check(short.returncode == 0 and re.search(r"frames=[23]\n", open(man).read()), "force replaces: " + short.stderr)
    check(not os.path.exists(s2) and not os.path.exists(s3), "stale sheets removed")
    for args, part in ((["anim", av, "--fps", "0"], "--fps"), (["anim", av, "--fps", "99"], "--fps"),
                       (["anim", av, "--width", "10"], "--width"), (["anim", av, "--width", "5000"], "--width"),
                       (["anim", av, "--quality", "99"], "--quality"),
                       (["anim", av, "--width", "600", "--cols", "2", "--force"], "over 1024"),
                       (["anim", os.path.join(ad, "nope.mp4")], "file not found")):
        e = tool(*args)
        check(e.returncode != 0 and "Traceback" not in e.stderr and part in e.stderr, "clean error for %s: %s" % (args[1:], e.stderr[-120:]))
    longv = os.path.join(ad, "long.mp4")
    ff("-f", "lavfi", "-i", "color=c=green:s=64x48:d=40", "-r", "10", longv)
    lg = tool("anim", longv, "--fps", "10", "--width", "64", "--max-seconds", "0")
    check(lg.returncode == 0 and "at most 240" in lg.stderr and "frames=240" in open(os.path.join(ad, "long.anim.txt")).read(),
          "frame cap warned and applied: " + lg.stderr[-200:])

print("tool tests: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
