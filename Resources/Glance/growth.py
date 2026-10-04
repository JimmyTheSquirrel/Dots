#!/usr/bin/env python3
"""growth.py — the Asgard dashboard's overgrowth, generated.

    growth.py OUTDIR [VERSION]

Writes every piece of forest the main Glance dashboard draws (asgard.css):

    <rune>-top.svg   what has grown down over each card's top edge — a
                     different piece on every card: ivy, a mossy bough hung
                     with old-man's-beard, rowan, bramble, ferns, oak, each
                     with its own tufts of hanging moss
    <rune>-rule.svg  the tendril under its title
    nav-<page>.svg   the growth along the navigation, one per page
    treeline-<page>.svg  the forest along the foot of the page, one per page
    glyph-<page>.svg the section-heading mark, one per page
    growth.css       which card and page wears which — the only place the
                     pieces are named, so this file and the CSS never drift

Everything grows from the TOP — over the navigation and down over the
cards' top edges — nothing sits at their feet. Each page has its own wood
(its navigation growth, its treeline and its section glyph):
    asgard    ivy and rowan — the hall gone back to the forest
    eclipse   night: a mossy bough, glowing toadstools, the eclipse itself
              low behind the trees
    power     bramble and oak
    terminal  roots

Nix runs it at build time (Modules/Server/glance.nix), so nothing generated is
committed. Every piece is seeded, so the forest is the same on every build;
change a seed (CARDS, PAGES below) and that one card grows differently.
Colours: forest greens (ivy, fern, moss, pine), rowan-berry red (a true
deep red, never pink), bark brown, the pale sage of lichen.
"""
import math
import os
import random
import sys

TAU = 2 * math.pi

# ── palette ──────────────────────────────────────────────────────────────────
IVY = ["#1f5a2c", "#24642f", "#2a6b33", "#2f7d3a", "#367f38", "#3d8c3f", "#4a9a44"]
IVY_YOUNG = ["#5fae4e", "#6dba55", "#7cc05c"]
FERN = ["#3f8f3c", "#4c9d42", "#5aa948", "#6ab452"]
MOSS = ["#4d6b2a", "#5d7a34", "#6f8f3a", "#7f9c42", "#8aa84a", "#9db45a"]
LICHEN = ["#8fa47a", "#9fb28a", "#aebd97", "#b9c6a0", "#7f9470"]
AUTUMN = ["#b8342c", "#a5452a", "#c4472f", "#9a2f25", "#b5612f"]
BERRY = ["#d6302a", "#c42820", "#e2412f", "#b3221c"]
BERRY_DEEP = "#6e1414"
BARK = ["#5a3d26", "#4a321f", "#6b4a2e", "#3b2716", "#7a5636"]
CAP_RED = "#d8302b"
WART = "#f1ebde"


PREC = [1]   # decimals in coordinates — the treeline, drawn small, needs none


def f(v):
    if PREC[0] == 0:
        s = "%d" % round(v)
    else:
        s = "%.1f" % v
        if s.endswith(".0"):
            s = s[:-2]
    return "0" if s == "-0" else s


def hx(c):
    c = c.lstrip("#")
    return [int(c[i:i + 2], 16) for i in (0, 2, 4)]


def mix(a, b, t):
    """a → b by t, in sRGB (fine for shading one colour lighter or darker)."""
    a, b = hx(a), hx(b)
    return "#%02x%02x%02x" % tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def dark(c, t=0.35):
    return mix(c, "#000000", t)


def light(c, t=0.25):
    return mix(c, "#ffffff", t)


# ── geometry ─────────────────────────────────────────────────────────────────
def catmull(pts, step=3.0):
    """Dense points along a Catmull-Rom spline through pts."""
    if len(pts) < 2:
        return list(pts)
    out = []
    P = [pts[0]] + list(pts) + [pts[-1]]
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        n = max(2, int(math.dist(p1, p2) / step))
        for j in range(n):
            t = j / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(
                0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                       + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3) for k in (0, 1)))
    out.append(tuple(pts[-1]))
    return out


def rnd(v):
    return round(v, PREC[0])


def nums(vals):
    """Numbers for a path: no separator before a minus sign."""
    out = ""
    for v in vals:
        t = f(v)
        out += t if (not out or t[0] == "-") else " " + t
    return out


def poly_d(pts, close=True):
    """A polyline in relative coordinates — each step measured from the
    ROUNDED previous point, so rounding never accumulates — about half the
    size of absolute ones."""
    cx, cy = rnd(pts[0][0]), rnd(pts[0][1])
    d = "M" + nums((cx, cy)) + "l"
    vals = []
    for x, y in pts[1:]:
        nx, ny = rnd(x), rnd(y)
        if nx == cx and ny == cy:
            continue
        vals += [nx - cx, ny - cy]
        cx, cy = nx, ny
    return d + nums(vals) + ("z" if close else "")


def smooth_d(pts):
    """A smooth open path through pts (quadratics through the midpoints),
    relative like poly_d."""
    if len(pts) < 3:
        return poly_d(pts, False)
    cx, cy = rnd(pts[0][0]), rnd(pts[0][1])
    d = "M" + nums((cx, cy)) + "q"
    vals = []
    for i in range(1, len(pts) - 1):
        qx, qy = rnd(pts[i][0]), rnd(pts[i][1])
        mx, my = rnd((pts[i][0] + pts[i + 1][0]) / 2), rnd((pts[i][1] + pts[i + 1][1]) / 2)
        vals += [qx - cx, qy - cy, mx - cx, my - cy]
        cx, cy = mx, my
    ex, ey = rnd(pts[-1][0]), rnd(pts[-1][1])
    return d + nums(vals) + "l" + nums((ex - cx, ey - cy))


def heading(pts, i):
    a, b = pts[max(0, i - 1)], pts[min(len(pts) - 1, i + 1)]
    return math.atan2(b[1] - a[1], b[0] - a[0])


def tapered(pts, w0, w1, knob=0.0, rng=None):
    """The outline of a stem drawn along pts, w0 wide at the start tapering
    to w1 — filled, not stroked, so it can taper. `knob` adds a little
    irregularity (bark is never a perfect tube)."""
    if len(pts) > 6:
        # the centre line comes in every ~3px; an outline needs half that
        pts = pts[::2] + ([pts[-1]] if len(pts) % 2 == 0 else [])
    n = len(pts)
    L, R = [], []
    for i, (x, y) in enumerate(pts):
        h = heading(pts, i)
        nx, ny = -math.sin(h), math.cos(h)
        t = i / max(1, n - 1)
        w = (w0 + (w1 - w0) * t) / 2
        if knob and rng:
            w *= 1 + knob * (rng.random() - 0.5)
        L.append((x + nx * w, y + ny * w))
        R.append((x - nx * w, y - ny * w))
    return poly_d(L + R[::-1])


def turtle(x, y, h, n, ds, bend=0.0, gravity=0.0, wander=0.0, rng=None, curl=0.0):
    """A walked line: n steps of ds, turning by bend each step (plus random
    wander), pulled toward straight down by gravity, the turn growing by
    curl (a spiral when curl > 0)."""
    pts = [(x, y)]
    k = bend
    for _ in range(n):
        if wander and rng:
            h += rng.uniform(-wander, wander)
        h += k
        k *= 1 + curl
        if gravity:
            # turn toward +y (down) by the shortest way
            d = (math.pi / 2 - h + math.pi) % TAU - math.pi
            h += gravity * d
        x += ds * math.cos(h)
        y += ds * math.sin(h)
        pts.append((x, y))
    return pts


def xform(pts, x, y, ang, s=1.0):
    ca, sa = math.cos(ang), math.sin(ang)
    return [(x + (u * ca - v * sa) * s, y + (u * sa + v * ca) * s) for u, v in pts]


def bulge_d(verts, bulges, centre):
    """A closed outline through verts, each edge a quadratic bowed outward
    (away from centre) by its bulge × the edge's length. Relative, like
    poly_d."""
    cx, cy = rnd(verts[0][0]), rnd(verts[0][1])
    d = "M" + nums((cx, cy)) + "q"
    vals = []
    for i in range(len(verts)):
        a, b = verts[i], verts[(i + 1) % len(verts)]
        mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        ex, ey = b[0] - a[0], b[1] - a[1]
        el = math.hypot(ex, ey) or 1
        nx, ny = -ey / el, ex / el
        if nx * (mx - centre[0]) + ny * (my - centre[1]) < 0:
            nx, ny = -nx, -ny
        bb = bulges[i % len(bulges)]
        qx, qy = rnd(mx + nx * bb * el), rnd(my + ny * bb * el)
        bx, by = rnd(b[0]), rnd(b[1])
        vals += [qx - cx, qy - cy, bx - cx, by - cy]
        cx, cy = bx, by
    return d + nums(vals) + "z"


def tri_d(tris):
    """Many small triangles (thorns, ridge-fur) as one path."""
    out = ""
    for (ax, ay), (bx, by), (cx, cy) in tris:
        ax, ay, bx, by, cx, cy = map(rnd, (ax, ay, bx, by, cx, cy))
        out += "M" + nums((ax, ay)) + "l" + nums((bx - ax, by - ay, cx - bx, cy - by)) + "z"
    return out


def seg_d(segs):
    """Many short lines as one path: [(x0, y0, x1, y1), …]."""
    return "".join("M" + nums((rnd(a), rnd(b))) + "l" + nums((rnd(c) - rnd(a), rnd(e) - rnd(b))) for a, b, c, e in segs)


# ── leaves ───────────────────────────────────────────────────────────────────
def ivy_leaf(x, y, ang, L, rng, fill, lobed=1.0):
    """English ivy: five pointed lobes (a long terminal one, two side, two
    small basal), the petiole in a notch, pale veins fanning from it. Older
    leaves (lobed < 1) are closer to a plain heart."""
    k = lobed
    j = lambda: rng.uniform(-0.04, 0.04)
    up = [(0.05 + j(), 0.36 * k + 0.14), (0.30 + j(), 0.24 + 0.08 * (1 - k)),
          (0.47 + j(), 0.50 * k + 0.16 * (1 - k)), (0.66 + j(), 0.17 + 0.12 * (1 - k))]
    dn = [(0.05 + j(), -(0.36 * k + 0.14)), (0.30 + j(), -(0.24 + 0.08 * (1 - k))),
          (0.47 + j(), -(0.50 * k + 0.16 * (1 - k))), (0.66 + j(), -(0.17 + 0.12 * (1 - k)))]
    local = [(0.0, 0.0)] + up + [(1.0, j())] + dn[::-1]
    v = xform(local, x, y, ang, L)
    c = xform([(0.45, 0)], x, y, ang, L)[0]
    # base→basal lobe round, lobe edges bowed, sinuses tight
    bul = [0.32, 0.22, 0.18, 0.22, 0.2, 0.2, 0.22, 0.18, 0.22, 0.32]
    edge = dark(fill, 0.45)
    out = ['<path d="%s" fill="%s" stroke="%s" stroke-width=".6"/>' % (bulge_d(v, bul, c), fill, edge)]
    vein = light(fill, 0.28)
    base = xform([(0.07, 0)], x, y, ang, L)[0]
    vd = seg_d([(base[0], base[1], base[0] + (t[0] - base[0]) * 0.86, base[1] + (t[1] - base[1]) * 0.86)
                for t in (v[1], v[3], v[5], v[7], v[9])])
    out.append('<path d="%s" stroke="%s" stroke-width=".55" opacity=".7" fill="none"/>' % (vd, vein))
    return "".join(out)


def blade_leaf(x, y, ang, L, W, rng, fill, teeth=0, vein=True, tip=1.0):
    """A pointed leaf (rowan leaflet, bramble, fern pinna…): widest a third of
    the way out, optionally toothed on its outer half."""
    n = 6 if L < 9 else (8 if L < 16 else 12)
    side = {1: [], -1: []}
    for s in (1, -1):
        for i in range(n + 1):
            t = i / n
            w = W * (math.sin(math.pi * t) ** 0.8) * (1.1 - 0.4 * t ** tip)
            if teeth and t > 0.3 and 0 < i < n and i % 2:
                w += teeth
            side[s].append((t, s * w / L))
    local = side[1] + side[-1][::-1]
    pts = xform(local, x, y, ang, L)
    d = poly_d(pts)
    if vein and L >= 9:
        a = xform([(0.02, 0), (0.88, 0)], x, y, ang, L)
        d += seg_d([(a[0][0], a[0][1], a[1][0], a[1][1])])
    return '<path d="%s" fill="%s" stroke="%s" stroke-width=".5"/>' % (d, fill, dark(fill, 0.4))


