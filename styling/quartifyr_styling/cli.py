"""Command-line entrypoint: ``quartifyr-styling <subcommand>``."""

from __future__ import annotations

import argparse
import sys

from .abbreviations import AbbreviationsError, build_abbreviations_tex
from .build_template import build_reference_docx
from .schema import StyleConfig, StyleConfigError


def _cmd_build(args: argparse.Namespace) -> int:
    try:
        config = StyleConfig.load(args.style, args.override)
        output_path = build_reference_docx(config, args.out)
    except (StyleConfigError, FileNotFoundError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(f"wrote {output_path}")
    return 0


def _cmd_abbrevs(args: argparse.Namespace) -> int:
    try:
        output_path = build_abbreviations_tex(args.footnotes, args.out)
    except (AbbreviationsError, FileNotFoundError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(f"wrote {output_path}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="quartifyr-styling")
    subparsers = parser.add_subparsers(dest="command", required=True)

    build = subparsers.add_parser("build", help="Generate a docx reference-template from a style YAML")
    build.add_argument("--style", default="styles/default.yaml", help="Base style YAML (default: styles/default.yaml)")
    build.add_argument("--override", default=None, help="Optional per-org/per-project style YAML, deep-merged over --style")
    build.add_argument("--out", default="templates/org-reference.docx", help="Output docx path")
    build.set_defaults(func=_cmd_build)

    abbrevs = subparsers.add_parser(
        "abbrevs", help="Convert a reportifyr standard_footnotes.yaml into abbreviations.tex for quarto-plus"
    )
    abbrevs.add_argument("--footnotes", required=True, help="Path to standard_footnotes.yaml")
    abbrevs.add_argument("--out", default="abbreviations.tex", help="Output abbreviations.tex path")
    abbrevs.set_defaults(func=_cmd_abbrevs)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
