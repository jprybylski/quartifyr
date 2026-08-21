#' Resolve "same-page" cross-reference hyperlink markers in a filled docx
#'
#' Delegates to `quartifyr-styling resolve-same-page-crossrefs` in the
#' bundled Python engine, via headless LibreOffice (read-only -- it decides
#' hyperlinked-vs-plain per cross-reference but never re-saves the docx
#' itself beyond that). Shares `styling_recalculate_fields()`'s
#' known-flaky headless-LibreOffice behavior.
#'
#' @param docx Path to the filled docx to resolve (modified in place).
#' @param timeout Timeout in seconds (default `120`).
#' @return The docx path (invisibly).
#' @examples
#' \dontrun{
#' # Requires a provisioned quartifyr Python environment and LibreOffice
#' # (soffice) on PATH -- run this after reportifyr::build_report() has
#' # filled in real content, so real page numbers exist to compare.
#' styling_resolve_same_page_crossrefs("report/final/report-final.docx")
#' }
#' @export
styling_resolve_same_page_crossrefs <- function(docx, timeout = 120) {
  result <- .run_quartifyr_styling_cli(c(
    "resolve-same-page-crossrefs",
    "--docx", docx,
    "--timeout", as.character(as.integer(timeout))
  ))
  invisible(result$path)
}
