#' Prompt for one line of interactive input
#'
#' Thin wrapper around `readline()` so the rest of `header_helper()` can be
#' mocked/tested without an interactive session (see
#' `tests/testthat/test-header-helper.R`).
#'
#' @param prompt Prompt text (no trailing space needed).
#' @return The trimmed input string (possibly `""`).
#' @keywords internal
.header_helper_ask <- function(prompt) {
  trimws(readline(paste0(prompt, " ")))
}

#' Ask a yes/no question
#'
#' @param prompt Question text (without a yes/no hint -- one is appended).
#' @param default Default answer if the user just presses enter.
#' @return `TRUE`/`FALSE`.
#' @keywords internal
.header_helper_ask_yn <- function(prompt, default = FALSE) {
  hint <- if (default) "[Y/n]" else "[y/N]"
  answer <- tolower(.header_helper_ask(paste(prompt, hint)))
  if (!nzchar(answer)) {
    return(default)
  }
  startsWith(answer, "y")
}

#' Collect one `{label, value}`-style list interactively
#'
#' Used for `title-page-extra:`, `address:` (label-less, value-only), and
#' `synopsis:` (label/value, text values only -- the multi-line/embedded-
#' figure form documented in `inst/extensions/quartifyr/README.md`'s
#' "Synopsis" section is left for hand-editing afterward, not part of this
#' quick-start flow).
#'
#' @param row_label What to call one row in prompts (e.g. `"row"`, `"line"`).
#' @param with_label Whether each entry has a separate `label:` (`TRUE`, for
#'   `title-page-extra:`/`synopsis:`) or is a bare string (`FALSE`, for
#'   `address:`).
#' @return A list (possibly empty) ready to splice into frontmatter.
#' @keywords internal
.header_helper_collect_rows <- function(row_label, with_label = TRUE) {
  rows <- list()
  article <- if (grepl("^[aeiouAEIOU]", row_label)) "an" else "a"
  repeat {
    if (!.header_helper_ask_yn(sprintf("Add %s %s?", if (length(rows) == 0) article else "one more", row_label))) {
      break
    }
    if (with_label) {
      label <- .header_helper_ask("  Label:")
      value <- .header_helper_ask("  Value:")
      rows[[length(rows) + 1]] <- list(label = label, value = value)
    } else {
      value <- .header_helper_ask("  Line:")
      rows[[length(rows) + 1]] <- value
    }
  }
  rows
}

#' Collect a `{name, title}`-style person list interactively
#'
#' Used for `contributors.authors`/`contributors.reviewers`/`approvers:`.
#'
#' @param person_label What to call one entry in prompts (e.g. `"author"`).
#' @return A list (possibly empty) of `{name, title}` lists.
#' @keywords internal
.header_helper_collect_people <- function(person_label) {
  people <- list()
  article <- if (grepl("^[aeiouAEIOU]", person_label)) "an" else "a"
  repeat {
    if (!.header_helper_ask_yn(sprintf("Add %s %s?", if (length(people) == 0) article else "one more", person_label))) {
      break
    }
    name <- .header_helper_ask("  Name:")
    title <- .header_helper_ask("  Title:")
    people[[length(people) + 1]] <- list(name = name, title = title)
  }
  people
}

#' Prompt for one registry-driven scalar field
#'
#' Required fields are asked directly; recommended/optional fields are
#' asked as an include-or-skip question first. An empty answer to a
#' required field leaves it unset (`validate_header()` will flag it, this
#' function doesn't force an answer).
#'
#' @param f One field spec from `.quartifyr_header_fields()`.
#' @param fm Frontmatter assembled so far -- `f$required()`/`f$recommended()`
#'   are evaluated against this, not a fresh/empty list, since some fields
#'   depend on an earlier answer (see `.header_helper_collect()`'s comment).
#' @return The entered string, or `NULL` if skipped/left blank.
#' @keywords internal
.header_helper_ask_scalar <- function(f, fm) {
  if (isTRUE(f$required(fm))) {
    prompt <- sprintf("%s (required):", f$label)
  } else {
    include <- .header_helper_ask_yn(
      sprintf("Set %s? -- %s", f$label, f$description),
      default = isTRUE(f$recommended(fm))
    )
    if (!include) {
      return(NULL)
    }
    prompt <- sprintf("%s%s:", f$label, if (!is.null(f$default)) paste0(" (default ", f$default, ")") else "")
  }
  value <- .header_helper_ask(prompt)
  if (!nzchar(value)) NULL else value
}

