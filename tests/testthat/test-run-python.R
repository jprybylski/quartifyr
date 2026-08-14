# .run_quartifyr_styling_cli() is the single bridge point every exported
# styling_*() wrapper funnels through (R/run-python.R). These tests mock
# pyro:: directly (via .package = "pyro") rather than requiring a real venv,
# so they run everywhere -- unlike test-wiring.R's round-trip tests, which
# skip without a provisioned .venv/.

test_that("returns the parsed JSON list on success", {
  local_mocked_bindings(
    get_venv_uv_paths = function() list(uv = "FAKE_UV", venv = "FAKE_VENV"),
    .package = "pyro"
  )
  local_mocked_bindings(
    run_python_script = function(uv_path, args, venv_path, script_name,
                                  pythonpath = NULL, stderr_callback = NULL,
                                  verbose_env = NULL) {
      expect_identical(uv_path, "FAKE_UV")
      expect_identical(venv_path, "FAKE_VENV")
      expect_identical(script_name, "quartifyr-styling")
      list(
        status = 0,
        stdout = jsonlite::toJSON(list(status = "success", path = "out.tex"), auto_unbox = TRUE),
        stderr = ""
      )
    },
    .package = "pyro"
  )

  result <- .run_quartifyr_styling_cli(c("abbrevs", "--footnotes", "f.yaml", "--out", "out.tex"))
  expect_identical(result$status, "success")
  expect_identical(result$path, "out.tex")
})

test_that("passes --all-groups and the caller's args through to the CLI invocation", {
  local_mocked_bindings(
    get_venv_uv_paths = function() list(uv = "FAKE_UV", venv = "FAKE_VENV"),
    .package = "pyro"
  )
  captured_args <- NULL
  local_mocked_bindings(
    run_python_script = function(uv_path, args, venv_path, script_name,
                                  pythonpath = NULL, stderr_callback = NULL,
                                  verbose_env = NULL) {
      captured_args <<- args
      list(status = 0, stdout = jsonlite::toJSON(list(status = "success"), auto_unbox = TRUE), stderr = "")
    },
    .package = "pyro"
  )

  .run_quartifyr_styling_cli(c("build", "--style", "s.yaml"))
  expect_identical(
    captured_args,
    c("run", "--all-groups", "-m", "quartifyr_styling", "--json", "build", "--style", "s.yaml")
  )
})

test_that("recovers the JSON error payload written to stderr on failure", {
  local_mocked_bindings(
    get_venv_uv_paths = function() list(uv = "FAKE_UV", venv = "FAKE_VENV"),
    .package = "pyro"
  )
  local_mocked_bindings(
    run_python_script = function(uv_path, args, venv_path, script_name,
                                  pythonpath = NULL, stderr_callback = NULL,
                                  verbose_env = NULL) {
      payload <- jsonlite::toJSON(
        list(status = "error", code = "FILE_NOT_FOUND", message = "no such file: f.yaml"),
        auto_unbox = TRUE
      )
      if (!is.null(stderr_callback)) stderr_callback(payload, NULL)
      stop("quartifyr-styling failed.")
    },
    .package = "pyro"
  )

  expect_error(
    .run_quartifyr_styling_cli(c("abbrevs", "--footnotes", "f.yaml", "--out", "out.tex")),
    "quartifyr-styling abbrevs failed \\[FILE_NOT_FOUND\\]: no such file: f\\.yaml"
  )
})

test_that("falls back to a generic error when stderr isn't parseable JSON", {
  local_mocked_bindings(
    get_venv_uv_paths = function() list(uv = "FAKE_UV", venv = "FAKE_VENV"),
    .package = "pyro"
  )
  local_mocked_bindings(
    run_python_script = function(uv_path, args, venv_path, script_name,
                                  pythonpath = NULL, stderr_callback = NULL,
                                  verbose_env = NULL) {
      if (!is.null(stderr_callback)) stderr_callback("Traceback (most recent call last): boom", NULL)
      stop("quartifyr-styling failed.")
    },
    .package = "pyro"
  )

  expect_error(
    .run_quartifyr_styling_cli(c("build", "--style", "s.yaml")),
    "did not produce a parseable error payload"
  )
})

test_that("errors when the CLI exits 0 but stdout isn't valid JSON", {
  local_mocked_bindings(
    get_venv_uv_paths = function() list(uv = "FAKE_UV", venv = "FAKE_VENV"),
    .package = "pyro"
  )
  local_mocked_bindings(
    run_python_script = function(uv_path, args, venv_path, script_name,
                                  pythonpath = NULL, stderr_callback = NULL,
                                  verbose_env = NULL) {
      list(status = 0, stdout = "not json", stderr = "")
    },
    .package = "pyro"
  )

  expect_error(
    .run_quartifyr_styling_cli(c("build", "--style", "s.yaml")),
    "did not return valid JSON"
  )
})

test_that("scopes venv_dir to the caller's current working directory", {
  seen_venv_dir <- NULL
  local_mocked_bindings(
    get_venv_uv_paths = function() {
      seen_venv_dir <<- getOption("venv_dir")
      list(uv = "FAKE_UV", venv = "FAKE_VENV")
    },
    .package = "pyro"
  )
  local_mocked_bindings(
    run_python_script = function(...) {
      list(status = 0, stdout = jsonlite::toJSON(list(status = "success"), auto_unbox = TRUE), stderr = "")
    },
    .package = "pyro"
  )

  scoped_dir <- withr::local_tempdir()
  withr::with_dir(scoped_dir, {
    .run_quartifyr_styling_cli(c("build", "--style", "s.yaml"))
  })
  expect_identical(normalizePath(seen_venv_dir), normalizePath(scoped_dir))
})
