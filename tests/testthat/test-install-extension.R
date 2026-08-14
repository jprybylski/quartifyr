# check_quarto_extensions() is mocked out in every test here: it shells out
# to the real `quarto` CLI via quarto::quarto_list_extensions(), which these
# unit tests shouldn't depend on having installed.

test_that("copies the bundled extension into a fresh project", {
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))

  project_dir <- withr::local_tempdir()

  dest <- install_quartifyr_extension(project_dir)

  expect_identical(normalizePath(dest), normalizePath(file.path(project_dir, "_extensions", "quartifyr")))
  expect_true(file.exists(file.path(dest, "_extension.yml")))
})

test_that("errors if _extensions/quartifyr already exists and force is FALSE", {
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))

  project_dir <- withr::local_tempdir()
  install_quartifyr_extension(project_dir)

  expect_error(
    install_quartifyr_extension(project_dir),
    "already exists.*force = TRUE"
  )
})

test_that("force = TRUE overwrites an existing installed extension", {
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))

  project_dir <- withr::local_tempdir()
  dest <- install_quartifyr_extension(project_dir)

  # Simulate a stale/corrupted prior install.
  writeLines("stale", file.path(dest, "stale-marker.txt"))

  install_quartifyr_extension(project_dir, force = TRUE)

  expect_false(file.exists(file.path(dest, "stale-marker.txt")))
  expect_true(file.exists(file.path(dest, "_extension.yml")))
})

test_that("runs check_quarto_extensions() as a non-fatal courtesy check afterward", {
  captured_path <- NULL
  captured_error <- NULL
  local_mocked_bindings(
    check_quarto_extensions = function(path, error = TRUE) {
      captured_path <<- path
      captured_error <<- error
      invisible(NULL)
    }
  )

  project_dir <- withr::local_tempdir()
  install_quartifyr_extension(project_dir)

  expect_identical(captured_path, project_dir)
  expect_false(captured_error)
})
