# --- .ensure_default_groups_all() ------------------------------------------

test_that(".ensure_default_groups_all() is a no-op when the file doesn't exist", {
  path <- file.path(withr::local_tempdir(), "pyproject.toml")
  expect_false(file.exists(path))

  result <- .ensure_default_groups_all(path)

  expect_false(result)
  expect_false(file.exists(path))
})

test_that(".ensure_default_groups_all() respects an already-configured default-groups", {
  path <- withr::local_tempfile(fileext = ".toml")
  writeLines(c("[tool.uv]", 'default-groups = ["reportifyr"]'), path)
  original <- readLines(path, warn = FALSE)

  result <- .ensure_default_groups_all(path)

  expect_false(result)
  expect_identical(readLines(path, warn = FALSE), original)
})

test_that(".ensure_default_groups_all() inserts the line right after an existing [tool.uv]", {
  path <- withr::local_tempfile(fileext = ".toml")
  writeLines(c("[project]", 'name = "demo"', "", "[tool.uv]", "some-other-key = true"), path)

  result <- .ensure_default_groups_all(path)

  expect_true(result)
  lines <- readLines(path, warn = FALSE)
  tool_uv_idx <- which(lines == "[tool.uv]")
  expect_identical(lines[tool_uv_idx + 1], 'default-groups = "all"')
  expect_identical(lines[tool_uv_idx + 2], "some-other-key = true")
})

test_that(".ensure_default_groups_all() appends a new [tool.uv] section when none exists", {
  path <- withr::local_tempfile(fileext = ".toml")
  writeLines(c("[project]", 'name = "demo"'), path)

  result <- .ensure_default_groups_all(path)

  expect_true(result)
  lines <- readLines(path, warn = FALSE)
  expect_identical(tail(lines, 3), c("", "[tool.uv]", 'default-groups = "all"'))
})

test_that(".ensure_default_groups_all() trims trailing blank lines before appending", {
  path <- withr::local_tempfile(fileext = ".toml")
  writeLines(c("[project]", 'name = "demo"', "", "", ""), path)

  .ensure_default_groups_all(path)

  lines <- readLines(path, warn = FALSE)
  # No blank line should separate the trimmed content from the new section
  # beyond the single deliberate one this function inserts.
  expect_identical(lines, c("[project]", 'name = "demo"', "", "[tool.uv]", 'default-groups = "all"'))
})

# --- .seed_pyproject_stub() -------------------------------------------------

test_that(".seed_pyproject_stub() creates a minimal valid pyproject.toml when none exists", {
  project_dir <- withr::local_tempdir()
  toml_path <- file.path(project_dir, "pyproject.toml")

  result <- .seed_pyproject_stub(project_dir)

  expect_true(result)
  expect_true(file.exists(toml_path))
  lines <- readLines(toml_path, warn = FALSE)
  expect_identical(lines[[1]], "[project]")
  expect_true(any(grepl('^version = "0\\.0\\.1"$', lines)))
  expect_true(any(grepl('^requires-python = ">=3\\.12"$', lines)))
  # No [dependency-groups] table yet -- write_group_to_pyproject() adds it.
  expect_false(any(grepl("^\\[dependency-groups\\]$", lines)))
})

test_that(".seed_pyproject_stub() is a no-op when pyproject.toml already exists", {
  project_dir <- withr::local_tempdir()
  toml_path <- file.path(project_dir, "pyproject.toml")
  writeLines(c("[project]", 'name = "existing"'), toml_path)
  original <- readLines(toml_path, warn = FALSE)

  result <- .seed_pyproject_stub(project_dir)

  expect_false(result)
  expect_identical(readLines(toml_path, warn = FALSE), original)
})

test_that(".seed_pyproject_stub() sanitizes a directory name with characters invalid in a TOML bare value", {
  parent <- withr::local_tempdir()
  project_dir <- file.path(parent, "My Report! (v2)")
  dir.create(project_dir)

  .seed_pyproject_stub(project_dir)

  lines <- readLines(file.path(project_dir, "pyproject.toml"), warn = FALSE)
  name_line <- lines[grepl("^name = ", lines)]
  expect_match(name_line, '^name = "[A-Za-z0-9._-]+"$')
})

