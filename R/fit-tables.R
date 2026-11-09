#' Fit the tables of a filled docx to the width of their page sections
#'
#' Delegates to `quartifyr-styling fit-tables` in the bundled Python engine.
#' `reportifyr::build_report()` leaves the column widths of the tables it
#' inserts to the word processor, which gives a table with a dozen or more
#' columns very narrow columns and header words that break mid-word. This
#' gives each of those tables an explicit fixed layout instead:
#'
#' * the width is the content width (page width minus margins) of the
#'   section the table is in, so a table on a landscape page
#'   (`{{< landscape >}}`) uses the landscape width;
#' * no column is narrower than its longest unbreakable word, including its
#'   cell padding;
#' * when the longest words alone don't fit the section, the font size is
#'   reduced in 1 pt steps, never below 7 pt; headers wrap at word
#'   boundaries.
#'
#' Only tables reportifyr inserted are changed (they carry a `{rpfy}:` alt
#' text); the tables quartifyr's own title page, signature pages and synopsis
#' generate are left alone. Widths are estimated from character metrics, not
#' measured with the real font.
#'
#' @param docx Path to the filled docx (modified in place).
#' @return A list (invisibly) with `path`, `fitted` (number of tables fitted),
#'   `shrunk` (the tables whose font size was reduced) and `overflowing`
#'   (the tables still too wide at the 7 pt minimum, where a word may break),
#'   the tables counted from 1 in document order.
#' @examples
#' \dontrun{
#' # Requires a provisioned quartifyr Python environment -- render_report()
#' # calls this automatically after reportifyr's pass 2.
#' styling_fit_tables("report/draft/report-draft.docx")
#' }
#' @export
styling_fit_tables <- function(docx) {
  result <- .run_quartifyr_styling_cli(c("fit-tables", "--docx", docx))
  invisible(result)
}
