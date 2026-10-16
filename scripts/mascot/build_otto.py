"""Turn one cut-out Otto pose PNG into the two vector assets the app uses.

    python3 scripts/mascot/build_otto.py <pose> <pose.png>

Writes HoursTracker/Assets.xcassets/Mascot/otto-<pose>.imageset (the full owl)
and otto-<pose>-scarf.imageset (the scarf alone, in gray, so OwlView can
colorMultiply it with the prestige accent while keeping the knit stripes).

Needs Pillow and vtracer (`python3 -m pip install --user vtracer`).
Cut poses out of a generated sheet first with cut_sheet.py.
"""
import colorsys
import json
import os
import re
import sys

import vtracer
from PIL import Image, ImageFilter

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CATALOG = os.path.join(REPO, "HoursTracker", "Assets.xcassets", "Mascot")
TRACE = dict(colormode="color", hierarchical="stacked", mode="spline",
             filter_speckle=6, corner_threshold=60, length_threshold=4.0,
             max_iterations=10, splice_threshold=45, path_precision=2)


def is_scarf(r, g, b):
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    return 0.66 <= h <= 0.84 and s > 0.22 and v > 0.22


def scarf_layer(src_png, dst_png):
    """Gray scarf: luminance stretched into [0.72, 1.0], grown 2px so the
    tinted layer fully covers the violet scarf underneath."""
    im = Image.open(src_png).convert("RGBA")
    w, h = im.size
    px = im.load()
    mask = Image.new("L", (w, h), 0)
    mp = mask.load()
    lums = []
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a >= 128 and is_scarf(r, g, b):
                mp[x, y] = 255
                lums.append(0.299 * r + 0.587 * g + 0.114 * b)
    if not lums:
        return False
    lums.sort()
    lo, hi = lums[int(len(lums) * 0.05)], lums[int(len(lums) * 0.95)]
    span = max(hi - lo, 1)

    def gray(l):
        t = max(0.0, min(1.0, (l - lo) / span))
        return int(round(255 * (0.72 + 0.28 * t)))

    base = gray(lums[len(lums) // 2])
    grown = mask.filter(ImageFilter.MaxFilter(5)).load()
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    op = out.load()
    for y in range(h):
        for x in range(w):
            if grown[x, y]:
                if mp[x, y]:
                    r, g, b, _ = px[x, y]
                    v = gray(0.299 * r + 0.587 * g + 0.114 * b)
                else:
                    v = base
                op[x, y] = (v, v, v, 255)
    out.save(dst_png)
    return True


def finish_svg(path):
    """Add a viewBox so the vector scales, and drop the generator comment."""
    s = open(path).read()
    s = re.sub(r'width="(\d+)" height="(\d+)">',
               r'width="\1" height="\2" viewBox="0 0 \1 \2">', s, count=1)
    s = re.sub(r"<!-- Generator:[^>]*-->\n?", "", s)
    open(path, "w").write(s)


def install(name, svg_path):
    folder = os.path.join(CATALOG, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    os.replace(svg_path, os.path.join(folder, f"{name}.svg"))
    contents = {
        "images": [{"filename": f"{name}.svg", "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True},
    }
    with open(os.path.join(folder, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)


def main(pose, src_png):
    work = os.path.join(os.path.dirname(os.path.abspath(src_png)), f"_{pose}_build")
    os.makedirs(work, exist_ok=True)

    base_svg = os.path.join(work, f"otto-{pose}.svg")
    vtracer.convert_image_to_svg_py(src_png, base_svg, color_precision=6, layer_difference=24, **TRACE)
    finish_svg(base_svg)
    install(f"otto-{pose}", base_svg)

    scarf_png = os.path.join(work, "scarf.png")
    if scarf_layer(src_png, scarf_png):
        scarf_svg = os.path.join(work, f"otto-{pose}-scarf.svg")
        vtracer.convert_image_to_svg_py(scarf_png, scarf_svg, color_precision=8, layer_difference=6, **TRACE)
        finish_svg(scarf_svg)
        install(f"otto-{pose}-scarf", scarf_svg)
    print(f"otto-{pose}: installed")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
