# Which LibreOffice the two headless steps (--recalculate-fields,
# --resolve-same-page-crossrefs) run. Same precedence as quarto_bin: an
# explicit argument, then QUARTIFYR_SOFFICE_BIN, then `soffice` on PATH.
.soffice_command <- function(soffice_bin = NULL) {
  if (!is.null(soffice_bin)) {
    return(soffice_bin)
  }
  from_env <- Sys.getenv("QUARTIFYR_SOFFICE_BIN")
  if (nzchar(from_env)) from_env else "soffice"
}

.check_soffice_bin_arg <- function(soffice_bin) {
  if (!is.null(soffice_bin) &&
    (!is.character(soffice_bin) || length(soffice_bin) != 1 || is.na(soffice_bin) || !nzchar(soffice_bin))) {
    stop("soffice_bin must be a single path to a LibreOffice executable.", call. = FALSE)
  }
  invisible(NULL)
}

# The full path `command` resolves to, or "" when it names nothing runnable:
# a bare command is looked up on PATH, anything with a directory part must be
# an existing, executable file.
.resolve_soffice <- function(command) {
  if (!grepl("[/\\\\]", command)) {
    return(unname(Sys.which(command)[[1]]))
  }
  path <- path.expand(command)
  if (file.exists(path) && !dir.exists(path) && file.access(path, mode = 1) == 0) path else ""
}

# NULL when LibreOffice is usable, else a finding (same shape as the other
# project preconditions) saying where it was looked for and how to fix it.
.check_soffice <- function(command) {
  if (nzchar(.resolve_soffice(command))) {
    return(NULL)
  }
  .finding(
    "soffice", "error", command,
    paste0(
      "LibreOffice executable not found or not executable: ", command,
      "\nInstall LibreOffice, or name it with `soffice_bin` / `--soffice-bin` ",
      "or the QUARTIFYR_SOFFICE_BIN environment variable."
    )
  )
}

# list(path, version) for the LibreOffice that will run, or NULL when it
# can't be found or won't report a version. `soffice --version` is slow on a
# cold start, so this is only asked when a LibreOffice step was requested.
.soffice_info <- function(command) {
  path <- .resolve_soffice(command)
  if (!nzchar(path)) {
    return(NULL)
  }
  version <- tryCatch(
    {
      res <- processx::run(path, "--version", error_on_status = FALSE, timeout = 60)
      first <- trimws(strsplit(res$stdout, "\n", fixed = TRUE)[[1]][1])
      if (isTRUE(res$status == 0) && !is.na(first) && nzchar(first)) first else NULL
    },
    error = function(e) NULL
  )
  list(path = path, version = version)
}
