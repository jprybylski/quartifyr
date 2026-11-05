# Command-line entry point behind `inst/scripts/check.R`: runs
# check_report_project() for a launcher or CI step and reports the findings,
# mirroring render.R (see R/render-cli.R).
#
# Contract:
#   stdout  the JSON result (with --json), else one line per finding.
#   stderr  usage and error messages.
#   exit    0 when there are no error findings (warnings are fine), 1 when
#           there are, 2 for bad usage.

.check_cli_usage <- function() {
  paste(
    "Usage: Rscript check.R --project <dir> --shell <report.qmd> [--json]",
    "",
    "  --project <dir>   Report project directory.",
    "  --shell <file>    Shell .qmd, relative to --project unless absolute.",
    "  --json            Print {schema_version, findings[{check, severity, path, message}]}.",
    "",
    "Exit status: 0 no errors, 1 at least one error finding, 2 bad usage.",
    sep = "\n"
  )
}

.check_findings_json <- function(findings) {
  jsonlite::toJSON(
    list(
      schema_version = 1L,
      findings = .rows_as_list(as.data.frame(unclass(findings), stringsAsFactors = FALSE))
    ),
    auto_unbox = TRUE, null = "null", na = "null", pretty = TRUE
  )
}

# Returns the exit status (invisibly); the script passes it to quit().
.check_cli <- function(args, out = stdout(), err = stderr()) {
  parsed <- tryCatch(
    .parse_cli_args(args, value_options = c("project", "shell"), flag_options = c("json", "help")),
    error = function(e) e
  )
  if (inherits(parsed, "error") || isTRUE(parsed$help)) {
    if (inherits(parsed, "error")) {
      writeLines(conditionMessage(parsed), err)
    }
    writeLines(.check_cli_usage(), if (inherits(parsed, "error")) err else out)
    return(invisible(if (inherits(parsed, "error")) 2L else 0L))
  }
  missing <- setdiff(c("project", "shell"), names(parsed))
  if (length(missing) > 0) {
    writeLines(paste0("Missing required option(s): --", paste(missing, collapse = ", --")), err)
    writeLines(.check_cli_usage(), err)
    return(invisible(2L))
  }

  shell_qmd <- .cli_shell_path(parsed$project, parsed$shell)
  # An unexpected failure is itself a finding the caller must see, not a crash
  # with no JSON.
  findings <- tryCatch(
    check_report_project(shell_qmd),
    error = function(e) {
      .as_findings(list(.finding("internal-error", "error", shell_qmd, conditionMessage(e))))
    }
  )

  if (isTRUE(parsed$json)) {
    writeLines(as.character(.check_findings_json(findings)), out)
  } else if (nrow(findings) == 0) {
    writeLines("No findings.", out)
  } else {
    writeLines(paste0(findings$severity, " [", findings$check, "] ", findings$message), out)
  }
  invisible(if (any(findings$severity == "error")) 1L else 0L)
}
