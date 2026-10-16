"""Cut one pose out of a 3-pose sheet: key out the near-black background
(flood fill from the edges), split poses by empty column gaps, drop tiny
specks, trim, and pad to a square-ish canvas."""
import sys
from collections import deque
from PIL import Image

BG = (15, 15, 20)
TOL = 30

def key_out(im):
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    seen = bytearray(w * h)
    q = deque()
    for x in range(w):
        q.append((x, 0)); q.append((x, h - 1))
    for y in range(h):
        q.append((0, y)); q.append((w - 1, y))
    tol2 = TOL * TOL
    while q:
        x, y = q.popleft()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        c = px[x, y]
        if (c[0] - BG[0]) ** 2 + (c[1] - BG[1]) ** 2 + (c[2] - BG[2]) ** 2 > tol2:
            continue
        px[x, y] = (0, 0, 0, 0)
        if x + 1 < w: q.append((x + 1, y))
        if x > 0: q.append((x - 1, y))
        if y + 1 < h: q.append((x, y + 1))
        if y > 0: q.append((x, y - 1))
    return im

def pose_groups(im, want=3, min_gap=24):
    w, h = im.size
    a = im.split()[3].load()
    occ = [any(a[x, y] > 0 for y in range(0, h, 2)) for x in range(w)]
    runs, start = [], None
    for x, o in enumerate(occ + [False]):
        if o and start is None:
            start = x
        elif not o and start is not None:
            runs.append([start, x]); start = None
    merged = []
    for r in runs:
        if merged and r[0] - merged[-1][1] < min_gap:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    while len(merged) > want:
        i = min(range(len(merged)), key=lambda k: merged[k][1] - merged[k][0])
        j = i - 1 if i == len(merged) - 1 or (i > 0 and merged[i][0] - merged[i-1][1] < merged[i+1][0] - merged[i][1]) else i + 1
        lo, hi = sorted((i, j))
        merged[lo] = [merged[lo][0], merged[hi][1]]
        del merged[hi]
    return merged

def drop_specks(im, frac=0.0008):
    w, h = im.size
    a = im.split()[3].load()
    px = im.load()
    label = [0] * (w * h)
    comps = []
    for y in range(h):
        for x in range(w):
            if a[x, y] and not label[y * w + x]:
                idx = len(comps) + 1
                pts = []
                q = deque([(x, y)]); label[y * w + x] = idx
                while q:
                    cx, cy = q.popleft(); pts.append((cx, cy))
                    for nx, ny in ((cx+1,cy),(cx-1,cy),(cx,cy+1),(cx,cy-1)):
                        if 0 <= nx < w and 0 <= ny < h and a[nx, ny] and not label[ny * w + nx]:
                            label[ny * w + nx] = idx; q.append((nx, ny))
                comps.append(pts)
    biggest = max(len(c) for c in comps)
    for c in comps:
        if len(c) < biggest * frac:
            for (x, y) in c:
                px[x, y] = (0, 0, 0, 0)
    return im

if __name__ == "__main__":
    src, index, dst = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    keyed = key_out(Image.open(src))
    groups = pose_groups(keyed)
    x0, x1 = groups[index]
    pose = keyed.crop((max(0, x0 - 2), 0, min(keyed.width, x1 + 2), keyed.height))
    pose = drop_specks(pose)
    pose = pose.crop(pose.getbbox())
    pad = int(max(pose.size) * 0.04)
    canvas = Image.new("RGBA", (pose.width + 2 * pad, pose.height + 2 * pad), (0, 0, 0, 0))
    canvas.paste(pose, (pad, pad))
    canvas.save(dst)
    print(dst, canvas.size, "groups:", groups)
