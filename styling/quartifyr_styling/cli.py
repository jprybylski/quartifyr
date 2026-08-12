"""Command-line entrypoint: ``quartifyr-styling <subcommand>``."""

from __future__ import annotations

import argparse
import sys

from .abbreviations import AbbreviationsError, build_abbreviations_tex
from .build_template import build_reference_docx
from .layout import LayoutError, apply_layout_from_qmd
from .recalculate_fields import FieldRecalculationError, recalculate_fields
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


def _cmd_recalculate_fields(args: argparse.Namespace) -> int:
    try:
        output_path = recalculate_fields(args.docx, timeout_seconds=args.timeout)
    except (FieldRecalculationError, FileNotFoundError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(f"recalculated {output_path}")
    return 0


def _cmd_apply_layout(args: argparse.Namespace) -> int:
    try:
        output_path = apply_layout_from_qmd(args.docx, args.qmd, status=args.status)
    except (LayoutError, FileNotFoundError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    print(f"applied layout to {output_path}")
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

    recalc = subparsers.add_parser(
        "recalculate-fields",
        help="Recalculate a docx's Word ToC (page numbers, entries) in place via headless LibreOffice",
    )
    recalc.add_argument("--docx", required=True, help="Path to the docx to recalculate (modified in place)")
    recalc.add_argument("--timeout", type=int, default=120, help="Timeout in seconds (default: 120)")
    recalc.set_defaults(func=_cmd_recalculate_fields)

    layout = subparsers.add_parser(
        "apply-layout",
        help="Split a rendered docx into front-matter/body sections at {{< body-start >}} and apply a dynamic header",
    )
    layout.add_argument("--docx", required=True, help="Path to the rendered docx (modified in place)")
    layout.add_argument("--qmd", required=True, help="Path to the shell .qmd (read for header-format: and its placeholders)")
    layout.add_argument("--status", required=True, choices=["draft", "final", "DRAFT", "FINAL"], help="Resolved draft/final status")
    layout.set_defaults(func=_cmd_apply_layout)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
