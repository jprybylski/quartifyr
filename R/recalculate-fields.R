#' Recalculate a docx's Word fields (ToC page numbers/entries) in place
#'
#' Delegates to `quartifyr-styling recalculate-fields` in the bundled Python
#' engine, via headless LibreOffice. **Experimental and known-flaky**: real
#' runs against the same document have produced three different outcomes
#' (hang, silent no-op, success), reproduced both sandboxed and in a plain
#' terminal. Don't treat a clean return as proof it worked.
#'
#' @param docx Path to the docx to recalculate (modified in place).
#' @param timeout Timeout in seconds (default `120`).
#' @return The docx path (invisibly).
#' @examples
#' \dontrun{
#' # Requires a provisioned quartifyr Python environment and LibreOffice
#' # (soffice) on PATH -- experimental and known-flaky, see above.
#' styling_recalculate_fields("report/final/report-final.docx")
#' }
#' @export
styling_recalculate_fields <- function(docx, timeout = 120) {
  result <- .run_quartifyr_styling_cli(c(
    "recalculate-fields",
    "--docx", docx,
    "--timeout", as.character(as.integer(timeout))
  ))
  invisible(result$path)
}
