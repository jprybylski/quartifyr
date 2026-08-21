#' Copy the bundled example reference-doc into a project
#'
#' A convenience over `file.copy(system.file("templates", "org-reference.docx",
#' package = "quartifyr"), ...)` -- the docx itself is an opaque binary
#' either way, so this is a plain file copy, no Python engine involved.
#'
#' @param dir Destination directory. Created if it doesn't exist.
#' @param file Destination filename within `dir`.
#' @param overwrite Replace the destination if it already exists.
#' @param src Reference-doc to copy. Defaults to the package's own bundled
#'   `org-reference.docx`; only worth overriding to start from an existing
#'   docx instead.
#' @return The destination path (invisibly).
#' @examples
#' dest_dir <- tempfile("quartifyr-project-")
#' dir.create(dest_dir)
#' styling_example_template(dest_dir)
#' list.files(dest_dir)
#' @export
styling_example_template <- function(dir = ".", file = "org-reference.docx", overwrite = FALSE,
                                      src = system.file("templates", "org-reference.docx", package = "quartifyr")) {
  if (!nzchar(src)) {
    stop(
      "quartifyr's bundled reference-doc (inst/templates/org-reference.docx) was not found in ",
      "the installed package -- reinstall the quartifyr R package.",
      call. = FALSE
    )
  }
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE)
  }
  dest <- file.path(dir, file)
  if (file.exists(dest) && !overwrite) {
    stop(dest, " already exists -- pass overwrite = TRUE to replace it.", call. = FALSE)
  }
  file.copy(src, dest, overwrite = overwrite)
  invisible(dest)
}
