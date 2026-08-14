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
  invisible(pyro::initialize_python(
    venv_dir = directory,
    pyproject_dir = directory,
    groups = "quartifyr"
  ))
}
