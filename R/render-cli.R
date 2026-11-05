# Command-line entry point behind `inst/scripts/render.R`: runs
# render_report() for a noninteractive caller (CI, a launcher running a
# background job) and reports the outcome as JSON on stdout. Kept in the
# package, with the script a one-line wrapper, so the argument handling and
# exit-code contract are unit-testable without spawning a subprocess.
#
# Contract:
#   stdout  the JSON result (with --json), nothing else. Anything the render
#           itself prints to stdout is re-routed to stderr so it can't
#           corrupt the JSON.
#   stderr  progress, warnings and error messages.
#   exit    0 only when the render finished and (with --strict) its status
#           is "ok". Any error, including a quarto failure or timeout, is
#           reported as a JSON object with status "error" and exits 1.
#           Bad usage exits 2. Without --strict, exit 0 only means the render
#           finished: read `status`.

.render_cli_value_options <- c(
  "project", "shell", "status", "reference-doc", "style", "override",
  "quarto-timeout", "quarto-bin"
)
.render_cli_flag_options <- c("json", "strict", "offline", "recalculate-fields", "resolve-same-page-crossrefs", "help")

# `--project <dir> --shell <file>`: the shell is relative to the project
# unless it is an existing absolute path.
.cli_shell_path <- function(project, shell) {
  if (file.exists(shell) && grepl("^(/|[A-Za-z]:[/\\\\])", shell)) shell else file.path(project, shell)
}

.render_cli_usage <- function() {
  paste(
    "Usage: Rscript render.R --project <dir> --shell <report.qmd> [options]",
    "",
    "  --project <dir>                 Report project directory (run with this as the working",
    "                                  directory so its renv library activates).",
    "  --shell <file>                  Shell .qmd, relative to --project unless absolute.",
    "  --status draft|final            Default: draft.",
    "  --json                          Print the result as JSON on stdout.",
    "  --strict                        Exit non-zero unless the result status is \"ok\". Without it,",
    "                                  exit 0 only means the render finished, not that it was complete.",
    "  --offline                       No network: set UV_OFFLINE/UV_NO_INDEX/UV_NO_SYNC for the render.",
    "                                  Default: on when quartifyr.offline or UV_OFFLINE is set.",
    "  --quarto-timeout <seconds>      Default 600; Inf disables.",
    "  --quarto-bin <path>             Quarto executable (default: QUARTO_PATH, then PATH).",
    "  --reference-doc <file>          docx reference-doc.",
    "  --style <file>, --override <file>   Style YAML paths (see render_report()).",
    "  --recalculate-fields            Run the headless-LibreOffice field recalculation.",
    "  --resolve-same-page-crossrefs   Run the headless-LibreOffice crossref resolution.",
    sep = "\n"
  )
}

.parse_cli_args <- function(args, value_options = .render_cli_value_options,
                            flag_options = .render_cli_flag_options) {
  parsed <- list()
  i <- 1L
  while (i <= length(args)) {
    arg <- args[[i]]
    if (!startsWith(arg, "--")) {
      stop("Unexpected argument: ", arg, call. = FALSE)
    }
    name <- sub("^--", "", arg)
    value <- NULL
    if (grepl("=", name, fixed = TRUE)) {
      value <- sub("^[^=]*=", "", name)
      name <- sub("=.*$", "", name)
    }
    if (name %in% flag_options) {
      parsed[[name]] <- TRUE
    } else if (name %in% value_options) {
      if (is.null(value)) {
        if (i == length(args)) {
          stop("Option --", name, " needs a value.", call. = FALSE)
        }
        i <- i + 1L
        value <- args[[i]]
      }
      parsed[[name]] <- value
    } else {
      stop("Unknown option: --", name, call. = FALSE)
    }
    i <- i + 1L
  }
  parsed
}

