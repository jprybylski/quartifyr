#' Copy the bundled example style YAML into a project
#'
#' A convenience over `file.copy(system.file("python", "styles",
#' "default.yaml", package = "quartifyr"), ...)` that also returns the
#' copy's parsed content as an R list, ready to edit in place and hand to
#' [styling_save_overrides()].
#'
#' @param dir Destination directory. Created if it doesn't exist.
#' @param file Destination filename within `dir`.
#' @param overwrite Replace the destination if it already exists.
#' @param base Style YAML to copy. Defaults to the package's own bundled
#'   `default.yaml`; only worth overriding to start from an existing org
#'   style YAML instead.
#' @return The copied style YAML, parsed into a nested list.
#' @examples
#' \dontrun{
#' # Requires a provisioned quartifyr Python environment (see
#' # initialize_quartifyr_project()).
#' style <- styling_example_style("path/to/project", file = "style.yaml")
#' style$page$margins_in$top <- 1.25
#' }
#' @export
styling_example_style <- function(dir = ".", file = "style.yaml",
                                   overwrite = FALSE,
                                   base = system.file("python", "styles", "default.yaml", package = "quartifyr")) {
  if (!nzchar(base)) {
    stop(
      "quartifyr's bundled default style YAML (inst/python/styles/default.yaml) was not found in ",
      "the installed package -- reinstall the quartifyr R package.",
      call. = FALSE
    )
  }
  args <- c("example-style", "--base", base, "--out", file.path(dir, file))
  if (overwrite) {
    args <- c(args, "--overwrite")
  }
  result <- .run_quartifyr_styling_cli(args)
  result$style
}