def oak_leaf(x, y, ang, L, rng, fill):
    """Oak: a short stalk, then 4–5 rounded lobes a side, deep sinuses."""
    lobes = rng.randint(4, 5)
    up = []
    for i in range(lobes):
        t = 0.14 + 0.78 * i / (lobes - 1)
        w = 0.34 * math.sin(math.pi * min(1, t * 1.08)) + 0.06
        up.append((t - 0.06, w * 0.45))           # sinus
        up.append((t + rng.uniform(-0.02, 0.02), w + rng.uniform(-0.03, 0.03)))  # lobe
    local = [(0.0, 0.0)] + up + [(1.0, 0.0)] + [(u, -v) for u, v in up[::-1]]
    v = xform(local, x, y, ang, L)
    c = xform([(0.5, 0)], x, y, ang, L)[0]
    bul = []
    for i in range(len(v)):
        bul.append(0.45 if i % 2 else 0.08)
    out = ['<path d="%s" fill="%s" stroke="%s" stroke-width=".6"/>' % (bulge_d(v, bul, c), fill, dark(fill, 0.45))]
    a = xform([(0.0, 0), (0.95, 0)], x, y, ang, L)
    out.append('<path d="M%s %sL%s %s" stroke="%s" stroke-width=".7" opacity=".7"/>' % (
        f(a[0][0]), f(a[0][1]), f(a[1][0]), f(a[1][1]), light(fill, 0.3)))
    return "".join(out)


# ── small things ─────────────────────────────────────────────────────────────
def tendril(x, y, h, rng, size=10, col="#3d7a34", w=0.8):
    """A climbing tendril: a short lead, then a tightening curl."""
    s = rng.choice([-1, 1])
    pts = turtle(x, y, h, 34, size / 11, bend=s * 0.03, curl=0.075, wander=0.02, rng=rng)
    return '<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round"/>' % (smooth_d(pts), col, f(w))


def usnea(x, y, rng, n, length, spread=6.0, sway=1.0):
    """Old-man's-beard: a tuft of pale lichen hanging from (x, y). Strands are
    walked, not drawn straight — each sways and wanders, a few cling
    together in ropes, the lengths run from stubs to long tails — with tiny
    branchlets all the way down."""
    out = []
    strands = []
    for _ in range(n):
        x0 = x + rng.uniform(-spread, spread)
        L = length * (0.25 + 0.75 * rng.random() ** 1.6)
        steps = max(4, int(L / 4.5))
        pts = turtle(x0, y, math.pi / 2 + rng.uniform(-0.5, 0.5), steps, L / steps,
                     wander=0.22 * sway, gravity=0.16, rng=rng)
        strands.append(pts)
        if rng.random() < 0.35:  # a rope: a second strand clinging to this one
            off = rng.uniform(0.8, 1.6) * rng.choice([-1, 1])
            strands.append([(px + off + rng.uniform(-0.4, 0.4), py) for px, py in pts[: int(len(pts) * rng.uniform(0.5, 1))]])
    # one path per (colour, weight) in the tuft, and one for all its branchlets
    groups = {}
    bl = []
    for pts in strands:
        key = (rng.choice(LICHEN), rng.choice((".5", ".75", "1")))
        groups.setdefault(key, []).append(poly_d(pts, False))
        for k in range(1, len(pts), 2):
            if rng.random() < 0.55:
                px, py = pts[k]
                a = math.pi / 2 + rng.choice([-1, 1]) * rng.uniform(0.6, 1.2)
                l = rng.uniform(1.5, 4.5)
                bl.append((px, py, px + l * math.cos(a), py + l * math.sin(a)))
    for (col, w), ds in groups.items():
        out.append('<path d="%s" fill="none" stroke="%s" stroke-width="%s" opacity="%s" stroke-linecap="round"/>' % (
            "".join(ds), col, w, f(rng.uniform(0.7, 0.92))))
    if bl:
        out.append('<path d="%s" stroke="%s" stroke-width=".45" opacity=".7" fill="none"/>' % (seg_d(bl), rng.choice(LICHEN)))
    return "".join(out)


