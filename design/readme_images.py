"""Rebuilds the README's images in docs/images/ from Fightcade screenshots.

Usage: python3 design/readme_images.py SCREENSHOT_DIR

The screenshots are 3840x2160 captures of Fightcade with the game scaled to 2880x2160 in the middle.
"""

import os
import sys

from PIL import Image

from card_explained import CLEAN, MISS, Figure

GAME_SCREEN = (480, 0, 3360, 2160)

HERO = ("Screenshot_20261114_164926.png", GAME_SCREEN, (1440, 1080), "clean-super.jpg", 88)
EXPLAINED = [(CLEAN, "card-explained.jpg"), (MISS, "miss-explained.jpg")]


def crop(source, box, size, output, quality):
    image = Image.open(source).convert("RGB").crop(box).resize(size, Image.LANCZOS)
    image.save(output, quality=quality, optimize=True, progressive=True)


if __name__ == "__main__":
    screenshots, images = sys.argv[1], "docs/images"
    for name, box, size, output, quality in [HERO]:
        crop(os.path.join(screenshots, name), box, size, os.path.join(images, output), quality)
    for spec, output in EXPLAINED:
        figure = Figure(spec, os.path.join(screenshots, spec.screenshot))
        figure.annotate().save(os.path.join(images, output), quality=92, optimize=True, progressive=True)
