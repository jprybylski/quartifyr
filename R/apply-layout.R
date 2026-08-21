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
#' @param style Optional path to a style YAML -- when given, applies its
#'   `equation.font` to the rendered docx's default math font (`NULL`,
#'   the default, leaves it untouched).
#' @param override Optional per-org/per-project style YAML, deep-merged
#'   over `style`. Ignored unless `style` is also given.
#' @return The docx path (invisibly).
#' @examples
#' \dontrun{
#' # Requires a provisioned quartifyr Python environment (see
#' # initialize_quartifyr_project()) -- render_report() calls this
#' # automatically, so it's rarely called directly.
#' styling_apply_layout("report/shell/report.docx", "report.qmd", status = "draft")
#' }
#' @export
styling_apply_layout <- function(docx, qmd, status, style = NULL, override = NULL) {
  args <- c("apply-layout", "--docx", docx, "--qmd", qmd, "--status", status)
  if (!is.null(style)) {
    args <- c(args, "--style", style)
    if (!is.null(override)) {
      args <- c(args, "--override", override)
    }
  }
  result <- .run_quartifyr_styling_cli(args)
  invisible(result$path)
}
