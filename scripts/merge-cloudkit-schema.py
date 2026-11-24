#!/usr/bin/env python3
"""Add fields from PowerJack's compiled model to a cktool Development export."""

import argparse
import json
from pathlib import Path
import re


IDENTIFIER = r'"[^"]+"|[A-Za-z_][A-Za-z0-9_]*'
RECORD = re.compile(
    rf"\bRECORD\s+TYPE\s+(?P<name>{IDENTIFIER})\s*\((?P<body>[^()]*)\)\s*;"
)
FIELD = re.compile(
    rf"(?:^|,)\s*(?P<name>{IDENTIFIER})\s+"
    r"(?P<type>NUMBER\s+PREFERRED\s+AS\s+(?:INT64|DOUBLE)|"
    r"(?:ENCRYPTED\s+)?(?:ASSET|BYTES|DOUBLE|INT64|LOCATION|NUMBER|REFERENCE|STRING|TIMESTAMP)|"
    r"LIST\s*<[^>]*>)(?=\s|,|$)"
)


def model_fields(entities):
    if not entities:
        raise ValueError("The compiled model has no entities.")

    records = {}
    for entity in entities:
        fields = records.setdefault(f"CD_{entity['root']}", {
            "CD_entityName": "STRING",
            "CD_moveReceipt": "BYTES",
            "CD_moveReceipt_ckAsset": "ASSET",
        })
        for attribute in entity["attributes"]:
            name = f"CD_{attribute['name']}"
            field_type, _, asset = attribute["type"].partition("+")
            if attribute["encrypted"]:
                field_type = f"ENCRYPTED {field_type}"
            add_field(fields, name, field_type)
            if asset:
                add_field(fields, f"{name}_ckAsset", asset)

        for relationship in entity["relationships"]:
            if not relationship["toMany"]:
                add_field(fields, f"CD_{relationship['name']}", "STRING")
            elif relationship["inverseToMany"]:
                records.setdefault("CDMR", {
                    "CD_entityNames": "STRING",
                    "CD_recordNames": "STRING",
                    "CD_relationships": "STRING",
                })
    return records


def add_field(fields, name, field_type):
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", name):
        raise ValueError(f"Invalid CloudKit field name {name!r}.")
    if fields.setdefault(name, field_type) != field_type:
        raise ValueError(f"The model generates conflicting types for {name}.")


def format_fields(fields):
    return ",\n".join(f'        "{name}" {field_type}' for name, field_type in sorted(fields.items()))


def merge_schema(schema, records):
    if not re.match(r"\s*DEFINE\s+SCHEMA\b", schema):
        raise ValueError("Expected a CloudKit schema exported by cktool.")
    remaining = dict(records)

    def update_record(match):
        name = match["name"].strip('"')
        expected = remaining.pop(name, None)
        if expected is None:
            return match[0]

        body = match["body"]
        existing = {
            field["name"].strip('"'): " ".join(field["type"].split())
            for field in FIELD.finditer(body)
        }
        if body.strip() and not existing:
            raise ValueError(f"Could not read fields for {name} in the Development export.")

        missing = {}
        for field_name, field_type in expected.items():
            if field_name not in existing:
                missing[field_name] = field_type
                continue

            deployed_type = existing[field_name].removeprefix("NUMBER PREFERRED AS ")
            if deployed_type != field_type and not (deployed_type == "NUMBER" and field_type in {"INT64", "DOUBLE"}):
                raise ValueError(
                    f"{name}.{field_name} is {existing[field_name]} in Development, "
                    f"but the compiled model requires {field_type}."
                )

        if not missing:
            return match[0]
        separator = "," if body.strip() else ""
        offset = match.start("body") - match.start()
        return match[0][:offset] + "\n" + format_fields(missing) + separator + match[0][offset:]

    merged = RECORD.sub(update_record, schema)
    if remaining:
        # New types mirror to PowerJack's private database and need no public grants.
        additions = [
            f'    RECORD TYPE "{name}" (\n{format_fields(fields)}\n    );'
            for name, fields in sorted(remaining.items())
        ]
        merged = merged.rstrip() + "\n\n" + "\n\n".join(additions) + "\n"
    return merged


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model", type=Path)
    parser.add_argument("development", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    try:
        records = model_fields(json.loads(args.model.read_text()))
        merged = merge_schema(args.development.read_text(), records)
        args.output.write_text(merged)
    except ValueError as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