#' Assign a value at a (possibly nested) dotted path into a list
#' @keywords internal
.header_field_set <- function(fm, path, value) {
  if (length(path) == 1) {
    fm[[path]] <- value
    return(fm)
  }
  head <- path[[1]]
  rest <- path[-1]
  child <- fm[[head]]
  if (is.null(child)) {
    child <- list()
  }
  fm[[head]] <- .header_field_set(child, rest, value)
  fm
}

#' Interactively build a quartifyr front-matter block
#'
#' Walks the same field registry `validate_header()` validates against
#' (see `R/header-fields.R`), prompting for required fields, offering
#' recommended/optional ones, and looping through the list-shaped fields
#' (`title-page-extra:`, `address:`, `synopsis:`, `contributors:`,
#' `approvers:`) a row/person at a time. The result is a ready-to-paste
#' YAML front-matter block -- printed to the console and, when available,
#' copied to the clipboard (via the optional `clipr` package), the same
#' "copy or print" convenience `reprex::reprex()` offers for its output.
#'
#' Evergreen by the same construction as `validate_header()`: a field
#' added to the registry is automatically prompted for here too, with no
#' separate wording to maintain.
#'
#' @param doc_type `"report"` (title page) or `"memo"` (memo cover).
#' @param clipboard Try to copy the result to the clipboard. Default `TRUE`.
#' @return Invisibly, the generated YAML block (a single string, including
#'   the `---` fences).
#' @export
header_helper <- function(doc_type = c("report", "memo"), clipboard = TRUE) {
  doc_type <- match.arg(doc_type)
  if (!interactive()) {
    cli::cli_abort(c(
      "x" = "header_helper() requires an interactive session.",
      "i" = "Non-interactively, start from {.path examples/demo-report/report.qmd} (report) or {.path examples/memo-example/report.qmd} (memo) instead, and check the result with {.fun validate_header}."
    ))
  }

  cli::cli_h1("quartifyr header helper ({doc_type})")
  fm <- .header_helper_collect(doc_type)

  yaml_block <- .header_helper_render(fm)
  cli::cli_h2("Generated front matter")
  cli::cat_line(yaml_block)

  copied <- FALSE
  if (isTRUE(clipboard) && requireNamespace("clipr", quietly = TRUE) &&
    isTRUE(tryCatch(clipr::clipr_available(), error = function(e) FALSE))) {
    copied <- isTRUE(tryCatch(
      {
        clipr::write_clip(yaml_block)
        TRUE
      },
      error = function(e) FALSE
    ))
  }
  if (copied) {
    cli::cli_alert_success("Copied to the clipboard -- paste it at the top of your .qmd.")
  } else {
    cli::cli_alert_info("Clipboard unavailable -- copy the block printed above into your .qmd.")
  }

  invisible(yaml_block)
}

