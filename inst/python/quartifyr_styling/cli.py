"""Command-line entrypoint: ``quartifyr-styling <subcommand>``.

Every subcommand accepts a top-level ``--json`` flag. It exists for the
`quartifyr` R package's pyro bridge (``R/run-python.R``): with ``--json``,
success prints ``{"status": "ok", ...}`` to stdout and any error prints
``{"status": "error", "code": ..., "message": ...}`` to stderr *before*
exiting non-zero, so the R side can recover a real diagnostic even though
``pyro::run_python_script()`` itself discards captured output on non-zero
exit. Don't change this stderr-JSON handshake on one side without the
matching R-side parsing in ``.run_quartifyr_styling_cli()``. Without
``--json`` (plain direct CLI use), behavior is unchanged: a human-readable
line on success, ``error: ...`` on stderr on failure.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .abbreviations import AbbreviationsError, build_abbreviations_tex
from .build_template import build_reference_docx
from .layout import LayoutError, apply_layout_from_qmd
from .recalculate_fields import FieldRecalculationError, recalculate_fields
from .reportifyr_sync import ReportifyrSyncError, sync_reportifyr_config
from .same_page_crossrefs import SamePageCrossrefError, resolve_same_page_crossrefs
from .schema import StyleConfig, StyleConfigError
from .style_editing import StyleEditingError, copy_example_style, save_overrides, update_style


def _ok(args: argparse.Namespace, message: str, **fields) -> int:
    if args.json:
        print(json.dumps({"status": "ok", **fields}))
    else:
        print(message)
    return 0


def _err(args: argparse.Namespace, exc: Exception) -> int:
    if args.json:
        print(
            json.dumps({"status": "error", "code": type(exc).__name__, "message": str(exc)}),
            file=sys.stderr,
        )
    else:
        print(f"error: {exc}", file=sys.stderr)
    return 1


def _cmd_build(args: argparse.Namespace) -> int:
    try:
        config = StyleConfig.load(args.style, args.override)
        output_path = build_reference_docx(config, args.out)
    except (StyleConfigError, FileNotFoundError) as exc:
        return _err(args, exc)
    return _ok(args, f"wrote {output_path}", path=str(output_path))


def _cmd_abbrevs(args: argparse.Namespace) -> int:
    try:
        output_path = build_abbreviations_tex(args.footnotes, args.out)
    except (AbbreviationsError, FileNotFoundError) as exc:
        return _err(args, exc)
    return _ok(args, f"wrote {output_path}", path=str(output_path))


def _cmd_recalculate_fields(args: argparse.Namespace) -> int:
    try:
        output_path = recalculate_fields(args.docx, timeout_seconds=args.timeout)
    except (FieldRecalculationError, FileNotFoundError) as exc:
        return _err(args, exc)
    return _ok(args, f"recalculated {output_path}", path=str(output_path))


def _cmd_resolve_same_page_crossrefs(args: argparse.Namespace) -> int:
    try:
        output_path = resolve_same_page_crossrefs(args.docx, timeout_seconds=args.timeout)
    except (SamePageCrossrefError, FileNotFoundError) as exc:
        return _err(args, exc)
    return _ok(args, f"resolved same-page crossrefs in {output_path}", path=str(output_path))


def _cmd_apply_layout(args: argparse.Namespace) -> int:
    try:
        equation_font = None
        if args.style is not None:
            equation_font = StyleConfig.load(args.style, args.override).equation.font
        output_path = apply_layout_from_qmd(args.docx, args.qmd, status=args.status, equation_font=equation_font)
    except (LayoutError, StyleConfigError, FileNotFoundError) as exc:
        return _err(args, exc)
    return _ok(args, f"applied layout to {output_path}", path=str(output_path))


def _cmd_sync_reportifyr_config(args: argparse.Namespace) -> int:
    def _no_interactive_prompt(_message: str) -> str:
        # Reached only when sync_reportifyr_config() found real changes and
        # assume_yes is False -- with --json (the R pyro bridge's own
        # invocation, always non-interactive/piped) there's no live stdin
        # to read a confirmation from, so fail clearly instead of hanging
        # on input() or silently treating EOF as "no".
        raise ReportifyrSyncError(
            "found changes but --yes was not given; interactive confirmation isn't "
            "available with --json -- pass --yes to confirm non-interactively"
        )

    try:
        config = StyleConfig.load(args.style, args.override)
        changed = sync_reportifyr_config(
            config, args.config,
            assume_yes=args.yes,
            prompt=_no_interactive_prompt if args.json else input,
            # --json mode's stdout must be pure JSON (the R pyro bridge
            # parses it as such) -- the diff summary is diagnostic-only,
            # so it goes to stderr there instead of polluting stdout.
            out=sys.stderr if args.json else sys.stdout,
        )
    except (StyleConfigError, ReportifyrSyncError, FileNotFoundError) as exc:
        return _err(args, exc)
    message = f"synced {args.config}" if changed else f"{args.config} already in sync"
    return _ok(args, message, path=str(args.config), changed=changed)


def _cmd_example_style(args: argparse.Namespace) -> int:
    try:
        parsed = copy_example_style(args.base, args.out, overwrite=args.overwrite)
    except (StyleEditingError, FileNotFoundError) as exc:
        return _err(args, exc)
    return _ok(args, f"wrote {args.out}", path=str(args.out), style=parsed)


def _read_json_arg(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def _cmd_save_overrides(args: argparse.Namespace) -> int:
    try:
        style = _read_json_arg(args.style_json)
        output = save_overrides(args.base, style, args.out, overwrite=args.overwrite, deconvolute=not args.no_deconvolute)
    except (StyleEditingError, FileNotFoundError) as exc:
        return _err(args, exc)
    return _ok(args, f"wrote {args.out}", path=str(args.out), overrides=output)


def _cmd_update_style(args: argparse.Namespace) -> int:
    def _no_interactive_prompt(_message: str) -> str:
        # Same reasoning as sync-reportifyr-config's identical guard: with
        # --json (the R pyro bridge's own invocation) there's no live
        # stdin to confirm over.
        raise StyleEditingError(
            "found changes but --yes was not given; interactive confirmation isn't "
            "available with --json -- pass --yes to confirm non-interactively"
        )

    try:
        updates = _read_json_arg(args.updates_json)
        merged = update_style(
            args.file,
            updates,
            assume_yes=args.yes,
            prompt=_no_interactive_prompt if args.json else input,
            out=sys.stderr if args.json else sys.stdout,
        )
    except (StyleEditingError, FileNotFoundError) as exc:
        return _err(args, exc)
    return _ok(args, f"updated {args.file}", path=str(args.file), style=merged)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="quartifyr-styling")
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON (stdout on success, stderr on error) instead of plain text",
    )
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

    same_page = subparsers.add_parser(
        "resolve-same-page-crossrefs",
        help=(
            "Resolve crossref-hyperlinks: \"same-page\" markers in a filled docx (post reportifyr) via "
            "headless LibreOffice, read-only -- decides hyperlinked vs. plain per cross-reference"
        ),
    )
    same_page.add_argument("--docx", required=True, help="Path to the filled docx to resolve (modified in place)")
    same_page.add_argument("--timeout", type=int, default=120, help="Timeout in seconds (default: 120)")
    same_page.set_defaults(func=_cmd_resolve_same_page_crossrefs)

    layout = subparsers.add_parser(
        "apply-layout",
        help="Split a rendered docx into front-matter/body sections at {{< body-start >}} and apply a dynamic header",
    )
    layout.add_argument("--docx", required=True, help="Path to the rendered docx (modified in place)")
    layout.add_argument("--qmd", required=True, help="Path to the shell .qmd (read for header-format: and its placeholders)")
    layout.add_argument("--status", required=True, choices=["draft", "final", "DRAFT", "FINAL"], help="Resolved draft/final status")
    layout.add_argument(
        "--style", default=None,
        help="Optional style YAML -- when given, applies its equation.font to the rendered docx's default math font",
    )
    layout.add_argument("--override", default=None, help="Optional per-org/per-project style YAML, deep-merged over --style")
    layout.set_defaults(func=_cmd_apply_layout)

    sync = subparsers.add_parser(
        "sync-reportifyr-config",
        help="Update reportifyr's report/config.yaml footnotes_font/footnotes_font_size to match a style YAML",
    )
    sync.add_argument("--style", default="styles/default.yaml", help="Base style YAML (default: styles/default.yaml)")
    sync.add_argument("--override", default=None, help="Optional per-org/per-project style YAML, deep-merged over --style")
    sync.add_argument("--config", default="report/config.yaml", help="Path to reportifyr's config.yaml (default: report/config.yaml)")
    sync.add_argument("--yes", action="store_true", help="Write without an interactive confirmation prompt")
    sync.set_defaults(func=_cmd_sync_reportifyr_config)

    example_style = subparsers.add_parser(
        "example-style",
        help="Copy a base style YAML (default: the bundled default.yaml) to a project, returning its parsed content",
    )
    example_style.add_argument("--base", default="styles/default.yaml", help="Style YAML to copy (default: styles/default.yaml)")
    example_style.add_argument("--out", default="style.yaml", help="Destination path (default: style.yaml)")
    example_style.add_argument("--overwrite", action="store_true", help="Replace --out if it already exists")
    example_style.set_defaults(func=_cmd_example_style)

    save_overrides_p = subparsers.add_parser(
        "save-overrides",
        help="Save a (possibly edited) style dict to a YAML file, by default as just its diff from a base style YAML",
    )
    save_overrides_p.add_argument("--base", default="styles/default.yaml", help="Base style YAML to diff against (default: styles/default.yaml)")
    save_overrides_p.add_argument("--style-json", required=True, help="Path to a JSON file holding the (possibly edited) full style dict")
    save_overrides_p.add_argument("--out", default="overrides.yaml", help="Destination path (default: overrides.yaml)")
    save_overrides_p.add_argument("--overwrite", action="store_true", help="Replace --out if it already exists")
    save_overrides_p.add_argument("--no-deconvolute", action="store_true", help="Save the full style dict as-is instead of just its diff from --base")
    save_overrides_p.set_defaults(func=_cmd_save_overrides)

    update_style_p = subparsers.add_parser(
        "update-style",
        help="Deep-merge an update onto an existing style YAML, in place",
    )
    update_style_p.add_argument("--file", required=True, help="Style YAML to update in place")
    update_style_p.add_argument("--updates-json", required=True, help="Path to a JSON file holding the updates to deep-merge onto --file")
    update_style_p.add_argument("--yes", action="store_true", help="Write without an interactive confirmation prompt")
    update_style_p.set_defaults(func=_cmd_update_style)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
