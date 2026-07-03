#!/usr/bin/env python3
"""GIF assembler for rake pito:capture / pitomd:capture (0.9.0 Phase CAP).

Pillow instead of ffmpeg: ffmpeg 8.1's paletteuse aborts with "Internal bug,
should not have happened" on real capture sequences (reproduced on the
mkt-linkage 35-frame set at a scroll-boundary frame), while Pillow's
per-frame MEDIANCUT quantization assembles the same frames reliably and reads
terminal-UI content well.

Usage: assemble_gif.py <frames_dir> <out.gif> <duration_ms> <width>
Frames: <frames_dir>/frame-NNNN.png, assembled in order, looped forever.
"""
import glob
import os
import sys

from PIL import Image


def main() -> int:
    frames_dir, out_path, duration_ms, width = sys.argv[1:5]
    duration_ms, width = int(duration_ms), int(width)

    paths = sorted(glob.glob(os.path.join(frames_dir, "frame-*.png")))
    if not paths:
        print(f"no frames in {frames_dir}", file=sys.stderr)
        return 1

    first = Image.open(paths[0])
    height = round(first.size[1] * (width / first.size[0]))
    frames = [
        Image.open(p).convert("RGB").resize((width, height), Image.LANCZOS)
        .quantize(colors=256, method=Image.MEDIANCUT)
        for p in paths
    ]
    frames[0].save(out_path, save_all=True, append_images=frames[1:],
                   duration=duration_ms, loop=0, optimize=True)
    print(f"{out_path}: {len(frames)} frames @ {width}px, {duration_ms}ms/frame")
    return 0


if __name__ == "__main__":
    sys.exit(main())