#' The interactive prompting loop behind `header_helper()`
#'
#' Factored out from `header_helper()` so it (and, transitively,
#' `.header_helper_render()`) can be driven with a scripted
#' `.header_helper_ask`/`.header_helper_ask_yn` mock in tests, without a
#' real interactive session.
#'
#' @param doc_type `"report"` or `"memo"`.
#' @return The assembled frontmatter list.
#' @keywords internal
.header_helper_collect <- function(doc_type) {
  fm <- list(format = "docx", filters = c("quarto-plus", "quartifyr"))
  if (identical(doc_type, "memo")) {
    fm$memo <- list()
  }

  # "title" itself has applies_when = always (it must still show up in
  # validate_header()'s report even when memo: is set, to explain a
  # title-vs-memo conflict) -- but here doc_type already picked one of
  # the two mutually-exclusive covers, so exclude the other explicitly;
  # applies_when() alone (checked below, per-field) isn't enough to keep
  # "title" out of a memo build.
  excluded_key <- if (identical(doc_type, "memo")) "title" else NULL
  fields <- Filter(
    function(f) f$kind == "scalar" && !identical(f$key, excluded_key) && isTRUE(f$applies_when(fm)),
    .quartifyr_header_fields()
  )
  # Re-filter after every answer (not just once up front): several fields'
  # applies_when()/required() depend on an earlier answer in this very
  # loop (signature-note on signature-mode, csl/link-citations on
  # bibliography, memo.* on memo already being seeded above) -- see
  # R/header-fields.R's field ordering, which is deliberately laid out so
  # each such dependency is answered before the field it gates.
  i <- 1
  while (i <= length(fields)) {
    f <- fields[[i]]
    if (isTRUE(f$applies_when(fm))) {
      value <- .header_helper_ask_scalar(f, fm)
      if (!is.null(value)) {
        fm <- .header_field_set(fm, f$path, value)
      }
    }
    i <- i + 1
  }

  # fm$memo was pre-seeded as list() above purely to gate has_memo/no_memo
  # predicates during the loop -- if every memo.* question was declined,
  # that leaves an empty, name-less list() sitting in fm$memo, which
  # yaml::as.yaml() would render as `memo: []` (a sequence) rather than
  # dropping it or rendering a mapping; drop it instead, since an empty
  # memo: with no To/From/Date/Re fields set isn't a meaningful cover
  # (validate_header() will flag the resulting "neither title nor memo"
  # gap as an error, same as if memo: had never been offered at all).
  if (identical(doc_type, "memo") && length(fm$memo) == 0) {
    fm$memo <- NULL
  }

  if (identical(doc_type, "memo")) {
    cli::cli_h2("Extra title-page rows")
  } else {
    cli::cli_h2("Title page")
    address <- .header_helper_collect_rows("address line", with_label = FALSE)
    if (length(address) > 0) {
      fm$address <- address
    }
  }
  extra <- .header_helper_collect_rows("extra title-page row")
  if (length(extra) > 0) {
    fm[["title-page-extra"]] <- extra
  }

  cli::cli_h2("Signature page")
  authors <- .header_helper_collect_people("author")
  reviewers <- .header_helper_collect_people("reviewer")
  if (length(authors) > 0 || length(reviewers) > 0) {
    contributors <- list()
    if (length(authors) > 0) contributors$authors <- authors
    if (length(reviewers) > 0) contributors$reviewers <- reviewers
    fm$contributors <- contributors
  }
  approvers <- .header_helper_collect_people("approver")
  if (length(approvers) > 0) {
    fm$approvers <- approvers
  }

  cli::cli_h2("Synopsis")
  if (.header_helper_ask_yn("Add a synopsis?")) {
    synopsis <- .header_helper_collect_rows("synopsis row")
    if (length(synopsis) > 0) {
      fm$synopsis <- synopsis
    }
  }

  fm
}

#' Render a collected frontmatter list as a pasteable YAML block
#'
#' Pure (no I/O): given the list `.header_helper_collect()` assembles,
#' returns the `---`-fenced YAML text. Kept separate so it's unit-testable
#' against fixed input, independent of the interactive prompting above.
#'
#' @param fm Frontmatter list.
#' @return A single string.
#' @keywords internal
.header_helper_render <- function(fm) {
  # Field order matters for readability -- yaml::as.yaml() would otherwise
  # emit list()-derived fields in insertion order already, but sort into
  # the registry's own section order (title/memo first, structure last)
  # so the block reads the way inst/extensions/quartifyr/README.md's own
  # examples do, regardless of the order fields happened to be answered
  # in.
  registry_order <- vapply(.quartifyr_header_fields(), function(f) f$path[[1]], character(1))
  known_order <- unique(registry_order)
  ordered_keys <- c(intersect(known_order, names(fm)), setdiff(names(fm), known_order))
  fm <- fm[ordered_keys]

  body <- yaml::as.yaml(fm, indent.mapping.sequence = TRUE)
  paste0("---\n", body, "---\n")
}
