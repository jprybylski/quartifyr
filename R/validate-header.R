#' Parse a .qmd's raw YAML frontmatter block
#'
#' Reads the block between the first two `---` lines directly with `yaml`,
#' the same way `inst/python/quartifyr_styling/layout.py`'s
#' `read_qmd_frontmatter()` does -- deliberately *not* `quarto::quarto_inspect()`,
#' which resolves frontmatter through Quarto's own config engine and, for
#' this extension's purposes, actively gets one thing wrong: `project:` is
#' a reserved Quarto project-config key, and Quarto's inspector silently
#' drops a document-level `project:` field from its parsed metadata (e.g.
#' `examples/demo-report/report.qmd`'s `project: "ACME-001"`, fed into
#' `header-format: "{project} - {report_number}"`). `apply-layout`'s own
#' `header-format:` resolution reads raw frontmatter for exactly this
#' reason, so `validate_header()` has to match it to check the same thing
#' it actually affects. This also means `validate_header()` needs no
#' Quarto installation at all -- useful for a brand-new project that
#' hasn't set one up yet (see `header_helper()`).
#'
#' @param shell_qmd Path to the `.qmd` file.
#' @return The parsed frontmatter as a list (`list()` if the file has none).
#' @keywords internal
.read_qmd_frontmatter <- function(shell_qmd) {
  lines <- readLines(shell_qmd, warn = FALSE)
  if (length(lines) == 0 || !identical(trimws(lines[[1]]), "---")) {
    return(list())
  }
  end <- which(trimws(lines[-1]) == "---")
  if (length(end) == 0) {
    return(list())
  }
  block <- lines[seq(2, end[[1]])]
  parsed <- yaml::yaml.load(paste(block, collapse = "\n"))
  if (is.null(parsed)) list() else parsed
}

