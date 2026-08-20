#' Save a (possibly edited) style list as an override YAML
#'
#' Complements [styling_example_style()] (issue #27): edit its returned
#' list in place, then save just what changed back out as an override
#' YAML, ready to pass as `override`/`--override` to
#' [styling_build_reference_docx()] or any other `styling_*()` function
#' that takes one.
#'
#' @param style The (possibly edited) style list, typically
#'   [styling_example_style()]'s return value after in-place edits.
#' @param file Destination path for the override YAML.
#' @param overwrite Replace the destination if it already exists.
#' @param deconvolute Save only the keys that differ from `base` (the
#'   default) -- an override meant to be deep-merged back onto that same
#'   base at load time, not a second full style YAML to keep in sync by
#'   hand. `FALSE` saves `style` in full instead.
#' @param base Style YAML `style` is diffed against when `deconvolute =
#'   TRUE`. Defaults to the package's own bundled `default.yaml`; only
#'   worth overriding if `style` didn't originate from
#'   [styling_example_style()]'s default `base` either.
#' @return The saved content, as a nested list (invisibly).
#' @export
styling_save_overrides <- function(style, file = "overrides.yaml", overwrite = FALSE, deconvolute = TRUE,
                                    base = system.file("python", "styles", "default.yaml", package = "quartifyr")) {
  if (!nzchar(base)) {
    stop(
      "quartifyr's bundled default style YAML (inst/python/styles/default.yaml) was not found in ",
      "the installed package -- reinstall the quartifyr R package.",
      call. = FALSE
    )
  }
  style_json <- withr::local_tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(style, auto_unbox = TRUE, null = "null"), style_json)

  args <- c("save-overrides", "--base", base, "--style-json", style_json, "--out", file)
  if (overwrite) {
    args <- c(args, "--overwrite")
  }
  if (!deconvolute) {
    args <- c(args, "--no-deconvolute")
  }
  result <- .run_quartifyr_styling_cli(args)
  invisible(result$overrides)
}
