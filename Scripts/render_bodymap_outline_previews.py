#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
BODYMAPS = ROOT / "PowerJack" / "PowerJack" / "Assets" / "BodyMap"
REVIEW = ROOT / "ReviewAssets" / "BodyMapOutline"
SIZES = [1024, 256, 96, 44]
SOURCES = [
    ("front", BODYMAPS / "powerjack.bodymap.front.svg"),
    ("back", BODYMAPS / "powerjack.bodymap.back.svg"),
]


def render(svg: Path, size: int, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="powerjack-outline-") as scratch:
        result = subprocess.run(
            ["qlmanage", "-t", "-s", str(size), "-o", scratch, str(svg)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise SystemExit(
                f"qlmanage failed for {svg} at {size}px\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
        pngs = sorted(Path(scratch).glob("*.png"))
        if not pngs:
            raise SystemExit(f"No PNG produced for {svg}")
        image = remove_white_matte(Image.open(pngs[0]).convert("RGBA"))
        if image.size != (size, size):
            canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            image.thumbnail((size, size), Image.Resampling.LANCZOS)
            canvas.alpha_composite(image, ((size - image.width) // 2, (size - image.height) // 2))
            image = canvas
        image.save(output)


def remove_white_matte(image: Image.Image) -> Image.Image:
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if a and r >= 248 and g >= 248 and b >= 248:
                pixels[x, y] = (255, 255, 255, 0)
    return image


def font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for path in [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def preview_sheet() -> None:
    sheet = Image.new("RGB", (1200, 760), (250, 250, 249))
    draw = ImageDraw.Draw(sheet)
    title = "PowerJack Outline Body Maps"
    draw.text((64, 44), title, font=font(34), fill=(47, 55, 68))

    for index, (name, _) in enumerate(SOURCES):
        x = 160 + index * 480
        icon = Image.open(REVIEW / "Previews" / "1024" / f"{name}.png").convert("RGBA")
        icon.thumbnail((360, 560), Image.Resampling.LANCZOS)
        sheet.paste(icon, (x + (360 - icon.width) // 2, 112), icon)
        label = f"powerjack.bodymap.{name}.svg"
        bounds = draw.textbbox((0, 0), label, font=font(22))
        draw.text((x + 180 - (bounds[2] - bounds[0]) / 2, 682), label, font=font(22), fill=(47, 55, 68))
    sheet.save(REVIEW / "bodymap-outline-sheet.png")


def main() -> None:
    if REVIEW.exists():
        shutil.rmtree(REVIEW)
    for name, svg in SOURCES:
        for size in SIZES:
            render(svg, size, REVIEW / "Previews" / str(size) / f"{name}.png")
    preview_sheet()
    print(f"Rendered outline previews to {REVIEW}")
    print(f"Preview sheet: {REVIEW / 'bodymap-outline-sheet.png'}")


if __name__ == "__main__":
    main()
