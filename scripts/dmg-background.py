#!/usr/bin/env python3
"""Draws install/dmg/background.png and background@2x.png from install/dmg/layout.json.

Rendered with headless Chrome (CHROME overrides the path) in Geist from Google Fonts.
The outputs are committed; rerun after changing the layout or the copy.
Usage: python3 scripts/dmg-background.py
"""
import base64
import json
import math
import os
import struct
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DMG = os.path.join(ROOT, "install", "dmg")
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

HEADING = "Drag Mac Janitor into Applications."
FOOTER = "Once copied, open it from Applications."
INK = "#0a1d2b"
MUTED = "#587083"
ARROW = "#23577a"


def load_layout():
    with open(os.path.join(DMG, "layout.json")) as f:
        return json.load(f)


def fmt(n):
    return f"{n:.2f}"


def arrow_path(layout):
    app, apps, half = layout["app"], layout["applications"], layout["iconSize"] / 2
    gap_left, gap_right = app["x"] + half, apps["x"] - half
    margin = (gap_right - gap_left - 100) / 2
    start = (gap_left + margin, app["y"] - 6)
    end = (gap_right - margin, apps["y"] - 8)
    c1 = (start[0] + 30, start[1] - 17)
    c2 = (end[0] - 34, end[1] - 16)
    tangent = math.atan2(end[1] - c2[1], end[0] - c2[0])
    head, spread = 11, math.radians(32)

    def barb(angle):
        return (end[0] - head * math.cos(tangent + angle), end[1] - head * math.sin(tangent + angle))

    b1, b2 = barb(spread), barb(-spread)
    return (
        f"M{fmt(start[0])} {fmt(start[1])} "
        f"C{fmt(c1[0])} {fmt(c1[1])} {fmt(c2[0])} {fmt(c2[1])} {fmt(end[0])} {fmt(end[1])} "
        f"M{fmt(b1[0])} {fmt(b1[1])} L{fmt(end[0])} {fmt(end[1])} L{fmt(b2[0])} {fmt(b2[1])}"
    )


def logo_data_uri():
    with open(os.path.join(ROOT, "assets", "logo.svg"), "rb") as f:
        return "data:image/svg+xml;base64," + base64.b64encode(f.read()).decode()


def page_html(layout):
    w, h = layout["window"]["width"], layout["window"]["height"]
    return f"""<!doctype html><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400;600&display=block">
<style>
html, body {{ margin: 0; width: {w}px; height: {h}px; overflow: hidden; }}
svg {{ display: block; }}
text {{ font-family: Geist, system-ui, sans-serif; }}
</style>
<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#f6f9fb"/><stop offset="1" stop-color="#e3edf2"/>
    </linearGradient>
    <linearGradient id="ice" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#cfe0e9" stop-opacity="0.5"/><stop offset="1" stop-color="#cfe0e9" stop-opacity="0.15"/>
    </linearGradient>
  </defs>
  <rect width="{w}" height="{h}" fill="url(#sky)"/>
  <path d="M0 292 L120 266 L200 276 L320 238 L430 270 L520 254 L{w} 274 V{h} H0 Z" fill="url(#ice)"/>
  <path d="M0 318 L150 300 L260 310 L400 290 L540 308 L{w} 298 V{h} H0 Z" fill="#ffffff" opacity="0.55"/>
  <image href="{logo_data_uri()}" x="26" y="20" width="22" height="22"/>
  <text x="56" y="36" font-size="15" font-weight="600" letter-spacing="-0.2" fill="{INK}">Mac Janitor</text>
  <text x="{w / 2}" y="86" text-anchor="middle" font-size="22" font-weight="600" letter-spacing="-0.5" fill="{INK}">{HEADING}</text>
  <path d="{arrow_path(layout)}" fill="none" stroke="{ARROW}" stroke-opacity="0.85" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
  <text x="{w / 2}" y="350" text-anchor="middle" font-size="12" fill="{MUTED}">{FOOTER}</text>
</svg>
"""


def png_size(path):
    with open(path, "rb") as f:
        header = f.read(24)
    return struct.unpack(">II", header[16:24])


def render(html_path, out, scale, w, h):
    subprocess.run(
        [CHROME, "--headless=new", "--hide-scrollbars", f"--force-device-scale-factor={scale}",
         f"--window-size={w},{h}", "--virtual-time-budget=5000", f"--screenshot={out}", f"file://{html_path}"],
        check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    if png_size(out) != (w * scale, h * scale):
        raise SystemExit(f"{out} is {png_size(out)}, expected {(w * scale, h * scale)}")
    print(f"wrote {os.path.relpath(out, ROOT)}")


def main():
    layout = load_layout()
    w, h = layout["window"]["width"], layout["window"]["height"]
    with tempfile.TemporaryDirectory() as work:
        html_path = os.path.join(work, "background.html")
        with open(html_path, "w") as f:
            f.write(page_html(layout))
        render(html_path, os.path.join(DMG, "background.png"), 1, w, h)
        render(html_path, os.path.join(DMG, "background@2x.png"), 2, w, h)


if __name__ == "__main__":
    main()
