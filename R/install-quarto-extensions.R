#' Install quartifyr's required third-party Quarto extensions from a local source
#'
#' Copies the Quarto extensions in [quartifyr_quarto_extensions] (today
#' `A2-ai/quarto-plus`) into `<path>/_extensions/<owner>/<name>/` without
#' touching the network. `quarto::quarto_add_extension()` and `quarto add`
#' fetch from GitHub, which is not an option in a firewalled environment;
#' this is the offline alternative.
#'
#' With `from = NULL` (the default) the copies bundled in this package are
#' used (`inst/extensions/quarto-plus/`, an unmodified copy of the MIT-licensed
#' upstream extension, with its `LICENSE` kept alongside; see
#' `inst/extensions/README.md` for the commit it was taken from). Pass `from`
#' to install a different version, for example one a site has vetted and
#' mirrored internally.
#'
#' @param path Target project directory. Defaults to the current directory.
#' @param from Where to find the extensions: `NULL` for the bundled copies, a
#'   directory, or a `.zip`/`.tar.gz`/`.tgz`/`.tar` archive (for instance a
#'   GitHub "download ZIP" of the extension's repository). The extension is
#'   located by looking for a directory with the extension's name that holds an
#'   `_extension.yml`, wherever it sits in `from`, so both a repository
#'   checkout (`_extensions/quarto-plus/`) and a project's own `_extensions/`
#'   (`A2-ai/quarto-plus/`) work.
#' @param extensions Registry to install. Defaults to
#'   [quartifyr_quarto_extensions]; pass your own data frame in the same shape
#'   to install others from `from`.
#' @param force Replace an extension that is already installed. Default
#'   `FALSE`, which leaves an existing `_extensions/<owner>/<name>/` alone, so
#'   the function is safe to call again.
#' @return The installed extension directories, named by extension id
#'   (invisibly).
#' @seealso [check_quarto_extensions()] to verify what is installed,
#'   [install_quartifyr_extension()] for quartifyr's own extension.
#' @examples
#' project <- file.path(tempdir(), "my-report")
#' dir.create(project)
#' install_quarto_extensions(project)
#' list.files(file.path(project, "_extensions", "A2-ai", "quarto-plus"))
#' @export
install_quarto_extensions <- function(path = ".", from = NULL, extensions = quartifyr_quarto_extensions,
                                      force = FALSE) {
  if (!dir.exists(path)) {
    stop("path does not exist: ", path, call. = FALSE)
  }
  search_root <- .extension_search_root(from)
  if (!is.null(search_root$cleanup)) {
    on.exit(unlink(search_root$cleanup, recursive = TRUE), add = TRUE)
  }

  installed <- character(0)
  for (i in seq_len(nrow(extensions))) {
    id <- extensions$id[i]
    required <- isTRUE(extensions$required[i])
    owner <- dirname(id)
    name <- basename(id)
    dest <- file.path(path, "_extensions", owner, name)

    if (!isTRUE(force) && file.exists(file.path(dest, "_extension.yml"))) {
      cli::cli_inform(c("i" = "{id} is already installed in {.path {dest}}; keeping it (use {.code force = TRUE} to replace)."))
      installed[[id]] <- dest
      next
    }

    source_dir <- .find_extension_dir(search_root$dir, owner, name, bundled = is.null(from))
    if (is.null(source_dir)) {
      msg <- c(
        "x" = paste0("Could not find the Quarto extension {.val {id}} in ",
                     if (is.null(from)) "this package's bundled extensions." else "{.path {from}}."),
        "i" = paste0("Look for a directory named {.val {name}} containing an {.file _extension.yml}. ",
                     "{.code from} can be a directory or a .zip/.tar.gz archive.")
      )
      if (required) {
        cli::cli_abort(msg, call = NULL)
      }
      cli::cli_warn(msg)
      next
    }

    if (dir.exists(dest)) {
      unlink(dest, recursive = TRUE)
    }
    dir.create(dest, recursive = TRUE, showWarnings = FALSE)
    ok <- file.copy(list.files(source_dir, full.names = TRUE, all.files = TRUE, no.. = TRUE), dest, recursive = TRUE)
    if (!all(ok)) {
      stop("Failed to copy ", id, " into ", dest, call. = FALSE)
    }
    installed[[id]] <- dest
  }

  invisible(installed)
}

# The directory to search for extensions: the bundled copies, a user
# directory, or an archive unpacked into a temp directory (which the caller
# removes via `$cleanup`).
.extension_search_root <- function(from) {
  if (is.null(from)) {
    bundled <- system.file("extensions", package = "quartifyr")
    if (!nzchar(bundled)) {
      stop("quartifyr's bundled extensions (inst/extensions) were not found in the installed package -- reinstall it.", call. = FALSE)
    }
    return(list(dir = bundled, cleanup = NULL))
  }
  if (dir.exists(from)) {
    return(list(dir = from, cleanup = NULL))
  }
  if (!file.exists(from)) {
    stop("from not found: ", from, call. = FALSE)
  }
  exdir <- tempfile("quartifyr-extensions-")
  dir.create(exdir)
  if (grepl("\\.zip$", from, ignore.case = TRUE)) {
    utils::unzip(from, exdir = exdir)
  } else if (grepl("(\\.tar\\.gz|\\.tgz|\\.tar)$", from, ignore.case = TRUE)) {
    utils::untar(from, exdir = exdir)
  } else {
    unlink(exdir, recursive = TRUE)
    stop("from must be a directory or a .zip/.tar.gz/.tgz/.tar archive: ", from, call. = FALSE)
  }
  list(dir = exdir, cleanup = exdir)
}

# Finds `<...>/<name>/_extension.yml` under `root`. Prefers a match whose
# parent directory is `owner` (a project's own `_extensions/<owner>/<name>/`)
# over any other. The bundled copies are looked up directly: they are
# `inst/extensions/<name>/`, with no owner level.
.find_extension_dir <- function(root, owner, name, bundled = FALSE) {
  if (bundled) {
    candidate <- file.path(root, name)
    return(if (file.exists(file.path(candidate, "_extension.yml"))) candidate else NULL)
  }
  manifests <- list.files(root, pattern = "^_extension\\.ya?ml$", recursive = TRUE, full.names = TRUE, all.files = TRUE)
  dirs <- dirname(manifests)
  if (file.exists(file.path(root, "_extension.yml")) && basename(root) == name) {
    dirs <- c(root, dirs)
  }
  dirs <- dirs[basename(dirs) == name]
  if (length(dirs) == 0) {
    return(NULL)
  }
  preferred <- dirs[basename(dirname(dirs)) == owner]
  if (length(preferred) > 0) preferred[[1]] else dirs[[1]]
}