#' Structural front-matter checks beyond the per-field registry
#'
#' Each check is `function(fm, shell_qmd, quarto_yml)` returning `NULL`
#' (no problem) or a single message string. Registered here (rather than
#' as one-off `if` statements inside `validate_header()`) for the same
#' "evergreen" reason the field registry is: adding a new cross-field rule
#' shouldn't require touching `validate_header()`'s own control flow.
#'
#' @return A list of `list(id, severity, check)` specs. `severity` is
#'   `"error"` (breaks or silently no-ops the render -- see each message)
#'   or `"warn"` (works, but likely not what's intended).
#' @keywords internal
.header_structural_checks <- function() {
  get <- .header_field_get

  list(
    list(
      id = "title-memo-conflict", severity = "error",
      check = function(fm, shell_qmd, quarto_yml) {
        if (!is.null(fm[["title"]]) && !is.null(fm[["memo"]])) {
          "Both `title:` and `memo:` are set -- memo_cover.lua skips the memo cover (with a render-time warning) and title_page.lua's title page renders instead. Remove one."
        }
      }
    ),
    list(
      id = "no-cover", severity = "error",
      check = function(fm, shell_qmd, quarto_yml) {
        if (is.null(fm[["title"]]) && is.null(fm[["memo"]])) {
          "Neither `title:` nor `memo:` is set -- no cover page will render, and (since `title:` also feeds it) neither will the Synopsis' automatic \"Title\" row."
        }
      }
    ),
    list(
      id = "quartifyr-filter-missing", severity = "error",
      check = function(fm, shell_qmd, quarto_yml) {
        filters <- unlist(get(fm, "filters"))
        if (!("quartifyr" %in% filters)) {
          "`filters:` does not include `quartifyr` -- none of this extension's frontmatter (title page, signature page, synopsis, appendices, ...) has any effect without it."
        }
      }
    ),
    list(
      id = "quarto-plus-filter-missing", severity = "warn",
      check = function(fm, shell_qmd, quarto_yml) {
        filters <- unlist(get(fm, "filters"))
        if ("quartifyr" %in% filters && !("quarto-plus" %in% filters)) {
          "`filters:` includes `quartifyr` but not `quarto-plus` -- the ToC/List of Figures/List of Tables/abbreviations divs and `fig_caption`/`tbl_caption`/`crossref` shortcodes come from quarto-plus. (quartifyr's own `.quartifyr_list_of_figures`/`.quartifyr_list_of_tables`/scoped caption shortcodes don't need quarto-plus at all, unless a document also mixes in its continuous `fig_caption`/`tbl_caption`.)"
        }
      }
    ),
    list(
      id = "docx-format-missing", severity = "error",
      check = function(fm, shell_qmd, quarto_yml) {
        fmt <- fm[["format"]]
        has_docx <- (is.character(fmt) && "docx" %in% fmt) ||
          (is.list(fmt) && "docx" %in% names(fmt))
        if (!has_docx) {
          "`format:` does not include `docx` -- this extension only targets Word output."
        }
      }
    ),
    list(
      id = "header-format-placeholders", severity = "error",
      check = function(fm, shell_qmd, quarto_yml) {
        template <- get(fm, "header-format")
        if (is.null(template)) {
          return(NULL)
        }
        placeholders <- unique(unlist(regmatches(
          template, gregexpr("\\{([A-Za-z0-9_.-]+)\\}", template)
        )))
        keys <- setdiff(gsub("[{}]", "", placeholders), "status")
        missing <- keys[!vapply(keys, function(k) !is.null(fm[[k]]), logical(1))]
        if (length(missing) > 0) {
          paste0(
            "`header-format: \"", template, "\"` references placeholder(s) not found in frontmatter: ",
            paste(sprintf("{%s}", missing), collapse = ", "),
            " -- apply-layout will error resolving the header (see render_report())."
          )
        }
      }
    ),
    list(
      id = "crossref-hyperlinks-value", severity = "error",
      check = function(fm, shell_qmd, quarto_yml) {
        value <- get(fm, "crossref-hyperlinks")
        if (is.null(value)) {
          return(NULL)
        }
        ok <- isTRUE(value) || isFALSE(value) || identical(value, "same-page")
        if (!ok) {
          paste0("`crossref-hyperlinks: ", value, "` is not recognized -- use `true`, `false`, or `\"same-page\"`.")
        }
      }
    ),
    list(
      id = "appendix-numbering-value", severity = "warn",
      check = function(fm, shell_qmd, quarto_yml) {
        value <- get(fm, "appendix-numbering")
        if (is.null(value) || value %in% c("alphabetic", "arabic", "roman")) {
          return(NULL)
        }
        paste0("`appendix-numbering: ", value, "` is not recognized -- falls back to \"alphabetic\" with a render-time warning.")
      }
    ),
    list(
      id = "signature-note-missing", severity = "warn",
      check = function(fm, shell_qmd, quarto_yml) {
        mode <- get(fm, "signature-mode")
        note <- get(fm, "signature-note")
        if (identical(mode, "note") && is.null(note)) {
          "`signature-mode: \"note\"` is set without `signature-note:` -- signature blocks fall back to an empty space instead of a note."
        }
      }
    ),
    list(
      id = "logo-file-missing", severity = "warn",
      check = function(fm, shell_qmd, quarto_yml) {
        logo <- get(fm, "logo")
        if (is.null(logo)) {
          return(NULL)
        }
        logo_path <- file.path(dirname(shell_qmd), logo)
        if (!file.exists(logo_path)) {
          paste0("`logo: \"", logo, "\"` does not exist relative to the .qmd (looked in ", logo_path, ").")
        }
      }
    ),
    list(
      id = "bibliography-file-missing", severity = "warn",
      check = function(fm, shell_qmd, quarto_yml) {
        bib <- get(fm, "bibliography")
        if (is.null(bib)) {
          return(NULL)
        }
        bib_path <- file.path(dirname(shell_qmd), bib)
        if (!file.exists(bib_path)) {
          paste0("`bibliography: \"", bib, "\"` does not exist relative to the .qmd (looked in ", bib_path, ").")
        }
      }
    ),
    list(
      id = "quarto-yml-output-dir", severity = "error",
      check = function(fm, shell_qmd, quarto_yml) {
        if (is.null(quarto_yml) || !file.exists(quarto_yml)) {
          return("No `_quarto.yml` found next to the .qmd -- render_report() requires one setting `project: {output-dir: report/shell}`.")
        }
        lines <- readLines(quarto_yml, warn = FALSE)
        if (!any(grepl("output-dir:\\s*report/shell", lines))) {
          paste0(
            basename(quarto_yml), " does not set `project: {output-dir: report/shell}` -- ",
            "render_report() derives report/draft//report/final from this (reportifyr::make_doc_dirs())."
          )
        }
      }
    )
  )
}