# --- initialize_quartifyr_project() regression: real pyro::write_group_to_pyproject() ---

test_that("initialize_quartifyr_project() never leaves an empty-deps quartifyr group (regression, #<empty PEP508 field>)", {
  # Reproduces the reported failure: on a project where pyproject.toml
  # doesn't exist yet, pyro::initialize_python(groups = "quartifyr") used
  # to be the one seeding it -- via pyro's own seed_pyproject(), which
  # renders an unrecognized group name (pyro doesn't know "quartifyr")
  # with a single spurious empty-string dependency. uv then rejects that
  # with "Empty field is not allowed for PEP508". This test exercises the
  # *real* pyro::write_group_to_pyproject() (only pyro::initialize_python()
  # is mocked, since it shells out to uv) to prove the fix -- pre-seeding
  # pyproject.toml ourselves -- keeps pyro's buggy seeding path from ever
  # running.
  project_dir <- withr::local_tempdir()

  local_mocked_bindings(
    initialize_python = function(...) invisible("initialized"),
    .package = "pyro"
  )

  initialize_quartifyr_project(project_dir)

  toml_path <- file.path(project_dir, "pyproject.toml")
  expect_true(file.exists(toml_path))
  lines <- readLines(toml_path, warn = FALSE)

  group_hdr <- which(grepl("^quartifyr = \\[$", lines))
  expect_length(group_hdr, 1)
  group_end <- which(grepl("^\\]$", lines))
  group_end <- group_end[group_end > group_hdr][1]
  dep_lines <- trimws(lines[(group_hdr + 1):(group_end - 1)])

  expect_true(length(dep_lines) > 0)
  expect_false(any(dep_lines %in% c('"",', '""')))
  expect_setequal(dep_lines, c('"python-docx",', '"pyyaml",'))
})

# --- initialize_quartifyr_project() -----------------------------------------

test_that("initialize_quartifyr_project() writes the quartifyr dependency group and initializes python", {
  project_dir <- withr::local_tempdir()

  captured_write_args <- NULL
  captured_init_args <- NULL
  local_mocked_bindings(
    write_group_to_pyproject = function(name, deps = NULL, pyproject_dir) {
      captured_write_args <<- list(name = name, deps = deps, pyproject_dir = pyproject_dir)
      invisible(NULL)
    },
    initialize_python = function(continue = NULL, venv_dir, uv_version = NULL, groups = NULL, pyproject_dir = NULL) {
      captured_init_args <<- list(venv_dir = venv_dir, pyproject_dir = pyproject_dir, groups = groups)
      invisible("initialized")
    },
    .package = "pyro"
  )

  result <- initialize_quartifyr_project(project_dir)

  expect_identical(captured_write_args$name, "quartifyr")
  expect_identical(captured_write_args$deps, c("python-docx", "pyyaml"))
  expect_identical(normalizePath(captured_write_args$pyproject_dir), normalizePath(project_dir))

  expect_identical(normalizePath(captured_init_args$venv_dir), normalizePath(project_dir))
  expect_identical(normalizePath(captured_init_args$pyproject_dir), normalizePath(project_dir))
  expect_identical(captured_init_args$groups, "quartifyr")

  expect_identical(result, "initialized")
})

test_that("initialize_quartifyr_project() re-raises a pyro::initialize_python() failure with an actionable message (#46)", {
  # Reproduces the reported failure: on an existing reportifyr project
  # created before reportifyr 0.4.0 added its own pyro dependency, its
  # pre-pyro Python environment isn't necessarily something `uv sync` can
  # adopt as-is -- pyro::initialize_python() surfaces that as a raw,
  # uv-internal error with no mention of quartifyr or reportifyr at all.
  project_dir <- withr::local_tempdir()

  local_mocked_bindings(
    write_group_to_pyproject = function(...) invisible(NULL),
    initialize_python = function(...) stop("uv sync failed: not a valid virtual environment"),
    .package = "pyro"
  )

  expect_error(
    initialize_quartifyr_project(project_dir),
    "pyro failed to provision a Python environment"
  )
})

