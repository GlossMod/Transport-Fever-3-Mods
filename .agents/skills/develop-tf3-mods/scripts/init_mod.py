#!/usr/bin/env python3
"""Create a fresh TF3 staging mod. Uses only Python's standard library.

The optional pre-run hook matches the installed official no-costs example
checked on 2026-10-04. Generated code still requires validation in TF3.
"""

import argparse
import json
import re
from pathlib import Path


def single_line(value, label, limit):
    if not value.strip() or len(value) > limit or any(ord(c) < 32 for c in value):
        raise ValueError(f"{label} must be a nonempty single line of at most {limit} characters")
    return value


def create_mod(output_root, mod_id, name, summary, author=None, script="none"):
    if not re.fullmatch(r"[a-z0-9_]+", mod_id):
        raise ValueError("mod-id must contain only lowercase a-z, 0-9 and underscores")
    reserved = {"con", "prn", "aux", "nul"} | {
        f"{prefix}{n}" for prefix in ("com", "lpt") for n in range(1, 10)
    }
    if mod_id in reserved:
        raise ValueError("mod-id is a reserved Windows directory name")
    single_line(name, "name", 32)
    single_line(summary, "summary", 100)
    if author is not None:
        single_line(author, "author", 100)
    if script not in ("none", "pre-run"):
        raise ValueError("script must be none or pre-run")

    root = Path(output_root).expanduser().resolve()
    destination = root / mod_id
    if destination.exists() or destination.is_symlink():
        raise FileExistsError(f"Refusing to overwrite existing mod: {destination}")

    definition = {
        "modId": mod_id,
        "revision": 1,
        "severityAdd": "None",
        "severityRemove": "Warning",
        "visible": True,
        "cosmetic": False,
    }
    metadata = {
        "name": name,
        "summary": summary,
        "description": summary,
        "authors": [{"name": author, "role": "CREATOR"}] if author else [],
        "url": "",
    }
    if script == "pre-run":
        definition["preRunScript"] = {
            "fileName": f"{mod_id}::/mod.script@preRunFn"
        }

    root.mkdir(parents=True, exist_ok=True)
    destination.mkdir()  # Exclusive creation; never merge into an existing mod.
    (destination / "_metadata").mkdir()
    (destination / "content").mkdir()
    for path, data in (
        (destination / "mod.json", definition),
        (destination / "_metadata/modinfo.json", metadata),
    ):
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if script == "pre-run":
        source = (
            "local mod = {}\n\n"
            "mod.preRunFn = function(captureParams, configDict : {{string, string}}, "
            "allModParams : {string : {string : integer}}, baseConfig : BaseConfig)\n"
            f'    debugPrint("[{mod_id}] preRunFn loaded")\n'
            "end\n\n"
            "return mod\n"
        )
        (destination / "content/mod.script.tl").write_text(source, encoding="utf-8")
    return destination


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", required=True, type=Path, help="Explicit staging/output directory")
    parser.add_argument("--mod-id", required=True)
    parser.add_argument("--name", required=True, help="Display name, at most 32 characters")
    parser.add_argument("--summary", default="Development scaffold; implement and validate the intended feature.")
    parser.add_argument("--author", help="Omit when the actual author is not yet specified")
    parser.add_argument("--script", choices=("none", "pre-run"), default="none")
    args = parser.parse_args()
    try:
        destination = create_mod(
            args.output_root, args.mod_id, args.name, args.summary, args.author, args.script
        )
    except (OSError, ValueError) as exc:
        parser.exit(1, f"Error: {exc}\n")
    print(json.dumps({
        "created": str(destination),
        "script": args.script,
        "runtime_tested": False,
        "next": "Implement the requested feature; review metadata and severity; validate in TF3.",
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
