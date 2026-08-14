#' Generate a docx reference-template from a style YAML
#'
#' Delegates to `quartifyr-styling build` in the bundled Python engine.
#'
#' @param style Path to the base style YAML.
#' @param override Optional per-org/per-project style YAML, deep-merged over
#'   `style`. `NULL` (default) to skip.
#' @param out Output docx path.
#' @return The output docx path (invisibly).
#' @export
styling_build_reference_docx <- function(style, override = NULL, out = "templates/org-reference.docx") {
  args <- c("build", "--style", style)
  if (!is.null(override)) {
    args <- c(args, "--override", override)
  }
  args <- c(args, "--out", out)
  result <- .run_quartifyr_styling_cli(args)
  invisible(result$path)
}
