#' Quarto extensions quartifyr's own output relies on
#'
#' A small registry of third-party Quarto extensions that quartifyr's
#' bundled `inst/extensions/quartifyr/` templates and `render_report()`'s
#' output assume are present in a project's `_extensions/`, checked by
#' [check_quarto_extensions()]. Quarto's own `_extension.yml` has no
#' "requires this other extension" field, so this list is quartifyr's own
#' substitute -- kept as data rather than hardcoded into the check
#' function so a future additional dependency (required or merely
#' suggested) is a one-line addition here, not a rewrite of the check
#' itself. Doesn't include quartifyr's own extension: that one is
#' installed and verified by [install_quartifyr_extension()] directly,
#' not `quarto::quarto_add_extension()`.
#'
#' @format A data frame with columns:
#' \describe{
#'   \item{id}{Extension identifier, in the form `quarto::quarto_add_extension()`/`quarto add` accepts (an `owner/repo` GitHub spec).}
#'   \item{required}{`TRUE` if a render is expected to fail (or silently misbehave) without it; `FALSE` if it's merely recommended.}
#'   \item{reason}{One-line explanation of what quartifyr uses it for, shown in [check_quarto_extensions()]'s diagnostic messages.}
#' }
#' @export
quartifyr_quarto_extensions <- data.frame(
  id = c("A2-ai/quarto-plus"),
  required = c(TRUE),
  reason = c(paste(
    "quartifyr's title/signature/synopsis/appendix filters layer on top",
    "of quarto-plus's ToC/List of Tables/List of Figures/caption",
    "machinery, and render_report() writes abbreviations.tex for its",
    "terms_and_abbreviations.lua filter to read -- see",
    'vignette("quarto-extension", "quartifyr").'
  )),
  stringsAsFactors = FALSE
)

#' Check that quartifyr's required/suggested Quarto extensions are installed
#'
#' Compares [quartifyr_quarto_extensions] (or a caller-supplied data frame
#' in the same shape) against `quarto::quarto_list_extensions()`'s output
#' for `path`, and reports anything missing with a clickable
#' `quarto::quarto_add_extension()` suggestion for each one.
#' `render_report()` calls this itself before rendering, so a missing
#' *required* extension stops the render with an actionable message
#' instead of Quarto's own much less specific "could not find executable"
#' filter failure. Call it directly to check a project on its own, e.g.
#' right after [install_quartifyr_extension()].
#'
#' @section A `quarto_list_extensions()` parsing gotcha:
#' `quarto::quarto_list_extensions()` feeds the `quarto list extensions`
#' CLI's plain-text table straight into `read.table(text = ..., header =
#' TRUE, fill = TRUE, sep = "")` (whitespace-delimited). Confirmed the
#' hard way: `A2-ai/quarto-plus`'s own `Contributes` value ("filters,
#' shortcodes") contains a space, so that row tokenizes to one more
#' whitespace-separated field than the 3-column header -- which triggers
#' `read.table()`'s classic "data row has one more field than the header"
#' rule and silently uses the extension id as a **row name** instead of
#' the `Id` column, shifting `Version`/`Contributes` left into
#' `Id`/`Version` for that row only. Trusting `df$Id` alone would miss
#' exactly the extension this package cares most about checking for. This
#' function instead searches every cell *and* row name of the returned
#' data frame, so the column shift doesn't matter.
#'
#' @param path Project directory to check (the one containing, or that
#'   should contain, `_extensions/`). Defaults to the current directory.
#' @param extensions Registry to check against. Defaults to
#'   [quartifyr_quarto_extensions]; pass your own data frame in the same
#'   shape (optionally `rbind()`'d onto the default) to also check
#'   project-specific extensions.
#' @param error Whether a missing extension with `required = TRUE` raises
#'   an error (default `TRUE`, and this is what `render_report()` uses).
#'   Extensions with `required = FALSE` never error, only warn, regardless
#'   of this argument.
#' @return `extensions` with an added logical `installed` column
#'   (invisibly).
#' @export
check_quarto_extensions <- function(path = ".", extensions = quartifyr_quarto_extensions, error = TRUE) {
  installed <- withr::with_dir(path, quarto::quarto_list_extensions())

  installed_text <- character(0)
  if (is.data.frame(installed) && nrow(installed) > 0) {
    installed_text <- trimws(c(rownames(installed), unlist(installed, use.names = FALSE)))
    installed_text <- installed_text[nzchar(installed_text)]
  }

  extensions$installed <- vapply(extensions$id, function(id) {
    short_id <- sub("^.*/", "", id)
    any(installed_text == id | installed_text == short_id | grepl(short_id, installed_text, fixed = TRUE))
  }, logical(1))

  missing <- extensions[!extensions$installed, , drop = FALSE]
  if (nrow(missing) == 0) {
    return(invisible(extensions))
  }

  bullets_for <- function(rows) {
    unlist(lapply(seq_len(nrow(rows)), function(i) {
      stats::setNames(
        sprintf(
          "%s -- %s Install it with {.run quarto::quarto_add_extension(\"%s\")}.",
          rows$id[i], rows$reason[i], rows$id[i]
        ),
        "*"
      )
    }))
  }

  missing_optional <- missing[!missing$required, , drop = FALSE]
  if (nrow(missing_optional) > 0) {
    cli::cli_warn(c(
      "!" = sprintf("Suggested Quarto extension(s) not installed in %s:", path),
      bullets_for(missing_optional)
    ))
  }

  missing_required <- missing[missing$required, , drop = FALSE]
  if (nrow(missing_required) > 0) {
    msg <- c(
      "x" = sprintf("Required Quarto extension(s) not installed in %s:", path),
      bullets_for(missing_required)
    )
    if (isTRUE(error)) {
      cli::cli_abort(msg, call = NULL)
    } else {
      cli::cli_warn(msg)
    }
  }

  invisible(extensions)
}
