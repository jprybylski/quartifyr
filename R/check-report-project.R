#' Check a report project without rendering it
#'
#' @description
#' A fast, render-free preflight. Reports everything that would make a
#' [render_report()] call fail, or come out with unfilled placeholders,
#' *before* the long Quarto + reportifyr build starts. It never invokes
#' Quarto, R subprocesses or Python, so it is cheap enough to call from a
#' launcher or a CI step ahead of queueing a job.
#'
#' It checks:
#' \itemize{
#'   \item the project preconditions `render_report()` itself enforces
#'     (the shell `.qmd` exists, `_quarto.yml` sets
#'     `output-dir: report/shell`, the reportifyr `*_init.json` marker is
#'     present, the reference-doc and `standard_footnotes.yaml` exist).
#'     `render_report()` shares this implementation, so the two can't
#'     disagree;
#'   \item that the required Quarto extensions are present in
#'     `_extensions/` (a directory scan, unlike [check_quarto_extensions()],
#'     which asks the Quarto CLI);
#'   \item every `{rpfy}:` placeholder in the `.qmd` (and every
#'     `synopsis:` `image:` entry in its front matter): the artifact exists
#'     under `figures_path`/`tables_path`, its
#'     `<stem>_<ext>_metadata.json` sidecar exists and parses, and the
#'     abbreviation keys and `meta_type` the sidecar references exist in
#'     `standard_footnotes.yaml`;
#'   \item placeholders that are the last thing in their section, which
#'     crashes reportifyr's `build_report()` (see the "Known upstream
#'     gotcha" section of [render_report()]).
#' }
#'
#' Placeholders are only recognized in the `.qmd` itself, not in files it
#' pulls in with `{{< include >}}`, and not inside HTML comments or fenced
#' code blocks.
#'
#' @param shell_qmd Path to the shell `.qmd`, as for [render_report()].
#' @param figures_path,tables_path Where the `{rpfy}:` artifacts live; default
#'   to `OUTPUTS/figures` and `OUTPUTS/tables` alongside `shell_qmd`, as for
#'   [render_report()].
#' @param standard_footnotes_yaml Path to `standard_footnotes.yaml`; defaults
#'   to `report/standard_footnotes.yaml` alongside `shell_qmd`.
#' @param reference_doc Path to the docx reference-template, as for
#'   [render_report()]. `NULL` (default) uses a `reference-doc` configured in
#'   the `.qmd` front matter or `_quarto.yml`, else the package default.
#' @param check_extensions Whether to check `_extensions/` for the required
#'   Quarto extensions (see [quartifyr_quarto_extensions]). Default `TRUE`.
#'
#' @return A data frame of class `quartifyr_findings` with one row per
#'   finding and columns `check` (a short identifier), `severity`
#'   (`"error"` or `"warning"`), `path` (the file concerned) and `message`.
#'   Zero rows when nothing is wrong. Errors are things that make a render
#'   fail or leave a placeholder unfilled; warnings are things worth a look.
#' @examples
#' \dontrun{
#' findings <- check_report_project("path/to/project/report.qmd")
#' findings
#' if (any(findings$severity == "error")) {
#'   stop("fix the errors above before rendering")
#' }
#' }
#' @export
check_report_project <- function(
  shell_qmd,
  figures_path = file.path(dirname(shell_qmd), "OUTPUTS", "figures"),
  tables_path = file.path(dirname(shell_qmd), "OUTPUTS", "tables"),
  standard_footnotes_yaml = file.path(dirname(shell_qmd), "report", "standard_footnotes.yaml"),
  reference_doc = NULL,
  check_extensions = TRUE
) {
  findings <- list()
  add <- function(f) {
    if (!is.null(f)) {
      findings[[length(findings) + 1L]] <<- f
    }
  }

  qmd_finding <- .check_shell_qmd(shell_qmd)
  if (!is.null(qmd_finding)) {
    # Nothing else is checkable without the shell .qmd.
    return(.as_findings(list(qmd_finding)))
  }
  project_dir <- dirname(normalizePath(shell_qmd, mustWork = TRUE))

  add(.check_output_dir(project_dir))
  add(.check_init_marker(project_dir))

  ref_path <- if (!is.null(reference_doc)) {
    reference_doc
  } else {
    .configured_reference_doc(project_dir, shell_qmd)
  }
  if (is.null(ref_path)) {
    ref_path <- system.file("templates", "org-reference.docx", package = "quartifyr")
  }
  add(.check_reference_doc(ref_path))

  footnotes_finding <- .check_footnotes_yaml(standard_footnotes_yaml)
  add(footnotes_finding)

  if (isTRUE(check_extensions)) {
    for (f in .check_extensions_on_disk(project_dir)) {
      add(f)
    }
  }

  footnotes <- NULL
  if (is.null(footnotes_finding)) {
    footnotes <- tryCatch(yaml::read_yaml(standard_footnotes_yaml), error = function(e) e)
    if (inherits(footnotes, "error")) {
      add(.finding(
        "footnotes-yaml-parse", "error", standard_footnotes_yaml,
        paste0("standard_footnotes_yaml does not parse as YAML: ", conditionMessage(footnotes))
      ))
      footnotes <- NULL
    }
  }

  placeholders <- .scan_placeholders(shell_qmd)
  for (f in .check_placeholder_artifacts(placeholders, figures_path, tables_path, footnotes)) {
    add(f)
  }
  for (f in .check_placeholder_placement(placeholders, shell_qmd)) {
    add(f)
  }

  .as_findings(findings)
}