#' Validate a quartifyr shell `.qmd`'s front matter
#'
#' Checks `shell_qmd`'s YAML frontmatter (and the project's `_quarto.yml`)
#' against every field this package's Quarto extension and `apply-layout`
#' step actually read, and prints a cli-formatted report: what's provided,
#' what's missing (required or merely recommended), what else is
#' available and what it does, and any structural conflicts (e.g. both
#' `title:` and `memo:` set, or a `header-format:` placeholder that
#' doesn't resolve). Driven entirely by the shared field registry (see
#' `R/header-fields.R`), so it stays in sync with the extension by
#' construction rather than by separately-maintained documentation.
#'
#' @param shell_qmd Path to the shell `.qmd`.
#' @param quarto_yml Path to the project's `_quarto.yml`. `NULL` (default)
#'   looks for one next to `shell_qmd`.
#' @param quiet Suppress the cli report and just return the result. Default `FALSE`.
#' @param strict Abort (via `cli::cli_abort()`) if any required field is
#'   missing or any `"error"`-severity structural check fails. Default `FALSE`.
#' @return Invisibly, a list with `ok` (logical), `provided`,
#'   `missing_required`, `missing_recommended`, `available` (each a
#'   character vector of field keys), and `problems` (a data frame of
#'   `id`/`severity`/`message` from the structural checks).
#' @examples
#' # A minimal shell .qmd -- title/format/filters are set, but there's no
#' # _quarto.yml next to it yet. The printed report below is real output,
#' # not a curated transcript: it reflects the current field registry
#' # (R/header-fields.R) exactly, so it can't drift from what
#' # validate_header() actually checks.
#' tmp <- tempfile(fileext = ".qmd")
#' writeLines(
#'   c(
#'     "---",
#'     "title: \"Demo Report\"",
#'     "filters:",
#'     "  - quarto-plus",
#'     "  - quartifyr",
#'     "format: docx",
#'     "---",
#'     "",
#'     "Body text."
#'   ),
#'   tmp
#' )
#' validate_header(tmp)
#' @export
validate_header <- function(shell_qmd, quarto_yml = NULL, quiet = FALSE, strict = FALSE) {
  if (!file.exists(shell_qmd)) {
    cli::cli_abort("shell_qmd not found: {.path {shell_qmd}}")
  }
  if (is.null(quarto_yml)) {
    quarto_yml <- file.path(dirname(shell_qmd), "_quarto.yml")
  }

  fm <- .read_qmd_frontmatter(shell_qmd)
  fields <- .quartifyr_header_fields()
  fields <- Filter(function(f) isTRUE(f$applies_when(fm)), fields)

  is_set <- function(f) !is.null(.header_field_get(fm, f$path))
  provided <- Filter(is_set, fields)
  missing <- Filter(Negate(is_set), fields)
  missing_required <- Filter(function(f) isTRUE(f$required(fm)), missing)
  missing_recommended <- Filter(function(f) !isTRUE(f$required(fm)) && isTRUE(f$recommended(fm)), missing)
  available <- Filter(function(f) !isTRUE(f$required(fm)) && !isTRUE(f$recommended(fm)), missing)

  checks <- .header_structural_checks()
  problems <- do.call(rbind, lapply(checks, function(chk) {
    msg <- chk$check(fm, shell_qmd, quarto_yml)
    if (is.null(msg)) {
      return(NULL)
    }
    data.frame(id = chk$id, severity = chk$severity, message = msg, stringsAsFactors = FALSE)
  }))
  if (is.null(problems)) {
    problems <- data.frame(id = character(), severity = character(), message = character(), stringsAsFactors = FALSE)
  }

  ok <- length(missing_required) == 0 && !any(problems$severity == "error")

  result <- list(
    ok = ok,
    provided = vapply(provided, `[[`, character(1), "key"),
    missing_required = vapply(missing_required, `[[`, character(1), "key"),
    missing_recommended = vapply(missing_recommended, `[[`, character(1), "key"),
    available = vapply(available, `[[`, character(1), "key"),
    problems = problems
  )

  if (!quiet) {
    .print_header_validation(shell_qmd, provided, missing_required, missing_recommended, available, problems)
  }

  if (strict && !ok) {
    cli::cli_abort("validate_header({.path {shell_qmd}}) found blocking issues -- see the report above.", call = NULL)
  }

  invisible(result)
}

