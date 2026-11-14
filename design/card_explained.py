"""Draws a card from a Fightcade screenshot with some of its parts lit and labelled.

The screenshots are 3840x2160 captures of Fightcade with the game scaled to 2880x2160 in the middle.
Part positions are measured in pixels from (700, 1250) of the capture, where the card sits.
"""

import re
from dataclasses import dataclass

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter


@dataclass
class Spec:
    screenshot: str
    right: int
    card: tuple
    parts: dict
    labels: dict
    left_side: tuple
    right_side: tuple
    below: str = None


CLEAN = Spec(
    screenshot="Screenshot_20261114_164926.png",
    right=1560,
    card=(100, 136, 1490, 660),
    parts={
        "needed": (158, 176, 1462, 336),
        "yours": (158, 360, 1462, 460),
        "meter": (766, 496, 968, 628),
        "total": (936, 54, 1360, 134),
        "recent": (128, 665, 944, 748),
    },
    labels={
        "needed": ("Needed inputs", ["One column per direction,", "then the button"]),
        "yours": ("Your inputs", ["What you pressed", "in each column"]),
        "total": ("Total frames", ["First input to button,", "and the fastest possible"]),
        "meter": ("Taken / allowed", ["The second 2 came 6 frames", "after the 6, out of 14"]),
        "recent": ("Recent attempts", ["One per attempt, newest on the right"]),
    },
    left_side=("needed", "yours"),
    right_side=("total", "meter"),
    below="recent",
)

MISS = Spec(
    screenshot="Screenshot_20261114_165138.png",
    right=1680,
    card=(100, 136, 1610, 665),
    parts={
        "reason": (748, 50, 1112, 134),
        "broke": (1450, 176, 1586, 340),
        "meter": (1325, 494, 1585, 630),
    },
    labels={
        "reason": ("The mistake", ["The punch came", "7 frames late"]),
        "broke": ("The input to fix", ["Boxed in red"]),
        "meter": ("Too late", ["17 frames after the", "motion, 10 allowed"]),
    },
    left_side=("reason",),
    right_side=("broke", "meter"),
)

CROP_LEFT, CROP_TOP, CROP_BOTTOM = 780, 1290, 2050
GRID_ORIGIN = (700, 1250)
SCALE = 0.75

BACKGROUND, ACCENT, INK, SHADOW = (22, 24, 29), (255, 211, 77), (236, 238, 242), (0, 0, 0)
OUTSIDE_BRIGHTNESS, CARD_BRIGHTNESS = 0.22, 0.42

FONT_FILE = "lua/input_grader/core/font.lua"
GLYPH_ADVANCE, GLYPH_ROWS, GLYPH_COLUMNS = 4, 7, 3
TITLE_SCALE, BODY_SCALE, LINE_GAP = 4, 3, 7
ARROW_PIXEL, ARROW_HEAD = 5, 4
MARGIN, REACH, TOP, BOTTOM, BOTTOM_WITH_LABEL = 36, 64, 36, 36, 150


def load_glyphs():
    rows = re.findall(r"\{\s*([\d,\s]+?)\s*\}", open(FONT_FILE).read())
    return [list(map(int, row.split(","))) for row in rows]


GLYPHS = load_glyphs()


def text_width(text, scale):
    return len(text) * GLYPH_ADVANCE * scale - scale


