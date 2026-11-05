# Helpers behind render_report()'s structured result (the "job contract" a
# noninteractive caller, e.g. CI or a workspace launcher, relies on): what
# was produced, what was left unfilled, and whether to trust it.

# Magic strings reportifyr left unresolved in a docx.
#
# A filled draft still carries each `{rpfy}:` paragraph as plain text (so
# build_report() can be re-run on it); what marks it as filled is the
# inserted figure/table's alt text, which reportifyr stamps with
# `{rpfy}:<name> [hash:...]`. So a magic string is unfilled when its text
# appears more often than the alt-text markers for it do. After
# finalize_document() the text paragraphs are gone and nothing is reported.
# Paragraph text is rebuilt from `<w:t>` runs because Word/pandoc can split
# one string across several runs.
.scan_unfilled_placeholders <- function(docx) {
  if (is.null(docx) || !file.exists(docx)) {
    return(character(0))
  }
  exdir <- tempfile("quartifyr-docx-")
  on.exit(unlink(exdir, recursive = TRUE), add = TRUE)

  parts <- tryCatch(
    suppressWarnings(utils::unzip(docx, files = c("word/document.xml", "word/footnotes.xml"), exdir = exdir)),
    error = function(e) character(0)
  )
  decode <- function(x) {
    x <- gsub("&lt;", "<", x, fixed = TRUE)
    x <- gsub("&gt;", ">", x, fixed = TRUE)
    x <- gsub("&quot;", "\"", x, fixed = TRUE)
    gsub("&amp;", "&", x, fixed = TRUE)
  }

  in_text <- character(0)
  in_alt_text <- character(0)
  for (part in parts) {
    xml <- paste(readLines(part, warn = FALSE, encoding = "UTF-8"), collapse = "\n")

    alt <- regmatches(xml, gregexpr("\\{rpfy\\}:[^\"]*? \\[hash:", xml))[[1]]
    in_alt_text <- c(in_alt_text, trimws(sub(" \\[hash:$", "", decode(alt))))

    paragraphs <- strsplit(xml, "</w:p>", fixed = TRUE)[[1]]
    text <- decode(gsub("<[^>]+>", "", paragraphs))
    in_text <- c(in_text, trimws(regmatches(text, regexpr("\\{rpfy\\}:.*$", text))))
  }

  unfilled <- character(0)
  for (name in unique(in_text)) {
    if (sum(in_text == name) > sum(in_alt_text == name)) {
      unfilled <- c(unfilled, name)
    }
  }
  unfilled
}

# Names of the artifacts the shell's placeholders point at that exist but
# have no `<stem>_<ext>_metadata.json` sidecar.
.missing_sidecars <- function(shell_qmd, figures_path, tables_path) {
  placeholders <- tryCatch(.scan_placeholders(shell_qmd), error = function(e) NULL)
  if (is.null(placeholders) || nrow(placeholders) == 0) {
    return(character(0))
  }
  missing <- character(0)
  for (name in unique(placeholders$name)) {
    dir <- if (.artifact_kind(name) == "figure") figures_path else tables_path
    artifact <- file.path(dir, name)
    if (file.exists(artifact) && !file.exists(.sidecar_path(artifact))) {
      missing <- c(missing, name)
    }
  }
  missing
}

# With reportifyr's default footnotes_fail_on_missing_metadata = TRUE, a
# missing metadata sidecar makes build_report() itself fail with a generic
# "Figure footnotes script failed." -- the actual cause is only in its log.
# When pass 2 fails and the project files show missing sidecars, say so in
# the error, and carry them on the condition (`$missing_metadata`) so the
# JSON error report can list them. Any other failure passes through as-is.
.with_missing_metadata_context <- function(expr, project_dir, shell_qmd, figures_path, tables_path) {
  tryCatch(
    expr,
    error = function(e) {
      missing <- withr::with_dir(
        project_dir,
        tryCatch(.missing_sidecars(shell_qmd, figures_path, tables_path), error = function(e2) character(0))
      )
      if (length(missing) == 0) {
        stop(e)
      }
      stop(structure(
        class = c("quartifyr_pass2_failed", "error", "condition"),
        list(
          message = paste0(
            conditionMessage(e), "\nMissing metadata sidecar for: ", paste(missing, collapse = ", "),
            " (expected <stem>_<ext>_metadata.json next to each artifact)."
          ),
          call = NULL,
          parent = e,
          missing_metadata = missing
        )
      ))
    }
  )
}