# --- Findings plumbing ------------------------------------------------------

.finding <- function(check, severity, path, message) {
  data.frame(
    check = check,
    severity = severity,
    path = as.character(path),
    message = message,
    stringsAsFactors = FALSE
  )
}

.as_findings <- function(findings) {
  out <- if (length(findings) == 0) {
    .finding(character(0), character(0), character(0), character(0))
  } else {
    do.call(rbind, findings)
  }
  rownames(out) <- NULL
  class(out) <- c("quartifyr_findings", "data.frame")
  out
}

#' @export
print.quartifyr_findings <- function(x, ...) {
  if (nrow(x) == 0) {
    cli::cli_alert_success("No findings.")
    return(invisible(x))
  }
  n_err <- sum(x$severity == "error")
  n_warn <- sum(x$severity == "warning")
  cli::cli_h3("{n_err} error{?s}, {n_warn} warning{?s}")
  for (i in seq_len(nrow(x))) {
    line <- paste0("[", x$check[i], "] ", x$message[i])
    if (x$severity[i] == "error") {
      cli::cli_alert_danger("{line}")
    } else {
      cli::cli_alert_warning("{line}")
    }
  }
  invisible(x)
}

# Stop with the first error finding's message verbatim -- how
# render_report() consumes the shared precondition checks below, so its
# user-facing error text stays exactly what it was before they were
# factored out.
.stop_on_finding <- function(finding) {
  if (!is.null(finding)) {
    stop(finding$message, call. = FALSE)
  }
  invisible(NULL)
}

# --- Shared precondition checks (also used by render_report()) --------------
# Each returns NULL when satisfied, or a one-row finding data frame.

.check_shell_qmd <- function(shell_qmd) {
  if (!file.exists(shell_qmd)) {
    return(.finding("shell-qmd", "error", shell_qmd, paste0("shell_qmd not found: ", shell_qmd)))
  }
  NULL
}

.check_output_dir <- function(project_dir) {
  quarto_yml <- file.path(project_dir, "_quarto.yml")
  if (!file.exists(quarto_yml) || !any(grepl("output-dir:\\s*report/shell", readLines(quarto_yml, warn = FALSE)))) {
    return(.finding(
      "output-dir", "error", quarto_yml,
      paste0(
        "Expected ", quarto_yml, " to set `project: {output-dir: report/shell}` -- ",
        "reportifyr::make_doc_dirs() derives draft/final paths from the rendered docx living in ",
        "report/shell/, and without that _quarto.yml setting the render won't land there."
      )
    ))
  }
  NULL
}

