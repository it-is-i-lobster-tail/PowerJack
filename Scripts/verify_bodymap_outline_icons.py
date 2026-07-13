#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BODYMAPS = ROOT / "PowerJack" / "PowerJack" / "Assets" / "BodyMap"
FILES = [
    BODYMAPS / "powerjack.bodymap.front.svg",
    BODYMAPS / "powerjack.bodymap.back.svg",
]


class CheckFailed(Exception):
    pass


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def has_id(root: ET.Element, value: str) -> bool:
    return any(element.attrib.get("id") == value for element in root.iter())


def verify(path: Path) -> None:
    if not path.exists():
        raise CheckFailed(f"Missing file: {path}")
    source = path.read_text(encoding="utf-8")
    try:
        root = ET.fromstring(source)
    except ET.ParseError as error:
        raise CheckFailed(f"{path}: XML parse failed: {error}") from error
    if local(root.tag) != "svg":
        raise CheckFailed(f"{path}: root element is not svg")
    if root.attrib.get("viewBox") != "0 0 1024 1024":
        raise CheckFailed(f'{path}: expected viewBox="0 0 1024 1024"')
    if re.search(r"<\s*(text|image|filter|style)\b", source, re.I):
        raise CheckFailed(f"{path}: contains forbidden text/image/filter/style element")
    if re.search(r"\b(href|xlink:href|filter|style)\s*=", source, re.I):
        raise CheckFailed(f"{path}: contains forbidden href/filter/style attribute")
    if "muscle-highlight" in source:
        raise CheckFailed(f"{path}: must not contain muscle-highlight")
    if re.search(r'fill="(?!none")', source):
        raise CheckFailed(f'{path}: outline body maps must use only fill="none"')
    if not has_id(root, "base-body"):
        raise CheckFailed(f'{path}: missing id="base-body"')
    if not has_id(root, "body-landmarks"):
        raise CheckFailed(f'{path}: missing id="body-landmarks"')


def main() -> int:
    try:
        for path in FILES:
            verify(path)
        print("Validated 2 outline body maps")
        print("All checks passed")
        return 0
    except CheckFailed as error:
        print(f"Verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
