#' Apply header/footer and body-start layout to a rendered docx
#'
#' Delegates to `quartifyr-styling apply-layout` in the bundled Python
#' engine: splits a rendered docx into front-matter/body OOXML sections at
#' `{{< body-start >}}` (if the source `.qmd` uses it) and applies a dynamic
#' page header resolved from the `.qmd`'s `header-format:` frontmatter (if
#' set). Both are opt-in per-project; a `.qmd` using neither is left
#' untouched.
#'
#' @param docx Path to the rendered docx (modified in place).
#' @param qmd Path to the shell `.qmd` (read for `header-format:` and its
#'   placeholders).
#' @param status `"draft"` or `"final"`.
#' @return The docx path (invisibly).
#' @export
styling_apply_layout <- function(docx, qmd, status) {
  result <- .run_quartifyr_styling_cli(c(
    "apply-layout",
    "--docx", docx,
    "--qmd", qmd,
    "--status", status
  ))
  invisible(result$path)
}
