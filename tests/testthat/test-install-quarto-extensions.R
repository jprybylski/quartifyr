.fake_extension_repo <- function(layout = c("repo", "project"), env = parent.frame()) {
  layout <- match.arg(layout)
  root <- withr::local_tempdir(.local_envir = env)
  ext <- if (layout == "repo") {
    file.path(root, "quarto-plus-main", "_extensions", "quarto-plus")
  } else {
    file.path(root, "_extensions", "A2-ai", "quarto-plus")
  }
  dir.create(ext, recursive = TRUE)
  writeLines("title: vetted copy", file.path(ext, "_extension.yml"))
  writeLines("-- lua", file.path(ext, "utils.lua"))
  writeLines("MIT", file.path(ext, "LICENSE"))
  root
}

test_that("installs the bundled quarto-plus, LICENSE included, under _extensions/<owner>/<name>", {
  project <- withr::local_tempdir()

  installed <- install_quarto_extensions(project)

  dest <- file.path(project, "_extensions", "A2-ai", "quarto-plus")
  expect_identical(installed[["A2-ai/quarto-plus"]], dest)
  expect_true(file.exists(file.path(dest, "_extension.yml")))
  expect_true(file.exists(file.path(dest, "LICENSE")))
  expect_true(file.exists(file.path(dest, "crossref.lua")))
})

test_that("the installed copy satisfies the preflight's extension check", {
  project <- withr::local_tempdir()
  expect_length(.check_extensions_on_disk(project), 1)

  install_quarto_extensions(project)

  expect_length(.check_extensions_on_disk(project), 0)
})

test_that("installs from a repository-style directory", {
  repo <- .fake_extension_repo("repo")
  project <- withr::local_tempdir()

  install_quarto_extensions(project, from = repo)

  expect_identical(
    readLines(file.path(project, "_extensions", "A2-ai", "quarto-plus", "_extension.yml")),
    "title: vetted copy"
  )
})

test_that("installs from another project's _extensions directory", {
  other <- .fake_extension_repo("project")
  project <- withr::local_tempdir()

  install_quarto_extensions(project, from = other)

  expect_true(file.exists(file.path(project, "_extensions", "A2-ai", "quarto-plus", "utils.lua")))
})

test_that("installs from a zip archive", {
  skip_if(Sys.which("zip") == "", "no `zip` binary")
  repo <- .fake_extension_repo("repo")
  archive <- file.path(withr::local_tempdir(), "quarto-plus.zip")
  withr::with_dir(repo, utils::zip(archive, "quarto-plus-main", flags = "-qr"))
  project <- withr::local_tempdir()

  install_quarto_extensions(project, from = archive)

  expect_true(file.exists(file.path(project, "_extensions", "A2-ai", "quarto-plus", "_extension.yml")))
})

test_that("installs from a tar.gz archive", {
  repo <- .fake_extension_repo("repo")
  archive <- file.path(withr::local_tempdir(), "quarto-plus.tar.gz")
  withr::with_dir(repo, utils::tar(archive, "quarto-plus-main", compression = "gzip"))
  project <- withr::local_tempdir()

  install_quarto_extensions(project, from = archive)

  expect_true(file.exists(file.path(project, "_extensions", "A2-ai", "quarto-plus", "_extension.yml")))
})

test_that("an existing install is left alone unless force = TRUE", {
  project <- withr::local_tempdir()
  repo <- .fake_extension_repo("repo")
  install_quarto_extensions(project)
  marker <- file.path(project, "_extensions", "A2-ai", "quarto-plus", "_extension.yml")
  original <- readLines(marker)

  expect_message(install_quarto_extensions(project, from = repo), "already installed")
  expect_identical(readLines(marker), original)

  install_quarto_extensions(project, from = repo, force = TRUE)
  expect_identical(readLines(marker), "title: vetted copy")
})

test_that("a source without the extension is an error naming it, and a bad `from` is rejected", {
  project <- withr::local_tempdir()
  empty <- withr::local_tempdir()

  expect_error(install_quarto_extensions(project, from = empty), "A2-ai/quarto-plus")
  expect_error(install_quarto_extensions(project, from = file.path(empty, "nope.zip")), "from not found")

  not_archive <- file.path(empty, "x.txt")
  writeLines("x", not_archive)
  expect_error(install_quarto_extensions(project, from = not_archive), "directory or a .zip")
  expect_error(install_quarto_extensions(file.path(empty, "missing-project")), "path does not exist")
})

test_that("a missing optional extension only warns", {
  project <- withr::local_tempdir()
  empty <- withr::local_tempdir()
  optional <- data.frame(id = "acme/optional-ext", required = FALSE, reason = "nice to have", stringsAsFactors = FALSE)

  expect_warning(install_quarto_extensions(project, from = empty, extensions = optional), "acme/optional-ext")
})
