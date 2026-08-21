#' Initialize a report project's quartifyr Python environment
#'
#' Provisions a project-local Python environment via pyro (writing a
#' `quartifyr` dependency group to the calling project's `pyproject.toml`)
#' so `render_report()`'s `styling_*()` calls have a `quartifyr_styling`
#' venv to run against. Call this once per report project, alongside
#' `reportifyr::initialize_report_project()` -- not implied by
#' `render_report()` itself, since re-provisioning on every render would be
#' wasteful.
#'
#' When `from_dir`/`from_repo` is given (issue #23), also scaffolds
#' `directory`'s `_quarto.yml`/style YAML/shell `.qmd` from a template
#' source instead of leaving `directory` empty: either a local directory
#' (`from_dir`) or a git repo (`from_repo`), fetched and materialized the
#' same way `../deckifyr`'s `initialize_deck_project()` does for its own
#' `design.yaml`/`layouts.yaml`/`presentation.yaml`. A template source is
#' either "flat" (a directory with its own `_quarto.yml` and exactly one
#' `.qmd` file at its root -- its `_quarto.yml`/`style.yaml`, if present,
#' are duplicated as-is, paired with a freshly generated, minimal shell
#' `.qmd`) or "typed" (a directory with a `templates/` subdirectory, each
#' holding its own named flat template -- select one with `type`; its
#' shell `.qmd` is copied verbatim as a real minimal starter, not
#' emptied).
#'
#' @section A stale-venv gotcha in existing reportifyr projects:
#' On a project already initialized by reportifyr *before* it depended on
#' pyro (reportifyr < 0.4.0), this can fail with an opaque error from
#' `pyro::initialize_python()`'s underlying `uv sync` call -- that
#' project's Python environment predates pyro/uv and isn't necessarily
#' something `uv` can adopt as-is. Run
#' `reportifyr::initialize_report_project(project_dir = directory)` first
#' (safe to re-run) to bring the environment up to a pyro-compatible
#' state before calling this function. This function catches that failure
#' and re-raises with a pointer to the same fix, instead of letting
#' pyro/uv's raw error propagate uninterpreted.
#'
#' @param directory Target project directory. Defaults to the current
#'   directory.
#' @param from_dir Use a local directory as the template source instead
#'   of leaving `directory` empty. Mutually exclusive with `from_repo`.
#' @param from_repo Fetch a git repo as the template source:
#'   `"[host/]owner/repo[/subdir][@ref]"` shorthand (host defaults to
#'   github.com -- an explicit host is how GitHub Enterprise is
#'   supported) or a full URL. Requires `git` on PATH. Mutually
#'   exclusive with `from_dir`.
#' @param ref Branch/tag/SHA to check out. Only valid with `from_repo`;
#'   overrides any `@ref` embedded in its shorthand.
#' @param subdir Subdirectory of the resolved repo to use as the
#'   template source. Only valid with `from_repo`; overrides any
#'   subdirectory embedded in its shorthand.
#' @param type Template name under a source's `templates/<name>/`
#'   structure. Only valid alongside `from_dir`/`from_repo`.
#' @param force Overwrite existing `_quarto.yml`/style YAML/shell `.qmd`
#'   files in `directory`. Only meaningful alongside `from_dir`/`from_repo`.
#'   Default `FALSE`.
#' @return Invisibly, the result of `pyro::initialize_python()`.
#' @examples
#' \dontrun{
#' # Provision the Python environment only (this mutates the calling
#' # project's pyproject.toml and provisions a Python/uv environment --
#' # run it somewhere disposable, not the current project).
#' project_dir <- file.path(tempdir(), "my-report")
#' initialize_quartifyr_project(project_dir)
#'
#' # Also scaffold _quarto.yml/style.yaml/report.qmd from an org-standard
#' # template repo, pinned to a tag, selecting the "csr" template type.
#' initialize_quartifyr_project(
#'   project_dir,
#'   from_repo = "acme-org/quartifyr-templates@v2",
#'   type = "csr"
#' )
#' }
#' @export
initialize_quartifyr_project <- function(directory = ".", from_dir = NULL, from_repo = NULL,
                                          ref = NULL, subdir = NULL, type = NULL, force = FALSE) {
  # Pass venv_dir/pyproject_dir explicitly rather than relying on
  # pyro::get_proj_dir()'s cwd-based default (`getOption("venv_dir") %||%
  # here::here()`) -- here::here() caches the first root it resolves in an
  # R session and ignores later working-directory changes, confirmed
  # directly (see R/run-python.R's .run_quartifyr_styling_cli() for the
  # same issue and a longer explanation). A bare withr::with_dir() around
  # this call is not sufficient on its own.
  directory <- normalizePath(directory, mustWork = TRUE)
  .seed_pyproject_stub(directory)
  pyro::write_group_to_pyproject(
    name = "quartifyr",
    deps = c("python-docx", "pyyaml"),
    pyproject_dir = directory
  )
  .ensure_default_groups_all(file.path(directory, "pyproject.toml"))
  python_result <- tryCatch(
    pyro::initialize_python(
      venv_dir = directory,
      pyproject_dir = directory,
      groups = "quartifyr"
    ),
    error = function(e) {
      cli::cli_abort(
        c(
          "x" = "pyro failed to provision a Python environment in {.path {directory}}.",
          "!" = paste(
            "This can happen in an existing reportifyr project created before",
            "reportifyr 0.4.0 added its own pyro dependency -- its Python setup",
            "predates pyro/uv, and pyro's {.code uv sync} against that stale",
            "environment is what's failing below, not this function itself."
          ),
          "i" = paste(
            "Run {.code reportifyr::initialize_report_project(project_dir = \"{directory}\")}",
            "first (safe to re-run on an already-initialized project) to bring the",
            "environment up to a pyro-compatible state, then retry."
          ),
          "i" = "Underlying error: {conditionMessage(e)}"
        ),
        call = NULL,
        parent = e
      )
    }
  )

  if (!is.null(from_dir) || !is.null(from_repo)) {
    init_args <- c("init", directory)
    if (!is.null(from_dir)) {
      init_args <- c(init_args, "--from-dir", from_dir)
    }
    if (!is.null(from_repo)) {
      init_args <- c(init_args, "--from-repo", from_repo)
    }
    if (!is.null(ref)) {
      init_args <- c(init_args, "--ref", ref)
    }
    if (!is.null(subdir)) {
      init_args <- c(init_args, "--subdir", subdir)
    }
    if (!is.null(type)) {
      init_args <- c(init_args, "--type", type)
    }
    if (isTRUE(force)) {
      init_args <- c(init_args, "--force")
    }
    withr::with_dir(directory, .run_quartifyr_styling_cli(init_args))
  }

  invisible(python_result)
}

