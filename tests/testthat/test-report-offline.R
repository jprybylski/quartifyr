# The pyro-free project setup and the one-environment-for-both-passes wiring
# (#85). Nothing here needs the network, uv or a Python interpreter.

.forbid_pyro <- function(env = parent.frame()) {
  boom <- function(...) stop("pyro was called; this must not reach for uv or the network")
  local_mocked_bindings(
    initialize_python = boom, write_group_to_pyproject = boom, get_uv_path = boom,
    .package = "pyro", .env = env
  )
}

test_that("initialize_report_project_offline() creates the folders, config and marker without pyro", {
  skip_if_not_installed("reportifyr")
  .forbid_pyro()
  project <- withr::local_tempdir()

  suppressMessages(initialize_report_project_offline(project))

  for (dir in c("draft", "final", "scripts", "shell")) {
    expect_true(file.exists(file.path(project, "report", dir, "readme.txt")), info = dir)
  }
  for (dir in c("figures", "tables", "listings")) {
    expect_true(dir.exists(file.path(project, "OUTPUTS", dir)), info = dir)
  }
  expect_true(file.exists(file.path(project, "report", "config.yaml")))
  expect_true(file.exists(file.path(project, "report", "standard_footnotes.yaml")))

  # Nothing pyro or uv would have made.
  expect_false(any(file.exists(file.path(project, c(".venv", "pyproject.toml", "uv.lock")))))

  marker <- jsonlite::fromJSON(file.path(project, ".report_init.json"))
  expect_setequal(names(marker), c("creation_timestamp", "last_modified", "user", "config", "venv_dir"))
  expect_identical(marker$venv_dir, ".")
  expect_identical(marker$config, yaml::read_yaml(file.path(project, "report", "config.yaml")))

  # What the project checks and reportifyr itself look for.
  expect_null(.check_init_marker(project))
})

test_that("the marker has the same fields as the one reportifyr writes", {
  demo_marker <- file.path(test_path("..", "..", "examples", "demo-report"), ".report_init.json")
  skip_if_not(file.exists(demo_marker), "no reportifyr-written marker to compare with")
  project <- withr::local_tempdir()
  skip_if_not_installed("reportifyr")
  suppressMessages(initialize_report_project_offline(project))
  expect_identical(
    names(jsonlite::fromJSON(file.path(project, ".report_init.json"))),
    names(jsonlite::fromJSON(demo_marker))
  )
})

test_that("initialize_report_project_offline() leaves what exists alone, so a second run changes nothing", {
  skip_if_not_installed("reportifyr")
  .forbid_pyro()
  project <- withr::local_tempdir()
  suppressMessages(initialize_report_project_offline(project))
  writeLines("key: mine", file.path(project, "report", "config.yaml"))
  writeLines("my readme", file.path(project, "report", "draft", "readme.txt"))
  marker_before <- readLines(file.path(project, ".report_init.json"))

  suppressMessages(initialize_report_project_offline(project))

  expect_identical(readLines(file.path(project, "report", "config.yaml")), "key: mine")
  expect_identical(readLines(file.path(project, "report", "draft", "readme.txt")), "my readme")
  expect_identical(readLines(file.path(project, ".report_init.json")), marker_before)
})

test_that("custom folder names are honoured, in the config and in the marker's name", {
  skip_if_not_installed("reportifyr")
  project <- withr::local_tempdir()
  suppressMessages(initialize_report_project_offline(project, report_dir_name = "docs", outputs_dir_name = "OUT"))

  expect_true(dir.exists(file.path(project, "OUT", "figures")))
  config <- yaml::read_yaml(file.path(project, "docs", "config.yaml"))
  expect_identical(config$report_dir_name, "docs")
  expect_identical(config$outputs_dir_name, "OUT")
  expect_true(file.exists(file.path(project, ".docs_init.json")))
  expect_null(.check_init_marker(project))
})

