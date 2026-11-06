# Offline / pre-provisioned operation. pyro, uv and Python are all mocked or
# replaced with tiny stub interpreters, so none of this needs a network or a
# real toolchain; the genuine no-network check is the `offline-pipeline` CI
# job, which runs init + render under `unshare -rn`.

.clean_offline_state <- function(env = parent.frame()) {
  withr::local_envvar(UV_OFFLINE = NA, QUARTIFYR_PYTHON_ENV = NA, .local_envir = env)
  withr::local_options(quartifyr.offline = NULL, quartifyr.python_env = NULL, .local_envir = env)
}

# A fake Python "environment": bin/python is a shell script whose behaviour
# the test controls, so what the real interpreter would do (report missing
# modules, run the CLI, fail) is deterministic.
.fake_python_env <- function(body, env = parent.frame()) {
  skip_on_os("windows")
  root <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(root, "bin"))
  python <- file.path(root, "bin", "python")
  writeLines(c("#!/bin/sh", body), python)
  Sys.chmod(python, "0755")
  root
}

test_that(".offline_mode() follows the option and UV_OFFLINE", {
  .clean_offline_state()
  expect_false(.offline_mode())

  withr::with_options(list(quartifyr.offline = TRUE), expect_true(.offline_mode()))
  for (value in c("1", "true", "TRUE", "yes")) {
    withr::with_envvar(c(UV_OFFLINE = value), expect_true(.offline_mode()))
  }
  withr::with_envvar(c(UV_OFFLINE = "0"), expect_false(.offline_mode()))
})

test_that(".abort_offline() names the step, the resource and how to provide it", {
  err <- tryCatch(
    .abort_offline(
      step = "fetch {.val {what}}",
      resource = "the thing",
      how = c("Do this.", "Or that: {extra}"),
      env = list2env(list(what = "widgets", extra = "details"))
    ),
    error = function(e) e
  )

  expect_s3_class(err, "quartifyr_offline_failure")
  msg <- conditionMessage(err)
  expect_match(msg, "Cannot fetch \"widgets\" without network access")
  expect_match(msg, "It needs the thing")
  expect_match(msg, "Do this.")
  expect_match(msg, "Or that: details")
})

# --- initialize_quartifyr_project(), offline via pyro ------------------------

test_that("offline with no uv installed stops before touching pyro, naming uv", {
  .clean_offline_state()
  withr::local_options(quartifyr.offline = TRUE)
  project_dir <- withr::local_tempdir()
  local_mocked_bindings(
    get_uv_path = function(...) NULL,
    initialize_python = function(...) stop("pyro must not be called"),
    write_group_to_pyproject = function(...) stop("pyro must not be called"),
    .package = "pyro"
  )

  err <- tryCatch(initialize_quartifyr_project(project_dir), error = function(e) e)

  expect_s3_class(err, "quartifyr_offline_failure")
  expect_match(conditionMessage(err), "provision the Python environment")
  expect_match(conditionMessage(err), "uv")
  expect_match(conditionMessage(err), "python_env")
  expect_false(file.exists(file.path(project_dir, "pyproject.toml")))
})

test_that("offline with uv installed runs pyro with UV_OFFLINE set and uv's own version", {
  .clean_offline_state()
  withr::local_options(quartifyr.offline = TRUE)
  project_dir <- withr::local_tempdir()
  seen <- list()
  local_mocked_bindings(
    get_uv_path = function(...) "/opt/bin/uv",
    get_uv_version = function(path) "9.9.9",
    write_group_to_pyproject = function(...) invisible(NULL),
    initialize_python = function(continue = NULL, venv_dir, uv_version = NULL, groups = NULL, pyproject_dir = NULL) {
      seen <<- list(uv_offline = Sys.getenv("UV_OFFLINE"), uv_version = uv_version)
      invisible("initialized")
    },
    .package = "pyro"
  )

  expect_identical(initialize_quartifyr_project(project_dir), "initialized")

  expect_identical(seen$uv_offline, "1")
  # Passing the installed version is what stops uv_setup.sh from deciding a
  # "mismatch" warrants curl-installing a different uv.
  expect_identical(seen$uv_version, "9.9.9")
  expect_identical(Sys.getenv("UV_OFFLINE"), "")
})

