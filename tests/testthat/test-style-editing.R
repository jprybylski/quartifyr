# styling_example_template() -- pure R, no pyro bridge involved.

test_that("styling_example_template() copies the bundled reference-doc", {
  dest_dir <- withr::local_tempdir()
  path <- styling_example_template(dir = dest_dir)
  expect_identical(path, file.path(dest_dir, "org-reference.docx"))
  expect_true(file.exists(path))
})

test_that("styling_example_template() refuses to overwrite by default", {
  dest_dir <- withr::local_tempdir()
  styling_example_template(dir = dest_dir)
  expect_error(styling_example_template(dir = dest_dir), "already exists")
})

test_that("styling_example_template() overwrite = TRUE replaces the destination", {
  dest_dir <- withr::local_tempdir()
  styling_example_template(dir = dest_dir)
  expect_no_error(styling_example_template(dir = dest_dir, overwrite = TRUE))
})

test_that("styling_example_template() creates dir when it doesn't exist", {
  dest_dir <- file.path(withr::local_tempdir(), "nested", "sub")
  expect_false(dir.exists(dest_dir))
  path <- styling_example_template(dir = dest_dir)
  expect_true(dir.exists(dest_dir))
  expect_true(file.exists(path))
})

test_that("styling_example_template() errors clearly when the bundled reference-doc can't be found", {
  expect_error(styling_example_template(src = ""), "was not found")
})

# styling_example_style() -- pyro bridge, mocked.

test_that("styling_example_style() forwards args and returns the parsed style", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "ok", path = "style.yaml", style = list(heading = list(all_caps = FALSE)))
    }
  )

  result <- styling_example_style(dir = "proj", file = "style.yaml", base = "default.yaml")

  expect_identical(captured_args, c("example-style", "--base", "default.yaml", "--out", "proj/style.yaml"))
  expect_identical(result, list(heading = list(all_caps = FALSE)))
})

test_that("styling_example_style() includes --overwrite when requested", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "ok", style = list())
    }
  )

  styling_example_style(dir = ".", file = "style.yaml", overwrite = TRUE, base = "default.yaml")

  expect_true("--overwrite" %in% captured_args)
})

test_that("styling_example_style() errors clearly when the bundled default style YAML can't be found", {
  expect_error(styling_example_style(base = ""), "was not found")
})

# styling_save_overrides() -- pyro bridge, mocked; only the args/return
# value matter here, not the real JSON-file round-trip (covered by
# tests/python/test_style_editing.py and a real end-to-end pyro call).

test_that("styling_save_overrides() writes a style-json tempfile and forwards args", {
  captured_args <- NULL
  tempfile_existed_during_call <- NA
  tempfile_json <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      # withr::local_tempfile() (inside styling_save_overrides()) defers
      # cleanup to when *that* function returns -- check existence and
      # contents now, while still inside the mocked call, not after.
      tempfile_existed_during_call <<- file.exists(args[5])
      tempfile_json <<- jsonlite::fromJSON(args[5], simplifyVector = FALSE)
      list(status = "ok", overrides = list(heading = list(all_caps = TRUE)))
    }
  )

  result <- styling_save_overrides(
    list(heading = list(all_caps = TRUE)),
    file = "overrides.yaml",
    base = "default.yaml"
  )

  expect_identical(captured_args[1:3], c("save-overrides", "--base", "default.yaml"))
  expect_identical(captured_args[4], "--style-json")
  expect_true(tempfile_existed_during_call)
  expect_identical(tempfile_json, list(heading = list(all_caps = TRUE)))
  expect_identical(captured_args[6:7], c("--out", "overrides.yaml"))
  expect_identical(result, list(heading = list(all_caps = TRUE)))
})

test_that("styling_save_overrides() includes --no-deconvolute when deconvolute = FALSE", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "ok", overrides = list())
    }
  )

  styling_save_overrides(list(a = 1), deconvolute = FALSE, base = "default.yaml")

  expect_true("--no-deconvolute" %in% captured_args)
})

test_that("styling_save_overrides() includes --overwrite when requested", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "ok", overrides = list())
    }
  )

  styling_save_overrides(list(a = 1), overwrite = TRUE, base = "default.yaml")

  expect_true("--overwrite" %in% captured_args)
})

test_that("styling_save_overrides() errors clearly when the bundled default style YAML can't be found", {
  expect_error(styling_save_overrides(list(a = 1), base = ""), "was not found")
})

# styling_update_style() -- pyro bridge, mocked.

test_that("styling_update_style() requires yes = TRUE", {
  expect_error(styling_update_style(list(a = 1), file = "style.yaml"), "yes = TRUE")
})

test_that("styling_update_style() writes an updates-json tempfile, forwards --yes, and returns the merged style", {
  captured_args <- NULL
  tempfile_existed_during_call <- NA
  tempfile_json <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      tempfile_existed_during_call <<- file.exists(args[5])
      tempfile_json <<- jsonlite::fromJSON(args[5], simplifyVector = FALSE)
      list(status = "ok", style = list(colors = list(text = "#123456")))
    }
  )

  result <- styling_update_style(list(colors = list(text = "#123456")), file = "style.yaml", yes = TRUE)

  expect_identical(captured_args[1:3], c("update-style", "--file", "style.yaml"))
  expect_identical(captured_args[4], "--updates-json")
  expect_true(tempfile_existed_during_call)
  expect_identical(tempfile_json, list(colors = list(text = "#123456")))
  expect_identical(captured_args[6], "--yes")
  expect_identical(result, list(colors = list(text = "#123456")))
})