.check_init_marker <- function(project_dir) {
  init_marker <- list.files(project_dir, pattern = "^\\.[^.]*_init\\.json$", all.files = TRUE)
  if (length(init_marker) == 0) {
    return(.finding(
      "init-marker", "error", project_dir,
      paste0(
        "No reportifyr *_init.json marker found in ", project_dir,
        "\nRun reportifyr::initialize_report_project(project_dir = \"", project_dir, "\") first."
      )
    ))
  }
  NULL
}

.check_reference_doc <- function(reference_doc) {
  if (!is.null(reference_doc) && !file.exists(reference_doc)) {
    return(.finding(
      "reference-doc", "error", reference_doc,
      paste0(
        "reference-doc not found: ", reference_doc,
        "\nBuild it first, e.g.: quartifyr::styling_build_reference_docx(",
        "\"inst/python/styles/default.yaml\", out = \"", reference_doc, "\")"
      )
    ))
  }
  NULL
}

.check_footnotes_yaml <- function(standard_footnotes_yaml) {
  if (!file.exists(standard_footnotes_yaml)) {
    return(.finding(
      "footnotes-yaml", "error", standard_footnotes_yaml,
      paste0("standard_footnotes_yaml not found: ", standard_footnotes_yaml)
    ))
  }
  NULL
}

# A `format: {docx: {reference-doc: ...}}` set in the shell's front matter or
# the project's _quarto.yml, resolved relative to the project directory. This
# is a cheap stand-in for quarto::quarto_inspect() (which shells out to
# Quarto); it doesn't reproduce Quarto's full merge precedence beyond
# "front matter wins over _quarto.yml", which is all a presence check needs.
.configured_reference_doc <- function(project_dir, shell_qmd) {
  from_list <- function(x) {
    docx <- if (is.list(x$format)) x$format$docx else NULL
    ref <- if (is.list(docx)) docx$`reference-doc` else NULL
    if (is.character(ref) && length(ref) == 1 && nzchar(ref)) ref else NULL
  }
  front <- tryCatch(.read_front_matter(shell_qmd), error = function(e) NULL)
  project <- tryCatch(
    yaml::read_yaml(file.path(project_dir, "_quarto.yml")),
    error = function(e) NULL
  )
  ref <- from_list(front)
  if (is.null(ref) && is.list(project)) {
    ref <- from_list(project)
  }
  if (is.null(ref)) {
    return(NULL)
  }
  if (grepl("^(/|[A-Za-z]:[/\\\\])", ref)) ref else file.path(project_dir, ref)
}

.read_front_matter <- function(qmd) {
  lines <- readLines(qmd, warn = FALSE)
  fences <- which(grepl("^---\\s*$", lines))
  if (length(fences) < 2 || fences[[1]] != 1) {
    return(list())
  }
  yaml::yaml.load(paste(lines[(fences[[1]] + 1):(fences[[2]] - 1)], collapse = "\n"))
}

# Disk scan of `_extensions/<owner>/<name>/_extension.yml`, so the preflight
# never needs the Quarto CLI (check_quarto_extensions() does).
.check_extensions_on_disk <- function(project_dir, extensions = quartifyr_quarto_extensions) {
  out <- list()
  for (i in seq_len(nrow(extensions))) {
    id <- extensions$id[i]
    ext_dir <- file.path(project_dir, "_extensions", id)
    installed <- file.exists(file.path(ext_dir, "_extension.yml")) ||
      file.exists(file.path(ext_dir, "_extension.yaml"))
    if (!installed) {
      required <- isTRUE(extensions$required[i])
      out[[length(out) + 1L]] <- .finding(
        "quarto-extension", if (required) "error" else "warning", ext_dir,
        paste0(
          if (required) "Required" else "Suggested", " Quarto extension not installed: ", id, ". ",
          extensions$reason[i], " Install it with quartifyr::install_quarto_extensions(\"", project_dir,
          "\") or quarto::quarto_add_extension(\"", id, "\")."
        )
      )
    }
  }
  out
}

# --- Placeholder scan ---------------------------------------------------------

.figure_extensions <- c("png", "jpg", "jpeg", "gif", "bmp", "tif", "tiff", "svg", "emf", "wmf")

