#!/usr/bin/env python3
"""Tests for tools/novaui_tool.py (needs ffmpeg). Run: python3 test/test_tool.py"""
import os
import re
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

print("tool tests: %s" % ("OK" if fails == 0 else "%d FAILED" % fails))
sys.exit(1 if fails else 0)
