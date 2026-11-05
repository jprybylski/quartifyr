# Offline / pre-provisioned operation (no network during init or render).
#
# quartifyr itself only needs the network in three places, all during setup:
# provisioning its Python dependency group through pyro/uv, fetching a
# template with `from_repo`, and installing a Quarto extension with
# `quarto add`. This file holds the pieces that let each of them be replaced
# with something local, and that name the step when one can't be.

# TRUE when quartifyr should assume no network: the `quartifyr.offline`
# option, or uv's own UV_OFFLINE environment variable (which uv itself
# honours, so a user who already set it gets consistent behaviour).
.offline_mode <- function() {
  isTRUE(getOption("quartifyr.offline")) ||
    tolower(Sys.getenv("UV_OFFLINE")) %in% c("1", "true", "yes", "on")
}

# Signals an error of class `quartifyr_offline_failure` saying which step
# needed the network, which resource it was after, and how to provide that
# locally. `step`, `resource` and `how` are cli templates evaluated in `env`
# (the caller's frame by default), so they can use {.arg}/{.path} markup and
# the caller's own variables; `how` may be a character vector, one bullet
# each.
.abort_offline <- function(step, resource, how, parent = NULL, env = parent.frame()) {
  cli::cli_abort(
    c(
      "x" = paste0("Cannot ", step, " without network access."),
      "!" = paste0("It needs ", resource, "."),
      stats::setNames(how, rep("i", length(how)))
    ),
    class = "quartifyr_offline_failure",
    call = NULL,
    parent = parent,
    .envir = env
  )
}

# The pre-provisioned Python environment to use instead of a pyro/uv one:
# an explicit argument, else `options(quartifyr.python_env)`, else the
# QUARTIFYR_PYTHON_ENV environment variable. Returns NULL when none is set.
.configured_python_env <- function(python_env = NULL) {
  env <- python_env
  if (is.null(env)) {
    env <- getOption("quartifyr.python_env")
  }
  if (is.null(env) || !nzchar(env)) {
    env <- Sys.getenv("QUARTIFYR_PYTHON_ENV")
  }
  if (is.null(env) || !nzchar(env)) {
    return(NULL)
  }
  env
}

# Makes a path absolute without resolving symlinks. That matters for a
# venv's `bin/python`: it is usually a symlink to the base interpreter, and
# Python finds its `pyvenv.cfg` (hence its site-packages) from the path it was
# *invoked* as, so normalizePath() -- which follows symlinks -- would run the
# base interpreter and make every module in the venv look missing.
.absolute_path <- function(path) {
  path <- path.expand(path)
  if (grepl("^(/|[A-Za-z]:[/\\\\])", path)) path else file.path(getwd(), path)
}

# The interpreter inside an environment directory: a venv itself, or a
# project directory that holds a `.venv`.
.python_exe <- function(env) {
  env <- .absolute_path(env)
  candidates <- c(
    file.path(env, "bin", "python"),
    file.path(env, "Scripts", "python.exe"),
    file.path(env, ".venv", "bin", "python"),
    file.path(env, ".venv", "Scripts", "python.exe")
  )
  found <- candidates[file.exists(candidates)]
  if (length(found) == 0) {
    cli::cli_abort(
      c(
        "x" = "No Python interpreter found in the configured Python environment {.path {env}}.",
        "i" = paste(
          "Expected {.path {candidates[1]}} (or {.path {candidates[2]}}), or the same under",
          "{.file .venv/} if this is a project directory."
        )
      ),
      class = "quartifyr_python_env_invalid",
      call = NULL
    )
  }
  found[[1]]
}

# What a pre-provisioned environment has to be able to import, and the PyPI
# distribution that provides each module.
.required_python_modules <- c(docx = "python-docx", yaml = "pyyaml", quartifyr_styling = "quartifyr_styling")

# PYTHONPATH for running the bundled quartifyr_styling source (inst/python)
# with an interpreter that doesn't have it installed.
.python_src <- function() {
  python_src <- system.file("python", package = "quartifyr")
  if (!nzchar(python_src)) {
    stop(
      "quartifyr's bundled Python source (inst/python) was not found in ",
      "the installed package -- reinstall the quartifyr R package.",
      call. = FALSE
    )
  }
  python_src
}

.python_env_vars <- function() {
  existing <- Sys.getenv("PYTHONPATH")
  c("current", PYTHONPATH = if (nzchar(existing)) paste(.python_src(), existing, sep = .Platform$path.sep) else .python_src())
}

# Checks that `env` provides every module quartifyr needs, naming what is
# missing. quartifyr_styling counts as present because the bundled source is
# put on PYTHONPATH. Returns the interpreter path.
.verify_python_env <- function(env) {
  python <- .python_exe(env)
  probe <- paste(
    "import importlib.util",
    sprintf("mods = %s", paste0("[", paste0("'", names(.required_python_modules), "'", collapse = ", "), "]")),
    "print(','.join(m for m in mods if importlib.util.find_spec(m) is None))",
    sep = "\n"
  )
  res <- processx::run(python, c("-c", probe), env = .python_env_vars(), error_on_status = FALSE)
  if (!isTRUE(res$status == 0)) {
    cli::cli_abort(
      c(
        "x" = "The Python interpreter {.path {python}} could not be run.",
        "i" = "Underlying error: {trimws(res$stderr)}"
      ),
      class = "quartifyr_python_env_invalid",
      call = NULL
    )
  }
  missing <- Filter(nzchar, strsplit(trimws(res$stdout), ",", fixed = TRUE)[[1]])
  if (length(missing) > 0) {
    packages <- unname(.required_python_modules[missing])
    cli::cli_abort(
      c(
        "x" = "The Python environment {.path {env}} is missing required module{?s}: {.val {missing}}.",
        "i" = paste(
          "Install {.val {packages}} into it, for example",
          "{.code pip install --no-index --find-links <wheel-dir> python-docx pyyaml}."
        )
      ),
      class = "quartifyr_python_env_invalid",
      call = NULL
    )
  }
  python
}

# pyro runs uv_setup.sh through processx and lets the failure propagate as
# "System command 'uv_setup.sh' failed", with the script's stderr -- the part
# that says what uv actually objected to -- only on the condition object.
# Pull it out (last lines are the useful ones) so errors can show it.
.process_error_detail <- function(e, max_lines = 12) {
  for (cond in list(e, e$parent)) {
    text <- cond$stderr
    if (is.character(text) && nzchar(trimws(paste(text, collapse = "")))) {
      lines <- strsplit(paste(text, collapse = "\n"), "\n", fixed = TRUE)[[1]]
      lines <- lines[nzchar(trimws(lines))]
      return(paste(utils::tail(lines, max_lines), collapse = "\n"))
    }
  }
  conditionMessage(e)
}
