"""Generate the boss indicator textures. Run from any directory with Python 3."""

import argparse
import math
from pathlib import Path
import re
import struct
import zlib


ROOT = Path(__file__).resolve().parents[1]
EFFECTS = ROOT / "developer/assets/atlas/effects"
DEFAULTS = ROOT / "developer/config/boss_defaults.lua"
DISC_SIZE = 1280
RING_SIZE = 704
FILL_ALPHA = 51


def chunk(kind, data):
    return (struct.pack(">I", len(data)) + kind + data
            + struct.pack(">I", zlib.crc32(kind + data)))


def png(size, alpha):
    rows = bytearray()
    for y in range(size):
        rows.append(0)  # No PNG row filter.
        for x in range(size):
            rows.extend((255, 255, 255, alpha(x, y)))
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def coverage(distance):
    return min(1, max(0, distance + 0.5))


def round_alpha(size, width, fill):
    radius = size / 2

    def alpha(x, y):
        edge_distance = radius - math.hypot(x + 0.5 - radius, y + 0.5 - radius)
        outer = coverage(edge_distance)
        inner = coverage(edge_distance - width)
        return round(255 * (outer - inner) + fill * inner)

    return alpha


def box_alpha(size, rim):
    def alpha(x, y):
        distance = min(x, y, size - 1 - x, size - 1 - y)
        return 255 if distance < rim else FILL_ALPHA

    return alpha


def rim_texels(source, field):
    match = re.search(rf"^\s+{field}\s*=\s*([1-9][0-9]*),", source, re.MULTILINE)
    if match is None:
        raise ValueError(f"{DEFAULTS}: {field} must be a positive whole number")
    return int(match[1])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=EFFECTS)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    source = DEFAULTS.read_text(encoding="utf-8")
    box_rim = rim_texels(source, "box_rim_pixels")
    box_size = 4 * box_rim
    for name, size, alpha in (
        ("disc", DISC_SIZE, round_alpha(DISC_SIZE, rim_texels(source, "disc_rim_texels"), FILL_ALPHA)),
        ("box", box_size, box_alpha(box_size, box_rim)),
        ("ring", RING_SIZE, round_alpha(RING_SIZE, rim_texels(source, "ring_rim_texels"), 0)),
    ):
        (args.output / f"boss_indicator_{name}.png").write_bytes(png(size, alpha))


if __name__ == "__main__":
    main()