#' Build a `cli::cli_bullets()`-ready named character vector
#' @keywords internal
.bullets <- function(symbol, messages) {
  names(messages) <- rep(symbol, length(messages))
  messages
}

#' Escape literal `{`/`}` for cli's glue-style interpolation
#'
#' Field descriptions and structural-check messages are plain prose that
#' quotes YAML syntax (`{label, value}`, `header-format:`'s own
#' `{placeholder}` templates, ...) -- cli's `{.field ...}`-style markup
#' uses the same glue delimiters, so any of that prose reaching
#' `cli_bullets()`/`cli_text()` unescaped is misparsed as an expression to
#' evaluate (confirmed: `{name, title}` in the `contributors` field's own
#' description raised a glue parse error). Doubling every brace in
#' free-form text before splicing it next to real `{.field}`/`{.strong}`
#' markup (added separately, already valid) is the standard glue escape.
#' @keywords internal
.cli_escape <- function(x) {
  gsub("([{}])", "\\1\\1", x)
}

#' cli-formatted report for `validate_header()`
#' @keywords internal
.print_header_validation <- function(shell_qmd, provided, missing_required, missing_recommended, available, problems) {
  cli::cli_h1("quartifyr header validation: {.path {shell_qmd}}")

  if (length(provided) > 0) {
    cli::cli_h2("Provided")
    by_section <- split(provided, vapply(provided, `[[`, character(1), "section"))
    for (section in names(by_section)) {
      cli::cli_bullets(c(">" = "{.strong {section}}"))
      cli::cli_ul(vapply(by_section[[section]], function(f) paste0("{.field ", f$key, "}"), character(1)))
    }
  }

  if (length(missing_required) > 0) {
    cli::cli_h2("Missing (required)")
    cli::cli_bullets(.bullets("x", vapply(missing_required, function(f) paste0("{.field ", f$key, "}: ", .cli_escape(f$description)), character(1))))
  }

  if (length(missing_recommended) > 0) {
    cli::cli_h2("Recommended, not set")
    cli::cli_bullets(.bullets("!", vapply(missing_recommended, function(f) paste0("{.field ", f$key, "}: ", .cli_escape(f$description)), character(1))))
  }

  if (nrow(problems) > 0) {
    cli::cli_h2("Conflicts / structural issues")
    for (i in seq_len(nrow(problems))) {
      symbol <- if (identical(problems$severity[[i]], "error")) "x" else "!"
      cli::cli_bullets(.bullets(symbol, .cli_escape(problems$message[[i]])))
    }
  }

  if (length(available) > 0) {
    cli::cli_h2("Also available")
    cli::cli_bullets(.bullets("i", vapply(available, function(f) {
      default_note <- if (!is.null(f$default)) paste0(" (default: ", f$default, ")") else ""
      paste0("{.field ", f$key, "}: ", .cli_escape(paste0(f$description, default_note)))
    }, character(1))))
  }

  cli::cli_rule()
  if (nrow(problems) > 0 && any(problems$severity == "error") || length(missing_required) > 0) {
    cli::cli_alert_danger("Blocking issues found -- see {.strong Missing (required)}/{.strong Conflicts} above.")
  } else if (length(missing_recommended) > 0 || any(problems$severity == "warn")) {
    cli::cli_alert_warning("No blocking issues, but see the warnings above.")
  } else {
    cli::cli_alert_success("No issues found.")
  }
}
