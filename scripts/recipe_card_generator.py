#!/usr/bin/env python3
"""
Recipe card image generator.

Examples:
    python recipe_card_generator.py \
        --title "Bifteck de Flan Farci" \
        --ingredients "2 bifteck de flan;2 c. à table de margarine;2 gros oignons hachés;1/2 tasse de céleri;2 tasses cubes de pain;1 œuf battu" \
        --output bifteck_recipe.png

    python recipe_card_generator.py \
        --title "Beef Stuffed Cabbage" \
        --ingredients-file ingredients.txt \
        --output beef_stuffed_cabbage.png \
        --photo dish.jpg
"""

from __future__ import annotations

import argparse
import math
import textwrap
from pathlib import Path
from typing import Iterable, List

from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps


WIDTH = 1400
HEIGHT = 2000
MARGIN = 90
TITLE_COLOR = (147, 34, 24)
TEXT_COLOR = (42, 31, 24)
BULLET_COLOR = (170, 52, 38)
PAPER = (237, 218, 187)
PAPER_DARK = (213, 184, 146)
WOOD = (120, 79, 47)
WOOD_DARK = (88, 54, 30)
ACCENT = (155, 111, 55)


def load_font(size: int, bold: bool = False, italic: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if bold:
        candidates += [
            "/System/Library/Fonts/Supplemental/Times New Roman Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
        ]
    elif italic:
        candidates += [
            "/System/Library/Fonts/Supplemental/Times New Roman Italic.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Italic.ttf",
        ]
    else:
        candidates += [
            "/System/Library/Fonts/Supplemental/Times New Roman.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
        ]

    # A more handwritten-looking fallback if available
    display_candidates = [
        "/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
        "/System/Library/Fonts/Supplemental/Brush Script.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
    ]

    for path in display_candidates if size >= 44 and bold else candidates:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size=size)
            except OSError:
                pass
    return ImageFont.load_default()


def parse_ingredients(args: argparse.Namespace) -> List[str]:
    items: List[str] = []

    if args.ingredients:
        parts = [p.strip() for p in args.ingredients.split(";")]
        items.extend([p for p in parts if p])

    if args.ingredients_file:
        text = Path(args.ingredients_file).read_text(encoding="utf-8")
        for line in text.splitlines():
            line = line.strip().lstrip("•-").strip()
            if line:
                items.append(line)

    if not items:
        raise ValueError("No ingredients provided. Use --ingredients or --ingredients-file.")

    return items


def fit_title(draw: ImageDraw.ImageDraw, title: str, max_width: int) -> ImageFont.ImageFont:
    for size in range(86, 38, -2):
        font = load_font(size=size, bold=True)
        bbox = draw.textbbox((0, 0), title, font=font)
        if bbox[2] - bbox[0] <= max_width:
            return font
    return load_font(size=40, bold=True)


def wrap_text(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.ImageFont, max_width: int) -> List[str]:
    words = text.split()
    if not words:
        return [""]

    lines: List[str] = []
    current = words[0]

    for word in words[1:]:
        candidate = current + " " + word
        width = draw.textbbox((0, 0), candidate, font=font)[2]
        if width <= max_width:
            current = candidate
        else:
            lines.append(current)
            current = word
    lines.append(current)
    return lines


def draw_wrapped(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, font: ImageFont.ImageFont,
                 fill: tuple[int, int, int], max_width: int, line_spacing: int = 8) -> int:
    x, y = xy
    lines = wrap_text(draw, text, font, max_width)
    for line in lines:
        draw.text((x, y), line, font=font, fill=fill)
        bbox = draw.textbbox((x, y), line, font=font)
        y += (bbox[3] - bbox[1]) + line_spacing
    return y


def make_wood_background(width: int, height: int) -> Image.Image:
    img = Image.new("RGB", (width, height), WOOD)
    draw = ImageDraw.Draw(img)

    plank_count = 10
    plank_h = height / plank_count

    for i in range(plank_count + 1):
        y = int(i * plank_h)
        shade = 12 if i % 2 == 0 else -8
        color = tuple(max(0, min(255, c + shade)) for c in WOOD)
        draw.rectangle([0, y, width, int(y + plank_h)], fill=color)
        draw.line([(0, y), (width, y)], fill=WOOD_DARK, width=3)

    # Wood grain
    for y in range(0, height, 7):
        offset = int(6 * math.sin(y / 37))
        draw.line([(0, y), (width, y + offset)], fill=(98, 64, 38), width=1)

    img = img.filter(ImageFilter.GaussianBlur(radius=0.4))
    return img


def make_paper(width: int, height: int) -> Image.Image:
    paper = Image.new("RGBA", (width, height), PAPER + (255,))
    draw = ImageDraw.Draw(paper)

    # Soft inner shading
    for i in range(18):
        alpha = 10
        draw.rounded_rectangle(
            [i, i, width - i - 1, height - i - 1],
            radius=20,
            outline=PAPER_DARK + (alpha,),
            width=2
        )

    # Mottled texture dots
    step = 22
    for y in range(20, height - 20, step):
        for x in range(20, width - 20, step):
            a = 8 + ((x * y) % 10)
            r = PAPER_DARK[0] + ((x + y) % 7) - 3
            g = PAPER_DARK[1] + ((x * 3 + y) % 7) - 3
            b = PAPER_DARK[2] + ((x + y * 2) % 7) - 3
            draw.ellipse([x, y, x + 3, y + 3], fill=(r, g, b, a))

    # Burnt-ish edges
    edge = Image.new("L", (width, height), 255)
    edge_draw = ImageDraw.Draw(edge)
    for i in range(24):
        edge_draw.rounded_rectangle([i, i, width - i - 1, height - i - 1], radius=20, outline=max(0, 255 - i * 9), width=2)
    edge = edge.filter(ImageFilter.GaussianBlur(radius=5))

    paper.putalpha(edge)
    return paper