test_that("online runs don't set UV_OFFLINE or pass a uv_version", {
  .clean_offline_state()
  project_dir <- withr::local_tempdir()
  seen <- list()
  local_mocked_bindings(
    write_group_to_pyproject = function(...) invisible(NULL),
    initialize_python = function(continue = NULL, venv_dir, uv_version = "unset", groups = NULL, pyproject_dir = NULL) {
      seen <<- list(uv_offline = Sys.getenv("UV_OFFLINE"), uv_version = uv_version)
      invisible("initialized")
    },
    .package = "pyro"
  )

  initialize_quartifyr_project(project_dir)

  expect_identical(seen$uv_offline, "")
  expect_identical(seen$uv_version, "unset")
})

test_that("an offline pyro failure names the step, the missing resource and the underlying error", {
  .clean_offline_state()
  withr::local_envvar(UV_OFFLINE = "1")
  project_dir <- withr::local_tempdir()
  local_mocked_bindings(
    get_uv_path = function(...) "/opt/bin/uv",
    get_uv_version = function(path) "9.9.9",
    write_group_to_pyproject = function(...) invisible(NULL),
    initialize_python = function(...) stop("No solution found: python-docx not in cache"),
    .package = "pyro"
  )

  err <- tryCatch(initialize_quartifyr_project(project_dir), error = function(e) e)

  expect_s3_class(err, "quartifyr_offline_failure")
  msg <- conditionMessage(err)
  expect_match(msg, "uv lock / uv sync")
  expect_match(msg, "python-docx and pyyaml")
  expect_match(msg, "UV_FIND_LINKS")
  expect_match(msg, "No solution found: python-docx not in cache")
})

test_that("offline refuses from_repo and points at from_dir, before doing anything", {
  .clean_offline_state()
  withr::local_options(quartifyr.offline = TRUE)
  project_dir <- withr::local_tempdir()
  local_mocked_bindings(
    get_uv_path = function(...) stop("must not get as far as uv"),
    initialize_python = function(...) stop("pyro must not be called"),
    .package = "pyro"
  )

  err <- tryCatch(
    initialize_quartifyr_project(project_dir, from_repo = "acme/templates"),
    error = function(e) e
  )

  expect_s3_class(err, "quartifyr_offline_failure")
  expect_match(conditionMessage(err), "from_repo")
  expect_match(conditionMessage(err), "acme/templates")
  expect_match(conditionMessage(err), "from_dir")
})

# --- python_env: skip pyro/uv entirely --------------------------------------

test_that("python_env skips pyro entirely and touches nothing in the project", {
  .clean_offline_state()
  env <- .fake_python_env('echo ""')
  project_dir <- withr::local_tempdir()
  local_mocked_bindings(
    get_uv_path = function(...) stop("pyro must not be used"),
    initialize_python = function(...) stop("pyro must not be used"),
    write_group_to_pyproject = function(...) stop("pyro must not be used"),
    .package = "pyro"
  )

  result <- NULL
  expect_message(result <- initialize_quartifyr_project(project_dir, python_env = env), "pyro/uv provisioning skipped")

  expect_null(result)
  expect_identical(list.files(project_dir, all.files = TRUE, no.. = TRUE), character(0))
})

test_that("python_env also works via the option, and a project directory holding .venv is accepted", {
  .clean_offline_state()
  venv <- .fake_python_env('echo ""')
  project_with_venv <- withr::local_tempdir()
  file.copy(venv, project_with_venv, recursive = TRUE)
  file.rename(file.path(project_with_venv, basename(venv)), file.path(project_with_venv, ".venv"))
  withr::local_options(quartifyr.python_env = project_with_venv)

  expect_no_error(suppressMessages(initialize_quartifyr_project(withr::local_tempdir())))
})

test_that("python_env missing modules are named, with the PyPI package to install", {
  .clean_offline_state()
  env <- .fake_python_env('echo "docx,yaml"')

  err <- tryCatch(initialize_quartifyr_project(withr::local_tempdir(), python_env = env), error = function(e) e)

  expect_s3_class(err, "quartifyr_python_env_invalid")
  expect_match(conditionMessage(err), "docx")
  expect_match(conditionMessage(err), "yaml")
  expect_match(conditionMessage(err), "python-docx")
  expect_match(conditionMessage(err), "pyyaml")
})

test_that("python_env without an interpreter, or with a broken one, fails clearly", {
  .clean_offline_state()
  empty <- withr::local_tempdir()
  expect_error(.verify_python_env(empty), "No Python interpreter found")

  broken <- .fake_python_env("echo 'python: bad install' >&2; exit 3")
  expect_error(.verify_python_env(broken), "could not be run")
})

