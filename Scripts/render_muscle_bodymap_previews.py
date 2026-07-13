#!/usr/bin/env python3
from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
MUSCLE_SWIFT = ROOT / "PowerJack" / "PowerJack" / "Shared" / "Models" / "Muscle.swift"
BODYMAPS = ROOT / "PowerJack" / "PowerJack" / "Assets" / "BodyMap"
MUSCLES = ROOT / "PowerJack" / "PowerJack" / "Assets" / "Muscles"
REVIEW = ROOT / "ReviewAssets" / "MuscleBodyMap"
SIZES = [1024, 512, 256, 96, 44]
SHEET_SIZES = [32]


def muscle_cases() -> list[str]:
    source = MUSCLE_SWIFT.read_text(encoding="utf-8")
    match = re.search(r"enum\s+Muscle\s*:[^{]+\{(?P<body>.*?)\n\}", source, re.S)
    if not match:
        raise SystemExit(f"Could not parse Muscle enum at {MUSCLE_SWIFT}")
    cases: list[str] = []
    for line in match.group("body").splitlines():
        found = re.match(r"\s*case\s+(.+)", line)
        if not found:
            continue
        for item in found.group(1).split(","):
            name = item.strip().split("=")[0].strip()
            if name:
                cases.append(name)
    return cases


def sources() -> list[tuple[str, Path]]:
    items = [
        ("front base", BODYMAPS / "powerjack.bodymap.front.svg"),
        ("back base", BODYMAPS / "powerjack.bodymap.back.svg"),
    ]
    items.extend((name, MUSCLES / f"powerjack.muscle.{name}.svg") for name in muscle_cases())
    return items