class Figure:
    def __init__(self, spec, screenshot_path):
        self.spec = spec
        box = (CROP_LEFT, CROP_TOP, GRID_ORIGIN[0] + spec.right, CROP_BOTTOM)
        card = Image.open(screenshot_path).convert("RGB").crop(box)
        self.card = card.resize((int(card.width * SCALE), int(card.height * SCALE)), Image.LANCZOS)
        self.left = MARGIN + max(self.label_width(k) for k in spec.left_side) + REACH
        self.right_margin = MARGIN + max(self.label_width(k) for k in spec.right_side) + REACH
        self.width = self.left + self.card.width + self.right_margin
        self.height = TOP + self.card.height + (BOTTOM_WITH_LABEL if spec.below else BOTTOM)
        self.parts = {key: self.place(box) for key, box in spec.parts.items()}
        self.image = self.spotlight()
        self.draw = ImageDraw.Draw(self.image)

    def label_width(self, key):
        title, body = self.spec.labels[key]
        return max([text_width(title.upper(), TITLE_SCALE)] + [text_width(line.upper(), BODY_SCALE) for line in body])

    def place(self, box):
        x0, y0, x1, y1 = box
        ox, oy = CROP_LEFT - GRID_ORIGIN[0], CROP_TOP - GRID_ORIGIN[1]
        return (self.left + (x0 - ox) * SCALE, TOP + (y0 - oy) * SCALE, self.left + (x1 - ox) * SCALE, TOP + (y1 - oy) * SCALE)

    def at_brightness(self, brightness):
        layer = Image.new("RGB", (self.width, self.height), BACKGROUND)
        layer.paste(ImageEnhance.Brightness(self.card).enhance(brightness), (self.left, TOP))
        return layer

    def feathered(self, boxes, radius, blur):
        mask = Image.new("L", (self.width, self.height), 0)
        draw = ImageDraw.Draw(mask)
        for box in boxes:
            draw.rounded_rectangle(box, radius=radius, fill=255)
        return mask.filter(ImageFilter.GaussianBlur(blur))

    def spotlight(self):
        image = self.at_brightness(OUTSIDE_BRIGHTNESS)
        image.paste(self.at_brightness(CARD_BRIGHTNESS), (0, 0), self.feathered([self.place(self.spec.card)], 20, 6))
        image.paste(self.at_brightness(1.0), (0, 0), self.feathered(self.parts.values(), 12, 5))
        return image

    def shadowed(self, cells, size, colour, shadow_offset):
        for offset, fill in ((shadow_offset, SHADOW), (0, colour)):
            for x, y in cells:
                self.draw.rectangle((x + offset, y + offset, x + offset + size - 1, y + offset + size - 1), fill=fill)

    def text(self, x, y, text, scale, colour, align):
        text = text.upper()
        if align == "right":
            x -= text_width(text, scale)
        cells = []
        for k, char in enumerate(text):
            glyph = GLYPHS[ord(char) - 32] if 32 <= ord(char) < 128 else GLYPHS[0]
            for row, bits in enumerate(glyph):
                for column in range(GLYPH_COLUMNS):
                    if bits >> column & 1:
                        cells.append((x + (k * GLYPH_ADVANCE + column) * scale, y + row * scale))
        self.shadowed(cells, scale, colour, scale)

    def label(self, key, x, title_middle, align):
        title, body = self.spec.labels[key]
        y = title_middle - GLYPH_ROWS * TITLE_SCALE // 2
        self.text(x, y, title, TITLE_SCALE, ACCENT, align)
        for i, line in enumerate(body):
            line_y = y + GLYPH_ROWS * TITLE_SCALE + LINE_GAP + i * (GLYPH_ROWS * BODY_SCALE + LINE_GAP)
            self.text(x, line_y, line, BODY_SCALE, INK, align)

    def arrow_across(self, x0, x1, y):
        step = ARROW_PIXEL
        direction = 1 if x1 > x0 else -1
        y = round(y / step) * step
        cells = [(x, y) for x in range(x0, x1 - direction * ARROW_HEAD * step, direction * step)]
        tip = x1 - direction * step
        for i in range(ARROW_HEAD):
            cells += [(tip - direction * i * step, y + dy * step) for dy in range(-i, i + 1)]
        self.shadowed(cells, step, ACCENT, step // 2 + 1)

    def arrow_up(self, x, y0, y1):
        step = ARROW_PIXEL
        x = round(x / step) * step
        cells = [(x, y) for y in range(y0, y1 + ARROW_HEAD * step, -step)]
        for i in range(ARROW_HEAD):
            cells += [(x + dx * step, y1 + i * step) for dx in range(-i, i + 1)]
        self.shadowed(cells, step, ACCENT, step // 2 + 1)

    def annotate(self):
        middle = lambda box: (box[1] + box[3]) / 2
        left_edge = self.left - REACH
        for key in self.spec.left_side:
            box = self.parts[key]
            self.label(key, left_edge, middle(box), "right")
            self.arrow_across(left_edge + 16, int(box[0]) - 10, middle(box))
        right_edge = self.left + self.card.width + REACH
        for key in self.spec.right_side:
            box = self.parts[key]
            self.label(key, right_edge, middle(box), "left")
            self.arrow_across(right_edge - 16, int(box[2]) + 10, middle(box))
        if not self.spec.below:
            return self.image
        box = self.parts[self.spec.below]
        x, top = int(box[0]) + 70, int(box[3]) + 64
        self.label(self.spec.below, x, top + GLYPH_ROWS * TITLE_SCALE // 2, "left")
        self.arrow_up(x - 30, top + GLYPH_ROWS * TITLE_SCALE, int(box[3]) + 8)
        return self.image
