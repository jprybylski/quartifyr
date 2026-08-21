import shutil
import subprocess
from pathlib import Path

import pytest
import yaml

from quartifyr_styling.templates import (
    TemplatesError,
    detect_template,
    fetch_git_template,
    materialize_template,
    resolve_repo_spec,
)

requires_git = pytest.mark.skipif(
    shutil.which("git") is None, reason="git binary not found on PATH"
)


# --- resolve_repo_spec ------------------------------------------------


def test_resolve_repo_spec_shorthand_defaults_to_github():
    source = resolve_repo_spec("acme/repo")
    assert source.clone_url == "https://github.com/acme/repo.git"
    assert source.ref is None
    assert source.subdir is None


def test_resolve_repo_spec_explicit_host_is_enterprise_support():
    source = resolve_repo_spec("git.example.com/acme/repo@v1")
    assert source.clone_url == "https://git.example.com/acme/repo.git"
    assert source.ref == "v1"


def test_resolve_repo_spec_embedded_subdir_and_ref():
    source = resolve_repo_spec("acme/repo/templates/foo@deadbeef")
    assert source.clone_url == "https://github.com/acme/repo.git"
    assert source.subdir == "templates/foo"
    assert source.ref == "deadbeef"


def test_resolve_repo_spec_full_url_passthrough():
    source = resolve_repo_spec(
        "https://example.com/acme/repo.git", ref="v3", subdir="templates/foo"
    )
    assert source.clone_url == "https://example.com/acme/repo.git"
    assert source.ref == "v3"
    assert source.subdir == "templates/foo"


def test_resolve_repo_spec_explicit_flags_override_embedded():
    source = resolve_repo_spec(
        "acme/repo/embedded-sub@embedded-ref", ref="explicit-ref", subdir="explicit-sub"
    )
    assert source.ref == "explicit-ref"
    assert source.subdir == "explicit-sub"


def test_resolve_repo_spec_owner_only_is_error():
    with pytest.raises(TemplatesError):
        resolve_repo_spec("just-an-owner")


# --- detect_template ----------------------------------------------------


def _write_flat_source(root: Path, *, qmd_name="report.qmd", with_style=True, logo=None, bibliography=None):
    root.mkdir(parents=True, exist_ok=True)
    (root / "_quarto.yml").write_text(
        yaml.safe_dump({"project": {"type": "default", "output-dir": "report/shell"}})
    )
    if with_style:
        (root / "style.yaml").write_text(yaml.safe_dump({"page": {"margins_in": {"top": 1}}}))

    frontmatter = {"title": "Source Report", "format": "docx"}
    if logo is not None:
        frontmatter["logo"] = logo
    if bibliography is not None:
        frontmatter["bibliography"] = bibliography
    qmd_text = "---\n" + yaml.safe_dump(frontmatter) + "---\n\nBody content.\n"
    (root / qmd_name).write_text(qmd_text)
    return root


def test_detect_template_flat_reads_the_shell_qmd_filename(tmp_path):
    source = _write_flat_source(tmp_path / "source", qmd_name="memo.qmd")
    resolved = detect_template(source, type_name=None)
    assert resolved.kind == "flat"
    assert resolved.shell_qmd_filename == "memo.qmd"
    assert resolved.style_path is not None


def test_detect_template_flat_without_style_yaml_is_fine(tmp_path):
    source = _write_flat_source(tmp_path / "source", with_style=False)
    resolved = detect_template(source, type_name=None)
    assert resolved.style_path is None


def test_detect_template_typed_without_type_lists_available_names(tmp_path):
    source = tmp_path / "source"
    _write_flat_source(source / "templates" / "alpha")
    _write_flat_source(source / "templates" / "beta")

    with pytest.raises(TemplatesError) as exc_info:
        detect_template(source, type_name=None)
    assert "alpha" in str(exc_info.value)
    assert "beta" in str(exc_info.value)


def test_detect_template_typed_unknown_type_lists_available_names(tmp_path):
    source = tmp_path / "source"
    _write_flat_source(source / "templates" / "alpha")

    with pytest.raises(TemplatesError) as exc_info:
        detect_template(source, type_name="bogus")
    assert "alpha" in str(exc_info.value)


def test_detect_template_typed_with_known_type(tmp_path):
    source = tmp_path / "source"
    _write_flat_source(source / "templates" / "alpha")
    resolved = detect_template(source, type_name="alpha")
    assert resolved.kind == "typed"


def test_detect_template_type_given_but_source_is_flat_is_an_error(tmp_path):
    source = _write_flat_source(tmp_path / "source")
    with pytest.raises(TemplatesError):
        detect_template(source, type_name="alpha")


def test_detect_template_neither_structure_is_an_error(tmp_path):
    source = tmp_path / "empty"
    source.mkdir()
    with pytest.raises(TemplatesError):
        detect_template(source, type_name=None)


def test_detect_template_flat_requires_exactly_one_qmd(tmp_path):
    source = _write_flat_source(tmp_path / "source", qmd_name="report.qmd")
    (source / "extra.qmd").write_text("---\ntitle: Extra\n---\n")
    with pytest.raises(TemplatesError):
        detect_template(source, type_name=None)


