#' Convert a reportifyr standard_footnotes.yaml into abbreviations.tex
#'
#' Delegates to `quartifyr-styling abbrevs` in the bundled Python engine, for
#' `quarto-plus`'s `terms_and_abbreviations.lua`.
#'
#' @param footnotes Path to `standard_footnotes.yaml`.
#' @param out Output `abbreviations.tex` path.
#' @return The output path (invisibly).
#' @export
styling_build_abbreviations_tex <- function(footnotes, out = "abbreviations.tex") {
  result <- .run_quartifyr_styling_cli(c(
    "abbrevs",
    "--footnotes", footnotes,
    "--out", out
  ))
  invisible(result$path)
}