.render_cli_error_json <- function(e, started_at = NULL, finished_at = NULL) {
  # An incomplete strict render carries the full result; report all of it.
  if (inherits(e, "quartifyr_render_incomplete") && !is.null(e$result)) {
    payload <- .render_result_as_list(e$result)
  } else {
    payload <- list(
      schema_version = .render_schema_version,
      status = "error",
      errors = list(conditionMessage(e)),
      started_at = started_at,
      finished_at = finished_at
    )
  }
  if (!is.null(e$missing_metadata)) {
    payload$missing_metadata <- as.list(e$missing_metadata)
  }
  payload$error_class <- class(e)[[1]]
  jsonlite::toJSON(payload, auto_unbox = TRUE, null = "null", pretty = TRUE)
}

# Returns the exit status (invisibly); the script passes it to quit().
.render_cli <- function(args, out = stdout(), err = stderr()) {
  parsed <- tryCatch(.parse_cli_args(args), error = function(e) e)
  if (inherits(parsed, "error") || isTRUE(parsed$help)) {
    if (inherits(parsed, "error")) {
      writeLines(conditionMessage(parsed), err)
    }
    writeLines(.render_cli_usage(), if (inherits(parsed, "error")) err else out)
    return(invisible(if (inherits(parsed, "error")) 2L else 0L))
  }
  missing <- setdiff(c("project", "shell"), names(parsed))
  if (length(missing) > 0) {
    writeLines(paste0("Missing required option(s): --", paste(missing, collapse = ", --")), err)
    writeLines(.render_cli_usage(), err)
    return(invisible(2L))
  }

  project <- parsed$project
  shell <- parsed$shell
  shell_qmd <- .cli_shell_path(project, shell)
  call_args <- list(
    shell_qmd = shell_qmd,
    status = if (is.null(parsed$status)) "draft" else parsed$status,
    strict = isTRUE(parsed$strict),
    recalculate_fields = isTRUE(parsed$`recalculate-fields`),
    resolve_same_page_crossrefs = isTRUE(parsed$`resolve-same-page-crossrefs`)
  )
  if (isTRUE(parsed$offline)) call_args$offline <- TRUE
  if (!is.null(parsed$`reference-doc`)) call_args$reference_doc <- parsed$`reference-doc`
  if (!is.null(parsed$style)) call_args$style <- parsed$style
  if (!is.null(parsed$override)) call_args$override <- parsed$override
  if (!is.null(parsed$`quarto-bin`)) call_args$quarto_bin <- parsed$`quarto-bin`
  if (!is.null(parsed$`quarto-timeout`)) {
    timeout <- suppressWarnings(as.numeric(parsed$`quarto-timeout`))
    if (is.na(timeout)) {
      writeLines(paste0("--quarto-timeout must be a number of seconds, got: ", parsed$`quarto-timeout`), err)
      return(invisible(2L))
    }
    call_args$quarto_timeout <- timeout
  }

  # Whatever the render prints to stdout (pyro/reportifyr progress, stray
  # print() calls) goes to stderr, so stdout carries the JSON and nothing else.
  outcome <- NULL
  started_at <- .timestamp_utc()
  noise <- utils::capture.output(
    outcome <- tryCatch(do.call(render_report, call_args), error = function(e) e),
    type = "output"
  )
  if (length(noise) > 0) {
    writeLines(noise, err)
  }

  if (inherits(outcome, "error")) {
    writeLines(paste0("quartifyr render failed: ", conditionMessage(outcome)), err)
    if (isTRUE(parsed$json)) {
      writeLines(as.character(.render_cli_error_json(outcome, started_at, .timestamp_utc())), out)
    }
    return(invisible(1L))
  }

  if (isTRUE(parsed$json)) {
    writeLines(as.character(.render_result_json(outcome)), out)
  } else {
    writeLines(c(
      paste0("status: ", outcome$status),
      paste0("shell: ", outcome$shell),
      paste0("draft: ", outcome$draft),
      if (!is.null(outcome$final)) paste0("final: ", outcome$final)
    ), out)
  }
  invisible(0L)
}