# Splits one `{rpfy}:` value into its file names, mirroring reportifyr's own
# parse_magic_entries(): a bracketed `[a.png<width: 3>, b.png]` list or a
# single entry, each with optional trailing `<key: value>` args.
.parse_magic_value <- function(value) {
  value <- trimws(value)
  if (startsWith(value, "[") && endsWith(value, "]")) {
    chars <- strsplit(substr(value, 2, nchar(value) - 1), "")[[1]]
    entries <- character(0)
    current <- character(0)
    depth <- 0L
    for (ch in chars) {
      if (ch == "<") {
        depth <- depth + 1L
      } else if (ch == ">" && depth > 0L) {
        depth <- depth - 1L
      }
      if (ch == "," && depth == 0L) {
        entries <- c(entries, paste(current, collapse = ""))
        current <- character(0)
        next
      }
      current <- c(current, ch)
    }
    entries <- c(entries, paste(current, collapse = ""))
  } else {
    entries <- value
  }
  entries <- trimws(sub("<.*$", "", entries))
  entries[nzchar(entries)]
}

# Blank out HTML comments (keeping newlines, so line numbers stay right) and
# fenced code blocks.
.mask_qmd_lines <- function(lines) {
  txt <- paste(lines, collapse = "\n")
  hits <- gregexpr("(?s)<!--.*?-->", txt, perl = TRUE)
  regmatches(txt, hits) <- lapply(regmatches(txt, hits), function(x) gsub("[^\n]", "", x))
  masked <- strsplit(txt, "\n", fixed = TRUE)[[1]]
  length(masked) <- length(lines)
  masked[is.na(masked)] <- ""
  in_fence <- FALSE
  for (i in seq_along(masked)) {
    if (grepl("^\\s*(```|~~~)", masked[i])) {
      in_fence <- !in_fence
      masked[i] <- ""
    } else if (in_fence) {
      masked[i] <- ""
    }
  }
  masked
}

# Every `image:` value anywhere under the front matter's `synopsis:` list.
.synopsis_images <- function(front) {
  images <- character(0)
  walk <- function(x) {
    if (is.list(x)) {
      for (nm in names(x)) {
        if (identical(nm, "image") && is.character(x[[nm]])) {
          images <<- c(images, x[[nm]])
        }
      }
      for (el in x) {
        walk(el)
      }
    }
  }
  walk(front$synopsis)
  images
}