def paste_photo(base: Image.Image, photo_path: str, box: tuple[int, int, int, int]) -> None:
    photo = Image.open(photo_path).convert("RGB")
    fitted = ImageOps.fit(photo, (box[2] - box[0], box[3] - box[1]), method=Image.Resampling.LANCZOS)

    mask = Image.new("L", fitted.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, fitted.size[0], fitted.size[1]], radius=28, fill=255)

    # Shadow
    shadow = Image.new("RGBA", (fitted.size[0] + 20, fitted.size[1] + 20), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([10, 10, shadow.size[0] - 1, shadow.size[1] - 1], radius=35, fill=(0, 0, 0, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=10))
    base.alpha_composite(shadow, (box[0] - 10, box[1] - 10))

    rgba = fitted.convert("RGBA")
    rgba.putalpha(mask)
    base.alpha_composite(rgba, (box[0], box[1]))


def generate_recipe_card(
    title: str,
    ingredients: List[str],
    output_path: str,
    photo_path: str | None = None,
    ingredients_image_path: str | None = None,
) -> None:
    base = make_wood_background(WIDTH, HEIGHT).convert("RGBA")
    paper = make_paper(WIDTH - 140, HEIGHT - 160)

    paper_x = (WIDTH - paper.width) // 2
    paper_y = (HEIGHT - paper.height) // 2
    base.alpha_composite(paper, (paper_x, paper_y))

    draw = ImageDraw.Draw(base)

    content_left = paper_x + MARGIN
    content_right = paper_x + paper.width - MARGIN
    y = paper_y + 90

    title_font = fit_title(draw, title, content_right - content_left)
    title_bbox = draw.textbbox((0, 0), title, font=title_font)
    title_width = title_bbox[2] - title_bbox[0]
    draw.text(((WIDTH - title_width) // 2, y), title, font=title_font, fill=TITLE_COLOR)
    y += (title_bbox[3] - title_bbox[1]) + 36

    # Decorative line
    draw.line((content_left + 50, y, content_right - 50, y), fill=ACCENT, width=3)
    y += 30

    header_font = load_font(42, bold=True)
    header_text = "Ingredients"
    header_bbox = draw.textbbox((0, 0), header_text, font=header_font)
    header_w = header_bbox[2] - header_bbox[0]
    draw.rounded_rectangle(
        [WIDTH // 2 - header_w // 2 - 28, y - 12, WIDTH // 2 + header_w // 2 + 28, y + 52],
        radius=18,
        fill=(177, 137, 89),
        outline=(120, 79, 47),
        width=3,
    )
    draw.text((WIDTH // 2 - header_w // 2, y), header_text, font=header_font, fill=(40, 27, 16))
    y += 92

    if ingredients_image_path:
        image_box = (content_left + 20, y, content_right - 20, paper_y + paper.height - 80)
        paste_photo(base, ingredients_image_path, image_box)
    else:
        bullet_font = load_font(18, bold=True)
        text_font = load_font(36)
        ingredient_max_width = content_right - content_left - 50

        for item in ingredients:
            draw.ellipse([content_left, y + 14, content_left + 16, y + 30], fill=BULLET_COLOR)
            y = draw_wrapped(
                draw,
                (content_left + 34, y),
                item,
                font=text_font,
                fill=TEXT_COLOR,
                max_width=ingredient_max_width,
                line_spacing=10,
            )
            y += 10

        if photo_path:
            remaining = (paper_y + paper.height - 80) - y
            if remaining > 260:
                photo_top = y + 20
                photo_box = (content_left + 50, photo_top, content_right - 50, paper_y + paper.height - 80)
                paste_photo(base, photo_path, photo_box)

    final = base.convert("RGB")
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    final.save(output_path, quality=95)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Generate a recipe card image from a recipe name and ingredients.")
    parser.add_argument("--title", required=True, help="Recipe name/title.")
    parser.add_argument(
        "--ingredients",
        help='Ingredients separated by semicolons. Example: "2 eggs;1 cup flour;1/2 cup milk"',
    )
    parser.add_argument(
        "--ingredients-file",
        help="Text file with one ingredient per line.",
    )
    parser.add_argument("--output", required=True, help="Output image path, e.g. recipe.png")
    parser.add_argument(
        "--photo",
        help="Optional dish photo to place in the lower part of the recipe card.",
    )
    parser.add_argument(
        "--ingredients-image",
        help="Optional image path to place on the card instead of the text ingredient list.",
    )
    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    try:
        ingredients = parse_ingredients(args)
        generate_recipe_card(
            title=args.title,
            ingredients=ingredients,
            output_path=args.output,
            photo_path=args.photo,
            ingredients_image_path=args.ingredients_image,
        )
        print(f"Recipe card saved to: {args.output}")
    except Exception as exc:
        raise SystemExit(f"Error: {exc}") from exc


if __name__ == "__main__":
    main()