def moss_mound(cx, cy, w, h, rng, palette=MOSS, sporophytes=0, dots=1.0):
    """A cushion of moss: many small domes packed into a mound, dark beneath
    and lit on top, optionally with sporophytes — wiry red-brown stalks with
    capsules — standing out of it."""
    out = []
    n = int(w * h / 12 * dots) + 6
    blobs = []
    for _ in range(n):
        u = rng.uniform(-1, 1)
        top = cy - h * (1 - u * u) ** 0.7
        y = rng.uniform(top, cy)
        x = cx + u * w / 2
        r = rng.uniform(1.6, 3.4)
        blobs.append((y, x, r))
    blobs.sort()
    for y, x, r in blobs:
        depth = (y - (cy - h)) / max(1, h)
        col = mix(rng.choice(palette), "#10180b", 0.45 * depth)
        out.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % (f(x), f(y), f(r), col))
    for y, x, r in blobs[: max(3, n // 5)]:
        out.append('<circle cx="%s" cy="%s" r="%s" fill="%s" opacity=".55"/>' % (f(x - r * 0.3), f(y - r * 0.35), f(r * 0.45), light(rng.choice(palette), 0.3)))
    for _ in range(sporophytes):
        x = cx + rng.uniform(-w / 2.4, w / 2.4)
        u = (x - cx) / (w / 2)
        y = cy - h * max(0, 1 - u * u) ** 0.7 + 1
        l = rng.uniform(6, 13)
        a = -math.pi / 2 + rng.uniform(-0.35, 0.35)
        tx, ty = x + l * math.cos(a), y + l * math.sin(a)
        out.append('<path d="M%s %sQ%s %s %s %s" stroke="#7a3a22" stroke-width=".55" fill="none"/>' % (
            f(x), f(y), f(x + rng.uniform(-2, 2)), f((y + ty) / 2), f(tx), f(ty)))
        out.append('<ellipse cx="%s" cy="%s" rx=".9" ry="1.7" fill="#9a3b24" transform="rotate(%s %s %s)"/>' % (
            f(tx), f(ty), f(math.degrees(a) + 90 + rng.uniform(-30, 30)), f(tx), f(ty)))
    return "".join(out)


def rowan_berries(cx, cy, rng, n=14, spread=11, r0=2.6):
    """A corymb: stalks from one point, berries domed below it."""
    placed = []
    for _ in range(n):
        for _ in range(40):
            r = rng.uniform(r0 * 0.8, r0 * 1.2)
            a = rng.uniform(0, TAU)
            d = spread * math.sqrt(rng.random())
            x, y = cx + d * math.cos(a) * 1.25, cy + spread * 0.8 + d * math.sin(a) * 0.7
            if all(math.hypot(x - px, y - py) > r + pr - 0.5 for px, py, pr in placed):
                placed.append((x, y, r))
                break
    out = []
    sd = seg_d([(cx, cy, x, y - r * 0.6) for x, y, r in placed])
    out.append('<path d="%s" stroke="#6a2a1e" stroke-width=".6" fill="none" opacity=".85"/>' % sd)
    for x, y, r in sorted(placed, key=lambda p: p[1]):
        out.append('<circle cx="%s" cy="%s" r="%s" fill="url(#berry)"/>' % (f(x), f(y), f(r)))
        out.append('<circle cx="%s" cy="%s" r="%s" fill="#ffe2cc" opacity=".55"/>' % (f(x - r * 0.35), f(y - r * 0.4), f(r * 0.27)))
        out.append('<circle cx="%s" cy="%s" r="%s" fill="#3a0a10" opacity=".6"/>' % (f(x + r * 0.1), f(y + r * 0.62), f(r * 0.17)))
    return "".join(out)


def blackberry(cx, cy, rng, r=4.2, ripe=1.0):
    """A bramble fruit: an aggregate of drupelets, black when ripe, red
    before, green before that."""
    col = "#22090f" if ripe > 0.66 else ("#c42820" if ripe > 0.33 else "#7aa04a")
    hi = "#5a2a30" if ripe > 0.66 else ("#f0866a" if ripe > 0.33 else "#b5d27a")
    out = []
    dr = ""
    hl = ""
    for i in range(11):
        a = i * 2.4
        d = r * 0.6 * math.sqrt((i + 0.5) / 11)
        x, y = cx + d * math.cos(a), cy + d * math.sin(a) * 1.15
        dr += '<circle cx="%s" cy="%s" r="%s"/>' % (f(x), f(y), f(r * 0.4))
        if i % 2:
            hl += '<circle cx="%s" cy="%s" r="%s"/>' % (f(x - r * 0.1), f(y - r * 0.12), f(r * 0.11))
    out.append('<g fill="%s" stroke="%s" stroke-width=".35">%s</g><g fill="%s" opacity=".7">%s</g>' % (col, dark(col, 0.5), dr, hi, hl))
    # the sepals
    sd = ""
    for i in range(5):
        a = -math.pi / 2 + (i - 2) * 0.5
        sd += "M%s %sl%s %s" % (f(cx), f(cy - r * 0.9), f(3 * math.cos(a)), f(3 * math.sin(a) * 0.6))
    out.append('<path d="%s" stroke="#3f6a2a" stroke-width="1" fill="none" stroke-linecap="round"/>' % sd)
    return "".join(out)


def bramble_flower(cx, cy, rng, r=5.5):
    out = []
    a0 = rng.uniform(0, TAU)
    for i in range(5):
        a = a0 + i * TAU / 5
        px, py = cx + r * 0.55 * math.cos(a), cy + r * 0.55 * math.sin(a)
        out.append('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="#f4f0e4" stroke="#cfc6ae" stroke-width=".4" transform="rotate(%s %s %s)"/>' % (
            f(px), f(py), f(r * 0.55), f(r * 0.42), f(math.degrees(a)), f(px), f(py)))
    out.append('<circle cx="%s" cy="%s" r="%s" fill="#c9b04a"/>' % (f(cx), f(cy), f(r * 0.32)))
    dd = "".join('<circle cx="%s" cy="%s" r=".45" fill="#8a6b1e"/>' % (f(cx + r * 0.25 * math.cos(i)), f(cy + r * 0.25 * math.sin(i))) for i in range(0, 7))
    return "".join(out) + dd


def acorn(x, y, ang, rng, s=1.0):
    out = []
    nut = xform([(0, 0)], x, y, ang)[0]
    deg = math.degrees(ang) - 90
    out.append('<g transform="translate(%s %s) rotate(%s) scale(%s)">' % (f(nut[0]), f(nut[1]), f(deg), f(s)))
    out.append('<path d="M-3.4 2 C-3.6 7 -1.6 10.5 0 11 C1.6 10.5 3.6 7 3.4 2Z" fill="#9c7a3a" stroke="#5e4620" stroke-width=".5"/>')
    out.append('<path d="M-1.6 4 C-1.5 7 -.6 9 .2 9.6" stroke="#c9a85c" stroke-width=".7" fill="none" opacity=".7"/>')
    out.append('<path d="M-4.2 2.6 C-4.4 -1 -2.2 -2.6 0 -2.6 C2.2 -2.6 4.4 -1 4.2 2.6Z" fill="#6b5232" stroke="#3e2d18" stroke-width=".5"/>')
    out.append('<path d="M-3.6 0.6h7.2M-3.9 1.8h7.8M-3 -.8h6" stroke="#4a3820" stroke-width=".45" stroke-dasharray="1 .8"/>')
    out.append('<path d="M0 -2.6v-2.2" stroke="#4a3820" stroke-width="1" stroke-linecap="round"/></g>')
    return "".join(out)


def toadstool(x, y, h, rng, lean=0.0, cap=None, glow=False):
    """A fly agaric: a cream stem with a ring, a red dome flecked with white
    warts. glow=True adds foxfire around it (the night wood)."""
    cap = cap or h * rng.uniform(0.55, 0.75)
    tx, ty = x + lean * h, y - h
    out = []
    if glow:
        out.append('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="url(#foxfire)"/>' % (f(tx), f(ty + h * 0.3), f(cap * 2.2), f(h * 1.1)))
    sw0, sw1 = h * 0.16, h * 0.11
    out.append('<path d="M%s %sQ%s %s %s %sL%s %sQ%s %s %s %sZ" fill="url(#stem)" stroke="#8c7d64" stroke-width=".4"/>' % (
        f(x - sw0), f(y), f(x - sw0 + lean * h * 0.4), f(y - h * 0.5), f(tx - sw1), f(ty + 1),
        f(tx + sw1), f(ty + 1), f(x + sw0 + lean * h * 0.4), f(y - h * 0.5), f(x + sw0), f(y)))
    ry = ty + h * 0.32
    out.append('<path d="M%s %sq%s %s %s 0" fill="#e9e1cf" stroke="#9a8b70" stroke-width=".4"/>' % (
        f(tx - sw1 * 1.6 + lean * h * 0.3), f(ry), f(sw1 * 1.6), f(sw1 * 1.2), f(sw1 * 3.2)))
    a = math.atan2(-h, lean * h) + math.pi / 2
    deg = math.degrees(a)
    out.append('<g transform="translate(%s %s) rotate(%s)">' % (f(tx), f(ty), f(deg * 0.6)))
    out.append('<path d="M%s 1C%s %s %s %s %s 1Z" fill="url(#cap)" stroke="#7a1612" stroke-width=".5"/>' % (
        f(-cap), f(-cap * 0.9), f(-cap * 1.05), f(cap * 0.9), f(-cap * 1.05), f(cap)))
    out.append('<path d="M%s 1Q0 %s %s 1" fill="#efe4cc" opacity=".9"/>' % (f(-cap * 0.92), f(cap * 0.16), f(cap * 0.92)))
    for _ in range(int(cap * 1.4) + 3):
        u = rng.uniform(-0.8, 0.8)
        vy = -cap * 0.72 * (1 - u * u) ** 0.6 * rng.uniform(0.35, 1.0) - 0.5
        out.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % (f(u * cap), f(vy), f(rng.uniform(0.35, 0.8) * max(1, cap / 6)), WART))
    out.append('</g>')
    return "".join(out)


def bonnet(x, y, h, rng, lean=0.0, col=None):
    """A small brown bonnet mushroom (Mycena): a thin tall stem, a conical cap."""
    col = col or rng.choice(["#a07a4c", "#8e6a40", "#b48d5c", "#7a5a36"])
    tx, ty = x + lean * h, y - h
    c = h * rng.uniform(0.28, 0.36)
    return ('<path d="M%s %sQ%s %s %s %s" stroke="#d8cbb0" stroke-width="%s" fill="none" stroke-linecap="round"/>'
            '<path d="M%s %sQ%s %s %s %sZ" fill="%s" stroke="%s" stroke-width=".4"/>'
            '<path d="M%s %sL%s %s" stroke="%s" stroke-width=".5" opacity=".6"/>') % (
        f(x), f(y), f(x + lean * h * 0.3), f(y - h * 0.6), f(tx), f(ty), f(max(0.7, h * 0.07)),
        f(tx - c), f(ty + c * 0.35), f(tx), f(ty - c * 1.3), f(tx + c), f(ty + c * 0.35), col, dark(col, 0.45),
        f(tx), f(ty - c * 1.2), f(tx), f(ty + c * 0.2), light(col, 0.35))


def grass(x, y, rng, n=7, h=10, palette=None):
    """A tuft of grass — one path, one colour a tuft."""
    palette = palette or ["#2f5a26", "#3b6b2c", "#4a7a32", "#5d8a3a"]
    d = ""
    for _ in range(n):
        bx = x + rng.uniform(-3, 3)
        l = h * rng.uniform(0.5, 1.1)
        a = -math.pi / 2 + rng.uniform(-0.6, 0.6)
        c = rng.uniform(-0.25, 0.25)
        x0, y0 = rnd(bx), rnd(y)
        d += "M" + nums((x0, y0)) + "q" + nums((rnd(l * 0.5 * math.cos(a + c)), rnd(l * 0.5 * math.sin(a + c)),
                                                rnd(l * math.cos(a)), rnd(l * math.sin(a))))
    return '<path d="%s" stroke="%s" stroke-width="%s" fill="none" stroke-linecap="round"/>' % (d, rng.choice(palette), f(rng.uniform(0.7, 1.0)))


def frond_silhouette(x, y, h0, length, rng, col, gravity=0.05):
    """A fern as a shadow — the rachis and its pinnae as strokes, one path."""
    pts = turtle(x, y, h0, int(length / 5), 5, gravity=gravity, wander=0.03, rng=rng)
    d = smooth_d(pts)
    for i in range(1, len(pts) - 1):
        t = i / len(pts)
        L = (4 + 10 * math.sin(math.pi * min(1, t * 1.15))) * (1 - 0.45 * t)
        h = heading(pts, i)
        for sd in (1, -1):
            a = h + sd * 1.0
            d += "M%s %sl%s %s" % (f(pts[i][0]), f(pts[i][1]), f(L * math.cos(a)), f(L * math.sin(a)))
    return '<path d="%s" stroke="%s" stroke-width="1.6" fill="none" stroke-linecap="round"/>' % (d, col)


def frond(x, y, h0, length, rng, gravity=0.04, bend=0.0, palette=FERN, scale=1.0, pinnae=True):
    """A fern frond: a rachis walked from (x, y), pinnae alternating along it,
    longest a third of the way out, shrinking to the tip."""
    n = int(length / 4)
    pts = turtle(x, y, h0, n, 4, bend=bend, gravity=gravity, wander=0.02, rng=rng)
    out = ['<path d="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round"/>' % (
        smooth_d(pts), dark(palette[0], 0.2), f(1.1 * scale))]
    col = rng.choice(palette)
    for i in range(2, len(pts) - 1):
        t = i / len(pts)
        h = heading(pts, i)
        L = (5 + 13 * math.sin(math.pi * min(1, t * 1.15)) ** 0.9) * scale * (1.0 - 0.5 * t)
        for s in (1, -1):
            a = h + s * (1.05 - 0.3 * t) + rng.uniform(-0.08, 0.08)
            px, py = pts[i][0] + s * 0.0, pts[i][1]
            if pinnae:
                out.append(blade_leaf(px, py, a, L, L * 0.2, rng, mix(col, rng.choice(palette), 0.5), teeth=0.45 * scale, vein=False))
            else:
                out.append('<path d="M%s %sl%s %s" stroke="%s" stroke-width="1"/>' % (f(px), f(py), f(L * math.cos(a)), f(L * math.sin(a)), col))
    return "".join(out)


def fiddlehead(x, y, rng, h=14, col="#5aa948"):
    """A young fern still curled: a stalk rising into a tight spiral."""
    pts = turtle(x, y, -math.pi / 2 + rng.uniform(-0.2, 0.2), 14, h / 14, bend=rng.choice([-1, 1]) * 0.02, rng=rng)
    s = 1 if rng.random() < 0.5 else -1
    curl = turtle(pts[-1][0], pts[-1][1], heading(pts, len(pts) - 1), 30, 0.9, bend=s * 0.12, curl=0.06)
    return ('<path d="%s" fill="none" stroke="%s" stroke-width="1.6" stroke-linecap="round"/>' % (smooth_d(pts + curl[1:]), col) +
            '<circle cx="%s" cy="%s" r="1.3" fill="%s"/>' % (f(curl[-1][0]), f(curl[-1][1]), light(col, 0.2)))


def stem(pts, w0, w1, col, rng=None, hi=True, knob=0.0):
    out = ['<path d="%s" fill="%s"/>' % (tapered(pts, w0, w1, knob, rng), col)]
    if hi and w0 > 2:
        # a highlight along the top of the stem
        hp = [(x, y - w0 * 0.12) for x, y in pts[: int(len(pts) * 0.8)]]
        if len(hp) > 2:
            out.append('<path d="%s" fill="none" stroke="%s" stroke-width="%s" opacity=".45" stroke-linecap="round"/>' % (
                smooth_d(hp), light(col, 0.35), f(w0 * 0.22)))
    return "".join(out)


def bark_lines(pts, w0, w1, rng, col, n=None):
    """Short lengthwise cracks along a branch, so it reads as bark."""
    out = ""
    n = n or len(pts) // 3
    for _ in range(n):
        i = rng.randrange(1, max(2, len(pts) - 3))
        t = i / len(pts)
        w = (w0 + (w1 - w0) * t) / 2
        h = heading(pts, i)
        off = rng.uniform(-0.6, 0.6) * w
        x, y = pts[i][0] - math.sin(h) * off, pts[i][1] + math.cos(h) * off
        l = rng.uniform(3, 9)
        out += "M%s %sl%s %s" % (f(x), f(y), f(l * math.cos(h)), f(l * math.sin(h)))
    return '<path d="%s" stroke="%s" stroke-width=".6" opacity=".55" fill="none" stroke-linecap="round"/>' % (out, col) if out else ""


# ── shared defs ──────────────────────────────────────────────────────────────
DEFS = (
    '<defs>'
    '<radialGradient id="berry" cx=".38" cy=".35" r=".75"><stop offset="0" stop-color="#ff7a52"/><stop offset=".5" stop-color="#d6302a"/><stop offset="1" stop-color="#6e1414"/></radialGradient>'
    '<radialGradient id="cap" cx=".4" cy=".2" r=".9"><stop offset="0" stop-color="#ff5a45"/><stop offset=".55" stop-color="#d8302b"/><stop offset="1" stop-color="#7a1612"/></radialGradient>'
    '<linearGradient id="stem" x1="0" x2="1"><stop offset="0" stop-color="#cfc3a8"/><stop offset=".45" stop-color="#f1ead8"/><stop offset="1" stop-color="#b9ab8c"/></linearGradient>'
    '<radialGradient id="foxfire"><stop offset="0" stop-color="#a8f0a0" stop-opacity=".35"/><stop offset="1" stop-color="#a8f0a0" stop-opacity="0"/></radialGradient>'
    '<filter id="sh" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="1" dy="2.2" stdDeviation="1.6" flood-color="#000" flood-opacity=".55"/></filter>'
    '</defs>'
)


def svg(w, h, body, note, shadow=True):
    g = '<g filter="url(#sh)">%s</g>' % body if shadow else body
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><!-- %s Generated by growth.py — see its header. -->%s%s</svg>'
            % (w, h, w, h, note, DEFS, g))


# ════════════════════════════════════════════════════════════════════════════
# Top pieces — what has grown over a card's top edge. E is the edge's y: the
# piece hangs E px above the card (the pseudo-element starts there).
# `side` is the corner it grows from; `keep` is how far from the title-side
# corner nothing may hang down (the title sits under it).
# ════════════════════════════════════════════════════════════════════════════
E = 18


def edge_path(W, rng, side, reach, keep, sag=(10, 30), step=10, lift=0.0, wrap=True):
    """The line a vine takes along the top edge: up round the card's corner,
    then inward, resting on the edge and sagging between holds — never down
    over the title (the first `keep` px from the left, where it sits)."""
    x0 = W - 9 if side == "right" else 9
    dirn = -1 if side == "right" else 1
    holds = [0]
    while holds[-1] < reach:
        holds.append(holds[-1] + rng.uniform(80, 170))
    depths = [rng.uniform(*sag) for _ in holds]
    hy = [E + rng.uniform(-6, 2) for _ in holds]
    pts = []
    if wrap:
        # round the corner: up the side, over the radius
        pts += [(x0 + dirn * -3, E + 34 + rng.uniform(0, 10)), (x0 + dirn * -4, E + 16), (x0 + dirn * 2, E + 1)]
    for k in range(1, int(reach / step)):
        d = k * step
        x = x0 + dirn * d
        j = 0
        while j < len(holds) - 2 and holds[j + 1] < d:
            j += 1
        u = min(1, (d - holds[j]) / max(1, holds[j + 1] - holds[j]))
        y = hy[j] + (hy[j + 1] - hy[j]) * u + depths[j] * math.sin(math.pi * u) ** 1.3
        if x < keep:
            y = min(y, E - 3 + 3 * math.sin(x / 23))
        pts.append((x, y - lift + rng.uniform(-1.8, 1.8)))
    return catmull(pts, 3)


