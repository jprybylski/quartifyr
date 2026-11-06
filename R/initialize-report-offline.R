#' Set up a reportifyr project without pyro, uv or the network
#'
#' `reportifyr::initialize_report_project()` creates the report folders, the
#' config files and the `.report_init.json` marker, but only after
#' `pyro::initialize_python()` has installed uv (with `curl`, if it isn't on
#' `PATH`) and run `uv lock` and `uv sync` against PyPI. This does the other
#' part on its own: the same folders, the same `config.yaml` and
#' `standard_footnotes.yaml` copied from reportifyr, and the same marker, for a
#' project whose Python runs from an environment you already have
#' (`python_env`, see [initialize_quartifyr_project()]). Nothing is installed,
#' no `.venv`, `pyproject.toml` or `uv.lock` is created, and nothing reaches the
#' network.
#'
#' It is safe to run again: anything that already exists is left as it is, the
#' marker included. (Running `reportifyr::initialize_report_project()` on a
#' project that already has its marker goes back through pyro and the network.)
#'
#' With a `python_env` set, [render_report()] runs reportifyr's pass 2 in that
#' same environment, so one environment serves both passes. reportifyr still
#' runs `uv` to do it, so uv must be installed, but it is told to use that
#' environment as it is and never syncs, resolves or downloads anything.
#'
#' @param project_dir The project directory (must exist).
#' @param python_env Path to a Python environment (or a project directory
#'   holding a `.venv`) with `python-docx`, `pyyaml` and `pillow`. Verified,
#'   not modified. Defaults to `getOption("quartifyr.python_env")`, then the
#'   `QUARTIFYR_PYTHON_ENV` environment variable; with neither, only the
#'   project scaffold is created.
#' @param report_dir_name,outputs_dir_name As for
#'   `reportifyr::initialize_report_project()`; the defaults are `"report"` and
#'   `"OUTPUTS"`.
#' @return `project_dir` (invisibly).
#' @examples
#' \dontrun{
#' initialize_report_project_offline(".", python_env = "/opt/envs/report")
#' initialize_quartifyr_project(".", python_env = "/opt/envs/report")
#'
#' # Then, with QUARTIFYR_PYTHON_ENV=/opt/envs/report set:
#' #   Rscript "$(Rscript -e 'cat(system.file("scripts", "render.R", package = "quartifyr"))')" \
#' #     --project . --shell report.qmd --strict --json --offline
#' }
#' @export
initialize_report_project_offline <- function(project_dir = ".", python_env = NULL,
                                              report_dir_name = NULL, outputs_dir_name = NULL) {
  project_dir <- normalizePath(project_dir, mustWork = TRUE)
  python_env <- .configured_python_env(python_env)
  if (!is.null(python_env)) {
    .verify_python_env(python_env, modules = .reportifyr_python_modules)
  }
  extdata <- function(name) system.file("extdata", name, package = "reportifyr")
  templates <- c(extdata("config.yaml"), extdata("standard_footnotes.yaml"))
  if (!all(nzchar(templates))) {
    cli::cli_abort(
      c(
        "x" = "The reportifyr package, which supplies the default {.file config.yaml} and {.file standard_footnotes.yaml}, is not installed.",
        "i" = "Install it (it is a dependency of quartifyr), then run this again."
      ),
      class = "quartifyr_report_project_offline",
      call = NULL
    )
  }

  report_dir <- file.path(project_dir, if (is.null(report_dir_name)) "report" else report_dir_name)
  outputs_dir <- file.path(project_dir, if (is.null(outputs_dir_name)) "OUTPUTS" else outputs_dir_name)

  readmes <- c(
    draft = "Directory for reportifyr draft documents",
    final = "Directory for reportifyr final document",
    scripts = "Directory for R and Rmd scripts for creating reportifyr documents",
    shell = "Directory for reportifyr shell"
  )
  for (name in names(readmes)) {
    dir.create(file.path(report_dir, name), showWarnings = FALSE, recursive = TRUE)
    readme <- file.path(report_dir, name, "readme.txt")
    if (!file.exists(readme)) writeLines(readmes[[name]], readme)
  }
  for (name in c("figures", "tables", "listings")) {
    dir.create(file.path(outputs_dir, name), showWarnings = FALSE, recursive = TRUE)
  }

  footnotes <- file.path(report_dir, "standard_footnotes.yaml")
  if (!file.exists(footnotes)) file.copy(extdata("standard_footnotes.yaml"), footnotes)
  config_path <- file.path(report_dir, "config.yaml")
  if (!file.exists(config_path)) {
    file.copy(extdata("config.yaml"), config_path)
    config <- yaml::read_yaml(config_path)
    if (!is.null(report_dir_name)) config$report_dir_name <- report_dir_name
    if (!is.null(outputs_dir_name)) config$outputs_dir_name <- outputs_dir_name
    yaml::write_yaml(config, config_path, handlers = list(logical = yaml::verbatim_logical))
  }

  # The marker reportifyr and pyro find the project by. Same name and fields
  # as reportifyr writes (`.report_init.json` for the default folder).
  marker <- file.path(project_dir, paste0(".", gsub("[/\\\\]", "_", basename(report_dir)), "_init.json"))
  if (!file.exists(marker)) {
    timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    writeLines(
      jsonlite::toJSON(
        list(
          creation_timestamp = timestamp,
          last_modified = timestamp,
          user = Sys.info()[["user"]],
          config = yaml::read_yaml(config_path),
          venv_dir = "."
        ),
        pretty = TRUE, auto_unbox = TRUE
      ),
      marker
    )
  }

  cli::cli_inform(c(
    "v" = "Report project set up in {.path {project_dir}} (no pyro, uv or network used).",
    if (is.null(python_env)) {
      c("i" = "Set {.envvar QUARTIFYR_PYTHON_ENV} or {.code options(quartifyr.python_env = )} so {.fn render_report} runs both passes in an environment you provide.")
    }
  ))
  invisible(project_dir)
}