#' Pre-seed a minimal pyproject.toml before pyro can seed it incorrectly
#'
#' `pyro::write_group_to_pyproject()` is a no-op when `pyproject.toml`
#' doesn't exist yet (it only edits an existing file). On a project where
#' `reportifyr::initialize_report_project()` hasn't already created that
#' file, that leaves `pyro::initialize_python(groups = "quartifyr")` --
#' called right after -- to seed it instead, via `pyro`'s own
#' `seed_pyproject()`. `"quartifyr"` isn't one of the group names in
#' `pyro`'s *bundled* spec (only `reportifyr`/`presentifyr` are), and
#' `pyro`'s seeding falls back to `character()` deps for unrecognized
#' groups -- which its `render_subgroup()` then renders as a single
#' spurious empty-string entry (`quartifyr = [\n    "",\n]`) due to an
#' R `paste0()` recycling quirk (`paste0("x", character(0))` returns
#' `"x"`, not `character(0)`). `uv` rejects that as "Empty field is not
#' allowed for PEP508", breaking `initialize_quartifyr_project()` on a
#' project where it's the first `pyro`-based initializer to run.
#' Confirmed directly against the installed `pyro` package (0.1.1); see
#' `tests/testthat/test-initialize.R`.
#'
#' Writing a minimal, valid `pyproject.toml` here -- before
#' `write_group_to_pyproject()`/`initialize_python()` run -- ensures the
#' file already exists by the time `pyro::initialize_python()` checks, so
#' it skips its own (buggy, for unrecognized group names) seeding step
#' entirely; `write_group_to_pyproject()` is what ends up creating the
#' `quartifyr` group instead, with the real, non-empty deps this package
#' controls. `requires-python = ">=3.12"` matches `pyro`'s own bundled
#' spec (not this repo's separate, looser `>=3.10` for the standalone
#' `quartifyr-styling` Python package) so the constraint is the same
#' regardless of whether this or `reportifyr::initialize_report_project()`
#' seeds the shared venv's `pyproject.toml` first.
#'
#' @param directory Target project directory (already normalized).
#' @return `TRUE` if the file was created, `FALSE` if it already existed
#'   (invisibly).
#' @keywords internal
.seed_pyproject_stub <- function(directory) {
  toml_path <- file.path(directory, "pyproject.toml")
  if (file.exists(toml_path)) {
    return(invisible(FALSE))
  }
  proj_name <- gsub("[^A-Za-z0-9._-]+", "-", basename(directory))
  proj_name <- sub("^[._-]+", "", proj_name)
  if (!nzchar(proj_name)) {
    proj_name <- "project"
  }
  writeLines(
    c(
      "[project]",
      sprintf("name = \"%s\"", proj_name),
      "version = \"0.0.1\"",
      "requires-python = \">=3.12\""
    ),
    toml_path
  )
  invisible(TRUE)
}