# Returns a data frame (name, source, line) of every placeholder the shell
# `.qmd` will emit: literal `{rpfy}:` lines in the body, plus the
# `synopsis:` `image:` entries synopsis.lua turns into magic strings.
.scan_placeholders <- function(shell_qmd) {
  lines <- readLines(shell_qmd, warn = FALSE)
  masked <- .mask_qmd_lines(lines)

  rows <- list()
  for (i in which(grepl("^\\s*\\{rpfy\\}:\\S", masked))) {
    value <- sub("^\\s*\\{rpfy\\}:", "", masked[i])
    for (nm in .parse_magic_value(value)) {
      rows[[length(rows) + 1L]] <- data.frame(name = nm, source = "body", line = i, stringsAsFactors = FALSE)
    }
  }

  front <- tryCatch(.read_front_matter(shell_qmd), error = function(e) list())
  for (nm in .synopsis_images(front)) {
    rows[[length(rows) + 1L]] <- data.frame(name = nm, source = "synopsis", line = NA_integer_, stringsAsFactors = FALSE)
  }

  if (length(rows) == 0) {
    return(data.frame(name = character(0), source = character(0), line = integer(0), stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

.artifact_kind <- function(name) {
  ext <- tolower(sub("^.*\\.([^.]+)$", "\\1", name))
  if (ext %in% .figure_extensions) "figure" else "table"
}

.sidecar_path <- function(artifact_path) {
  sub("^(.*)\\.([^.]+)$", "\\1_\\2_metadata.json", artifact_path)
}

# One finding per problem, never two for the same placeholder: if the
# artifact itself is missing, its sidecar isn't checked.
.check_placeholder_artifacts <- function(placeholders, figures_path, tables_path, footnotes) {
  out <- list()
  seen <- character(0)
  for (i in seq_len(nrow(placeholders))) {
    name <- placeholders$name[i]
    if (name %in% seen) {
      next
    }
    seen <- c(seen, name)

    kind <- .artifact_kind(name)
    dir <- if (kind == "figure") figures_path else tables_path
    artifact <- file.path(dir, name)
    where <- if (placeholders$source[i] == "synopsis") "synopsis image" else paste0("line ", placeholders$line[i])

    if (!file.exists(artifact)) {
      out[[length(out) + 1L]] <- .finding(
        "missing-artifact", "error", artifact,
        paste0("{rpfy}:", name, " (", where, ") has no ", kind, " file at ", artifact, ".")
      )
      next
    }

    sidecar <- .sidecar_path(artifact)
    if (!file.exists(sidecar)) {
      out[[length(out) + 1L]] <- .finding(
        "missing-sidecar", "error", sidecar,
        paste0(
          "{rpfy}:", name, " (", where, ") has no metadata sidecar at ", sidecar,
          " (reportifyr::make_figure_metadata()/make_table_metadata() writes it)."
        )
      )
      next
    }

    meta <- tryCatch(jsonlite::fromJSON(sidecar, simplifyVector = FALSE), error = function(e) e)
    if (inherits(meta, "error") || !is.list(meta$object_meta)) {
      out[[length(out) + 1L]] <- .finding(
        "invalid-sidecar", "error", sidecar,
        paste0("Metadata sidecar ", sidecar, " for {rpfy}:", name, " is not valid reportifyr metadata JSON.")
      )
      next
    }

    if (is.null(footnotes)) {
      next
    }
    object_meta <- meta$object_meta
    abbrevs <- unlist(object_meta$footnotes$abbreviations)
    known <- names(footnotes$abbreviations)
    unknown <- setdiff(abbrevs, known)
    if (length(unknown) > 0) {
      out[[length(out) + 1L]] <- .finding(
        "unknown-abbreviation", "error", sidecar,
        paste0(
          "Sidecar for {rpfy}:", name, " references abbreviation(s) not defined in ",
          "standard_footnotes.yaml: ", paste(unknown, collapse = ", "), "."
        )
      )
    }
    meta_type <- object_meta$meta_type
    if (is.character(meta_type) && length(meta_type) == 1 && !is.na(meta_type) && meta_type != "NA") {
      section <- footnotes[[paste0(kind, "_footnotes")]]
      if (!(meta_type %in% names(section))) {
        out[[length(out) + 1L]] <- .finding(
          "unknown-meta-type", "error", sidecar,
          paste0(
            "Sidecar for {rpfy}:", name, " has meta_type '", meta_type, "', which is not in the ",
            kind, "_footnotes section of standard_footnotes.yaml."
          )
        )
      }
    }
  }
  out
}

# A `{rpfy}:` line followed by nothing but the end of its section (a heading
# or the end of the file) crashes reportifyr's validate_alt_text_magic_strings();
# see render_report()'s "Known upstream gotcha".
.check_placeholder_placement <- function(placeholders, shell_qmd) {
  body <- placeholders[placeholders$source == "body", , drop = FALSE]
  if (nrow(body) == 0) {
    return(list())
  }
  masked <- .mask_qmd_lines(readLines(shell_qmd, warn = FALSE))
  out <- list()
  for (line in unique(body$line)) {
    rest <- masked[seq_along(masked) > line]
    rest <- rest[nzchar(trimws(rest))]
    next_line <- if (length(rest) > 0) rest[[1]] else NULL
    if (is.null(next_line) || grepl("^\\s*#{1,6}\\s", next_line)) {
      out[[length(out) + 1L]] <- .finding(
        "placeholder-last-in-section", "warning", shell_qmd,
        paste0(
          "The {rpfy}: placeholder at line ", line, " is the last thing in its section. ",
          "reportifyr's build_report() crashes when a magic string has no paragraph after it; ",
          "add at least one line of real content after it."
        )
      )
    }
  }
  out
}
