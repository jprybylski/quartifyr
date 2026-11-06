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
#' @param soffice_bin Path to the LibreOffice executable. `NULL` (default)
#'   uses the `QUARTIFYR_SOFFICE_BIN` environment variable if set, else
#'   `soffice` on `PATH`.
#' @return The docx path (invisibly).
#' @examples
#' \dontrun{
#' # Requires a provisioned quartifyr Python environment and LibreOffice
#' # (soffice) on PATH -- run this after reportifyr::build_report() has
#' # filled in real content, so real page numbers exist to compare.
#' styling_resolve_same_page_crossrefs("report/final/report-final.docx")
#' }
#' @export
styling_resolve_same_page_crossrefs <- function(docx, timeout = 120, soffice_bin = NULL) {
  result <- .run_quartifyr_styling_cli(c(
    "resolve-same-page-crossrefs",
    "--docx", docx,
    if (!is.null(soffice_bin)) c("--soffice-bin", soffice_bin),
    "--timeout", as.character(as.integer(timeout))
  ))
  invisible(result$path)
}