test_that("the bundled quartifyr_styling source is on PYTHONPATH when probing and running", {
  .clean_offline_state()
  record <- withr::local_tempfile()
  env <- .fake_python_env(c(
    sprintf("echo \"$PYTHONPATH\" > %s", shQuote(record)),
    'echo ""'
  ))

  .verify_python_env(env)

  expect_match(readLines(record)[[1]], "python", fixed = TRUE)
  expect_true(startsWith(readLines(record)[[1]], .python_src()))
})

# --- python_env: the styling CLI runs in it directly -------------------------

test_that(".run_quartifyr_styling_cli() runs a configured python_env directly, never touching pyro", {
  .clean_offline_state()
  record <- withr::local_tempfile()
  env <- .fake_python_env(c(
    sprintf("echo \"$@\" > %s", shQuote(record)),
    "echo '{\"status\": \"ok\", \"out\": \"x.docx\"}'"
  ))
  withr::local_options(quartifyr.python_env = env)
  local_mocked_bindings(
    get_venv_uv_paths = function() stop("pyro must not be used"),
    run_python_script = function(...) stop("pyro must not be used"),
    .package = "pyro"
  )

  parsed <- .run_quartifyr_styling_cli(c("build", "--style", "s.yaml"))

  expect_identical(parsed$out, "x.docx")
  expect_identical(readLines(record), "-m quartifyr_styling --json build --style s.yaml")
})

test_that("a failing styling CLI in a python_env still surfaces its JSON diagnostic", {
  .clean_offline_state()
  env <- .fake_python_env(c(
    "echo '{\"status\": \"error\", \"code\": \"bad_style\", \"message\": \"style.yaml is invalid\"}' >&2",
    "exit 1"
  ))
  withr::local_options(quartifyr.python_env = env)

  expect_error(.run_quartifyr_styling_cli(c("build")), "bad_style.*style.yaml is invalid")
})

test_that("QUARTIFYR_PYTHON_ENV is honoured when the option isn't set", {
  .clean_offline_state()
  env <- .fake_python_env("echo '{\"status\": \"ok\"}'")
  withr::local_envvar(QUARTIFYR_PYTHON_ENV = env)

  expect_identical(.configured_python_env(), env)
  expect_identical(.run_quartifyr_styling_cli("build")$status, "ok")
})

# --- install_extensions ------------------------------------------------------

test_that("install_extensions = TRUE installs quarto-plus from a local source, then quartifyr's own", {
  .clean_offline_state()
  env <- .fake_python_env('echo ""')
  project_dir <- withr::local_tempdir()
  source_root <- withr::local_tempdir()
  ext <- file.path(source_root, "_extensions", "quarto-plus")
  dir.create(ext, recursive = TRUE)
  writeLines("title: mirrored", file.path(ext, "_extension.yml"))
  installed_own <- FALSE
  local_mocked_bindings(install_quartifyr_extension = function(path, ...) {
    installed_own <<- TRUE
    invisible(NULL)
  })

  suppressMessages(initialize_quartifyr_project(
    project_dir, python_env = env, install_extensions = TRUE, extensions_from = source_root
  ))

  expect_identical(
    readLines(file.path(project_dir, "_extensions", "A2-ai", "quarto-plus", "_extension.yml")),
    "title: mirrored"
  )
  expect_true(installed_own)
})

# A venv's bin/python is normally a symlink to the base interpreter, and
# Python locates the venv (and its site-packages) from the path it was
# invoked as. Following the link would silently probe the wrong interpreter.
test_that("the venv's python is invoked by its own path, not its symlink target", {
  .clean_offline_state()
  skip_on_os("windows")
  record <- withr::local_tempfile()
  real <- withr::local_tempfile(fileext = ".sh")
  writeLines(c("#!/bin/sh", sprintf("echo \"$0\" > %s", shQuote(record)), 'echo ""'), real)
  Sys.chmod(real, "0755")
  env <- withr::local_tempdir()
  dir.create(file.path(env, "bin"))
  file.symlink(real, file.path(env, "bin", "python"))

  .verify_python_env(env)

  expect_match(readLines(record), "/bin/python$")
})

test_that("a relative python_env is made absolute without resolving symlinks", {
  skip_on_os("windows")
  env <- withr::local_tempdir()
  dir.create(file.path(env, "bin"))
  target <- withr::local_tempfile()
  file.create(target)
  file.symlink(target, file.path(env, "bin", "python"))

  rel <- basename(env)
  python <- withr::with_dir(dirname(env), .python_exe(rel))

  expect_match(python, paste0(rel, "/bin/python$"))
})

