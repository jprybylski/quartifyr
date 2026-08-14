#' Invoke the bundled quartifyr-styling Python CLI via pyro
#'
#' Internal helper every exported `styling_*()` function funnels through --
#' the single bridge point, so docx-generation/layout logic is never
#' reimplemented in R (mirrors ../deckifyr's `.run_deckifyr_cli()` pattern).
#' Always requests `--json` so results come back as a parsed R list rather
#' than needing prose scraping.
#'
#' **Why this isn't a thin wrapper around `pyro::run_python_script()`:**
#' confirmed against a real pyro install, `run_python_script()` calls
#' `processx::run(..., error_on_status = TRUE)` and, on any non-zero exit,
#' discards the captured stdout/stderr entirely and raises a bare
#' "<script_name> failed." -- so `quartifyr-styling`'s own diagnostic JSON
#' (emitted to stderr on error when `--json` is passed, see
#' `inst/python/quartifyr_styling/cli.py`'s module docstring) would
#' otherwise be lost. The fix is `stderr_callback`: processx invokes it per
#' output chunk *while the process is still running*, before the exit-status
#' check fires, so output captured that way survives even when the call
#' ultimately errors. This only works because `cli.py` deliberately writes
#' its JSON error payload to stderr rather than stdout on the error path --
#' don't change one side of this handshake without the other.
#'
#' @param args Character vector of CLI arguments *after* `quartifyr-styling`,
#'   e.g. `c("build", "--style", "path/to/style.yaml", "--out", "out.docx")`.
#' @return A parsed list from the CLI's JSON output.
#' @keywords internal
.run_quartifyr_styling_cli <- function(args) {
  python_src <- system.file("python", package = "quartifyr")
  if (!nzchar(python_src)) {
    stop(
      "quartifyr's bundled Python source (inst/python) was not found in ",
      "the installed package -- reinstall the quartifyr R package.",
      call. = FALSE
    )
  }

  # pyro::get_venv_uv_paths() takes no arguments -- it resolves the
  # project/venv directory via pyro::get_proj_dir(), which is
  # `getOption("venv_dir") %||% here::here()`. here::here() caches the
  # *first* root it resolves in an R session and ignores later
  # setwd()/withr::with_dir() calls (confirmed directly: calling
  # get_proj_dir() from two different withr::with_dir()-scoped
  # directories in the same session returns the *first* directory both
  # times) -- exactly the class of cwd-based footgun this repo's CLAUDE.md
  # already warns about for reportifyr/pyro's own project detection.
  # Setting `venv_dir` explicitly here, scoped to the caller's *current*
  # getwd() (which callers set via withr::with_dir(project_dir, ...)
  # before calling any styling_*() wrapper), sidesteps here::here()
  # entirely rather than relying on it.
  withr::local_options(venv_dir = getwd())
  paths <- pyro::get_venv_uv_paths()
  cli_args <- c("run", "-m", "quartifyr_styling", "--json", args)

  stderr_lines <- character(0)
  capture_stderr <- function(chunk, proc) {
    stderr_lines <<- c(stderr_lines, chunk)
  }

  # `outcome` is either the list pyro::run_python_script() returns on
  # success, or the caught `error` condition on failure -- inspecting its
  # class below, rather than mutating an outer variable from inside the
  # tryCatch expression, sidesteps a real R scoping trap: a bare `{ ... }`
  # block passed as `expr` does NOT get its own environment, so a
  # `var <<- value` inside it (when `var` already exists in that same
  # enclosing frame) skips right past that local binding and writes to a
  # *further* enclosing scope instead. See ../deckifyr's
  # `.run_deckifyr_cli()` for the same pattern, confirmed there the hard
  # way via an earlier version that silently left "captured" stdout
  # permanently NULL.
  outcome <- tryCatch(
    pyro::run_python_script(
      uv_path = paths$uv,
      venv_path = paths$venv,
      args = cli_args,
      script_name = "quartifyr-styling",
      pythonpath = python_src,
      stderr_callback = capture_stderr
    ),
    error = function(e) e
  )

  command_desc <- paste("uv run -m quartifyr_styling", paste(args, collapse = " "))

  if (inherits(outcome, "error")) {
    # The process exited non-zero; pyro's own error message is generic
    # ("quartifyr-styling failed."), so recover the real diagnostic from
    # the stderr we captured via the callback above -- cli.py writes
    # exactly one JSON error object there on failure when --json is set.
    stderr_text <- paste(stderr_lines, collapse = "")
    parsed_error <- tryCatch(
      jsonlite::fromJSON(stderr_text, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (!is.null(parsed_error) && identical(parsed_error$status, "error")) {
      stop(
        sprintf(
          "quartifyr-styling %s failed [%s]: %s",
          args[[1]], parsed_error$code, parsed_error$message
        ),
        "\n  command: ", command_desc,
        call. = FALSE
      )
    }
    stop(
      "quartifyr-styling ", args[[1]], " failed and did not produce a ",
      "parseable error payload.\n  command: ", command_desc,
      "\n  stderr: ", stderr_text,
      call. = FALSE
    )
  }

  parsed <- tryCatch(
    jsonlite::fromJSON(outcome$stdout, simplifyVector = FALSE),
    error = function(e) {
      stop(
        "quartifyr-styling CLI exited successfully but did not return ",
        "valid JSON.\n  command: ", command_desc, "\n  stdout: ", outcome$stdout,
        call. = FALSE
      )
    }
  )

  parsed
}
