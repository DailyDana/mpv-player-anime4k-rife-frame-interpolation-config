# -*- coding: utf-8 -*-
"""Generate nine simple colour LUTs for the Colors menu.

These are produced from plain maths (saturation, channel gain, S-curve), so they
carry no third-party licence and can live in this repository. Drop your own
.cube files into the same folder and they will appear in the menu as well.

Usage:
    python tools/gen_luts.py                 # write to %APPDATA%/mpv/luts
    python tools/gen_luts.py --out <folder>  # write somewhere else
"""
import argparse
import os

N = 33  # 33^3 lattice, the usual size for video LUTs


def clamp(v):
    return 0.0 if v < 0.0 else (1.0 if v > 1.0 else v)


def luma(r, g, b):
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def saturate(r, g, b, k):
    y = luma(r, g, b)
    return (y + (r - y) * k, y + (g - y) * k, y + (b - y) * k)


def scurve(v, k):
    """k=0 leaves v untouched, k=1 is a full smoothstep."""
    s = v * v * (3.0 - 2.0 * v)
    return v + (s - v) * k


def lift(v, amount):
    """Raise the black point for a matte look."""
    return v * (1.0 - amount) + amount


def warm(r, g, b):
    r, g, b = r * 1.07, g * 1.01, b * 0.90
    return saturate(r, g, b, 1.03)


def cool(r, g, b):
    r, g, b = r * 0.92, g * 1.00, b * 1.08
    return saturate(r, g, b, 1.03)


def vivid(r, g, b):
    r, g, b = saturate(r, g, b, 1.28)
    return tuple(scurve(v, 0.25) for v in (r, g, b))


def anime_boost(r, g, b):
    """Slight vibrance, slight warmth, slight contrast - lifts flat cel colour."""
    r, g, b = saturate(r, g, b, 1.15)
    r, g, b = r * 1.03, g * 1.005, b * 0.97
    return tuple(scurve(v, 0.15) for v in (r, g, b))


def cinematic(r, g, b):
    """Teal shadows, warm highlights."""
    y = luma(r, g, b)
    shadow = (1.0 - y) ** 2
    high = y ** 2
    r = r - 0.06 * shadow + 0.05 * high
    g = g + 0.02 * shadow + 0.01 * high
    b = b + 0.07 * shadow - 0.05 * high
    r, g, b = saturate(r, g, b, 1.08)
    return tuple(scurve(v, 0.18) for v in (r, g, b))


def pastel(r, g, b):
    r, g, b = saturate(r, g, b, 0.85)
    return tuple(lift(v, 0.05) * 0.97 for v in (r, g, b))


def sepia(r, g, b):
    sr = 0.393 * r + 0.769 * g + 0.189 * b
    sg = 0.349 * r + 0.686 * g + 0.168 * b
    sb = 0.272 * r + 0.534 * g + 0.131 * b
    # 80% sepia so the image does not go fully monochrome
    return (r * 0.2 + sr * 0.8, g * 0.2 + sg * 0.8, b * 0.2 + sb * 0.8)


def black_and_white(r, g, b):
    y = scurve(luma(r, g, b), 0.12)
    return (y, y, y)


def night(r, g, b):
    """Cut blue light and darken slightly."""
    r, g, b = r * 1.02, g * 0.92, b * 0.72
    return tuple(v * 0.96 for v in (r, g, b))


MODES = [
    ("anime-boost.cube", "Anime Boost", anime_boost),
    ("canli.cube", "Vivid", vivid),
    ("sinematik.cube", "Cinematic (teal-orange)", cinematic),
    ("sicak.cube", "Warm", warm),
    ("soguk.cube", "Cool", cool),
    ("pastel.cube", "Pastel (matte)", pastel),
    ("sepya.cube", "Sepia", sepia),
    ("siyah-beyaz.cube", "Black and White", black_and_white),
    ("gece.cube", "Night (low blue)", night),
]


def write_cube(path, title, fn):
    lines = [f'TITLE "{title}"', f"LUT_3D_SIZE {N}",
             "DOMAIN_MIN 0.0 0.0 0.0", "DOMAIN_MAX 1.0 1.0 1.0"]
    for bi in range(N):
        for gi in range(N):
            for ri in range(N):
                r, g, b = ri / (N - 1), gi / (N - 1), bi / (N - 1)
                ro, go, bo = fn(r, g, b)
                lines.append(f"{clamp(ro):.6f} {clamp(go):.6f} {clamp(bo):.6f}")
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    default = os.path.join(os.environ.get("APPDATA", "."), "mpv", "luts")
    ap = argparse.ArgumentParser(description="Generate the simple colour LUTs.")
    ap.add_argument("--out", default=default, help=f"output folder (default: {default})")
    args = ap.parse_args()

    os.makedirs(args.out, exist_ok=True)
    for name, title, fn in MODES:
        path = os.path.join(args.out, name)
        write_cube(path, title, fn)
        print(f"  {name:<20} {os.path.getsize(path) // 1024:>4} KB   {title}")
    print(f"\n{len(MODES)} LUTs written to {args.out}")


if __name__ == "__main__":
    main()