# reportifyr writes one log file per R session under `<project>/.rpfy-logs/`
# and a long-lived session appends to the same file across renders. Snapshot
# each file's line count before pass 2 so only this run's lines are read.
.rpfy_log_snapshot <- function(log_dir) {
  files <- list.files(log_dir, pattern = "-rpfy\\.log$", full.names = TRUE)
  stats::setNames(
    vapply(files, function(f) length(readLines(f, warn = FALSE)), integer(1)),
    files
  )
}

.rpfy_log_new_lines <- function(log_dir, snapshot) {
  files <- list.files(log_dir, pattern = "-rpfy\\.log$", full.names = TRUE)
  out <- character(0)
  for (f in files) {
    lines <- readLines(f, warn = FALSE)
    already <- if (f %in% names(snapshot)) snapshot[[f]] else 0L
    if (length(lines) > already) {
      out <- c(out, lines[(already + 1L):length(lines)])
    }
  }
  out
}

# The two reportifyr 0.4.0 warnings that mean "a placeholder was left
# alone": a figure file it couldn't find, and a missing metadata sidecar.
# Returns the artifact each one names.
.parse_rpfy_log <- function(lines) {
  pick <- function(pattern) {
    hits <- regmatches(lines, regexpr(paste0(pattern, ".*$"), lines))
    unique(trimws(sub(paste0("^", pattern), "", hits)))
  }
  list(
    missing_figures = pick("Figure file not found:"),
    missing_metadata = pick("Metadata file not found for:")
  )
}

.sha256_file <- function(path) {
  # openssl returns a classed raw vector; as.character() on it keeps the
  # class, so hex-encode the bare bytes to get a plain string.
  paste(as.character(unclass(openssl::sha256(file(path)))), collapse = "")
}

# Where render_report() leaves each output, relative to the project: the
# shell docx quarto renders, and the files reportifyr's make_doc_dirs()
# derives from it by swapping "shell" for "draft"/"final" in the directory.
# make_doc_dirs() refuses a docx that doesn't exist yet, so the convention is
# repeated here to know what is about to be regenerated (a test compares the
# two so they can't drift apart).
.render_output_paths <- function(project_dir, stem) {
  list(
    shell = file.path(project_dir, "report", "shell", paste0(stem, ".docx")),
    draft = file.path(
      project_dir, "report", "draft",
      paste0(stem, c("-clean", "-tabs", "-tabsfigs", "-draft"), ".docx")
    ),
    final = file.path(project_dir, "report", "final", paste0(stem, "-final.docx"))
  )
}

# A render that fails, times out or is killed must not leave an earlier
# render's docx where a caller (or a person opening the folder) would take it
# for this render's. So before rendering, whatever this render is about to
# regenerate is moved to `report/.previous/<shell|draft|final>/`, replacing
# the copy already there. Returns the new paths of what was moved.
.move_previous_outputs <- function(project_dir, stem) {
  moved <- character(0)
  outputs <- .render_output_paths(project_dir, stem)
  for (role in names(outputs)) {
    existing <- outputs[[role]][file.exists(outputs[[role]])]
    if (length(existing) == 0) {
      next
    }
    dest_dir <- file.path(project_dir, "report", ".previous", role)
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
    for (path in existing) {
      dest <- file.path(dest_dir, basename(path))
      unlink(dest)
      if (!file.rename(path, dest)) {
        stop("Could not move the previous output ", path, " to ", dest, ".", call. = FALSE)
      }
      moved <- c(moved, dest)
    }
  }
  moved
}

# TRUE when `path` exists and was written by the render that began at
# `since`. The extra two seconds cover filesystems with coarse timestamps.
.produced_since <- function(path, since) {
  file.exists(path) && isTRUE(file.mtime(path) >= since - 2)
}