def render(svg: Path, size: int, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="powerjack-bodymap-") as scratch:
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
        image = remove_quicklook_matte(Image.open(pngs[0]).convert("RGBA"))
        if image.size != (size, size):
            canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
            image.thumbnail((size, size), Image.Resampling.LANCZOS)
            canvas.alpha_composite(image, ((size - image.width) // 2, (size - image.height) // 2))
            image = canvas
        image.save(output)


def remove_quicklook_matte(image: Image.Image) -> Image.Image:
    pixels = image.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a and r >= 248 and g >= 248 and b >= 248:
                pixels[x, y] = (255, 255, 255, 0)
    return image


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            pass
    return ImageFont.load_default()


def slug(label: str) -> str:
    return label.replace(" ", "-")


def dark_reference_background(size: tuple[int, int]) -> Image.Image:
    width, height = size
    base = Image.new("RGB", size, (18, 19, 20))
    pixels = base.load()
    for y in range(height):
        center_boost = max(0, 1 - abs(y - height * 0.47) / (height * 0.45))
        for x in range(width):
            horizontal = max(0, 1 - abs(x - width / 2) / (width * 0.62))
            value = int(24 + 105 * center_boost * horizontal)
            pixels[x, y] = (value, value, value)
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse((170, 95, 470, 565), fill=(255, 255, 255, 34))
    draw.ellipse((554, 95, 854, 565), fill=(255, 255, 255, 34))
    draw.ellipse((170, 660, 470, 1015), fill=(255, 255, 255, 34))
    draw.ellipse((554, 660, 854, 1015), fill=(255, 255, 255, 34))
    draw.ellipse((120, 1100, 900, 1420), fill=(255, 255, 255, 22))
    glow = glow.filter(ImageFilter.GaussianBlur(55))
    return Image.alpha_composite(base.convert("RGBA"), glow)


def paste_icon(sheet: Image.Image, label: str, center: tuple[int, int], size: int) -> None:
    icon = Image.open(REVIEW / "Previews" / "512" / f"{slug(label)}.png").convert("RGBA")
    icon = icon.resize((size, size), Image.Resampling.LANCZOS)
    sheet.alpha_composite(icon, (center[0] - size // 2, center[1] - size // 2))


def centered_label(draw: ImageDraw.ImageDraw, text: str, y: int, cx: int, size: int = 24) -> None:
    label_font = font(size)
    bounds = draw.textbbox((0, 0), text, font=label_font)
    draw.text((cx - (bounds[2] - bounds[0]) / 2, y), text, font=label_font, fill=(96, 98, 100, 125))


def reference_gate() -> None:
    sheet = dark_reference_background((1024, 1536))
    draw = ImageDraw.Draw(sheet)
    paste_icon(sheet, "front base", (320, 328), 430)
    paste_icon(sheet, "back base", (704, 328), 430)
    paste_icon(sheet, "chest", (320, 835), 430)
    paste_icon(sheet, "back", (704, 835), 430)
    centered_label(draw, "powerjack bodymap front.svg", 575, 320, 23)
    centered_label(draw, "powerjack bodymap back.svg", 575, 704, 23)
    centered_label(draw, "powerjack muscle chest.svg", 985, 320, 23)
    centered_label(draw, "powerjack muscle back.svg", 985, 704, 23)
    title_font = font(31)
    bounds = draw.textbbox((0, 0), "Body Map Reference", font=title_font)
    draw.text(((1024 - (bounds[2] - bounds[0])) / 2, 1080), "Body Map Reference", font=title_font, fill=(104, 106, 108, 125))
    draw.line((165, 1134, 859, 1134), fill=(137, 139, 142, 70), width=2)
    for label, cx in [("front base", 260), ("back base", 430), ("chest", 610), ("back", 775)]:
        paste_icon(sheet, label, (cx, 1248), 170)
    sheet.convert("RGB").save(REVIEW / "reference-gate.png")


def contact_sheet(items: list[tuple[str, Path]]) -> None:
    cols = 4
    tile = 250
    gap = 34
    margin = 48
    header = 82
    rows = (len(items) + cols - 1) // cols
    width = margin * 2 + cols * tile + (cols - 1) * gap
    height = margin * 2 + header + rows * 318
    sheet = dark_reference_background((width, height))
    draw = ImageDraw.Draw(sheet)
    draw.text((margin, 30), "PowerJack Muscle Body-Map Icons", font=font(34), fill=(176, 180, 184, 210))
    for index, (label, _) in enumerate(items):
        row = index // cols
        col = index % cols
        x = margin + col * (tile + gap)
        y = margin + header + row * 318
        icon = Image.open(REVIEW / "Previews" / "256" / f"{slug(label)}.png").convert("RGBA")
        icon = icon.resize((tile, tile), Image.Resampling.LANCZOS)
        sheet.alpha_composite(icon, (x, y))
        bounds = draw.textbbox((0, 0), label, font=font(18))
        draw.text((x + tile / 2 - (bounds[2] - bounds[0]) / 2, y + tile + 12), label, font=font(18), fill=(156, 160, 164, 205))
    sheet.convert("RGB").save(REVIEW / "contact-sheet.png")


def small_sheet(items: list[tuple[str, Path]]) -> None:
    width = 600
    row = 76
    margin = 28
    header = 84
    height = margin * 2 + header + row * len(items)
    sheet = Image.new("RGB", (width, height), (238, 241, 244))
    draw = ImageDraw.Draw(sheet)
    draw.text((margin, 25), "Small-Size Check", font=font(28), fill=(33, 36, 39))
    draw.text((260, 72), "44 px", font=font(14), fill=(78, 84, 92))
    draw.text((408, 72), "32 px", font=font(14), fill=(78, 84, 92))
    for index, (label, _) in enumerate(items):
        y = margin + header + index * row
        draw.text((margin, y + 25), label, font=font(17), fill=(33, 36, 39))
        for offset, size, bg in [
            (250, 44, (255, 255, 255)),
            (318, 44, (18, 20, 24)),
            (402, 32, (255, 255, 255)),
            (470, 32, (18, 20, 24)),
        ]:
            draw.rounded_rectangle((offset - 9, y + 8, offset + 53, y + 70), radius=12, fill=bg, outline=(203, 209, 216), width=1)
            icon = Image.open(REVIEW / "Previews" / str(size) / f"{slug(label)}.png").convert("RGBA")
            x = offset + (44 - size) // 2
            sheet.paste(icon, (x, y + 17 + (44 - size) // 2), icon)
    sheet.save(REVIEW / "small-size-check.png")


def main() -> None:
    items = sources()
    if REVIEW.exists():
        shutil.rmtree(REVIEW)
    for label, svg in items:
        if not svg.exists():
            raise SystemExit(f"Missing SVG: {svg}")
        for size in [*SIZES, *SHEET_SIZES]:
            render(svg, size, REVIEW / "Previews" / str(size) / f"{slug(label)}.png")
    reference_gate()
    contact_sheet(items)
    small_sheet(items)
    print(f"Rendered review assets to {REVIEW}")
    print(f"Reference gate: {REVIEW / 'reference-gate.png'}")
    print(f"Contact sheet: {REVIEW / 'contact-sheet.png'}")
    print(f"Small-size sheet: {REVIEW / 'small-size-check.png'}")


if __name__ == "__main__":
    main()