#' Ensure a project's pyproject.toml defaults every dependency group on
#'
#' A report project's `pyproject.toml` ends up with more than one
#' `[dependency-groups]` entry sharing one venv: `reportifyr`'s own
#' (from `reportifyr::initialize_report_project()`) and `quartifyr`'s
#' (above). `uv run`/`uv sync` only include *default* groups unless a
#' call explicitly passes `--group`/`--all-groups` -- and both
#' `reportifyr::validate_docx()` (external, `reportipyr.cli`) and, before
#' a fix, this package's own `.run_quartifyr_styling_cli()` invoke a bare
#' `uv run` with no group flag at all, which resyncs the venv down to
#' *zero* groups, silently uninstalling whichever group(s) aren't
#' explicitly requested -- confirmed the hard way against a fully fresh
#' venv in CI, as an import error inside whichever tool ran second.
#' `default-groups = "all"` (uv's own supported `[tool.uv]` config, not a
#' quartifyr invention) makes *every* bare `uv run`/`uv sync` call include
#' every declared group by default, which is the only fix available for
#' the bug in `reportifyr::validate_docx()` specifically, since that's
#' external code this package doesn't control.
#'
#' @param pyproject_path Path to the `pyproject.toml` to check/edit.
#' @return `TRUE` if the file was modified, `FALSE` otherwise (invisibly).
#' @keywords internal
.ensure_default_groups_all <- function(pyproject_path) {
  if (!file.exists(pyproject_path)) {
    return(invisible(FALSE))
  }
  lines <- readLines(pyproject_path, warn = FALSE)

  if (any(grepl("^\\s*default-groups\\s*=", lines))) {
    return(invisible(FALSE)) # respect whatever's already configured
  }

  tool_uv_idx <- which(grepl("^\\[tool\\.uv\\]\\s*$", lines))
  if (length(tool_uv_idx) > 0) {
    insert_at <- tool_uv_idx[[1]]
    lines <- append(lines, 'default-groups = "all"', after = insert_at)
  } else {
    # Trim trailing blank lines before appending, so this doesn't pile up
    # an extra blank line on top of one the file already ended with.
    while (length(lines) > 0 && !nzchar(trimws(lines[[length(lines)]]))) {
      lines <- lines[-length(lines)]
    }
    lines <- c(lines, "", "[tool.uv]", 'default-groups = "all"')
  }

  writeLines(lines, pyproject_path)
  invisible(TRUE)
}