# role/path/sha256/bytes for each of `paths` that exists (and isn't in `skip`).
.file_table <- function(roles, paths, skip = character(0)) {
  keep <- !is.na(paths) & file.exists(paths) & !(paths %in% skip)
  roles <- roles[keep]
  paths <- paths[keep]
  data.frame(
    role = as.character(roles),
    path = as.character(paths),
    sha256 = vapply(paths, .sha256_file, character(1), USE.NAMES = FALSE),
    bytes = as.numeric(file.size(paths)),
    stringsAsFactors = FALSE
  )
}

.artifact_table <- function(shell, draft, final, skip = character(0)) {
  roles <- c(shell = shell, draft = draft, final = final)
  roles <- roles[!vapply(roles, is.null, logical(1))]
  paths <- unlist(roles, use.names = TRUE)
  .file_table(names(paths), unname(paths), skip)
}

# What went into a render, so a downstream build manifest can say which
# sources produced a document: the shell .qmd, every figure/table the shell
# references with its metadata sidecar, standard_footnotes.yaml, config.yaml
# and the reference-doc. Only files that exist are listed.
.input_table <- function(shell_qmd, figures_path, tables_path, standard_footnotes_yaml,
                         config_yaml, reference_doc) {
  roles <- c("shell_qmd", "standard_footnotes", "config", "reference_doc")
  paths <- c(shell_qmd, standard_footnotes_yaml, config_yaml, if (is.null(reference_doc)) NA_character_ else reference_doc)
  placeholders <- tryCatch(.scan_placeholders(shell_qmd), error = function(e) NULL)
  for (name in unique(if (is.null(placeholders)) character(0) else placeholders$name)) {
    kind <- .artifact_kind(name)
    artifact <- file.path(if (kind == "figure") figures_path else tables_path, name)
    roles <- c(roles, kind, "sidecar")
    paths <- c(paths, artifact, .sidecar_path(artifact))
  }
  .file_table(roles, paths)
}

# Tool versions that shaped the output. A version that can't be determined is
# NULL (null in the JSON) rather than missing, so consumers see it was asked.
.tool_versions <- function(quarto_command) {
  pkg_version <- function(pkg) {
    tryCatch(as.character(utils::packageVersion(pkg)), error = function(e) NULL)
  }
  quarto <- tryCatch(
    {
      res <- processx::run(quarto_command, "--version", error_on_status = FALSE, timeout = 30)
      version <- trimws(res$stdout)
      if (isTRUE(res$status == 0) && nzchar(version)) version else NULL
    },
    error = function(e) NULL
  )
  list(
    quartifyr = pkg_version("quartifyr"),
    reportifyr = pkg_version("reportifyr"),
    quarto = quarto,
    quartifyr_styling = .styling_version(),
    r = as.character(getRversion())
  )
}

# The bundled quartifyr_styling package's version, read from its source
# rather than by running Python (which would be one more subprocess that can
# need uv).
.styling_version <- function(
  init = system.file("python", "quartifyr_styling", "__init__.py", package = "quartifyr")
) {
  if (!nzchar(init)) {
    return(NULL)
  }
  hit <- grep("^__version__\\s*=", readLines(init, warn = FALSE), value = TRUE)
  if (length(hit) == 0) {
    return(NULL)
  }
  gsub("^[^\"']*[\"']|[\"'][^\"']*$", "", hit[[1]])
}

