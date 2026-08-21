"""Template-based ``init`` (issue #23): scaffold a new project's
``_quarto.yml``/style YAML/shell ``.qmd`` from a local directory or a git
repo instead of starting from nothing. Ported from ``../deckifyr``'s
identical ``inst/python/deckifyr/templates.py`` (issue #34) -- see this
repo's own CLAUDE.md and its ``deckifyr_template_init_pattern`` design note
for why this is a port, not a from-scratch design.

Mechanism only -- ``cli.py``'s ``_cmd_init`` owns argument validation and
orchestration, the same "mechanism in its own module, orchestration in
cli.py" split every other subcommand here already follows.

Two source shapes, adapted from deckifyr's design.yaml/layouts.yaml/
presentation.yaml split to quartifyr's own three root config files:

- **Flat**: a source directory with ``_quarto.yml`` (Quarto's own fixed
  project-config filename) at its root, plus exactly one ``.qmd`` file
  there. Unlike deckifyr's design/layouts filenames (read out of a field
  in presentation.yaml, since they aren't fixed), a quartifyr shell
  ``.qmd``'s filename isn't fixed either (``report.qmd``, ``memo.qmd``,
  ...) -- but there's no field anywhere that names it, since Quarto
  itself auto-discovers ``.qmd`` files by glob, no config entry required.
  Discovering it the same way here (exactly one ``.qmd`` at the source
  root) reuses that existing Quarto convention rather than inventing a
  new field. ``_quarto.yml`` and a ``style.yaml`` at the source root (if
  present -- unlike deckifyr's design/layouts, a custom style YAML is
  optional; many projects use ``render_report()``'s bundled default
  reference-doc with no project style YAML at all) are copied verbatim;
  the shell ``.qmd`` is **not** copied verbatim -- a fresh, minimal shell
  ``.qmd`` is generated instead, under the source's own filename. This
  mirrors deckifyr's flat case generating an empty ``slides: []``
  presentation.yaml: reuse an org's Quarto config and style, start a new
  project with empty content, not a duplicate of the source project's own
  document.
- **Typed**: a source directory with a ``templates/`` subdirectory, each
  entry a named flat-shaped template of its own. ``--type NAME`` selects
  one; unlike the flat case, its shell ``.qmd`` is copied verbatim (it's
  meant to be a real, minimal starter document for that report kind, not
  emptied).

Git access (``fetch_git_template``) shells out to a real ``git`` binary
(``git clone`` + ``git checkout <ref>``) rather than adding a new HTTP
client dependency -- the same "shell out to an already-trusted external
tool, raise a clear error if it's missing" posture ``recalculate_fields.py``/
``same_page_crossrefs.py`` already establish for LibreOffice. A full,
non-shallow clone is used deliberately: template repos are small config
repos, and a full clone sidesteps any shallow-clone limitation on checking
out an arbitrary commit SHA (as opposed to a branch/tag ref a shallow
fetch can target directly).

``resolve_repo_spec``'s ``[host/]owner/repo[/subdir][@ref]`` shorthand is
ported byte-for-byte from deckifyr's identical grammar (the first
host-qualified, remotes/pak-style ref grammar in the "fyr ecosystem",
confirmed via direct research that quartifyr had no prior art for this at
all before this module) -- GitHub Enterprise support falls out for free
from the optional host segment, disambiguated from a bare ``owner/repo``
by requiring the first segment to look like a real hostname (contains a
``.``, or is ``localhost``) rather than by position alone, since real
GitHub owner names essentially never contain a dot. A full URL (containing
``"://"``) is accepted verbatim instead, for any git host including ones
this shorthand can't express (the ``ref``/``subdir`` come only from the
separate ``--ref``/``--subdir`` flags in that form, since they can't be
embedded unambiguously in an arbitrary URL). Explicit ``--ref``/``--subdir``
flags always win over an embedded ``@ref``/``/subdir`` in the shorthand
form. A bare local filesystem path is deliberately not a third accepted
``--from-repo`` form -- it would be ambiguous with the shorthand grammar,
and ``--from-dir`` already exists for local directories; a local git
checkout can still be cloned through ``--from-repo`` by spelling it as a
``file://`` URL, which correctly takes the full-URL branch.

v1 deliberately copies only the three root config files -- never local
assets they reference (a logo image, a bibliography ``.bib`` file, a
synopsis figure). ``_scan_asset_warnings`` reports what it finds in a
typed source's copied shell ``.qmd`` frontmatter instead of trying to
resolve and copy it -- the same well-scoped, documented-gap posture
deckifyr's identical scan takes for design.yaml/presentation.yaml.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import tempfile
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterator, Literal

import yaml

GIT_INSTALL_URL = "https://git-scm.com/downloads"
DEFAULT_GIT_HOST = "github.com"

_HOST_LIKE_RE = re.compile(r"^(localhost(:\d+)?|[^/]+\.[^/]+)$")

_MINIMAL_SHELL_QMD = """---
title: "New Report"
document-status: "draft"
format: docx
filters:
  - quarto-plus
  - quartifyr
