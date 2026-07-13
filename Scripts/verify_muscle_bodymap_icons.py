#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MUSCLE_SWIFT = ROOT / "PowerJack" / "PowerJack" / "Shared" / "Models" / "Muscle.swift"
ASSETS = ROOT / "PowerJack" / "PowerJack" / "Assets"
BODYMAPS = ASSETS / "BodyMap"
MUSCLES = ASSETS / "Muscles"

FRONT = {"chest", "shoulders", "biceps", "abs", "obliques", "forearms", "quads"}
BACK = {"back", "triceps", "glutes", "calves", "hamstrings"}
BLUE = "#0A84FF"


class CheckFailed(Exception):
    pass


def muscle_cases() -> list[str]:
    source = MUSCLE_SWIFT.read_text(encoding="utf-8")
    match = re.search(r"enum\s+Muscle\s*:[^{]+\{(?P<body>.*?)\n\}", source, re.S)
    if not match:
        raise CheckFailed(f"Could not parse Muscle enum at {MUSCLE_SWIFT}")
    cases: list[str] = []
    for line in match.group("body").splitlines():
        case = re.match(r"\s*case\s+(.+)", line)
        if not case:
            continue
        for item in case.group(1).split(","):
            name = item.strip().split("=")[0].strip()
            if name:
                cases.append(name)
    if not cases:
        raise CheckFailed("Muscle enum has no cases")
    return cases


def local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag


def parse(path: Path) -> ET.Element:
    try:
        return ET.fromstring(path.read_text(encoding="utf-8"))
    except ET.ParseError as error:
        raise CheckFailed(f"{path}: XML parse failed: {error}") from error


def element_with_id(root: ET.Element, value: str) -> ET.Element | None:
    for element in root.iter():
        if element.attrib.get("id") == value:
            return element
    return None


def raw_group(source: str, group_id: str) -> str:
    found = re.search(rf'<g id="{re.escape(group_id)}"(?: [^>]*)?>.*?</g>', source, re.S)
    if not found:
        raise CheckFailed(f'Missing group id="{group_id}"')
    return found.group(0)


