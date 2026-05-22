#!/usr/bin/env python3
import math
import os
import struct
import subprocess
import zlib

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
BRAND_DIR = os.path.join(ROOT, "Assets", "Brand")
CHROME_DIR = os.path.join(ROOT, "Browser Extension", "chrome")
PACKAGING_DIR = os.path.join(ROOT, "Packaging")


def blend(dst, src):
    sr, sg, sb, sa = src
    if sa <= 0:
        return dst
    if sa >= 255:
        return (sr, sg, sb, 255)
    dr, dg, db, da = dst
    a = sa / 255.0
    inv = 1.0 - a
    return (
        int(sr * a + dr * inv),
        int(sg * a + dg * inv),
        int(sb * a + db * inv),
        255,
    )


def lerp(a, b, t):
    return int(a + (b - a) * t)


def gradient(c1, c2, t):
    return tuple(lerp(c1[i], c2[i], t) for i in range(3)) + (255,)


def rounded_rect_alpha(x, y, rect, radius):
    rx, ry, rw, rh = rect
    px = abs(x - (rx + rw / 2)) - (rw / 2 - radius)
    py = abs(y - (ry + rh / 2)) - (rh / 2 - radius)
    ox = max(px, 0)
    oy = max(py, 0)
    outside = math.hypot(ox, oy)
    inside = min(max(px, py), 0)
    distance = outside + inside - radius
    return max(0.0, min(1.0, 0.5 - distance))


def point_in_polygon(x, y, polygon):
    inside = False
    j = len(polygon) - 1
    for i in range(len(polygon)):
        xi, yi = polygon[i]
        xj, yj = polygon[j]
        crosses = (yi > y) != (yj > y)
        if crosses:
            x_at_y = (xj - xi) * (y - yi) / (yj - yi + 1e-9) + xi
            if x < x_at_y:
                inside = not inside
        j = i
    return inside


def draw_rounded_rect(pixels, size, rect, radius, color_fn):
    x0 = max(0, int(rect[0] - 2))
    y0 = max(0, int(rect[1] - 2))
    x1 = min(size, int(rect[0] + rect[2] + 2))
    y1 = min(size, int(rect[1] + rect[3] + 2))
    for y in range(y0, y1):
        for x in range(x0, x1):
            a = rounded_rect_alpha(x + 0.5, y + 0.5, rect, radius)
            if a <= 0:
                continue
            idx = y * size + x
            color = color_fn(x, y)
            pixels[idx] = blend(pixels[idx], color[:3] + (int(color[3] * a),))


def draw_polygon(pixels, size, polygon, color):
    min_x = max(0, int(min(p[0] for p in polygon)))
    max_x = min(size, int(max(p[0] for p in polygon)) + 1)
    min_y = max(0, int(min(p[1] for p in polygon)))
    max_y = min(size, int(max(p[1] for p in polygon)) + 1)
    samples = [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)]
    for y in range(min_y, max_y):
        for x in range(min_x, max_x):
            coverage = sum(1 for sx, sy in samples if point_in_polygon(x + sx, y + sy, polygon)) / len(samples)
            if coverage:
                idx = y * size + x
                pixels[idx] = blend(pixels[idx], color[:3] + (int(color[3] * coverage),))


def draw_logo(path, size=1024):
    pixels = [(0, 0, 0, 0)] * (size * size)
    s = size / 1024.0

    def scale_rect(rect):
        return tuple(v * s for v in rect)

    def scale_poly(points):
        return [(x * s, y * s) for x, y in points]

    draw_rounded_rect(
        pixels,
        size,
        scale_rect((64, 64, 896, 896)),
        220 * s,
        lambda x, y: gradient((249, 253, 255), (221, 242, 255), (x + y) / (2 * size)),
    )

    draw_rounded_rect(
        pixels,
        size,
        scale_rect((214, 246, 596, 514)),
        128 * s,
        lambda x, y: gradient((35, 167, 255), (0, 107, 255), (x + y) / (2 * size)),
    )

    green = (28, 198, 91, 255)
    draw_rounded_rect(pixels, size, scale_rect((434, 178, 156, 360)), 78 * s, lambda _x, _y: green)
    draw_polygon(
        pixels,
        size,
        scale_poly([(259, 393), (361, 393), (434, 466), (434, 538), (512, 616), (590, 538), (590, 466), (663, 393), (765, 393), (512, 646)]),
        (28, 198, 91, 255),
    )

    white = (255, 255, 255, 245)
    for rect in [(318, 624, 98, 62), (448, 624, 98, 62), (578, 624, 128, 62), (318, 724, 180, 62), (530, 724, 176, 62)]:
        draw_rounded_rect(pixels, size, scale_rect(rect), 22 * s, lambda _x, _y: white)

    write_png(path, size, size, pixels)


def write_png(path, width, height, pixels):
    def chunk(kind, data):
        payload = kind + data
        return struct.pack(">I", len(data)) + payload + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)

    raw_rows = []
    for y in range(height):
        row = bytearray([0])
        for x in range(width):
            row.extend(pixels[y * width + x])
        raw_rows.append(bytes(row))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(b"".join(raw_rows), 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def resize(source, target, size):
    subprocess.run(["sips", "-z", str(size), str(size), source, "--out", target], check=True, stdout=subprocess.DEVNULL)


def main():
    os.makedirs(BRAND_DIR, exist_ok=True)
    os.makedirs(CHROME_DIR, exist_ok=True)
    os.makedirs(PACKAGING_DIR, exist_ok=True)

    master = os.path.join(BRAND_DIR, "logo-1024.png")
    draw_logo(master)

    for size in [16, 32, 48, 128]:
        resize(master, os.path.join(CHROME_DIR, f"icon-{size}.png"), size)

    iconset = os.path.join(PACKAGING_DIR, "FastNativeDownloadManager.iconset")
    os.makedirs(iconset, exist_ok=True)
    icon_sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for size, name in icon_sizes:
        resize(master, os.path.join(iconset, name), size)

    write_icns(
        os.path.join(PACKAGING_DIR, "FastNativeDownloadManager.icns"),
        [
            ("icp4", os.path.join(iconset, "icon_16x16.png")),
            ("icp5", os.path.join(iconset, "icon_32x32.png")),
            ("icp6", os.path.join(iconset, "icon_32x32@2x.png")),
            ("ic07", os.path.join(iconset, "icon_128x128.png")),
            ("ic08", os.path.join(iconset, "icon_256x256.png")),
            ("ic09", os.path.join(iconset, "icon_512x512.png")),
            ("ic10", os.path.join(iconset, "icon_512x512@2x.png")),
        ],
    )
    print("Generated brand assets.")


def write_icns(path, entries):
    chunks = []
    for kind, png_path in entries:
        with open(png_path, "rb") as handle:
            data = handle.read()
        chunks.append(kind.encode("ascii") + struct.pack(">I", len(data) + 8) + data)

    payload = b"".join(chunks)
    with open(path, "wb") as handle:
        handle.write(b"icns" + struct.pack(">I", len(payload) + 8) + payload)


if __name__ == "__main__":
    main()