test_that("initialize_report_project_offline() verifies a python_env for reportifyr's modules", {
  skip_if_not_installed("reportifyr")
  project <- withr::local_tempdir()
  seen <- NULL
  local_mocked_bindings(.verify_python_env = function(env, modules = NULL) {
    seen <<- list(env = env, modules = names(modules))
    "python"
  })
  suppressMessages(initialize_report_project_offline(project, python_env = "/opt/env"))
  expect_identical(seen$env, "/opt/env")
  expect_setequal(seen$modules, c("docx", "yaml", "PIL"))

  local_mocked_bindings(.verify_python_env = function(...) {
    cli::cli_abort("missing pillow", class = "quartifyr_python_env_invalid", call = NULL)
  })
  other <- withr::local_tempdir()
  expect_error(
    initialize_report_project_offline(other, python_env = "/opt/env"),
    class = "quartifyr_python_env_invalid"
  )
  expect_false(file.exists(file.path(other, ".report_init.json"))) # nothing created for a bad env
})

# --- Pointing pass 2 at the python_env ------------------------------------------

test_that(".python_env_venv() accepts a venv or a project directory holding a .venv", {
  base <- withr::local_tempdir()
  venv <- .make_venv(base, "envs-elsewhere")
  expect_identical(.python_env_venv(venv), venv)

  project <- withr::local_tempdir()
  nested <- .make_venv(project)
  expect_identical(.python_env_venv(project), nested)
})

test_that(".python_env_wiring() uses the .venv's parent directly and exports the uv settings", {
  project <- withr::local_tempdir()
  venv <- .make_venv(project)

  wiring <- .python_env_wiring(venv)

  # (Compared as paths: dirname() writes forward slashes, tempdir() on Windows doesn't.)
  expect_identical(normalizePath(wiring$options$venv_dir), normalizePath(project))
  expect_identical(wiring$env[["UV_PROJECT_ENVIRONMENT"]], venv)
  expect_identical(wiring$env[["UV_NO_SYNC"]], "1")
  # The environment's own interpreter, so a .python-version can't switch it.
  expect_identical(wiring$env[["UV_PYTHON"]], file.path(venv, "bin", "python"))
  # pyro's VIRTUAL_ENV for this is <venv_dir>/.venv, i.e. the environment itself.
  expect_identical(normalizePath(file.path(wiring$options$venv_dir, ".venv")), normalizePath(venv))
})

test_that(".python_env_wiring() exposes a venv with another name through a .venv link (a junction on Windows)", {
  base <- withr::local_tempdir()
  venv <- .make_venv(base, "report-env")

  # The temporary directory is tied to the frame that asked for it.
  wiring <- (function() .python_env_wiring(venv))()
  expect_false(dir.exists(wiring$options$venv_dir))

  inside <- NULL
  (function() {
    wiring <- .python_env_wiring(venv)
    linked <- file.path(wiring$options$venv_dir, ".venv")
    inside <<- list(
      dir = wiring$options$venv_dir,
      exists = dir.exists(linked),
      same = identical(normalizePath(linked), normalizePath(venv)),
      cfg = file.exists(file.path(linked, "pyvenv.cfg")),
      uv = wiring$env[["UV_PROJECT_ENVIRONMENT"]]
    )
  })()
  expect_true(inside$exists)
  expect_true(inside$same)
  expect_true(inside$cfg)
  expect_identical(inside$uv, venv)
  expect_false(dir.exists(inside$dir))
})

test_that(".use_python_env_for_pass2() applies for the caller's frame, then restores", {
  .mock_python_env()
  project <- withr::local_tempdir()
  venv <- .make_venv(project)
  withr::local_options(venv_dir = NULL, quartifyr.python_env = venv)
  withr::local_envvar(UV_PROJECT_ENVIRONMENT = NA, UV_NO_SYNC = NA)

  inside <- (function() {
    .use_python_env_for_pass2()
    list(
      venv_dir = getOption("venv_dir"),
      env = Sys.getenv(c("UV_PROJECT_ENVIRONMENT", "UV_NO_SYNC"), unset = "<unset>")
    )
  })()

  expect_identical(normalizePath(inside$venv_dir), normalizePath(project))
  expect_identical(unname(inside$env[1:2]), c(venv, "1"))
  expect_null(getOption("venv_dir"))
  expect_identical(Sys.getenv("UV_NO_SYNC", "<unset>"), "<unset>")
})

