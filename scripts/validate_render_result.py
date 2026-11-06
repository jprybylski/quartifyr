#!/usr/bin/env python3
"""Validate real `render.R --json` output against the shipped v1 schema.

    validate_render_result.py ok.json=ok failed.json=error

Each argument is `<file>=<expected status>`. A file passes when it parses, validates
against inst/schemas/render-result-v1.schema.json and carries that status. Used by
the CI pipeline jobs, so the schema is checked against what the script actually
prints (for a success and for a forced failure), not just against result objects
built by hand in the R tests.

Needs `jsonschema` (the `dev` extra).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

SCHEMA = Path(__file__).resolve().parent.parent / "inst" / "schemas" / "render-result-v1.schema.json"


def check(path: Path, expected_status: str, validator) -> list[str]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"{path}: not readable JSON ({exc})"]
    problems = [
        f"{path}: {'/'.join(str(p) for p in err.absolute_path) or '<root>'}: {err.message}"
        for err in sorted(validator.iter_errors(payload), key=lambda e: list(e.absolute_path))
    ]
    if payload.get("status") != expected_status:
        problems.append(f"{path}: status is {payload.get('status')!r}, expected {expected_status!r}")
    return problems


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        import jsonschema
    except ImportError:
        print("error: jsonschema is not installed (pip install jsonschema, or the dev extra)", file=sys.stderr)
        return 2

    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    validator = jsonschema.Draft7Validator(schema)
    failures: list[str] = []
    for arg in argv:
        name, _, status = arg.rpartition("=")
        if not name or not status:
            print(f"error: expected <file>=<status>, got {arg!r}", file=sys.stderr)
            return 2
        problems = check(Path(name), status, validator)
        failures.extend(problems)
        print(f"{'FAIL' if problems else 'ok  '} {name} (status {status})")
    for problem in failures:
        print(f"  {problem}", file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