test_that("initialize_quartifyr_project() adds default-groups = \"all\" to an existing pyproject.toml", {
  project_dir <- withr::local_tempdir()
  writeLines(c("[tool.uv]", "index-strategy = \"unsafe-best-match\""), file.path(project_dir, "pyproject.toml"))

  local_mocked_bindings(
    write_group_to_pyproject = function(...) invisible(NULL),
    initialize_python = function(...) invisible("initialized"),
    .package = "pyro"
  )

  initialize_quartifyr_project(project_dir)

  lines <- readLines(file.path(project_dir, "pyproject.toml"), warn = FALSE)
  expect_true('default-groups = "all"' %in% lines)
})

# --- initialize_quartifyr_project() template scaffolding (#23) --------------

test_that("initialize_quartifyr_project() never calls the init CLI when no template source is given", {
  project_dir <- withr::local_tempdir()

  cli_called <- FALSE
  local_mocked_bindings(
    write_group_to_pyproject = function(...) invisible(NULL),
    initialize_python = function(...) invisible("initialized"),
    .package = "pyro"
  )
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      cli_called <<- TRUE
      list(created = character(0))
    }
  )

  initialize_quartifyr_project(project_dir)

  expect_false(cli_called)
})

test_that("initialize_quartifyr_project() forwards from_dir to the init CLI", {
  project_dir <- withr::local_tempdir()

  captured_args <- NULL
  local_mocked_bindings(
    write_group_to_pyproject = function(...) invisible(NULL),
    initialize_python = function(...) invisible("initialized"),
    .package = "pyro"
  )
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(created = character(0))
    }
  )

  initialize_quartifyr_project(project_dir, from_dir = "/some/template/source")

  expect_identical(
    captured_args,
    c("init", normalizePath(project_dir), "--from-dir", "/some/template/source")
  )
})

test_that("initialize_quartifyr_project() forwards from_repo/ref/subdir/type/force to the init CLI", {
  project_dir <- withr::local_tempdir()

  captured_args <- NULL
  local_mocked_bindings(
    write_group_to_pyproject = function(...) invisible(NULL),
    initialize_python = function(...) invisible("initialized"),
    .package = "pyro"
  )
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(created = character(0))
    }
  )

  initialize_quartifyr_project(
    project_dir,
    from_repo = "acme-org/quartifyr-templates@v2",
    ref = "v3",
    subdir = "templates/csr",
    type = "csr",
    force = TRUE
  )

  expect_identical(
    captured_args,
    c(
      "init", normalizePath(project_dir),
      "--from-repo", "acme-org/quartifyr-templates@v2",
      "--ref", "v3",
      "--subdir", "templates/csr",
      "--type", "csr",
      "--force"
    )
  )
})

test_that("initialize_quartifyr_project() calls the init CLI with the project directory as cwd", {
  project_dir <- withr::local_tempdir()

  captured_wd <- NULL
  local_mocked_bindings(
    write_group_to_pyproject = function(...) invisible(NULL),
    initialize_python = function(...) invisible("initialized"),
    .package = "pyro"
  )
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_wd <<- getwd()
      list(created = character(0))
    }
  )

  initialize_quartifyr_project(project_dir, from_dir = "/some/template/source")

  expect_identical(normalizePath(captured_wd), normalizePath(project_dir))
})

test_that("initialize_quartifyr_project() still returns pyro::initialize_python()'s result when scaffolding too", {
  project_dir <- withr::local_tempdir()

  local_mocked_bindings(
    write_group_to_pyproject = function(...) invisible(NULL),
    initialize_python = function(...) invisible("initialized"),
    .package = "pyro"
  )
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) list(created = character(0))
  )

  result <- initialize_quartifyr_project(project_dir, from_dir = "/some/template/source")

  expect_identical(result, "initialized")
})
