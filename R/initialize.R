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
#' @param directory Target project directory. Defaults to the current
#'   directory.
#' @return Invisibly, the result of `pyro::initialize_python()`.
#' @export
initialize_quartifyr_project <- function(directory = ".") {
  # Pass venv_dir/pyproject_dir explicitly rather than relying on
  # pyro::get_proj_dir()'s cwd-based default (`getOption("venv_dir") %||%
  # here::here()`) -- here::here() caches the first root it resolves in an
  # R session and ignores later working-directory changes, confirmed
  # directly (see R/run-python.R's .run_quartifyr_styling_cli() for the
  # same issue and a longer explanation). A bare withr::with_dir() around
  # this call is not sufficient on its own.
  directory <- normalizePath(directory, mustWork = TRUE)
  pyro::write_group_to_pyproject(
    name = "quartifyr",
    deps = c("python-docx", "pyyaml"),
    pyproject_dir = directory
  )
  .ensure_default_groups_all(file.path(directory, "pyproject.toml"))
  invisible(pyro::initialize_python(
    venv_dir = directory,
    pyproject_dir = directory,
    groups = "quartifyr"
  ))
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