test_that(".process_error_detail() prefers the subprocess's stderr, wherever processx put it", {
  inner <- structure(
    class = c("system_command_status_error", "error", "condition"),
    list(message = "System command 'uv_setup.sh' failed", call = NULL, stderr = "noise\n  x lxml wheel not in cache\n\n")
  )
  outer <- structure(
    class = c("error", "condition"),
    list(message = "wrapped", call = NULL, parent = inner)
  )

  expect_match(.process_error_detail(outer), "lxml wheel not in cache")
  expect_identical(.process_error_detail(simpleError("plain failure")), "plain failure")
})

# --- Render-time offline handling --------------------------------------------

test_that(".looks_like_uv_failure() recognises uv/network failures and not ordinary ones", {
  yes <- c(
    "error: No solution found when resolving dependencies",
    "Failed to fetch: https://pypi.org/simple/x/",
    "failed to download distribution",
    "Network is unreachable",
    "Connection refused (os error 111)",
    "dns error: failed to lookup address",
    "error sending request for url",
    "System command 'uv_setup.sh' failed",
    "Because x was not found in the package registry",
    "cannot run while uv is offline"
  )
  no <- c("Figure footnotes script failed.", "python exploded", "Metadata file not found for: a.png")
  expect_true(all(.looks_like_uv_failure(yes)))
  expect_false(any(.looks_like_uv_failure(no)))
})

test_that(".with_offline_context() relabels uv failures only in offline mode", {
  uv_failure <- function() stop("error: Failed to fetch: https://pypi.org/simple/x/")
  step <- "fill the shell with reportifyr (pass 2)"

  err <- withr::with_options(
    list(quartifyr.offline = TRUE),
    suppressMessages(tryCatch(.with_offline_context(uv_failure(), step), error = function(e) e))
  )
  expect_s3_class(err, "quartifyr_offline_failure")
  expect_match(conditionMessage(err), "fill the shell with reportifyr \\(pass 2\\)")
  expect_match(conditionMessage(err), "Failed to fetch")

  online <- withr::with_options(
    list(quartifyr.offline = FALSE),
    withr::with_envvar(c(UV_OFFLINE = ""), tryCatch(.with_offline_context(uv_failure(), step), error = function(e) e))
  )
  expect_false(inherits(online, "quartifyr_offline_failure"))
  expect_match(conditionMessage(online), "Failed to fetch")
})

test_that(".with_offline_context() leaves ordinary and already-classed errors alone", {
  step <- "pass 2"
  withr::local_options(quartifyr.offline = TRUE)

  ordinary <- tryCatch(.with_offline_context(stop("python exploded"), step), error = function(e) e)
  expect_false(inherits(ordinary, "quartifyr_offline_failure"))
  expect_match(conditionMessage(ordinary), "python exploded")

  sidecar <- structure(
    class = c("quartifyr_pass2_failed", "error", "condition"),
    list(message = "offline sidecar problem", call = NULL)
  )
  expect_s3_class(tryCatch(.with_offline_context(stop(sidecar), step), error = function(e) e), "quartifyr_pass2_failed")

  already <- structure(
    class = c("quartifyr_offline_failure", "error", "condition"),
    list(message = "network", call = NULL)
  )
  expect_identical(tryCatch(.with_offline_context(stop(already), step), error = function(e) e), already)

  expect_identical(.with_offline_context("fine", step), "fine")
})

# --- Interpreter vs. the project's pin ------------------------------------------

test_that(".satisfies_requires_python() reads the common PEP 440 specifiers", {
  v <- c(3L, 12L, 3L)
  expect_true(.satisfies_requires_python(v, ">=3.10"))
  expect_true(.satisfies_requires_python(v, ">=3.10, <3.13"))
  expect_false(.satisfies_requires_python(v, ">=3.13"))
  expect_false(.satisfies_requires_python(v, ">3.12.3"))
  expect_true(.satisfies_requires_python(v, "==3.12.*"))
  expect_false(.satisfies_requires_python(v, "==3.11.*"))
  expect_true(.satisfies_requires_python(v, "!=3.11.*"))
  expect_true(.satisfies_requires_python(v, "~=3.12"))
  expect_false(.satisfies_requires_python(v, "~=3.12.4"))
  expect_true(is.na(.satisfies_requires_python(v, "===3.12")))
  expect_true(is.na(.satisfies_requires_python(v, "")))
})