.timestamp_utc <- function(time = Sys.time()) {
  format(time, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

# status is about whether the delivered document is complete, not whether R
# threw: "error" = unfilled placeholders or a requested post-processing step
# that failed; "warning" = complete but something reportifyr flagged (e.g. a
# missing metadata sidecar); "ok" = nothing to report.
.new_render_result <- function(shell, draft, final, warnings = character(0), errors = character(0),
                               unfilled_placeholders = character(0), missing_metadata = character(0),
                               log_dir = NULL, not_produced = character(0), inputs = NULL,
                               versions = NULL, started_at = NULL, finished_at = NULL) {
  status <- if (length(errors) > 0 || length(unfilled_placeholders) > 0) {
    "error"
  } else if (length(warnings) > 0 || length(missing_metadata) > 0) {
    "warning"
  } else {
    "ok"
  }
  structure(
    list(
      shell = shell,
      draft = draft,
      final = final,
      status = status,
      artifacts = .artifact_table(shell, draft, final, skip = not_produced),
      warnings = unique(as.character(warnings)),
      errors = unique(as.character(errors)),
      unfilled_placeholders = unique(as.character(unfilled_placeholders)),
      missing_metadata = unique(as.character(missing_metadata)),
      log_dir = log_dir,
      inputs = inputs,
      versions = versions,
      started_at = started_at,
      finished_at = finished_at
    ),
    class = c("quartifyr_render_result", "list")
  )
}

#' @export
print.quartifyr_render_result <- function(x, ...) {
  cli::cli_h3("quartifyr render: {x$status}")
  for (role in c("shell", "draft", "final")) {
    if (!is.null(x[[role]])) {
      cli::cli_text("{role}: {.path {x[[role]]}}")
    }
  }
  if (length(x$unfilled_placeholders) > 0) {
    cli::cli_alert_danger("{length(x$unfilled_placeholders)} unfilled placeholder{?s}: {x$unfilled_placeholders}")
  }
  if (length(x$missing_metadata) > 0) {
    cli::cli_alert_warning("{length(x$missing_metadata)} missing metadata sidecar{?s}: {x$missing_metadata}")
  }
  for (msg in x$errors) {
    cli::cli_alert_danger("{msg}")
  }
  for (msg in x$warnings) {
    cli::cli_alert_warning("{msg}")
  }
  invisible(x)
}

# One-line description of why a result isn't "ok", for the strict-mode error.
.describe_incomplete <- function(result) {
  parts <- c(
    if (length(result$unfilled_placeholders) > 0) {
      paste0(length(result$unfilled_placeholders), " unfilled placeholder(s): ",
             paste(result$unfilled_placeholders, collapse = ", "))
    },
    if (length(result$missing_metadata) > 0) {
      paste0("missing metadata for: ", paste(result$missing_metadata, collapse = ", "))
    },
    result$errors,
    result$warnings
  )
  paste0("Render is incomplete: ", paste(parts, collapse = "; "), ".")
}

# Under strict mode an incomplete render is a failure, so the result carried
# on the condition says so: status "error", with the reason in `errors`,
# even when the render itself only warned.
.abort_incomplete <- function(result) {
  message <- .describe_incomplete(result)
  result$status <- "error"
  result$errors <- unique(c(result$errors, message))
  stop(structure(
    class = c("quartifyr_render_incomplete", "error", "condition"),
    list(message = message, call = NULL, result = result)
  ))
}

# Version of the JSON shape in inst/schemas/render-result-v1.schema.json.
# New optional fields keep it; removing or renaming one bumps it (and the
# schema file name).
.render_schema_version <- 1L

.rows_as_list <- function(df) {
  lapply(seq_len(nrow(df)), function(i) as.list(df[i, , drop = FALSE]))
}

# Plain-list form of a result, ready for jsonlite. Empty vectors become [],
# `final = NULL` becomes null, artifacts and inputs become arrays of objects.
.render_result_as_list <- function(result) {
  arr <- function(x) as.list(as.character(x))
  list(
    schema_version = .render_schema_version,
    status = result$status,
    shell = result$shell,
    draft = result$draft,
    final = result$final,
    artifacts = .rows_as_list(result$artifacts),
    warnings = arr(result$warnings),
    errors = arr(result$errors),
    unfilled_placeholders = arr(result$unfilled_placeholders),
    missing_metadata = arr(result$missing_metadata),
    log_dir = result$log_dir,
    inputs = if (is.null(result$inputs)) list() else .rows_as_list(result$inputs),
    versions = if (is.null(result$versions)) stats::setNames(list(), character(0)) else result$versions,
    started_at = result$started_at,
    finished_at = result$finished_at
  )
}

.render_result_json <- function(result, pretty = TRUE) {
  jsonlite::toJSON(
    .render_result_as_list(result),
    auto_unbox = TRUE, null = "null", pretty = pretty, na = "null"
  )
}