def ivy_top(W, H, rng, side="right", reach=0.7, keep=210, autumn=0.0, moss=4, drop=0, berries=0, young=0.25, second=True):
    """Ivy over the top edge: a woody stem up round the corner and along the
    edge, sagging between holds, with a younger stem winding through it;
    leaves both ways (big and dark near the root, small and bright towards the
    tips), shoots hanging down, tendrils, tufts of old-man's-beard, and — if
    drop — a strand trailing down the corner it came from."""
    reach_px = W * reach
    # from the title's own corner it can't come round the side (the rune is
    # there): it starts on the edge
    pts = edge_path(W, rng, side, reach_px, keep, wrap=(side == "right"))
    vines = [(pts, 4.6, 1.0, 1.0)]
    if second:
        p2 = edge_path(W, rng, side, reach_px * rng.uniform(0.55, 0.85), keep, sag=(4, 22), wrap=False)
        vines.append((p2, 2.4, 0.6, 0.7))
    back, mid, front, top = [], [], [], []
    for vi, (vp, w0, w1, ls) in enumerate(vines):
        n = len(vp)
        # shoots hanging off it, past the title
        for _ in range(rng.randint(2, 4) if vi == 0 else rng.randint(1, 2)):
            i = rng.randrange(n // 6, n - 4)
            x, y = vp[i]
            if x < keep:
                continue
            L = rng.uniform(18, 46)
            sp = turtle(x, y, math.pi / 2 + rng.uniform(-0.7, 0.7), int(L / 3), 3, gravity=0.05, wander=0.14, rng=rng)
            back.append(stem(sp, 1.8, 0.5, "#3f5a2a", hi=False))
            for k in range(3, len(sp), rng.randint(2, 4)):
                a = heading(sp, k) + rng.choice([-1, 1]) * rng.uniform(0.7, 1.4)
                a += 0.35 * ((math.pi / 2 - a + math.pi) % TAU - math.pi)
                front.append(leaf_on(sp[k], a, rng.uniform(9, 15), rng, autumn, young=0.5))
            if rng.random() < 0.6:
                top.append(tendril(sp[-1][0], sp[-1][1], heading(sp, len(sp) - 1), rng, size=rng.uniform(8, 13)))
        # the stem
        mid.append(stem(vp, w0, w1, "#4a3a22" if vi == 0 else "#4f5a2a", rng, knob=0.25))
        if vi == 0:
            mid.append(bark_lines(vp[: n // 2], w0, w1 * 2, rng, "#2a1f12"))
        # leaves along it
        i, s = 2, 1
        while i < n - 1:
            t = i / n
            over_title = vp[i][0] < keep
            if over_title:
                # pointing up, off the card (the stem heads left from the
                # right corner and right from the left one)
                s = 1 if side == "right" else -1
            h = heading(vp, i)
            a = h + s * rng.uniform(0.8, 2.0)
            if s < 0 and not over_title:  # the leaves below the stem droop
                a += 0.4 * ((math.pi / 2 - a + math.pi) % TAU - math.pi)
            L = (28 - 14 * t) * rng.uniform(0.7, 1.25) * ls * (0.7 if over_title else 1)
            if not (s > 0 and vp[i][1] - L * 0.8 < 0):
                front.append(leaf_on(vp[i], a, L, rng, autumn, young=young * t * 2, lobed=1.0 - 0.6 * (1 - t) * rng.random()))
            i += rng.randint(2, 5)
            s = -s if rng.random() < 0.75 else s
        for _ in range(rng.randint(2, 3)):
            i = rng.randrange(n // 3, n - 1)
            top.append(tendril(vp[i][0], vp[i][1], heading(vp, i) + rng.uniform(-1.4, 1.4), rng, size=rng.uniform(8, 15)))
        top.append(tendril(vp[-1][0], vp[-1][1], heading(vp, n - 1), rng, size=13))
    # old-man's-beard hanging off the old stem
    n = len(pts)
    for _ in range(moss):
        i = rng.randrange(n // 6, n - 2)
        x, y = pts[i]
        if x < keep:
            continue
        back.append(usnea(x, y + 1, rng, rng.randint(12, 24), rng.uniform(22, 46), spread=8, sway=1.5))
    # a strand trailing down the corner it came from
    if drop:
        cx = W - 16 if side == "right" else 16
        sp = turtle(cx, E + 30, math.pi / 2, int(drop / 3), 3, wander=0.1, gravity=0.05, rng=rng)
        back.append(stem(sp, 2.4, 0.6, "#4a3a22", hi=False))
        for k in range(2, len(sp), 2):
            a = math.pi / 2 + rng.choice([-1, 1]) * rng.uniform(0.6, 1.4)
            front.append(leaf_on(sp[k], a, rng.uniform(9, 15) * (1 - 0.4 * k / len(sp)), rng, autumn, young=0.3))
        top.append(tendril(sp[-1][0], sp[-1][1], math.pi / 2, rng, size=10))
    for _ in range(berries):
        i = rng.randrange(n // 3, n - 3)
        if pts[i][0] > keep:
            top.append(rowan_berries(pts[i][0], pts[i][1] + 2, rng, n=rng.randint(9, 14), spread=8, r0=2.4))
    return "".join(back) + "".join(mid) + "".join(front) + "".join(top)


def leaf_on(p, a, L, rng, autumn=0.0, young=0.0, lobed=None):
    """An ivy leaf on a short petiole at p, pointing along a."""
    pl = rng.uniform(3, 6)
    bx, by = p[0] + pl * math.cos(a), p[1] + pl * math.sin(a)
    if rng.random() < autumn:
        col = rng.choice(AUTUMN)
    elif rng.random() < young:
        col = rng.choice(IVY_YOUNG)
    else:
        col = rng.choice(IVY)
    lob = lobed if lobed is not None else rng.uniform(0.6, 1.0)
    return ('<path d="%s" stroke="#3a4a24" stroke-width=".9"/>' % seg_d([(p[0], p[1], bx, by)]) +
            ivy_leaf(bx, by, a + rng.uniform(-0.2, 0.2), L, rng, col, lobed=lob))


def inward(side, tilt):
    """The heading from a top corner into the card, tilted down by tilt
    (radians; negative tilts up)."""
    return math.pi - tilt if side == "right" else tilt


def bracket(x, y, w, rng, flip=1):
    """A bracket fungus shelf on a branch's side: layered half-discs, growth
    rings, a pale rim."""
    out = []
    for k in range(rng.randint(1, 3)):
        ww = w * (1 - 0.25 * k)
        yy = y + k * w * 0.32
        col = rng.choice(["#a7804f", "#8e6a40", "#b8935f", "#7a5a36"])
        out.append('<path d="M%s %sQ%s %s %s %sZ" fill="%s" stroke="#e6d6b4" stroke-width=".8"/>' % (
            f(x), f(yy), f(x + flip * ww * 1.1), f(yy + ww * 0.15), f(x), f(yy + ww * 0.45), col))
        for r in (0.45, 0.75):
            out.append('<path d="M%s %sQ%s %s %s %s" fill="none" stroke="%s" stroke-width=".5" opacity=".7"/>' % (
                f(x), f(yy + ww * 0.05), f(x + flip * ww * 1.1 * r), f(yy + ww * 0.15), f(x), f(yy + ww * 0.45 * r + ww * 0.05), dark(col, 0.3)))
    return "".join(out)


def compound_leaf(x0, y0, ang, length, rng, pairs=5, palette=None, autumn=0.0, scale=1.0):
    """A rowan leaf: a rachis with paired toothed leaflets and a terminal one."""
    palette = palette or ["#2f7d3a", "#3d8c3f", "#367f38", "#4a9a44", "#2a6b33"]
    pts = turtle(x0, y0, ang, int(length / 4), 4, gravity=0.03, wander=0.02, rng=rng)
    out = ['<path d="%s" fill="none" stroke="#3a5a2a" stroke-width="%s" stroke-linecap="round"/>' % (smooth_d(pts), f(1.2 * scale))]
    n = len(pts)
    for i in range(pairs):
        k = int(2 + (n - 3) * i / max(1, pairs - 1))
        k = min(k, n - 2)
        t = k / n
        L = (15 + 5 * math.sin(math.pi * t)) * scale * rng.uniform(0.85, 1.1)
        h = heading(pts, k)
        for sd in (1, -1):
            a = h + sd * (1.0 - 0.25 * t) + rng.uniform(-0.12, 0.12)
            col = rng.choice(AUTUMN) if rng.random() < autumn else rng.choice(palette)
            out.append(blade_leaf(pts[k][0], pts[k][1], a, L, L * 0.24, rng, col, teeth=0.55 * scale))
    col = rng.choice(palette)
    out.append(blade_leaf(pts[-1][0], pts[-1][1], heading(pts, n - 1), 17 * scale, 4.2 * scale, rng, col, teeth=0.55 * scale))
    return "".join(out)


def rowan_top(W, H, rng, side="right", keep=210, reach=0.5, clusters=3, autumn=0.12):
    """A rowan bough over the corner: a bark twig sweeping in from it, side
    twigs, pinnate leaves fanning down, bunches of red berries, a few
    leaflets already turning."""
    dirn = -1 if side == "right" else 1
    x0 = W - 4 if side == "right" else 4
    L = W * reach
    main = turtle(x0, E - 4, inward(side, rng.uniform(0.05, 0.2)), int(L / 4), 4, wander=0.05, rng=rng)
    main = [(x, max(4, min(y, E + 26))) for x, y in main]
    twigs = [(main, 5.2, 1.4)]
    for _ in range(rng.randint(2, 3)):
        i = rng.randrange(len(main) // 4, len(main) - 3)
        a = heading(main, i) + dirn * rng.choice([-1, 1]) * rng.uniform(0.4, 0.9)
        tw = turtle(main[i][0], main[i][1], a, rng.randint(8, 16), 4, wander=0.08, gravity=0.02, rng=rng)
        twigs.append(([(x, max(4, y)) for x, y in tw], 2.4, 0.8))
    back, mid, front = [], [], []
    for tw, w0, w1 in twigs:
        mid.append(stem(tw, w0, w1, "#5b4632", rng, knob=0.2))
        mid.append(bark_lines(tw, w0, w1, rng, "#2f2216", n=len(tw) // 4))
        for k in range(2, len(tw) - 1, rng.randint(4, 6)):
            x, y = tw[k]
            if x < keep and y > E - 2:
                continue
            a = math.pi / 2 + rng.uniform(-1.1, 1.1)
            back.append(compound_leaf(x, y, a, rng.uniform(34, 58), rng, pairs=rng.randint(4, 5), autumn=autumn, scale=0.85))
    for _ in range(clusters):
        tw = rng.choice(twigs)[0]
        k = rng.randrange(len(tw) // 3, len(tw))
        x, y = tw[k]
        if x < keep:
            continue
        front.append(rowan_berries(x, y + 1, rng, n=rng.randint(14, 24), spread=rng.uniform(10, 14), r0=2.9))
    # lichen on the bark, and tufts of it hanging
    lich = "".join('<circle cx="%s" cy="%s" r="%s" fill="%s" opacity=".8"/>' % (
        f(p[0] + rng.uniform(-1.5, 1.5)), f(p[1] + rng.uniform(-1.5, 1.5)), f(rng.uniform(0.8, 1.8)), rng.choice(LICHEN))
        for p in rng.sample(main, min(len(main), 10)))
    for _ in range(rng.randint(2, 3)):
        x, y = main[rng.randrange(len(main) // 5, len(main))]
        if x > keep:
            back.insert(0, usnea(x, y + 2, rng, rng.randint(8, 16), rng.uniform(18, 40), spread=7))
    return "".join(back) + "".join(mid) + lich + "".join(front)


def bough_top(W, H, rng, side="right", keep=210, reach=0.62, ferns=False):
    """A dead bough lying along the top edge, thick with moss: cushions of it
    along the top, curtains of old-man's-beard hanging under, a shelf of
    bracket fungus, and — with ferns — polypody sprouting from the moss."""
    pts = edge_path(W, rng, side, W * reach, keep, sag=(2, 10), wrap=False, lift=-5)
    n = len(pts)
    back, mid, front = [], [], []
    # curtains first, behind the wood
    k = n // 8
    while k < n - 3:
        x, y = pts[k]
        if x > keep:
            for _ in range(rng.randint(1, 3)):
                back.append(usnea(x + rng.uniform(-10, 10), y + 3, rng, rng.randint(6, 16), rng.uniform(16, 46),
                                  spread=rng.uniform(4, 12), sway=rng.uniform(1.2, 2.2)))
        k += rng.randint(3, n // 6 + 4)
    mid.append(stem(pts, 11, 4, "#4b3826", rng, knob=0.3))
    mid.append(bark_lines(pts, 11, 4, rng, "#24190f", n=n // 2))
    # a broken-off stub and a knot
    i = rng.randrange(n // 3, 2 * n // 3)
    stub = turtle(pts[i][0], pts[i][1], heading(pts, i) + rng.choice([-1, 1]) * 0.9 - 0.4, 6, 3, rng=rng)
    mid.append(stem(stub, 5, 3, "#4b3826", hi=False))
    mid.append('<ellipse cx="%s" cy="%s" rx="2.4" ry="1.6" fill="#2e2216"/>' % (f(pts[i + 6][0]), f(pts[i + 6][1])))
    # moss along the top
    k = 0
    while k < n - 4:
        x, y = pts[k]
        w = rng.uniform(18, 46)
        front.append(moss_mound(x, y - 2, w, rng.uniform(4, 9), rng, sporophytes=rng.randint(0, 4)))
        k += max(2, int(w / 3) + rng.randint(-2, 3))
    # fungus on its flank
    i = rng.randrange(n // 2, n - 4)
    if pts[i][0] > keep:
        front.append(bracket(pts[i][0], pts[i][1] + 3, rng.uniform(9, 14), rng, flip=rng.choice([-1, 1])))
    if ferns:
        for _ in range(rng.randint(3, 5)):
            i = rng.randrange(2, n - 6)
            x, y = pts[i]
            front.append(frond(x, y - 5, -math.pi / 2 + rng.uniform(-0.9, 0.9), rng.uniform(26, 44), rng, gravity=0.05, scale=0.55))
    return "".join(back) + "".join(mid) + "".join(front)


def bramble_top(W, H, rng, side="right", keep=210, canes=3):
    """Bramble arching over the corner: thorny red-brown canes, leaves in
    threes, blackberries at every stage and a few white flowers."""
    dirn = -1 if side == "right" else 1
    x0 = W - 6 if side == "right" else 6
    back, mid, front = [], [], []
    for c in range(canes):
        L = W * rng.uniform(0.3, 0.5)
        h0 = inward(side, -rng.uniform(0.3, 0.55))  # up and in
        n = int(L / 4)
        bend = dirn * rng.uniform(0.018, 0.03)  # arching over and down
        pts = turtle(x0 + dirn * rng.uniform(0, 26), E + rng.uniform(14, 34), h0, n, 4, bend=bend, wander=0.03, rng=rng)
        pts = [(x, max(3, min(y, E + 58))) for x, y in pts]
        col = rng.choice(["#6b2f2a", "#5e3326", "#73392c"])
        mid.append(stem(pts, 3.4, 1.1, col, rng))
        # thorns, raked back
        td = []
        for i in range(3, len(pts) - 1, 2):
            h = heading(pts, i)
            sdn = rng.choice([-1, 1])
            nx, ny = -math.sin(h) * sdn, math.cos(h) * sdn
            w = 1.7 * (1 - i / len(pts)) + 0.6
            bx, by = pts[i][0] + nx * w, pts[i][1] + ny * w
            tx, ty = bx + nx * 2.6 - math.cos(h) * 2.2, by + ny * 2.6 - math.sin(h) * 2.2
            td.append(((bx - math.cos(h) * 1.2, by - math.sin(h) * 1.2), (tx, ty), (bx + math.cos(h) * 1.2, by + math.sin(h) * 1.2)))
        mid.append('<path d="%s" fill="#c9907e"/>' % tri_d(td))
        # leaves in threes
        for i in range(4, len(pts) - 2, rng.randint(4, 6)):
            x, y = pts[i]
            if x < keep and y > E - 4:
                continue
            a = heading(pts, i) + rng.choice([-1, 1]) * rng.uniform(0.6, 1.3)
            a += 0.3 * ((math.pi / 2 - a + math.pi) % TAU - math.pi)
            pl = rng.uniform(6, 11)
            px, py = x + pl * math.cos(a), y + pl * math.sin(a)
            back.append('<path d="M%s %sL%s %s" stroke="%s" stroke-width="1"/>' % (f(x), f(y), f(px), f(py), col))
            tint = rng.random()
            for da, sc in ((0, 1.0), (-0.75, 0.82), (0.75, 0.82)):
                fill = rng.choice(["#2c5a2a", "#356a30", "#2a4f26", "#3f6f34", "#46783a"]) if tint > 0.15 else rng.choice(["#7a3a2e", "#8a4030", "#6a4a2a"])
                back.append(blade_leaf(px, py, a + da, 21 * sc, 8.5 * sc, rng, fill, teeth=1.0, tip=0.6))
        # fruit and flowers towards the tip
        tip = pts[-1]
        for k in range(rng.randint(3, 6)):
            fx = tip[0] + rng.uniform(-9, 9) - dirn * k * 3
            fy = tip[1] + rng.uniform(3, 14)
            if fx < keep:
                continue
            front.append('<path d="M%s %sL%s %s" stroke="#4f6b2e" stroke-width=".8"/>' % (f(tip[0]), f(tip[1]), f(fx), f(fy - 3)))
            front.append(blackberry(fx, fy, rng, r=rng.uniform(3.6, 4.8), ripe=rng.random()))
        for _ in range(rng.randint(0, 2)):
            i = rng.randrange(len(pts) // 2, len(pts))
            if pts[i][0] > keep:
                front.append(bramble_flower(pts[i][0] + rng.uniform(-6, 6), pts[i][1] + rng.uniform(4, 10), rng))
        i = rng.randrange(len(pts) // 3, len(pts))
        if pts[i][0] > keep and pts[i][1] > E - 6:
            back.insert(0, usnea(pts[i][0], pts[i][1] + 2, rng, rng.randint(6, 12), rng.uniform(16, 34), spread=6))
    return "".join(back) + "".join(mid) + "".join(front)


def fern_top(W, H, rng, side="right", keep=210, fronds=7):
    """Ferns spilling over the top edge from a cushion of moss on the corner:
    long fronds arching down, a couple of fiddleheads still curled, lichen
    hanging under them."""
    dirn = -1 if side == "right" else 1
    x0 = W - 30 if side == "right" else 30
    back, front = [], []
    for k in range(fronds):
        ox = x0 + dirn * rng.uniform(-10, 90)
        a = inward(side, -rng.uniform(-0.3, 1.1))
        L = rng.uniform(60, 135)
        back.append(frond(ox, E + rng.uniform(-2, 4), a, L, rng, gravity=rng.uniform(0.03, 0.065), scale=rng.uniform(0.75, 1.05)))
    # one or two thrown back over the edge the other way
    for _ in range(rng.randint(1, 2)):
        ox = x0 + dirn * rng.uniform(0, 50)
        back.append(frond(ox, E + 2, inward("left" if side == "right" else "right", -rng.uniform(0.6, 1.0)), rng.uniform(40, 70), rng, gravity=0.06, scale=0.7))
    for _ in range(2):
        front.append(fiddlehead(x0 + dirn * rng.uniform(5, 70), E + 1, rng, h=rng.uniform(10, 16)))
    clump = moss_mound(x0 + dirn * 40, E + 5, 120, 10, rng, sporophytes=4)
    moss = "".join(usnea(x0 + dirn * rng.uniform(20, 110), E + 6, rng, rng.randint(6, 12), rng.uniform(16, 36), spread=8)
                   for _ in range(2))
    return moss + "".join(back) + clump + "".join(front)


def oak_top(W, H, rng, side="right", keep=210, reach=0.42, autumn=0.35):
    """An oak twig over the corner: lobed leaves, some turned, acorns in
    their cups, lichen on the bark."""
    dirn = -1 if side == "right" else 1
    x0 = W - 4 if side == "right" else 4
    main = turtle(x0, E - 4, inward(side, rng.uniform(0.0, 0.15)), int(W * reach / 4), 4, wander=0.07, rng=rng)
    main = [(x, max(5, min(y, E + 22))) for x, y in main]
    twigs = [(main, 5.0, 1.3)]
    for _ in range(rng.randint(2, 3)):
        i = rng.randrange(len(main) // 4, len(main) - 2)
        a = heading(main, i) + rng.choice([-1, 1]) * rng.uniform(0.5, 1.0)
        tw = turtle(main[i][0], main[i][1], a, rng.randint(5, 10), 4, wander=0.1, gravity=0.03, rng=rng)
        twigs.append(([(x, max(5, y)) for x, y in tw], 2.2, 0.8))
    back, mid, front = [], [], []
    for tw, w0, w1 in twigs:
        mid.append(stem(tw, w0, w1, "#5a4636", rng, knob=0.25))
        mid.append(bark_lines(tw, w0, w1, rng, "#2a1f15", n=len(tw) // 3))
        for k in range(2, len(tw), rng.randint(3, 4)):
            x, y = tw[k]
            if x < keep and y > E - 2:
                continue
            for _ in range(rng.randint(1, 2)):
                a = math.pi / 2 + rng.uniform(-1.3, 1.3)
                col = rng.choice(AUTUMN + ["#8a6a2a", "#a07a30"]) if rng.random() < autumn else rng.choice(["#3f6f2e", "#4a7a32", "#365f28", "#557f36"])
                back.append(oak_leaf(x, y, a, rng.uniform(24, 36), rng, col))
    for _ in range(rng.randint(2, 4)):
        tw = rng.choice(twigs)[0]
        x, y = tw[rng.randrange(len(tw) // 3, len(tw))]
        if x < keep:
            continue
        a = math.pi / 2 + rng.uniform(-0.5, 0.5)
        front.append(acorn(x, y + 3, a, rng, s=rng.uniform(1.0, 1.3)))
        if rng.random() < 0.6:
            front.append(acorn(x + rng.uniform(4, 7), y + 4, a + 0.5, rng, s=rng.uniform(0.9, 1.15)))
    lich = "".join('<circle cx="%s" cy="%s" r="%s" fill="%s" opacity=".75"/>' % (
        f(p[0]), f(p[1]), f(rng.uniform(0.8, 1.6)), rng.choice(LICHEN)) for p in rng.sample(main, min(len(main), 8)))
    for _ in range(rng.randint(2, 3)):
        x, y = main[rng.randrange(len(main) // 5, len(main))]
        if x > keep:
            back.insert(0, usnea(x, y + 2, rng, rng.randint(8, 16), rng.uniform(18, 40), spread=7))
    return "".join(back) + "".join(mid) + lich + "".join(front)




def lingonberry(x, y, rng):
    """A lingonberry sprig: a short woody stem, small glossy oval leaves and
    a few red berries."""
    pts = turtle(x, y, -math.pi / 2 + rng.uniform(-0.5, 0.5), 5, 2.2, wander=0.15, rng=rng)
    out = ['<path d="%s" stroke="#4a3a24" stroke-width=".9" fill="none"/>' % smooth_d(pts)]
    for k in range(1, len(pts)):
        for sd in (1, -1):
            a = heading(pts, k) + sd * rng.uniform(0.7, 1.3)
            out.append(blade_leaf(pts[k][0], pts[k][1], a, 5.2, 2.3, rng, rng.choice(["#1f4a26", "#25552c", "#2c5f30"]), vein=False, tip=0.3))
    for _ in range(rng.randint(2, 4)):
        bx, by = pts[-1][0] + rng.uniform(-3, 3), pts[-1][1] + rng.uniform(-1, 4)
        out.append('<circle cx="%s" cy="%s" r="%s" fill="url(#berry)"/><circle cx="%s" cy="%s" r=".5" fill="#ffe2cc"/>' % (
            f(bx), f(by), f(rng.uniform(1.5, 2.1)), f(bx - 0.6), f(by - 0.6)))
    return "".join(out)


# ════════════════════════════════════════════════════════════════════════════
# The tendril under each card's title — the page's plant, small, fading out.
# ════════════════════════════════════════════════════════════════════════════
def rule(kind, rng, W=320, H=22):
    y0 = 13
    pts = [(x, y0 + 2.2 * math.sin(x / rng.uniform(17, 26) + rng.uniform(0, TAU)) + 1.2 * math.sin(x / 7.3)) for x in range(2, W - 30, 6)]
    pts = catmull(pts, 3)
    out = []
    if kind == "terminal":
        out.append(stem(pts, 2.6, 0.4, "#6b4a2e", hi=False))
        for _ in range(16):
            i = rng.randrange(2, len(pts) - 2)
            rl = turtle(pts[i][0], pts[i][1], heading(pts, i) + rng.choice([-1, 1]) * rng.uniform(0.6, 1.4), rng.randint(2, 4), 1.6, wander=0.6, rng=rng)
            out.append('<path d="%s" stroke="#8a6a46" stroke-width=".5" fill="none"/>' % smooth_d(rl))
    elif kind == "power":
        out.append(stem(pts, 2.2, 0.6, "#6b2f2a", hi=False))
        td = []
        for i in range(3, len(pts) - 3, 4):
            h = heading(pts, i)
            sd = 1 if (i // 4) % 2 else -1
            nx, ny = -math.sin(h) * sd, math.cos(h) * sd
            bx, by = pts[i][0] + nx, pts[i][1] + ny
            td.append(((bx - math.cos(h), by - math.sin(h)), (bx + nx * 2.2 - math.cos(h) * 1.8, by + ny * 2.2 - math.sin(h) * 1.8), (bx + math.cos(h), by + math.sin(h))))
        out.append('<path d="%s" fill="#c9907e"/>' % tri_d(td))
        for i in range(10, len(pts) - 10, rng.randint(16, 22)):
            a = heading(pts, i) + rng.choice([-1, 1]) * 1.1
            out.append(blade_leaf(pts[i][0], pts[i][1], a, 8, 3.4, rng, rng.choice(["#2c5a2a", "#356a30", "#6b3a2e"]), teeth=0.5, tip=0.6))
        i = rng.randrange(len(pts) // 4, len(pts) // 2)
        out.append(blackberry(pts[i][0], pts[i][1] + 3, rng, r=2.8, ripe=0.9))
    elif kind == "eclipse":
        out.append(stem(pts, 1.6, 0.4, "#3f6a30", hi=False))
        for i in range(2, len(pts) - 1, 2):
            t = i / len(pts)
            for sd in (1, -1):
                a = heading(pts, i) + sd * (1.15 - 0.3 * t)
                L = 6.5 * (1 - 0.55 * t)
                out.append(blade_leaf(pts[i][0], pts[i][1], a, L, L * 0.24, rng, rng.choice(FERN), vein=False))
    else:
        out.append(stem(pts, 1.8, 0.4, "#4a3a22", hi=False))
        i, sd = 3, 1
        while i < len(pts) - 2:
            a = heading(pts, i) + sd * rng.uniform(0.9, 1.6)
            out.append(ivy_leaf(pts[i][0], pts[i][1], a, 7.5 * (1 - 0.4 * i / len(pts)) * rng.uniform(0.8, 1.15), rng,
                                rng.choice(IVY + IVY_YOUNG), lobed=rng.uniform(0.7, 1)))
            i += rng.randint(5, 9)
            sd = -sd
        i = rng.randrange(len(pts) // 3, len(pts) // 2)
        out.append(rowan_berries(pts[i][0], pts[i][1], rng, n=6, spread=3.5, r0=1.6))
    for _ in range(2):
        i = rng.randrange(len(pts) // 3, len(pts) - 2)
        out.append(tendril(pts[i][0], pts[i][1], heading(pts, i) + rng.uniform(-1.2, 1.2), rng, size=6,
                           col="#6a4a30" if kind == "terminal" else "#3d7a34", w=0.6))
    mask = ('<mask id="fade"><rect width="%d" height="%d" fill="url(#fadeg)"/></mask>'
            '<linearGradient id="fadeg"><stop offset=".45" stop-color="#fff"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>') % (W, H)
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><!-- The tendril under a card title. '
            'Generated by growth.py — see its header. -->%s<defs>%s</defs><g mask="url(#fade)">%s</g></svg>') % (W, H, W, H, DEFS, mask, "".join(out))


# ════════════════════════════════════════════════════════════════════════════
# The growth along the navigation: one seamless strip a page, NW wide (so its
# repeat is never seen on one screen), resting on the bar's foot at y = NE and
# hanging below it.
# ════════════════════════════════════════════════════════════════════════════
NW, NH, NE = 2400, 64, 14


def periodic(rng, base, amp, terms=7, kmin=2, kmax=19):
    """y(x) for 0 ≤ x ≤ NW that wraps seamlessly: a sum of sines whose
    periods all divide the strip."""
    ks = rng.sample(range(kmin, kmax), terms)
    ws = [(k, amp * rng.uniform(0.3, 1.0) / (1 + 0.15 * k), rng.uniform(0, TAU)) for k in ks]
    return lambda x: base + sum(a * math.sin(TAU * k * x / NW + ph) for k, a, ph in ws)


def strip_path(yf, step=8, pad=60):
    return catmull([(x, yf(x)) for x in range(-pad, NW + pad + 1, step)], 3)


def wrapped(items):
    """Elements near either end drawn again one strip over, so the seam is
    invisible."""
    out = []
    for x, el in items:
        out.append(el)
        if x < 160:
            out.append('<g transform="translate(%d 0)">%s</g>' % (NW, el))
        if x > NW - 160:
            out.append('<g transform="translate(%d 0)">%s</g>' % (-NW, el))
    return "".join(out)


def nav_asgard(rng):
    """Ivy, two stems winding along the bar, shoots and old-man's-beard
    hanging from it, now and then a bunch of rowan berries."""
    back, mid, front = [], [], []
    for vi, (amp, w) in enumerate(((5, 3.6), (7, 2.0))):
        yf = periodic(rng, NE + 1 + vi * 2, amp)
        pts = strip_path(yf)
        mid.append((NW / 2, stem(pts, w, w, "#4a3a22" if vi == 0 else "#4f5a2a", rng, knob=0.2)))
        i, sd = 2, 1
        while i < len(pts) - 2:
            x, y = pts[i]
            if 0 <= x < NW:
                a = heading(pts, i) + sd * rng.uniform(0.8, 2.0)
                if sd < 0:
                    a += 0.4 * ((math.pi / 2 - a + math.pi) % TAU - math.pi)
                L = rng.uniform(10, 21) * (1 if vi == 0 else 0.8)
                if not (sd > 0 and y - L * 0.8 < 0):
                    front.append((x, leaf_on((x, y), a, L, rng, autumn=0.06, young=0.25)))
            i += rng.randint(4, 8)
            sd = -sd if rng.random() < 0.75 else sd
    yf = periodic(rng, NE + 1, 5)
    for _ in range(26):
        x = rng.uniform(0, NW)
        y = yf(x)
        r = rng.random()
        if r < 0.45:
            back.append((x, usnea(x, y + 2, rng, rng.randint(6, 14), rng.uniform(14, NH - y - 6), spread=7, sway=1.4)))
        elif r < 0.8:
            sp = turtle(x, y, math.pi / 2 + rng.uniform(-0.5, 0.5), rng.randint(6, 14), 3, gravity=0.06, wander=0.14, rng=rng)
            sp = [(px, min(py, NH - 4)) for px, py in sp]
            el = stem(sp, 1.5, 0.5, "#3f5a2a", hi=False)
            for k in range(2, len(sp), 3):
                el += leaf_on(sp[k], heading(sp, k) + rng.choice([-1, 1]) * rng.uniform(0.7, 1.3), rng.uniform(7, 11), rng, young=0.4)
            back.append((x, el))
        else:
            front.append((x, rowan_berries(x, y + 1, rng, n=rng.randint(8, 13), spread=7, r0=2.3)))
    for _ in range(30):
        x = rng.uniform(0, NW)
        front.append((x, tendril(x, yf(x), rng.uniform(-math.pi, math.pi), rng, size=rng.uniform(7, 12))))
    return wrapped(back) + wrapped(mid) + wrapped(front)


def nav_eclipse(rng):
    """The night wood: a long mossy bough along the bar, curtains of lichen
    under it, polypody ferns along its back, foxfire toadstools glowing."""
    yf = periodic(rng, NE + 3, 4)
    pts = strip_path(yf)
    back, mid, front = [], [], []
    mid.append((NW / 2, stem(pts, 8, 8, "#3f3022", rng, knob=0.3)))
    mid.append((NW / 2, bark_lines(pts, 8, 8, rng, "#1e160d", n=len(pts) // 3)))
    x = 0.0
    while x < NW:
        y = yf(x)
        back.append((x, usnea(x, y + 3, rng, rng.randint(4, 12), rng.uniform(10, NH - y - 4), spread=rng.uniform(4, 10), sway=1.6)))
        x += rng.uniform(30, 90)
    x = 0.0
    while x < NW:
        w = rng.uniform(16, 44)
        front.append((x, moss_mound(x, yf(x) - 2.5, w, rng.uniform(3, 6), rng, sporophytes=rng.randint(0, 3))))
        x += w + rng.uniform(10, 70)
    for _ in range(16):
        x = rng.uniform(0, NW)
        front.append((x, frond(x, yf(x) - 3, -math.pi / 2 + rng.uniform(-1.2, 1.2), rng.uniform(14, 24), rng, gravity=0.03, scale=0.45)))
    for _ in range(9):
        x = rng.uniform(0, NW)
        front.append((x, toadstool(x, yf(x) - 2, rng.uniform(8, 11), rng, lean=rng.uniform(-0.2, 0.2), glow=True)))
    for _ in range(18):
        x = rng.uniform(0, NW)
        front.append((x, bonnet(x, yf(x) - 2, rng.uniform(5, 8), rng, lean=rng.uniform(-0.3, 0.3))))
    return wrapped(back) + wrapped(mid) + wrapped(front)


def nav_power(rng):
    """Bramble: thorny canes looping along and under the bar, leaves in
    threes, blackberries at every stage, white flowers."""
    back, mid, front = [], [], []
    for vi in range(3):
        yf = periodic(rng, NE + 2 + vi * 3, 9 - vi * 2, kmin=3, kmax=24)
        pts = strip_path(yf)
        col = rng.choice(["#6b2f2a", "#5e3326", "#73392c"])
        w = 2.8 - vi * 0.6
        mid.append((NW / 2, stem(pts, w, w, col, rng)))
        td = []
        for i in range(2, len(pts) - 2, 3):
            h = heading(pts, i)
            sd = rng.choice([-1, 1])
            nx, ny = -math.sin(h) * sd, math.cos(h) * sd
            bx, by = pts[i][0] + nx * w / 2, pts[i][1] + ny * w / 2
            td.append(((bx - math.cos(h), by - math.sin(h)), (bx + nx * 2.6 - math.cos(h) * 2.2, by + ny * 2.6 - math.sin(h) * 2.2), (bx + math.cos(h), by + math.sin(h))))
        mid.append((NW / 2, '<path d="%s" fill="#c9907e"/>' % tri_d(td)))
        for i in range(3, len(pts) - 3, rng.randint(12, 18)):
            x, y = pts[i]
            if not 0 <= x < NW:
                continue
            a = heading(pts, i) + rng.choice([-1, 1]) * rng.uniform(0.6, 1.3)
            a += 0.35 * ((math.pi / 2 - a + math.pi) % TAU - math.pi)
            px, py = x + 6 * math.cos(a), y + 6 * math.sin(a)
            el = '<path d="M%s %sL%s %s" stroke="%s" stroke-width="1"/>' % (f(x), f(y), f(px), f(py), col)
            tint = rng.random()
            for da, sc in ((0, 1.0), (-0.75, 0.82), (0.75, 0.82)):
                fill = rng.choice(["#2c5a2a", "#356a30", "#2a4f26", "#3f6f34"]) if tint > 0.15 else rng.choice(["#7a3a2e", "#8a4030"])
                el += blade_leaf(px, py, a + da, 15 * sc, 6 * sc, rng, fill, teeth=0.8, tip=0.6)
            back.append((x, el))
    yf = periodic(rng, NE + 4, 6)
    for _ in range(26):
        x = rng.uniform(0, NW)
        y = yf(x) + rng.uniform(2, 14)
        front.append((x, blackberry(x, min(y, NH - 6), rng, r=rng.uniform(3.2, 4.2), ripe=rng.random())))
    for _ in range(14):
        x = rng.uniform(0, NW)
        front.append((x, bramble_flower(x, yf(x) + rng.uniform(-2, 8), rng, r=rng.uniform(4.5, 6))))
    return wrapped(back) + wrapped(mid) + wrapped(front)


def nav_terminal(rng):
    """Roots: roots threading along under the bar, moss on them, rootlets
    trailing."""
    back, mid, front = [], [], []
    for vi in range(3):
        yf = periodic(rng, NE + vi * 3, 6, kmin=3, kmax=22)
        pts = strip_path(yf)
        w = [4.2, 2.6, 1.8][vi]
        mid.append((NW / 2, stem(pts, w, w, rng.choice(["#6b4a2e", "#5a3d26", "#7a5636"]), rng, knob=0.3)))
    yf = periodic(rng, NE + 2, 5)
    for _ in range(70):
        x = rng.uniform(0, NW)
        rl = turtle(x, yf(x), math.pi / 2 + rng.uniform(-0.8, 0.8), rng.randint(5, 16), 2.6, wander=0.35, gravity=0.06, rng=rng)
        rl = [(px, min(py, NH - 3)) for px, py in rl]
        back.append((x, stem(rl, rng.uniform(1.0, 2.2), 0.3, "#7a5a3a", hi=False)))
    for _ in range(16):
        x = rng.uniform(0, NW)
        y = yf(x)
        w = rng.uniform(14, 34)
        front.append((x, moss_mound(x, y + 1, w, rng.uniform(3, 5), rng, sporophytes=rng.randint(0, 2))))
    return wrapped(back) + wrapped(mid) + wrapped(front)


NAVS = {"asgard": nav_asgard, "eclipse": nav_eclipse, "power": nav_power, "terminal": nav_terminal}


def nav(page, rng):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><!-- The growth along the navigation '
            'on the %s page; tiles seamlessly left-right. Generated by growth.py — see its header. -->%s<g filter="url(#sh)">%s</g></svg>') % (
            NW, NH, NW, NH, page, DEFS, NAVS[page](rng))


# ════════════════════════════════════════════════════════════════════════════
# The forest along the foot of each page. TW × TH, tiles seamlessly; drawn
# far to near: sky, a ridge furred with trees, mist, the far wood, mist, the
# middle wood, the near trees, and the forest floor.
# ════════════════════════════════════════════════════════════════════════════
TW, TH = 1600, 400


def spruce(x, base, h, w, rng, tier=6.0):
    """A spruce silhouette with a ragged edge: tier on tier of drooping
    branches, each tip with a smaller one beside it."""
    top = base - h
    tiers = max(6, int(h / tier))
    R, L = [], []
    for sd, out in ((1, R), (-1, L)):
        for i in range(tiers):
            t = (i + 0.6) / tiers
            y = top + h * 0.05 + t * h * 0.88
            half = w * (0.05 + 0.95 * t ** 0.92) * rng.uniform(0.62, 1.08)
            droop = h * 0.01 + half * 0.2
            out.append((x + sd * half * rng.uniform(0.18, 0.42), y - droop * 0.2))
            out.append((x + sd * half * rng.uniform(0.62, 0.8), y + droop * 0.35))
            out.append((x + sd * half, y + droop))
            out.append((x + sd * half * rng.uniform(0.74, 0.9), y + droop * 0.8))
    return poly_d([(x, top - h * 0.04)] + R + [(x + w * 0.06, base), (x - w * 0.06, base)] + L[::-1])


def blob_crown(cx, cy, rx, ry, rng, cols, n=40, rmin=4, rmax=10, lit=None):
    """A broadleaf crown: many overlapping leaf-clumps, dark inside, the edge
    toward the light lifted."""
    out = []
    for _ in range(n):
        a = rng.uniform(0, TAU)
        d = math.sqrt(rng.random())
        x, y = cx + rx * d * math.cos(a), cy + ry * d * math.sin(a)
        r = rng.uniform(rmin, rmax) * (1.1 - 0.4 * d)
        out.append('<circle cx="%s" cy="%s" r="%s" fill="%s"/>' % (f(x), f(y), f(r), rng.choice(cols)))
        if lit and math.cos(a - lit) > 0.55 and d > 0.6:
            out.append('<circle cx="%s" cy="%s" r="%s" fill="%s" opacity=".35"/>' % (f(x + math.cos(lit) * r * 0.3), f(y + math.sin(lit) * r * 0.3), f(r * 0.6), light(cols[0], 0.3)))
    return "".join(out)


def birch(x, base, h, rng, bark="#9b978a", crown=("#2f4a2a", "#38552e", "#2a4226")):
    """A birch: a slim pale trunk with black lenticels and scars, a light,
    ragged crown."""
    out = []
    pts = turtle(x, base, -math.pi / 2 + rng.uniform(-0.05, 0.05), int(h / 6), 6, wander=0.03, rng=rng)
    out.append(stem(pts, h * 0.035, h * 0.012, bark, hi=False))
    d = ""
    for _ in range(int(h / 6)):
        i = rng.randrange(0, len(pts) - 2)
        t = i / len(pts)
        w = h * (0.035 - 0.023 * t) / 2
        px, py = pts[i]
        l = rng.uniform(0.3, 1.0) * w * 2
        d += "M%s %sh%s" % (f(px - w + rng.uniform(0, w)), f(py), f(l))
    out.append('<path d="%s" stroke="#1a1a16" stroke-width="%s" fill="none" opacity=".85"/>' % (d, f(max(0.8, h * 0.006))))
    tx, ty = pts[-1]
    out.append(blob_crown(tx, ty + h * 0.12, h * 0.16, h * 0.22, rng, list(crown), n=int(h / 7), rmin=4, rmax=8))
    return "".join(out)


def ridge(rng, base, amp, fill, fuzz=True):
    """A far ridge, its line furred with tiny trees."""
    yf_ = periodic_t(rng, base, amp)
    pts = [(x, yf_(x)) for x in range(0, TW + 1, 8)]
    d = poly_d([(0, TH)] + pts + [(TW, TH)])
    out = ['<path d="%s" fill="%s"/>' % (d, fill)]
    if fuzz:
        td = []
        for x in range(0, TW, 5):
            y = yf_(x) + 1
            h = rng.uniform(4, 11)
            td.append(((x - h * 0.28, y), (x, y - h), (x + h * 0.28, y)))
        out.append('<path d="%s" fill="%s"/>' % (tri_d(td), fill))
    return "".join(out)


def periodic_t(rng, base, amp, terms=6):
    ks = rng.sample(range(1, 12), terms)
    ws = [(k, amp * rng.uniform(0.3, 1.0) / (1 + 0.2 * k), rng.uniform(0, TAU)) for k in ks]
    return lambda x: base + sum(a * math.sin(TAU * k * x / TW + ph) for k, a, ph in ws)


def twrap(items):
    out = []
    for x, el in items:
        out.append(el)
        if x < 140:
            out.append('<g transform="translate(%d 0)">%s</g>' % (TW, el))
        if x > TW - 140:
            out.append('<g transform="translate(%d 0)">%s</g>' % (-TW, el))
    return "".join(out)


def mist(y, h, col, op):
    return '<rect x="0" y="%s" width="%d" height="%s" fill="%s" opacity="%s"/>' % (f(y), TW, f(h), col, op)


def forest_floor(rng, page, col_ground="#1a130c"):
    """The near ground: an uneven bank of earth, moss along its top, grass,
    ferns, stones capped with moss, a fallen log (toadstools on it; glowing in
    the night wood), lingonberries or brambles."""
    yf_ = periodic_t(rng, TH - 30, 7)
    items = []
    top = [(x, yf_(x)) for x in range(0, TW + 1, 6)]
    ground = '<path d="%s" fill="url(#tground)"/>' % poly_d([(0, TH)] + top + [(TW, TH)])
    for x in range(0, TW, 11):
        items.append((x, grass(x + rng.uniform(-4, 4), yf_(x) + 2, rng, n=rng.randint(4, 9), h=rng.uniform(8, 18),
                                palette=["#1f3a1c", "#264522", "#2d5026", "#1a3018"])))
    for _ in range(int(TW / 60)):
        x = rng.uniform(0, TW)
        items.append((x, moss_mound(x, yf_(x) + 3, rng.uniform(20, 50), rng.uniform(4, 8), rng,
                                     palette=["#2e4a1e", "#3a5a24", "#456628", "#33521f"], dots=0.35)))
    for _ in range(11):
        x = rng.uniform(0, TW)
        col = rng.choice(["#1f3c1b", "#24461f", "#1b351a"])
        for _ in range(rng.randint(3, 6)):
            items.append((x, frond_silhouette(x + rng.uniform(-6, 6), yf_(x) + 3, -math.pi / 2 + rng.uniform(-1.1, 1.1), rng.uniform(24, 48), rng, col)))
    for _ in range(6):
        x = rng.uniform(0, TW)
        w = rng.uniform(16, 34)
        y = yf_(x) + 4
        rock = []
        for k in range(13):
            a = math.pi + math.pi * k / 12
            rock.append((x + w / 2 * math.cos(a) * rng.uniform(0.92, 1.05), y + w * 0.55 * math.sin(a) * rng.uniform(0.85, 1.05)))
        el = '<path d="%s" fill="%s"/>' % (poly_d(rock + [(x + w / 2, y + 4), (x - w / 2, y + 4)]), rng.choice(["#2f302b", "#34352f", "#2a2b26"]))
        el += moss_mound(x - w * 0.08, y - w * 0.36, w * 0.8, w * 0.18, rng, palette=["#3a5a24", "#456628", "#4f702b"], dots=0.8)
        items.append((x, el))
    # the fallen log
    lx = rng.uniform(300, TW - 300)
    ly = yf_(lx) - 2
    lw = rng.uniform(150, 220)
    logp = [(lx - lw / 2 + k * lw / 20, ly + 1.5 * math.sin(k)) for k in range(21)]
    el = stem(logp, 15, 12, "#3a2a1c", rng, knob=0.2) + bark_lines(logp, 15, 12, rng, "#1c140c", n=24)
    el += '<ellipse cx="%s" cy="%s" rx="6" ry="7.5" fill="#5a4330" stroke="#2a1e12"/><ellipse cx="%s" cy="%s" rx="3" ry="4" fill="none" stroke="#3a2a1c"/>' % (
        f(logp[-1][0]), f(logp[-1][1]), f(logp[-1][0]), f(logp[-1][1]))
    for k in range(0, 20, 3):
        el += moss_mound(logp[k][0], logp[k][1] - 5, rng.uniform(16, 28), rng.uniform(3, 6), rng, palette=["#3a5a24", "#456628", "#4f702b"], sporophytes=1)
    glow = page == "eclipse"
    for _ in range(rng.randint(3, 5)):
        k = rng.randrange(2, 18)
        el += toadstool(logp[k][0] + rng.uniform(-4, 4), logp[k][1] - 6, rng.uniform(9, 15), rng, lean=rng.uniform(-0.2, 0.2), glow=glow)
    for _ in range(rng.randint(4, 7)):
        k = rng.randrange(1, 19)
        el += bonnet(logp[k][0], logp[k][1] - 6, rng.uniform(5, 9), rng, lean=rng.uniform(-0.3, 0.3))
    if rng.random() < 0.9:
        el += bracket(logp[12][0], logp[12][1] + 2, 9, rng)
    items.append((lx, el))
    for _ in range(14 if page != "power" else 6):
        x = rng.uniform(0, TW)
        items.append((x, lingonberry(x, yf_(x) + 2, rng)))
    if page == "power":
        for _ in range(7):
            x = rng.uniform(0, TW)
            y = yf_(x)
            el = ""
            for c in range(3):
                pts = turtle(x + rng.uniform(-10, 10), y + 3, -math.pi / 2 + rng.uniform(-0.9, 0.9), rng.randint(8, 14), 4, bend=rng.choice([-1, 1]) * 0.05, rng=rng)
                el += stem(pts, 2.4, 0.8, "#4e2622", hi=False)
                for k in range(2, len(pts), 3):
                    el += blade_leaf(pts[k][0], pts[k][1], heading(pts, k) + rng.choice([-1, 1]) * 1.0, 10, 4.4, rng, rng.choice(["#1f3c1b", "#24461f", "#4a2a20"]), teeth=0.6)
                el += blackberry(pts[-1][0], pts[-1][1] + 4, rng, r=3.2, ripe=rng.random())
            items.append((x, el))
    return ground + twrap(items)


def treeline(page, rng):
    PREC[0] = 0
    try:
        return _treeline(page, rng)
    finally:
        PREC[0] = 1


def _treeline(page, rng):
    P = {
        "asgard":   dict(sky=None, ridge="#33292a", far="#26302b", mid="#18241d", near="#0e1611", mistc="#c62f27", mistop=".05", birches=3, rowans=4, oak=False),
        "eclipse":  dict(sky="eclipse", ridge="#1d2622", far="#18211c", mid="#111a15", near="#0a110d", mistc="#a8f0a0", mistop=".045", birches=2, rowans=0, oak=False),
        "power":    dict(sky=None, ridge="#2c2a22", far="#232c22", mid="#17221a", near="#0e1610", mistc="#e0b065", mistop=".04", birches=1, rowans=2, oak=True),
        "terminal": dict(sky=None, ridge="#22282a", far="#1f2a26", mid="#152019", near="#0c130f", mistc="#9fbfb6", mistop=".05", birches=2, rowans=1, oak=False),
    }[page]
    out = []
    if P["sky"] == "eclipse":
        st = "".join('<circle cx="%s" cy="%s" r="%s" fill="#e8f0e4" opacity="%s"/>' % (
            f(rng.uniform(0, TW)), f(rng.uniform(0, 200)), f(rng.uniform(0.4, 1.1)), f(rng.uniform(0.25, 0.8))) for _ in range(120))
        ex, ey = rng.uniform(1050, 1300), 120
        out.append(st)
        out.append('<circle cx="%s" cy="%s" r="95" fill="url(#corona)"/>' % (f(ex), f(ey)))
        out.append('<circle cx="%s" cy="%s" r="36" fill="none" stroke="#ff7a5c" stroke-width="2.5" opacity=".75" filter="url(#soft)"/>' % (f(ex), f(ey)))
        out.append('<circle cx="%s" cy="%s" r="35" fill="#070a08"/>' % (f(ex), f(ey)))
        out.append('<circle cx="%s" cy="%s" r="2.6" fill="#ffd8c8" opacity=".9" filter="url(#soft)"/>' % (f(ex + 26), f(ey - 23)))
    out.append(ridge(rng, 205, 26, P["ridge"]))
    out.append(mist(190, 70, P["mistc"], P["mistop"]))
    # far wood
    items = []
    for i in range(46):
        x = (i + rng.uniform(-0.4, 0.4)) * TW / 46
        h = rng.uniform(80, 140)
        items.append((x, '<path d="%s" fill="%s"/>' % (spruce(x, TH - 30, h, h * 0.3, rng, tier=12), P["far"])))
    out.append(twrap(items))
    out.append(mist(TH - 150, 80, P["mistc"], P["mistop"]))
    # middle wood
    items = []
    for i in range(30):
        x = (i + rng.uniform(-0.4, 0.4)) * TW / 30
        h = rng.uniform(130, 220)
        items.append((x, '<path d="%s" fill="%s"/>' % (spruce(x, TH - 24, h, h * 0.31, rng, tier=9), P["mid"])))
    for _ in range(P["birches"]):
        x = rng.uniform(60, TW - 60)
        items.append((x, birch(x, TH - 24, rng.uniform(150, 210), rng, bark="#5e5c55", crown=("#1f2f1f", "#24361f", "#1b2a1a"))))
    out.append(twrap(items))
    # near trees
    items = []
    for i in range(13):
        x = (i + rng.uniform(-0.35, 0.35)) * TW / 13
        h = rng.uniform(220, 340)
        items.append((x, '<path d="%s" fill="%s"/>' % (spruce(x, TH - 18, h, h * 0.33, rng, tier=7), P["near"])))
    for _ in range(P["rowans"]):
        x = rng.uniform(80, TW - 80)
        h = rng.uniform(170, 230)
        tr = turtle(x, TH - 18, -math.pi / 2 + rng.uniform(-0.08, 0.08), int(h * 0.55 / 6), 6, wander=0.05, rng=rng)
        el = stem(tr, 7, 3, "#120d0a", hi=False)
        for _ in range(3):
            i = rng.randrange(len(tr) // 2, len(tr))
            br = turtle(tr[i][0], tr[i][1], -math.pi / 2 + rng.uniform(-1.0, 1.0), rng.randint(5, 9), 5, wander=0.1, rng=rng)
            el += stem(br, 3, 1, "#120d0a", hi=False)
        cx, cy = tr[-1][0], tr[-1][1] - h * 0.08
        el += blob_crown(cx, cy, h * 0.24, h * 0.2, rng, ["#13241a", "#172b1e", "#1b3121", "#10201a"], n=int(h / 3.2), rmin=5, rmax=11, lit=-2.4)
        bd = ""
        for _ in range(rng.randint(6, 9)):
            a = rng.uniform(0.1, math.pi - 0.1)
            bx, by = cx + h * 0.22 * math.cos(a) * rng.uniform(0.5, 1), cy + h * 0.18 * math.sin(a) * rng.uniform(0.4, 1)
            for _ in range(rng.randint(4, 8)):
                bd += '<circle cx="%s" cy="%s" r="%s"/>' % (f(bx + rng.uniform(-4, 4)), f(by + rng.uniform(-2, 4)), f(rng.uniform(1.3, 2.1)))
        el += '<g fill="url(#berry)" opacity=".9">%s</g>' % bd
        items.append((x, el))
    for _ in range(P["birches"] // 2 + 1):
        x = rng.uniform(60, TW - 60)
        items.append((x, birch(x, TH - 18, rng.uniform(230, 300), rng, bark="#8d897c", crown=("#1c2e1e", "#213522", "#18281a"))))
    if P["oak"]:
        x = rng.uniform(380, 700)
        h = 300
        tr = turtle(x, TH - 18, -math.pi / 2 + 0.05, 22, 7, wander=0.06, rng=rng)
        el = stem(tr, 34, 14, "#120d0a", rng, hi=False, knob=0.25)
        for _ in range(7):
            i = rng.randrange(len(tr) // 3, len(tr))
            br = turtle(tr[i][0], tr[i][1], -math.pi / 2 + rng.uniform(-1.4, 1.4), rng.randint(8, 16), 7, wander=0.18, rng=rng)
            el += stem(br, 10, 2, "#120d0a", hi=False)
        for sd in (-1, 1):
            for _ in range(3):
                rt = turtle(x + sd * 10, TH - 22, (0 if sd > 0 else math.pi) + rng.uniform(-0.3, 0.6) * sd, rng.randint(8, 16), 5, wander=0.2, gravity=0.06, rng=rng)
                el += stem(rt, 9, 1, "#160f0a", hi=False)
        el += blob_crown(x, TH - 18 - h * 0.78, h * 0.55, h * 0.3, rng, ["#13221a", "#162819", "#1a2e1c", "#11201a"], n=150, rmin=9, rmax=18, lit=-2.2)
        items.append((x, el))
    out.append(twrap(items))
    out.append(forest_floor(rng, page))
    defs = ('<defs>'
            '<linearGradient id="tground" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#14211a"/><stop offset="1" stop-color="#070b08"/></linearGradient>'
            '<radialGradient id="corona"><stop offset=".33" stop-color="#ff6a4a" stop-opacity=".55"/><stop offset=".45" stop-color="#c62f27" stop-opacity=".22"/><stop offset="1" stop-color="#c62f27" stop-opacity="0"/></radialGradient>'
            '<filter id="soft"><feGaussianBlur stdDeviation="2"/></filter>'
            '</defs>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" preserveAspectRatio="xMidYMax slice">'
            '<!-- The forest along the foot of the %s page; tiles seamlessly left-right. Generated by growth.py — see its header. -->'
            '%s%s%s</svg>') % (TW, TH, TW, TH, page, DEFS, defs, "".join(out))


# ════════════════════════════════════════════════════════════════════════════
# Section-heading glyphs, one a page.
# ════════════════════════════════════════════════════════════════════════════
GLYPHS = {
    # a rowan leaflet and three berries
    "asgard": ("<path d='M1.4 10.6C1.4 5.4 4.6 1.9 10.2.9c-.5 5.6-3.6 9.2-8.8 9.7z' fill='#4a9a44'/>"
               "<path d='M1.6 10.4 8.4 3.2' stroke='#1f5a2c' stroke-width='.8' fill='none'/>"
               "<circle cx='11.6' cy='10.4' r='2' fill='#e2412f'/><circle cx='8' cy='12.6' r='2.3' fill='#d6302a'/>"
               "<circle cx='11.3' cy='14' r='1.8' fill='#8f1d1d'/>"),
    # a fiddlehead, still coiled
    "eclipse": ("<path d='M4 15.5C4 11 3.6 8 5.2 5.2 6.6 2.8 10 2.4 11.4 4.4 12.6 6.2 11.4 8.6 9.3 8.6 7.6 8.6 7 7 8 6.1' "
                "fill='none' stroke='#5aa948' stroke-width='1.9' stroke-linecap='round'/>"
                "<path d='M4.3 12.5 2 11.2M4.2 10 1.8 8.4M4.6 7.6 2.6 5.8' stroke='#3f8f3c' stroke-width='1.2' stroke-linecap='round'/>"),
    # an acorn under an oak leaf
    "power": ("<path d='M8 1.2c1.6 1.4 3.6.8 4.4 2.4-1.4.6-.6 2.2-2 2.6-1-.4-1.8.4-2.6 0-.8.4-1.6-.4-2.6 0-1.4-.4-.6-2-2-2.6C4.2 2 6.4 2.6 8 1.2z' fill='#4a7a32'/>"
              "<path d='M8 1.5v5' stroke='#2e4f1f' stroke-width='.6'/>"
              "<path d='M4.6 9.8C4.5 13 6.2 15.4 8 15.6 9.8 15.4 11.5 13 11.4 9.8z' fill='#a07a3c'/>"
              "<path d='M3.8 10.4C3.6 8.2 5.6 7 8 7s4.4 1.2 4.2 3.4z' fill='#6b5232'/>"),
    # a toadstool
    "terminal": ("<path d='M6.6 9h2.8l.6 6.4H6z' fill='#efe6d2'/>"
                 "<path d='M1 9.6C1 5 4.2 2.4 8 2.4s7 2.6 7 7.2z' fill='#d8302b'/>"
                 "<circle cx='5' cy='6' r='1' fill='#f1ebde'/><circle cx='9.4' cy='4.6' r='.9' fill='#f1ebde'/><circle cx='11.6' cy='7.6' r='1' fill='#f1ebde'/>"),
}


def glyph(page):
    return "<svg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 16 16'>%s</svg>" % GLYPHS[page]


# ════════════════════════════════════════════════════════════════════════════
# Who wears what. A card is named by its rune (every card has its own — see
# asgard.css), so that is the key. Sizes: a "full" card's piece is drawn for
# the wide column, a "small" card's for the narrow one; on a phone the CSS
# scales both down to fit. (Yggdrasil's card has its tree; nothing grows on it.)
#   top    (plant, corner it grows from, extras)
#   seed   change it and only that card grows differently
# ════════════════════════════════════════════════════════════════════════════
TOPS = {"ivy": ivy_top, "rowan": rowan_top, "bough": bough_top, "bramble": bramble_top, "fern": fern_top, "oak": oak_top}
SIZE = {"full": dict(tw=640, th=190), "small": dict(tw=340, th=170)}

CARDS = [
    # Ivy and moss lead; no two neighbours wear the same thing. Ferns and
    # bramble only ever come from the right: they hang straight down where
    # they start, and the title is on the left.
    # rune      page        size     top                                                           seed
    ("ansuz",   "asgard",   "full",  ("bough", "right", {}),                                        11),
    ("othala",  "asgard",   "full",  ("ivy", "left", dict(berries=1)),                              12),
    ("raidho",  "asgard",   "full",  ("fern", "right", {}),                                         13),
    ("algiz",   "asgard",   "full",  ("rowan", "right", {}),                                        14),
    ("jera",    "asgard",   "small", ("ivy", "right", dict(reach=0.85, drop=50)),                   15),
    ("laguz",   "asgard",   "small", ("bough", "left", dict(reach=0.85)),                           16),
    ("fehu",    "asgard",   "small", ("bramble", "right", dict(canes=2)),                           17),
    ("dagaz",   "eclipse",  "full",  ("ivy", "right", dict(young=0, drop=80)),                      21),
    ("ehwaz",   "eclipse",  "full",  ("oak", "left", dict(autumn=0.2)),                             22),
    ("perthro", "eclipse",  "small", ("rowan", "right", dict(reach=0.6, clusters=2)),               23),
    ("mannaz",  "eclipse",  "small", ("fern", "right", dict(fronds=5)),                             24),
    ("kenaz",   "power",    "full",  ("ivy", "right", dict(autumn=0.4, drop=60)),                   31),
    ("sowilo",  "power",    "full",  ("oak", "left", {}),                                           32),
    ("tiwaz",   "power",    "full",  ("bough", "right", {}),                                        33),
    ("gebo",    "power",    "small", ("rowan", "right", dict(reach=0.6, clusters=2)),               34),
    ("uruz",    "power",    "small", ("fern", "right", dict(fronds=5)),                             35),
    ("isa",     "terminal", "full",  ("ivy", "right", dict(drop=90, berries=1)),                    41),
]
PAGES = {"asgard": 101, "eclipse": 102, "power": 103, "terminal": 104}

# How far from the title's side nothing may hang over it, per size: a piece
# from the far corner only needs to clear the title once a phone has scaled
# it across the whole card; one from the title's own corner must run along
# above the edge until it is past the title.
KEEP = {("full", "right"): 120, ("full", "left"): 300, ("small", "right"): 210, ("small", "left"): 190}


def main(out, ver):
    os.makedirs(out, exist_ok=True)
    q = "?v=" + ver if ver else ""
    url = lambda n: 'url("/assets/growth/%s%s")' % (n, q)
    css = ["/* growth.css — GENERATED by Resources/Glance/growth.py; which card and which page wears which piece.",
           "   asgard.css draws them (.widget::before, .widget-header, .header::after, body::after, .ag-sec). */"]
    for rune, page, size, top, seed in CARDS:
        z = SIZE[size]
        kind, side, kw = top
        rng = random.Random(seed)
        body = TOPS[kind](z["tw"], z["th"], rng, side=side, keep=KEEP[(size, side)], **kw)
        open(os.path.join(out, rune + "-top.svg"), "w").write(svg(z["tw"], z["th"], body, "%s over the top of the %s card." % (kind.title(), rune)))
        props = ["--g-top:" + url(rune + "-top.svg"), "--g-top-at:%s top" % side, "--g-top-w:%dpx" % z["tw"]]
        open(os.path.join(out, rune + "-rule.svg"), "w").write(rule(page, random.Random(seed * 13 + 5)))
        props.append("--g-rule:" + url(rune + "-rule.svg"))
        css.append(".rune-%s { %s; }" % (rune, "; ".join(props)))
    for page, seed in PAGES.items():
        open(os.path.join(out, "nav-%s.svg" % page), "w").write(nav(page, random.Random(seed)))
        open(os.path.join(out, "treeline-%s.svg" % page), "w").write(treeline(page, random.Random(seed + 50)))
        open(os.path.join(out, "glyph-%s.svg" % page), "w").write(glyph(page))
        sel = 'html:has(.nav-item-current[href="/%s"])' % page
        if page == "asgard":
            sel = ":root, " + sel   # the default, before the page is known
        css.append('%s { --g-page: %s; --g-nav: %s; --g-trees: %s; --g-glyph: %s; }' % (
            sel, page, url("nav-%s.svg" % page), url("treeline-%s.svg" % page), url("glyph-%s.svg" % page)))
    open(os.path.join(out, "growth.css"), "w").write("\n".join(css) + "\n")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "")