.python_env_fixture <- function(version, pin = NULL, requires = NULL, key = "version", env = parent.frame()) {
  project <- withr::local_tempdir(.local_envir = env)
  dir.create(file.path(project, ".venv"))
  writeLines(c("home = /usr/bin", paste0(key, " = ", version)), file.path(project, ".venv", "pyvenv.cfg"))
  if (!is.null(pin)) writeLines(c("# the pin", pin), file.path(project, ".python-version"))
  if (!is.null(requires)) {
    writeLines(c("[project]", paste0("requires-python = \"", requires, "\"  # comment")), file.path(project, "pyproject.toml"))
  }
  project
}

test_that(".python_env_mismatch() flags an interpreter that doesn't match .python-version", {
  project <- .python_env_fixture("3.12.3", pin = "3.12.16")
  msg <- .python_env_mismatch(project, file.path(project, ".venv"))
  expect_match(msg, "runs Python 3.12.3")
  expect_match(msg, "pins 3.12.16 \\(.python-version\\)")

  # uv writes version_info, and a pin may be coarser than the interpreter.
  project <- .python_env_fixture("3.12.3.final.0", pin = "3.12", key = "version_info")
  expect_null(.python_env_mismatch(project, file.path(project, ".venv")))
  project <- .python_env_fixture("3.12.3", pin = "cpython-3.12.3-macos-aarch64-none")
  expect_null(.python_env_mismatch(project, file.path(project, ".venv")))
  project <- .python_env_fixture("3.11.9", pin = "3.12")
  expect_match(.python_env_mismatch(project, file.path(project, ".venv")), "pins 3.12")
})

test_that(".python_env_mismatch() falls back to requires-python and stays quiet when it can't tell", {
  project <- .python_env_fixture("3.9.18", requires = ">=3.10")
  expect_match(.python_env_mismatch(project, file.path(project, ".venv")), "requires-python in pyproject.toml")
  project <- .python_env_fixture("3.12.3", requires = ">=3.10")
  expect_null(.python_env_mismatch(project, file.path(project, ".venv")))

  no_pin <- .python_env_fixture("3.12.3")
  expect_null(.python_env_mismatch(no_pin, file.path(no_pin, ".venv")))
  no_venv <- withr::local_tempdir()
  writeLines("3.12.16", file.path(no_venv, ".python-version"))
  expect_null(.python_env_mismatch(no_venv, file.path(no_venv, ".venv")))
})

test_that(".render_python_env() prefers the configured python_env over the project's .venv", {
  project <- withr::local_tempdir()
  withr::local_options(quartifyr.python_env = NULL, venv_dir = NULL)
  withr::local_envvar(QUARTIFYR_PYTHON_ENV = NA)
  expect_identical(.render_python_env(project), file.path(project, ".venv"))
  withr::local_options(quartifyr.python_env = "/opt/env")
  expect_identical(.render_python_env(project), "/opt/env")
})

test_that(".parse_py_version() reads the first version number and gives NULL for none", {
  expect_identical(.parse_py_version("cpython-3.12.3-macos"), c(3L, 12L, 3L))
  expect_identical(.parse_py_version("3.12"), c(3L, 12L))
  expect_null(.parse_py_version("not a version"))
})

test_that(".satisfies_requires_python() handles every comparison operator", {
  v <- c(3L, 12L, 3L)
  expect_true(.satisfies_requires_python(v, "<=3.12.3"))
  expect_false(.satisfies_requires_python(v, "<=3.12.2"))
  expect_true(.satisfies_requires_python(v, "<3.13"))
  expect_true(.satisfies_requires_python(v, "==3.12.3"))
  expect_false(.satisfies_requires_python(v, "==3.12.4"))
  expect_true(.satisfies_requires_python(v, "!=3.12.4"))
  expect_false(.satisfies_requires_python(v, "!=3.12.3"))
  expect_false(.satisfies_requires_python(v, "!=3.12.*"))
})

test_that(".venv_python_version() is NULL without a pyvenv.cfg or without a version line", {
  empty <- withr::local_tempdir()
  expect_null(.venv_python_version(empty))
  writeLines(c("home = /usr/bin", "include-system-site-packages = false"), file.path(empty, "pyvenv.cfg"))
  expect_null(.venv_python_version(empty))
})