# --- materialize_template -------------------------------------------------


def test_materialize_flat_generates_a_fresh_minimal_shell_qmd(tmp_path):
    source = _write_flat_source(tmp_path / "source", qmd_name="report.qmd")
    resolved = detect_template(source, type_name=None)
    target = tmp_path / "my-new-report"

    created, warnings = materialize_template(resolved, target, force=False)

    assert (target / "_quarto.yml").is_file()
    assert (target / "style.yaml").is_file()
    qmd_text = (target / "report.qmd").read_text()
    assert "document-status" in qmd_text
    assert "Source Report" not in qmd_text
    assert warnings == []
    assert len(created) == 3


def test_materialize_typed_copies_shell_qmd_verbatim(tmp_path):
    source = tmp_path / "source"
    _write_flat_source(source / "templates" / "alpha", qmd_name="alpha.qmd")
    resolved = detect_template(source, type_name="alpha")
    target = tmp_path / "my-new-report"

    created, _warnings = materialize_template(resolved, target, force=False)

    qmd_text = (target / "alpha.qmd").read_text()
    assert "Source Report" in qmd_text
    assert len(created) == 3


def test_materialize_warns_about_uncopied_local_logo(tmp_path):
    # Typed sources are the only ones whose qmd frontmatter gets scanned
    # (a flat source's shell .qmd is regenerated fresh, never copied).
    typed_source = tmp_path / "typed-source"
    _write_flat_source(typed_source / "templates" / "alpha", qmd_name="alpha.qmd", logo="assets/logo.png")
    resolved = detect_template(typed_source, type_name="alpha")
    _created, warnings = materialize_template(resolved, tmp_path / "target", force=False)
    assert any("assets/logo.png" in w for w in warnings)


def test_materialize_does_not_warn_about_a_url_logo(tmp_path):
    typed_source = tmp_path / "typed-source"
    _write_flat_source(
        typed_source / "templates" / "alpha", qmd_name="alpha.qmd", logo="https://example.com/logo.png"
    )
    resolved = detect_template(typed_source, type_name="alpha")
    _created, warnings = materialize_template(resolved, tmp_path / "target", force=False)
    assert warnings == []


def test_materialize_refuses_conflicting_file_without_force(tmp_path):
    source = _write_flat_source(tmp_path / "source")
    resolved = detect_template(source, type_name=None)
    target = tmp_path / "target"
    target.mkdir()
    (target / "_quarto.yml").write_text("sentinel")

    with pytest.raises(TemplatesError):
        materialize_template(resolved, target, force=False)
    assert (target / "_quarto.yml").read_text() == "sentinel"


def test_materialize_force_overwrites_conflicting_file(tmp_path):
    source = _write_flat_source(tmp_path / "source")
    resolved = detect_template(source, type_name=None)
    target = tmp_path / "target"
    target.mkdir()
    (target / "_quarto.yml").write_text("sentinel")

    materialize_template(resolved, target, force=True)
    assert (target / "_quarto.yml").read_text() != "sentinel"


# --- fetch_git_template (real git) ----------------------------------------


def _git(*args: str, cwd: Path) -> None:
    subprocess.run(
        ["git", "-c", "user.email=test@example.com", "-c", "user.name=Test", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
    )


def _make_upstream_repo(root: Path) -> Path:
    repo = root / "upstream"
    repo.mkdir()
    _git("init", cwd=repo)
    _write_flat_source(repo)
    _git("add", "-A", cwd=repo)
    _git("commit", "-m", "initial", cwd=repo)
    _git("tag", "v1", cwd=repo)
    return repo


@requires_git
def test_fetch_git_template_clones_and_checks_out_a_tag(tmp_path):
    repo = _make_upstream_repo(tmp_path)
    with fetch_git_template(str(repo), ref="v1", subdir=None) as source_dir:
        assert (source_dir / "_quarto.yml").is_file()


@requires_git
def test_fetch_git_template_scopes_into_a_subdir(tmp_path):
    repo = tmp_path / "upstream"
    repo.mkdir()
    _git("init", cwd=repo)
    _write_flat_source(repo / "templates" / "alpha")
    _git("add", "-A", cwd=repo)
    _git("commit", "-m", "initial", cwd=repo)

    with fetch_git_template(str(repo), ref=None, subdir="templates/alpha") as source_dir:
        assert (source_dir / "_quarto.yml").is_file()


@requires_git
def test_fetch_git_template_missing_subdir_is_an_error(tmp_path):
    repo = _make_upstream_repo(tmp_path)
    with pytest.raises(TemplatesError):
        with fetch_git_template(str(repo), ref="v1", subdir="does-not-exist"):
            pass


@requires_git
def test_fetch_git_template_bad_clone_url_is_an_error(tmp_path):
    with pytest.raises(TemplatesError):
        with fetch_git_template(str(tmp_path / "does-not-exist"), ref=None, subdir=None):
            pass


def test_fetch_git_template_requires_git_on_path(tmp_path, monkeypatch):
    monkeypatch.setattr(shutil, "which", lambda name: None)
    with pytest.raises(TemplatesError):
        with fetch_git_template(str(tmp_path), ref=None, subdir=None):
            pass
