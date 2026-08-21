#' Convert a reportifyr standard_footnotes.yaml into abbreviations.tex
#'
#' Delegates to `quartifyr-styling abbrevs` in the bundled Python engine, for
#' `quarto-plus`'s `terms_and_abbreviations.lua`.
#'
#' @param footnotes Path to `standard_footnotes.yaml`.
#' @param out Output `abbreviations.tex` path.
#' @return The output path (invisibly).
#' @examples
#' \dontrun{
#' # Requires a provisioned quartifyr Python environment (see
#' # initialize_quartifyr_project()).
#' styling_build_abbreviations_tex("report/standard_footnotes.yaml", out = "abbreviations.tex")
#' }
#' @export
styling_build_abbreviations_tex <- function(footnotes, out = "abbreviations.tex") {
  result <- .run_quartifyr_styling_cli(c(
    "abbrevs",
    "--footnotes", footnotes,
    "--out", out
  ))
  invisible(result$path)
}
