# One Python environment for both passes.
#
# `python_env` (option `quartifyr.python_env`, or QUARTIFYR_PYTHON_ENV) already
# replaces pyro/uv for quartifyr's own Python calls (R/run-python.R).
# reportifyr's pass 2 is a different story: it goes through pyro, which looks
# for `<venv_dir>/.venv` (`getOption("venv_dir")`, else the project root) and
# runs `uv run -m reportipyr.cli` against it. Left alone, a render with a
# python_env still needs the project's own `.venv` and lets uv sync it or
# write a `uv.lock`. So when a python_env is set, the render points pyro at it
# and tells uv to use exactly that environment and not touch the project:
#
#   options(venv_dir)        a directory whose `.venv` is the environment, for
#                            pyro's get_venv_uv_paths() (it also sets
#                            VIRTUAL_ENV from it)
#   UV_PROJECT_ENVIRONMENT   the environment uv runs in, in place of the
#                            project's `.venv` (without it uv ignores
#                            VIRTUAL_ENV and creates `.venv` next to
#                            pyproject.toml)
#   UV_NO_SYNC               never sync it, and with it never write uv.lock
#
# uv still has to be installed (reportifyr runs it), but it never reaches the
# network and creates nothing in the project.

# The venv directory behind a python_env, which is either a venv itself or a
# project directory that holds a `.venv` (the same two shapes .python_exe()
# accepts).
.python_env_venv <- function(env) {
  env <- .absolute_path(env)
  if (file.exists(file.path(env, "pyvenv.cfg"))) {
    return(env)
  }
  nested <- file.path(env, ".venv")
  if (dir.exists(nested)) {
    return(nested)
  }
  env
}

# options() and environment variables that point reportifyr's pass 2 at
# `env`. A venv that isn't called `.venv` is exposed through a symlink in a
# temporary directory (pyro insists on `<venv_dir>/.venv`); the directory
# lives as long as `.local_envir`.
.python_env_wiring <- function(env, .local_envir = parent.frame()) {
  venv <- .python_env_venv(env)
  if (basename(venv) == ".venv") {
    venv_dir <- dirname(venv)
  } else {
    venv_dir <- withr::local_tempdir(pattern = "quartifyr-venv-", .local_envir = .local_envir)
    linked <- suppressWarnings(file.symlink(venv, file.path(venv_dir, ".venv")))
    if (!isTRUE(linked)) {
      cli::cli_abort(
        c(
          "x" = "Cannot point reportifyr at the Python environment {.path {venv}}.",
          "i" = paste(
            "reportifyr's pass 2 (through pyro) needs it to be called {.file .venv}, and the symlink that",
            "would stand in for that name could not be created. Rename the environment to {.file .venv}",
            "or pass its project directory as {.arg python_env}."
          )
        ),
        class = "quartifyr_python_env_invalid",
        call = NULL
      )
    }
  }
  list(
    options = list(venv_dir = venv_dir),
    env = c(UV_PROJECT_ENVIRONMENT = venv, UV_NO_SYNC = "1")
  )
}

# Applies .python_env_wiring() for the rest of the caller's frame, after
# checking the environment can run reportifyr's pass 2. A no-op without a
# python_env.
.use_python_env_for_pass2 <- function(.local_envir = parent.frame()) {
  env <- .configured_python_env()
  if (is.null(env)) {
    return(invisible(NULL))
  }
  .verify_python_env(env, modules = .reportifyr_python_modules)
  wiring <- .python_env_wiring(env, .local_envir = .local_envir)
  do.call(withr::local_options, c(wiring$options, list(.local_envir = .local_envir)))
  withr::local_envvar(wiring$env, .local_envir = .local_envir)
  invisible(wiring)
}
