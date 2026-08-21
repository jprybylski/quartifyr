# Unit coverage of styling_export_skills()'s own CLI arg assembly,
# independent of a real pyro/uv toolchain -- see test-run-python.R's
# header comment.

test_that("passes the directory through to the CLI", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(created = character(0))
    }
  )

  styling_export_skills("my-skills")
  expect_equal(captured_args, c("skills", "my-skills"))
})

test_that("defaults to the current directory and omits --force", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(created = character(0))
    }
  )

  styling_export_skills()
  expect_equal(captured_args, c("skills", "."))
})

test_that("adds --force when requested", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(created = character(0))
    }
  )

  styling_export_skills("my-skills", force = TRUE)
  expect_equal(captured_args, c("skills", "my-skills", "--force"))
})

test_that("returns its result invisibly", {
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) list(created = character(0))
  )

  expect_invisible(styling_export_skills("my-skills"))
})