test_that(".use_python_env_for_pass2() does nothing without a python_env", {
  withr::local_options(venv_dir = NULL, quartifyr.python_env = NULL)
  withr::local_envvar(QUARTIFYR_PYTHON_ENV = NA, UV_PROJECT_ENVIRONMENT = NA)
  expect_null(.use_python_env_for_pass2())
  expect_null(getOption("venv_dir"))
  expect_identical(Sys.getenv("UV_PROJECT_ENVIRONMENT", "<unset>"), "<unset>")
})

test_that("initialize_report_project_offline() says so when reportifyr's defaults can't be found", {
  local_mocked_bindings(.reportifyr_extdata = function(name) "")
  project <- withr::local_tempdir()
  expect_error(
    initialize_report_project_offline(project),
    class = "quartifyr_report_project_offline"
  )
  expect_false(dir.exists(file.path(project, "report")))
})

test_that(".python_env_venv() leaves a directory that is neither a venv nor holds one as it is", {
  plain <- withr::local_tempdir()
  expect_identical(.python_env_venv(plain), plain)
})

test_that(".python_env_wiring() explains when a .venv name can't be made with a symlink", {
  base <- withr::local_tempdir()
  venv <- .make_venv(base, "report-env")
  local_mocked_bindings(.link_venv = function(venv, link) FALSE)
  expect_error(
    (function() .python_env_wiring(venv))(),
    class = "quartifyr_python_env_invalid"
  )
})

test_that("a python_env's interpreter is pinned for uv, so a .python-version can't pick another", {
  .mock_python_env()
  project <- withr::local_tempdir()
  venv <- .make_venv(project)
  withr::local_options(venv_dir = NULL, quartifyr.python_env = venv)
  withr::local_envvar(UV_PYTHON = NA)
  seen <- (function() {
    .use_python_env_for_pass2()
    Sys.getenv("UV_PYTHON", "<unset>")
  })()
  expect_identical(seen, file.path(venv, "bin", "python"))
  expect_identical(Sys.getenv("UV_PYTHON", "<unset>"), "<unset>")
})

test_that(".junction_command() builds an mklink /J call with backslash paths", {
  cmd <- .junction_command("/envs/report-env", "/tmp/x/.venv")
  expect_identical(cmd$args[1:3], c("/c", "mklink", "/J"))
  expect_length(cmd$args, 5)
  expect_match(cmd$args[[4]], "\\.venv$")
  expect_match(cmd$args[[5]], "report-env$")
  # (normalizePath(winslash = "\\") only changes the slashes on Windows itself.)
})

test_that(".unlink_venv_link() removes the link and never what it points at", {
  base <- withr::local_tempdir()
  venv <- .make_venv(base, "report-env")
  link <- file.path(withr::local_tempdir(), ".venv")
  expect_true(.link_venv(venv, link))
  expect_true(dir.exists(link))

  .unlink_venv_link(link)

  expect_false(file.exists(link))
  expect_true(file.exists(file.path(venv, "pyvenv.cfg"))) # the environment is untouched
})

test_that("the temporary link made for a differently named venv is removed without touching the venv", {
  base <- withr::local_tempdir()
  venv <- .make_venv(base, "report-env")
  dir_made <- NULL
  (function() {
    wiring <- .python_env_wiring(venv)
    dir_made <<- wiring$options$venv_dir
    expect_true(dir.exists(file.path(dir_made, ".venv")))
  })()
  expect_false(dir.exists(dir_made))
  expect_true(file.exists(file.path(venv, "pyvenv.cfg")))
})

