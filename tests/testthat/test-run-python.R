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

# --- Offline: no re-sync, and uv failures name the step ----------------------

.mock_pyro_run <- function(run) {
  local_mocked_bindings(
    get_venv_uv_paths = function() list(uv = "FAKE_UV", venv = "FAKE_VENV"),
    .package = "pyro",
    .env = parent.frame()
  )
  local_mocked_bindings(run_python_script = run, .package = "pyro", .env = parent.frame())
}

test_that("offline mode adds --no-sync to the uv run, online mode does not", {
  captured <- NULL
  .mock_pyro_run(function(uv_path, args, ...) {
    captured <<- args
    list(status = 0, stdout = jsonlite::toJSON(list(status = "success"), auto_unbox = TRUE), stderr = "")
  })

  withr::with_options(list(quartifyr.offline = TRUE), .run_quartifyr_styling_cli("build"))
  expect_identical(
    captured,
    c("run", "--all-groups", "--no-sync", "-m", "quartifyr_styling", "--json", "build")
  )

  withr::with_options(list(quartifyr.offline = FALSE), withr::with_envvar(c(UV_OFFLINE = ""), .run_quartifyr_styling_cli("build")))
  expect_false("--no-sync" %in% captured)
})

test_that("offline, a uv failure with no CLI payload is a quartifyr_offline_failure naming the step", {
  .mock_pyro_run(function(uv_path, args, stderr_callback = NULL, ...) {
    stderr_callback("error: Failed to fetch: https://pypi.org/simple/python-docx/\n", NULL)
    stop("quartifyr-styling failed.")
  })

  err <- withr::with_options(
    list(quartifyr.offline = TRUE),
    suppressMessages(tryCatch(.run_quartifyr_styling_cli("apply-layout"), error = function(e) e))
  )

  expect_s3_class(err, "quartifyr_offline_failure")
  expect_match(conditionMessage(err), "run the quartifyr styling step \\(apply-layout\\)")
  expect_match(conditionMessage(err), "Failed to fetch")
})

test_that("offline, a uv failure that printed nothing still reports the underlying error", {
  .mock_pyro_run(function(uv_path, args, ...) stop("System command 'uv' failed"))

  err <- withr::with_options(
    list(quartifyr.offline = TRUE),
    suppressMessages(tryCatch(.run_quartifyr_styling_cli("build"), error = function(e) e))
  )

  expect_s3_class(err, "quartifyr_offline_failure")
  expect_match(conditionMessage(err), "System command 'uv' failed")
})

test_that("online, a failure with no payload stays the generic error", {
  .mock_pyro_run(function(uv_path, args, ...) stop("quartifyr-styling failed."))

  err <- withr::with_options(
    list(quartifyr.offline = FALSE),
    withr::with_envvar(c(UV_OFFLINE = ""), suppressMessages(tryCatch(.run_quartifyr_styling_cli("build"), error = function(e) e)))
  )

  expect_false(inherits(err, "quartifyr_offline_failure"))
  expect_match(conditionMessage(err), "did not produce a parseable error payload")
})