---
"""


class TemplatesError(Exception):
    """Raised when template-based init fails."""


# --- Repo-spec parsing (remotes/pak-style shorthand) ------------------------


@dataclass
class GitSource:
    clone_url: str
    ref: str | None
    subdir: str | None


def resolve_repo_spec(
    spec: str, *, ref: str | None = None, subdir: str | None = None
) -> GitSource:
    """Parse ``--from-repo``'s ``spec`` into a clone URL + ref + subdir.

    Two forms:

    - A full URL (contains ``"://"``): passed through verbatim as the
      clone URL. ``ref``/``subdir`` come only from the ``ref``/``subdir``
      keyword arguments (this repo's own ``--ref``/``--subdir`` flags) --
      nothing is parsed out of the URL itself.
    - Shorthand: ``[host/]owner/repo[/subdir][@ref]``. ``host`` defaults
      to ``DEFAULT_GIT_HOST`` (github.com); an explicit host segment is
      recognized only when it looks like a real hostname (contains a
      ``.``, or is ``localhost`` with an optional ``:port``) -- otherwise
      the first segment is ``owner``. Explicit ``ref``/``subdir`` keyword
      arguments override anything embedded in the shorthand string.
    """
    if "://" in spec:
        return GitSource(clone_url=spec, ref=ref, subdir=subdir)

    remainder, _, embedded_ref = spec.partition("@")
    if not embedded_ref:
        remainder = spec

    segments = [s for s in remainder.split("/") if s]
    if not segments:
        raise TemplatesError(f"invalid --from-repo spec: {spec!r}")

    host = DEFAULT_GIT_HOST
    if len(segments) >= 3 and _HOST_LIKE_RE.match(segments[0]):
        host = segments[0]
        segments = segments[1:]

    if len(segments) < 2:
        raise TemplatesError(
            f"invalid --from-repo spec: {spec!r} "
            "(expected '[host/]owner/repo[/subdir][@ref]')"
        )

    owner, repo = segments[0], segments[1]
    embedded_subdir = "/".join(segments[2:]) or None

    return GitSource(
        clone_url=f"https://{host}/{owner}/{repo}.git",
        ref=ref if ref is not None else (embedded_ref or None),
        subdir=subdir if subdir is not None else embedded_subdir,
    )


# --- Git fetch ---------------------------------------------------------------


def _require_git() -> None:
    if shutil.which("git") is None:
        raise TemplatesError(
            "'git' not found on PATH -- install Git "
            f"({GIT_INSTALL_URL}) to use --from-repo"
        )


def _run_git(args: list[str], *, cwd: Path | None = None) -> None:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=120,
        )
    except subprocess.TimeoutExpired as exc:
        raise TemplatesError(f"git {' '.join(args)} timed out") from exc

    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise TemplatesError(f"git {' '.join(args)} failed: {detail}")


@contextmanager
def fetch_git_template(
    clone_url: str, *, ref: str | None, subdir: str | None
) -> Iterator[Path]:
    """Clone ``clone_url`` to a temp dir, check out ``ref`` if given, and
    yield the resolved source directory (the clone root, or its
    ``subdir``). The temp dir is removed on exit -- callers must copy
    anything they need out of the yielded path before the ``with`` block
    ends.
    """
    _require_git()
    with tempfile.TemporaryDirectory(prefix="quartifyr-template-") as tmp:
        repo_dir = Path(tmp) / "repo"
        _run_git(["clone", clone_url, str(repo_dir)])
        if ref:
            _run_git(["checkout", ref], cwd=repo_dir)

        source_dir = repo_dir / subdir if subdir else repo_dir
        if not source_dir.is_dir():
            raise TemplatesError(f"--subdir {subdir!r} not found in {clone_url}")
        yield source_dir


# --- Structure detection -----------------------------------------------------


@dataclass
class ResolvedTemplate:
    kind: Literal["flat", "typed"]
    quarto_yml_path: Path
    style_path: Path | None
    shell_qmd_path: Path
    shell_qmd_filename: str


def _find_shell_qmd(source_dir: Path) -> Path:
    candidates = sorted(p for p in source_dir.glob("*.qmd") if not p.name.startswith("_"))
    if len(candidates) != 1:
        raise TemplatesError(
            f"{source_dir} must have exactly one .qmd file at its root to be "
            f"a flat template source (found {len(candidates)})"
        )
    return candidates[0]


def _resolve_flat(source_dir: Path) -> ResolvedTemplate:
    quarto_yml_path = source_dir / "_quarto.yml"
    if not quarto_yml_path.is_file():
        raise TemplatesError(f"{source_dir}: missing _quarto.yml")
    shell_qmd_path = _find_shell_qmd(source_dir)
    style_path = source_dir / "style.yaml"
    return ResolvedTemplate(
        kind="flat",
        quarto_yml_path=quarto_yml_path,
        style_path=style_path if style_path.is_file() else None,
        shell_qmd_path=shell_qmd_path,
        shell_qmd_filename=shell_qmd_path.name,
    )


def _resolve_typed(templates_dir: Path, type_name: str | None) -> ResolvedTemplate:
    available = sorted(p.name for p in templates_dir.iterdir() if p.is_dir())
    if type_name is None:
        raise TemplatesError(
            "this source has a templates/ directory -- pass --type to "
            f"select one of: {', '.join(available) or '(none found)'}"
        )
    type_dir = templates_dir / type_name
    if type_name not in available or not type_dir.is_dir():
        raise TemplatesError(
            f"unknown --type {type_name!r} -- available: {', '.join(available) or '(none found)'}"
        )

    resolved = _resolve_flat(type_dir)
    return ResolvedTemplate(
        kind="typed",
        quarto_yml_path=resolved.quarto_yml_path,
        style_path=resolved.style_path,
        shell_qmd_path=resolved.shell_qmd_path,
        shell_qmd_filename=resolved.shell_qmd_filename,
    )


def detect_template(source_dir: Path, *, type_name: str | None) -> ResolvedTemplate:
    templates_dir = source_dir / "templates"
    if templates_dir.is_dir():
        return _resolve_typed(templates_dir, type_name)

    if (source_dir / "_quarto.yml").is_file():
        if type_name is not None:
            raise TemplatesError(
                f"--type {type_name!r} given, but {source_dir} has no "
                "templates/ directory (it's a flat template source)"
            )
        return _resolve_flat(source_dir)

    raise TemplatesError(
        f"{source_dir} is not a recognizable quartifyr template source "
        "(expected a _quarto.yml or a templates/<type>/ directory)"
    )


# --- Materialization ----------------------------------------------------------


def _read_qmd_frontmatter(path: Path) -> dict:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return {}
    end = next((i for i, line in enumerate(lines[1:], start=1) if line.strip() == "---"), None)
    if end is None:
        return {}
    parsed = yaml.safe_load("\n".join(lines[1:end]))
    return parsed if isinstance(parsed, dict) else {}


def _scan_asset_warnings(shell_qmd_data: dict) -> list[str]:
    warnings: list[str] = []

    def _is_local_reference(value: Any) -> bool:
        return isinstance(value, str) and bool(value) and "://" not in value

    logo = shell_qmd_data.get("logo")
    if _is_local_reference(logo):
        warnings.append(f"shell .qmd's logo: ({logo!r}) was not copied -- bring this asset over manually")

    bibliography = shell_qmd_data.get("bibliography")
    if _is_local_reference(bibliography):
        warnings.append(
            f"shell .qmd's bibliography: ({bibliography!r}) was not copied -- bring this file over manually"
        )

    return warnings


def materialize_template(
    resolved: ResolvedTemplate, target: Path, *, force: bool
) -> tuple[list[str], list[str]]:
    """Copy ``resolved``'s files into ``target``, generating a fresh
    minimal shell ``.qmd`` for a flat source or copying a typed source's
    own shell ``.qmd`` verbatim. Returns ``(created_paths, warnings)``.

    Refuses (unless ``force``) only on the exact destination paths this
    call is about to write already existing -- not on ``target``'s whole
    non-emptiness, since pulling a template into an already-populated
    project directory (one that already has a ``.git/``, ``README.md``,
    ...) is this feature's own normal use case.
    """
    target.mkdir(parents=True, exist_ok=True)
    quarto_yml_dest = target / "_quarto.yml"
    style_dest = target / "style.yaml" if resolved.style_path is not None else None
    shell_qmd_dest = target / resolved.shell_qmd_filename

    conflicts = [p for p in (quarto_yml_dest, style_dest, shell_qmd_dest) if p is not None and p.exists()]
    if conflicts and not force:
        names = ", ".join(str(p) for p in conflicts)
        raise TemplatesError(f"{names} already exist (use --force to overwrite)")

    created: list[str] = []
    shutil.copyfile(resolved.quarto_yml_path, quarto_yml_dest)
    created.append(str(quarto_yml_dest))

    if style_dest is not None:
        shutil.copyfile(resolved.style_path, style_dest)
        created.append(str(style_dest))

    if resolved.kind == "typed":
        shutil.copyfile(resolved.shell_qmd_path, shell_qmd_dest)
        created.append(str(shell_qmd_dest))
        warnings = _scan_asset_warnings(_read_qmd_frontmatter(resolved.shell_qmd_path))
    else:
        shell_qmd_dest.write_text(_MINIMAL_SHELL_QMD, encoding="utf-8")
        created.append(str(shell_qmd_dest))
        warnings = []

    return created, warnings


# --- Orchestration entrypoint -------------------------------------------------


def init_from_template(
    target: Path,
    *,
    from_dir: str | None,
    from_repo: str | None,
    ref: str | None,
    subdir: str | None,
    type_name: str | None,
    force: bool,
) -> dict[str, Any]:
    """Single entrypoint ``cli.py``'s ``_cmd_init`` calls for a template-
    based init (``--from-dir``/``--from-repo``). Resolves the source (a
    local directory as-is, or a git repo cloned to a temp dir), then
    detects and materializes the template. Returns
    ``{"directory", "created", "warnings"}``.
    """
    if from_dir:
        source_dir = Path(from_dir)
        if not source_dir.is_dir():
            raise TemplatesError(f"--from-dir not found: {source_dir}")
        resolved = detect_template(source_dir, type_name=type_name)
        created, warnings = materialize_template(resolved, target, force=force)
    else:
        assert from_repo is not None
        git_source = resolve_repo_spec(from_repo, ref=ref, subdir=subdir)
        with fetch_git_template(
            git_source.clone_url, ref=git_source.ref, subdir=git_source.subdir
        ) as source_dir:
            resolved = detect_template(source_dir, type_name=type_name)
            created, warnings = materialize_template(resolved, target, force=force)

    return {"directory": str(target), "created": created, "warnings": warnings}