# --- The Windows branches, run anywhere with the platform and processx mocked ---

test_that(".link_venv() uses a junction on Windows and reports whether it worked", {
  local_mocked_bindings(.is_windows = function() TRUE)
  base <- withr::local_tempdir()
  venv <- .make_venv(base, "tools-venv")
  link <- file.path(withr::local_tempdir(), ".venv")
  calls <- list()
  fake_run <- function(command, args, ...) {
    calls[[length(calls) + 1L]] <<- list(command = command, args = args)
    dir.create(link) # what a successful mklink /J leaves behind
    list(status = 0L, stdout = "", stderr = "")
  }
  local_mocked_bindings(run = fake_run, .package = "processx")

  expect_true(.link_venv(venv, link))

  expect_identical(calls[[1]]$args[1:3], c("/c", "mklink", "/J"))
})

test_that(".link_venv() falls back to a symlink when mklink fails or can't be run", {
  skip_on_os("windows")
  local_mocked_bindings(.is_windows = function() TRUE)
  base <- withr::local_tempdir()
  venv <- .make_venv(base, "tools-venv")

  local_mocked_bindings(run = function(...) list(status = 1L, stdout = "", stderr = "denied"), .package = "processx")
  link1 <- file.path(withr::local_tempdir(), ".venv")
  expect_true(.link_venv(venv, link1)) # the symlink fallback worked here
  expect_true(dir.exists(link1))

  local_mocked_bindings(run = function(...) stop("no cmd.exe"), .package = "processx")
  link2 <- file.path(withr::local_tempdir(), ".venv")
  expect_true(.link_venv(venv, link2))

  # And when nothing can make a link, the answer is FALSE (wiring then explains).
  local_mocked_bindings(run = function(...) list(status = 1L, stdout = "", stderr = ""), .package = "processx")
  local_mocked_bindings(.is_windows = function() TRUE)
  link3 <- file.path(venv, "pyvenv.cfg", "not-a-dir", ".venv") # a parent that can't exist
  expect_false(.link_venv(venv, link3))
})

test_that(".unlink_venv_link() uses rmdir on Windows, which removes a junction and nothing behind it", {
  local_mocked_bindings(.is_windows = function() TRUE)
  seen <- NULL
  local_mocked_bindings(
    run = function(command, args, ...) {
      seen <<- args
      list(status = 0L, stdout = "", stderr = "")
    },
    .package = "processx"
  )
  expect_null(.unlink_venv_link("C:/tmp/x/.venv"))
  expect_identical(seen[1:2], c("/c", "rmdir"))
  expect_false(any(c("/s", "/S") %in% seen)) # never recursive
})

test_that(".unlink_venv_link() aims rmdir at the link itself, never at the environment it resolves to", {
  skip_on_os("windows")
  # normalizePath() of an existing link gives its target. The command must be
  # built from the link path as given, or `rmdir` would be pointed at the real
  # environment (found on Windows, where the junction then survived).
  base <- withr::local_tempdir()
  venv <- .make_venv(base, "report-env")
  link <- file.path(withr::local_tempdir(), ".venv")
  expect_true(file.symlink(venv, link))
  local_mocked_bindings(.is_windows = function() TRUE)
  seen <- NULL
  local_mocked_bindings(
    run = function(command, args, ...) {
      seen <<- args
      list(status = 0L, stdout = "", stderr = "")
    },
    .package = "processx"
  )

  .unlink_venv_link(link)

  expect_match(seen[[3]], "\\.venv$")
  expect_false(grepl("report-env", seen[[3]], fixed = TRUE))
})

test_that(".windows_path() only swaps the slashes", {
  expect_identical(.windows_path("C:/Users/me/My Docs/.venv"), "C:\\Users\\me\\My Docs\\.venv")
  expect_identical(.windows_path("already\\back"), "already\\back")
})
