#' Install the quartifyr Quarto extension into a project
#'
#' Copies the bundled `inst/extensions/quartifyr/` into
#' `<path>/_extensions/quartifyr/`. A plain file copy, not a
#' `quarto::quarto_add_extension()` call: that function only accepts an
#' archive or a GitHub repository as its `extension` argument, not a
#' bundled local package path, so it isn't the right tool for installing
#' an extension that ships inside this R package itself. Quarto doesn't
#' follow symlinks for extensions (confirmed: `quarto render` fails
#' outright against a symlinked `_extensions/quartifyr/`), so a real
#' physical copy is required -- the same reason
#' `scripts/sync_demo_extension.py` keeps the two bundled examples'
#' copies in sync with this package's own canonical one.
#'
#' Also runs [check_quarto_extensions()] (`error = FALSE`) afterward as a
#' courtesy nudge -- quartifyr's own extension layers on top of
#' `quarto-plus`'s ToC/List of Tables/List of Figures/abbreviations
#' machinery, which this function doesn't install itself (it isn't
#' bundled in this R package the way quartifyr's own extension is).
#'
#' @param path Target project directory. Defaults to the current directory.
#' @param force Overwrite an existing `_extensions/quartifyr/` in `path`.
#'   Default `FALSE` (errors if one already exists and differs).
#' @return The installed extension path (invisibly).
#' @export
install_quartifyr_extension <- function(path = ".", force = FALSE) {
  source_dir <- system.file("extensions", "quartifyr", package = "quartifyr")
  if (!nzchar(source_dir)) {
    stop(
      "quartifyr's bundled Quarto extension (inst/extensions/quartifyr) ",
      "was not found in the installed package -- reinstall the quartifyr R package.",
      call. = FALSE
    )
  }

  dest_dir <- file.path(path, "_extensions", "quartifyr")

  if (dir.exists(dest_dir)) {
    if (!isTRUE(force)) {
      stop(
        dest_dir, " already exists. Pass force = TRUE to overwrite it.",
        call. = FALSE
      )
    }
    unlink(dest_dir, recursive = TRUE)
  }

  dir.create(dirname(dest_dir), recursive = TRUE, showWarnings = FALSE)
  ok <- file.copy(source_dir, dirname(dest_dir), recursive = TRUE, overwrite = TRUE)
  if (!isTRUE(ok)) {
    stop("Failed to copy the quartifyr extension into ", dest_dir, call. = FALSE)
  }

  check_quarto_extensions(path, error = FALSE)

  invisible(dest_dir)
}