def normalized_svg(source: str) -> str:
    result, count = re.subn(
        r'<g id="muscle-highlight" data-muscle="[^"]+">.*?</g>',
        '<g id="muscle-highlight" data-muscle="__MUSCLE__">\n</g>',
        source,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise CheckFailed("Expected exactly one muscle-highlight group to normalize")
    return result


def verify_svg(path: Path, *, muscle: bool) -> ET.Element:
    if not path.exists():
        raise CheckFailed(f"Missing file: {path}")
    source = path.read_text(encoding="utf-8")
    root = parse(path)
    if local(root.tag) != "svg":
        raise CheckFailed(f"{path}: root element must be svg")
    if root.attrib.get("viewBox") != "0 0 1024 1024":
        raise CheckFailed(f'{path}: expected viewBox="0 0 1024 1024"')
    if re.search(r"<\s*(text|image|filter|style)\b", source, re.I):
        raise CheckFailed(f"{path}: contains a forbidden element")
    if re.search(r"\b(href|xlink:href|filter)\s*=", source, re.I):
        raise CheckFailed(f"{path}: contains a forbidden reference/filter attribute")
    if "style=" in source:
        raise CheckFailed(f"{path}: contains a style attribute")
    if re.search(r"shadow|drop-shadow|box-shadow", source, re.I):
        raise CheckFailed(f"{path}: contains shadow-like content")
    for element in root.iter():
        name = local(element.tag)
        if name in {"text", "image", "filter", "style"}:
            raise CheckFailed(f"{path}: contains <{name}>")
        if "style" in element.attrib:
            raise CheckFailed(f"{path}: style attributes are not allowed")
        for attr in element.attrib:
            attr_name = local(attr)
            if attr_name in {"href", "filter"}:
                raise CheckFailed(f"{path}: {attr_name} attributes are not allowed")
        if name == "rect":
            fill = element.attrib.get("fill", "").lower()
            if (
                element.attrib.get("x", "0") in {"0", "0.0"}
                and element.attrib.get("y", "0") in {"0", "0.0"}
                and element.attrib.get("width") == "1024"
                and element.attrib.get("height") == "1024"
                and fill not in {"none", "transparent"}
            ):
                raise CheckFailed(f"{path}: contains an opaque full-size background")
    if element_with_id(root, "base-body") is None:
        raise CheckFailed(f'{path}: missing id="base-body"')
    if element_with_id(root, "body-landmarks") is None:
        raise CheckFailed(f'{path}: missing id="body-landmarks"')
    has_highlight = element_with_id(root, "muscle-highlight") is not None
    if muscle and not has_highlight:
        raise CheckFailed(f'{path}: missing id="muscle-highlight"')
    if not muscle and has_highlight:
        raise CheckFailed(f"{path}: base map must not contain muscle-highlight")
    return root


def short_hash(*parts: str) -> str:
    digest = hashlib.sha256("\n".join(parts).encode("utf-8")).hexdigest()
    return digest[:16]


def main() -> int:
    try:
        cases = muscle_cases()
        unsupported = set(cases) - FRONT - BACK
        if unsupported:
            raise CheckFailed("Unsupported enum cases: " + ", ".join(sorted(unsupported)))

        front_base_path = BODYMAPS / "powerjack.bodymap.front.svg"
        back_base_path = BODYMAPS / "powerjack.bodymap.back.svg"
        verify_svg(front_base_path, muscle=False)
        verify_svg(back_base_path, muscle=False)
        front_source = front_base_path.read_text(encoding="utf-8")
        back_source = back_base_path.read_text(encoding="utf-8")
        front_body = raw_group(front_source, "base-body")
        front_marks = raw_group(front_source, "body-landmarks")
        back_body = raw_group(back_source, "base-body")
        back_marks = raw_group(back_source, "body-landmarks")

        expected = set(cases)
        actual = {
            item.name.removeprefix("powerjack.muscle.").removesuffix(".svg")
            for item in MUSCLES.glob("powerjack.muscle.*.svg")
        }
        missing = expected - actual
        extra = actual - expected
        if missing:
            raise CheckFailed("Missing muscle icons: " + ", ".join(sorted(missing)))
        if extra:
            raise CheckFailed("Unexpected muscle icons: " + ", ".join(sorted(extra)))

        skeleton: dict[str, str] = {}
        colors: set[str] = set()

        for name in cases:
            path = MUSCLES / f"powerjack.muscle.{name}.svg"
            root = verify_svg(path, muscle=True)
            highlight = element_with_id(root, "muscle-highlight")
            if highlight is None or highlight.attrib.get("data-muscle") != name:
                raise CheckFailed(f'{path}: data-muscle must be "{name}"')
            source = path.read_text(encoding="utf-8")
            body = raw_group(source, "base-body")
            marks = raw_group(source, "body-landmarks")
            highlight_source = raw_group(source, "muscle-highlight")
            colors.update(color.upper() for color in re.findall(r"#[0-9a-fA-F]{6}", highlight_source))
            view = "front" if name in FRONT else "back"
            if view == "front":
                if body != front_body or marks != front_marks:
                    raise CheckFailed(f"{path}: front base groups are not byte-identical")
            else:
                if body != back_body or marks != back_marks:
                    raise CheckFailed(f"{path}: back base groups are not byte-identical")
            normalized = normalized_svg(source)
            if view in skeleton and skeleton[view] != normalized:
                raise CheckFailed(f"{path}: same-view SVG differs outside muscle-highlight")
            skeleton.setdefault(view, normalized)

        if colors != {BLUE}:
            raise CheckFailed(f"Expected only {BLUE} highlights, found {', '.join(sorted(colors))}")

        print("Validated 2 body maps")
        print(f"Validated {len(cases)} muscle icons")
        print(f"Front base hash: {short_hash(front_body, front_marks)}")
        print(f"Back base hash: {short_hash(back_body, back_marks)}")
        print("All checks passed")
        return 0
    except CheckFailed as error:
        print(f"Verification failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
