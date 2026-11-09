# render_report() is the orchestration driver chaining quarto render ->
# styling_apply_layout() -> reportifyr::build_report()/finalize_document().
# These tests never invoke the real `quarto` CLI, Python venv, or reportifyr
# pass 2 -- every external boundary is mocked, so this file runs on any
# machine with just the R package dependencies installed (see test-wiring.R
# for the real end-to-end round-trip, which skips without the full
# toolchain).

# The table-fitting step (styling_fit_tables(), on by default) needs the
# Python environment, so it is mocked for the whole file; the tests of that
# step itself, at the end, replace this with their own mock.
local_mocked_bindings(
  styling_fit_tables = function(docx) invisible(list(path = docx, fitted = 0L, shrunk = list(), overflowing = list())),
  .env = teardown_env()
)

.render_report_fixture <- function(env = parent.frame()) {
  project_dir <- withr::local_tempdir(.local_envir = env)

  writeLines(c("project:", "  output-dir: report/shell"), file.path(project_dir, "_quarto.yml"))
  writeLines("# shell", file.path(project_dir, "report.qmd"))
  file.create(file.path(project_dir, ".report_init.json"))

  dir.create(file.path(project_dir, "report"), recursive = TRUE)
  writeLines("footnotes: []", file.path(project_dir, "report", "standard_footnotes.yaml"))
  writeLines("key: value", file.path(project_dir, "report", "config.yaml"))

  reference_doc <- file.path(project_dir, "org-reference.docx")
  file.create(reference_doc)

  list(
    project_dir = project_dir,
    shell_qmd = file.path(project_dir, "report.qmd"),
    reference_doc = reference_doc,
    standard_footnotes_yaml = file.path(project_dir, "report", "standard_footnotes.yaml"),
    config_yaml = file.path(project_dir, "report", "config.yaml")
  )
}

# A quarto::render() stand-in that actually creates the shell docx it
# claims to, so downstream reportifyr::make_doc_dirs()-style path derivation
# (mocked below, per-test) has something real to reason about.
# The real processx::run(), kept so calls to a (fake) `uv` can reach it while
# everything else is mocked.
.real_processx_run <- processx::run

.mock_quarto_run <- function(record_into) {
  function(command, args, wd = ".", error_on_status = TRUE, ...) {
    if (identical(basename(command), "uv")) {
      return(.real_processx_run(command, args, error_on_status = error_on_status, ...))
    }
    if (!identical(args[[1]], "render")) {
      return(list(status = 0, stdout = "1.9.9\n", stderr = ""))
    }
    assign("quarto_run", list(command = command, args = args, wd = wd), envir = record_into)
    output_name <- args[which(args == "--output") + 1]
    # render_report() points quarto at its staging folder with --output-dir
    # (relative to the project); without it quarto uses _quarto.yml's.
    output_dir <- if ("--output-dir" %in% args) args[which(args == "--output-dir") + 1] else file.path("report", "shell")
    dir.create(file.path(wd, output_dir), recursive = TRUE, showWarnings = FALSE)
    file.create(file.path(wd, output_dir, output_name))
    list(status = 0, stdout = "", stderr = "")
  }
}

.mock_make_doc_dirs <- function(docx_in) {
  base <- sub("\\.docx$", "", docx_in)
  base <- sub("([/\\\\])shell([/\\\\])", "\\1draft\\2", base)
  list(
    doc_in = docx_in,
    doc_draft = paste0(base, "-draft.docx"),
    doc_final = paste0(sub("draft", "final", base), "-final.docx")
  )
}

# render_report() works in report/.staging-<id>/ and moves the finished
# render into report/{shell,draft,final}/, so the paths the mocks see are
# staged ones while the result carries the delivered ones.
.is_staged <- function(path) grepl("[/\\\\]\\.staging-[0-9a-f]+[/\\\\]", path)
.live_path <- function(fixture, role, name) {
  file.path(fixture$project_dir, "report", role, name)
}

# --- Pre-flight validation (no mocking needed) ------------------------------

test_that("errors when shell_qmd doesn't exist", {
  expect_error(render_report(file.path(withr::local_tempdir(), "missing.qmd")), "shell_qmd not found")
})

test_that("errors when _quarto.yml is missing", {
  project_dir <- withr::local_tempdir()
  shell_qmd <- file.path(project_dir, "report.qmd")
  writeLines("# shell", shell_qmd)

  expect_error(render_report(shell_qmd), "output-dir: report/shell")
})

test_that("errors when _quarto.yml doesn't set output-dir: report/shell", {
  project_dir <- withr::local_tempdir()
  shell_qmd <- file.path(project_dir, "report.qmd")
  writeLines("# shell", shell_qmd)
  writeLines(c("project:", "  output-dir: build"), file.path(project_dir, "_quarto.yml"))

  expect_error(render_report(shell_qmd), "output-dir: report/shell")
})

test_that("errors when no reportifyr *_init.json marker is found", {
  project_dir <- withr::local_tempdir()
  shell_qmd <- file.path(project_dir, "report.qmd")
  writeLines("# shell", shell_qmd)
  writeLines(c("project:", "  output-dir: report/shell"), file.path(project_dir, "_quarto.yml"))

  expect_error(render_report(shell_qmd), "initialize_report_project")
})

test_that("errors when reference_doc doesn't exist", {
  fixture <- .render_report_fixture()

  expect_error(
    render_report(fixture$shell_qmd, reference_doc = file.path(fixture$project_dir, "missing.docx")),
    "reference-doc not found"
  )
})

# --- reference_doc = NULL resolution (#30) -----------------------------------
# render_report() must not silently override an already-configured Quarto
# reference-doc with its own package default, and must fall back to the
# package default (with a notice) only when nothing is configured at all.

test_that("reference_doc = NULL falls back to the package default and emits a notice when nothing is configured", {
  fixture <- .render_report_fixture()
  local_mocked_bindings(
    quarto_inspect = function(...) list(formats = list(docx = list(pandoc = list()))),
    .package = "quarto"
  )
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) invisible(docx)
  )
  record <- new.env()
  local_mocked_bindings(run = .mock_quarto_run(record), .package = "processx")
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(...) invisible(NULL),
    .package = "reportifyr"
  )

  expect_message(
    render_report(
      fixture$shell_qmd,
      standard_footnotes_yaml = fixture$standard_footnotes_yaml,
      config_yaml = fixture$config_yaml
    ),
    "package default reference-doc"
  )

  used <- record$quarto_run$args[which(record$quarto_run$args == "--reference-doc") + 1]
  expect_identical(normalizePath(used), normalizePath(
    system.file("templates", "org-reference.docx", package = "quartifyr")
  ))
})

test_that("reference_doc = NULL leaves an already-configured Quarto reference-doc alone", {
  fixture <- .render_report_fixture()
  local_mocked_bindings(
    quarto_inspect = function(...) {
      list(formats = list(docx = list(pandoc = list(`reference-doc` = "already-configured.docx"))))
    },
    .package = "quarto"
  )
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) invisible(docx)
  )
  record <- new.env()
  local_mocked_bindings(run = .mock_quarto_run(record), .package = "processx")
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(...) invisible(NULL),
    .package = "reportifyr"
  )

  expect_no_message(
    render_report(
      fixture$shell_qmd,
      standard_footnotes_yaml = fixture$standard_footnotes_yaml,
      config_yaml = fixture$config_yaml
    ),
    message = "package default reference-doc"
  )

  expect_false("--reference-doc" %in% record$quarto_run$args)
})

test_that("an explicit reference_doc always wins over a configured Quarto reference-doc", {
  fixture <- .render_report_fixture()
  local_mocked_bindings(
    quarto_inspect = function(...) {
      stop("quarto_inspect() should not be consulted when reference_doc is given explicitly")
    },
    .package = "quarto"
  )
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) invisible(docx)
  )
  record <- new.env()
  local_mocked_bindings(run = .mock_quarto_run(record), .package = "processx")
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(...) invisible(NULL),
    .package = "reportifyr"
  )

  render_report(
    fixture$shell_qmd,
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml
  )

  used <- record$quarto_run$args[which(record$quarto_run$args == "--reference-doc") + 1]
  expect_identical(normalizePath(used), normalizePath(fixture$reference_doc))
})

test_that("errors when standard_footnotes_yaml doesn't exist", {
  fixture <- .render_report_fixture()

  expect_error(
    render_report(
      fixture$shell_qmd,
      reference_doc = fixture$reference_doc,
      standard_footnotes_yaml = file.path(fixture$project_dir, "missing.yaml")
    ),
    "standard_footnotes_yaml not found"
  )
})

test_that("surfaces a quarto render failure instead of continuing", {
  fixture <- .render_report_fixture()
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(styling_build_abbreviations_tex = function(...) invisible(NULL))
  local_mocked_bindings(
    run = function(command, args, wd = ".", error_on_status = TRUE, ...) {
      list(status = 1, stdout = "", stderr = "boom")
    },
    .package = "processx"
  )

  expect_error(
    render_report(
      fixture$shell_qmd,
      reference_doc = fixture$reference_doc,
      standard_footnotes_yaml = fixture$standard_footnotes_yaml,
      config_yaml = fixture$config_yaml
    ),
    "quarto render failed"
  )
})

# --- Full orchestration (happy path) ----------------------------------------

test_that("orchestrates quarto render -> apply-layout -> build_report() for status = 'draft'", {
  fixture <- .render_report_fixture()
  record <- new.env()

  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(footnotes, out) {
      assign("abbrevs", list(footnotes = footnotes, out = out), envir = record)
      invisible(out)
    },
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) {
      assign("apply_layout", list(docx = docx, qmd = qmd, status = status, style = style, override = override), envir = record)
      invisible(docx)
    }
  )
  local_mocked_bindings(run = .mock_quarto_run(record), .package = "processx")
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(docx_in, docx_out, figures_path, tables_path,
                             standard_footnotes_yaml, config_yaml, ...) {
      assign(
        "build_report",
        list(
          docx_in = docx_in, docx_out = docx_out, figures_path = figures_path,
          tables_path = tables_path, standard_footnotes_yaml = standard_footnotes_yaml,
          config_yaml = config_yaml
        ),
        envir = record
      )
      invisible(NULL)
    },
    finalize_document = function(...) stop("finalize_document() must not run for status = 'draft'"),
    .package = "reportifyr"
  )

  result <- render_report(
    fixture$shell_qmd,
    status = "draft",
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml
  )

  expect_identical(record$abbrevs$footnotes, fixture$standard_footnotes_yaml)
  expect_identical(record$quarto_run$command, "quarto")
  expect_true("document-status:DRAFT" %in% record$quarto_run$args)
  expect_true(normalizePath(fixture$reference_doc) == normalizePath(
    record$quarto_run$args[which(record$quarto_run$args == "--reference-doc") + 1]
  ))

  expect_identical(record$apply_layout$status, "draft")
  expect_true(.is_staged(record$apply_layout$docx))
  expect_identical(basename(record$apply_layout$docx), basename(result$shell))
  expect_identical(
    normalizePath(result$shell),
    normalizePath(.live_path(fixture, "shell", "report.docx"))
  )

  # Mirror render_report()'s own expression exactly (dirname() of the
  # *normalized* shell_qmd) rather than normalizing project_dir
  # independently -- on Windows the two don't produce identical slash
  # styles (confirmed via a real CI run: normalizePath(shell_qmd) then
  # dirname() yields forward slashes throughout, while normalizing
  # project_dir on its own doesn't), so only the identical call sequence
  # is guaranteed to match.
  expected_dir <- dirname(normalizePath(fixture$shell_qmd, mustWork = TRUE))
  expect_identical(record$build_report$figures_path, file.path(expected_dir, "OUTPUTS", "figures"))
  expect_identical(record$build_report$tables_path, file.path(expected_dir, "OUTPUTS", "tables"))
  expect_identical(record$build_report$standard_footnotes_yaml, fixture$standard_footnotes_yaml)
  expect_identical(record$build_report$config_yaml, fixture$config_yaml)

  expect_true(.is_staged(record$build_report$docx_out))
  expect_identical(basename(result$draft), basename(record$build_report$docx_out))
  expect_identical(
    normalizePath(dirname(result$draft)),
    normalizePath(file.path(fixture$project_dir, "report", "draft"))
  )
  expect_null(result$final)
})

test_that("also runs finalize_document() and returns a final path for status = 'final'", {
  fixture <- .render_report_fixture()
  record <- new.env()

  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) invisible(docx)
  )
  local_mocked_bindings(run = .mock_quarto_run(record), .package = "processx")
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(...) invisible(NULL),
    finalize_document = function(docx_in, docx_out, config_yaml = NULL) {
      assign("finalize", list(docx_in = docx_in, docx_out = docx_out, config_yaml = config_yaml), envir = record)
      invisible(NULL)
    },
    .package = "reportifyr"
  )

  result <- render_report(
    fixture$shell_qmd,
    status = "final",
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml
  )

  expect_true("document-status:FINAL" %in% record$quarto_run$args)
  expect_true(.is_staged(record$finalize$docx_out))
  expect_identical(basename(result$final), basename(record$finalize$docx_out))
  expect_identical(basename(record$finalize$docx_in), basename(result$draft))
  expect_identical(
    normalizePath(dirname(result$final)),
    normalizePath(file.path(fixture$project_dir, "report", "final"))
  )
})

# --- Opt-in post-processing steps --------------------------------------------

.base_render_report_mocks <- function(record) {
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL), .env = parent.frame())
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_fit_tables = function(docx) invisible(list(path = docx, fitted = 0L, shrunk = list(), overflowing = list())),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) invisible(docx),
    .env = parent.frame()
  )
  local_mocked_bindings(run = .mock_quarto_run(record), .package = "processx", .env = parent.frame())
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(...) invisible(NULL),
    .package = "reportifyr",
    .env = parent.frame()
  )
}

# LibreOffice itself isn't needed by these tests (the steps are mocked), but
# render_report() checks the executable exists before rendering.
.mock_soffice_present <- function(.env = parent.frame()) {
  local_mocked_bindings(.resolve_soffice = function(command) command, .env = .env)
}

test_that("recalculate_fields = TRUE runs styling_recalculate_fields() on each produced docx", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)
  .mock_soffice_present()

  recalculated <- character(0)
  local_mocked_bindings(
    styling_recalculate_fields = function(docx, timeout = 120, soffice_bin = NULL) {
      recalculated <<- c(recalculated, docx)
      invisible(docx)
    }
  )

  result <- render_report(
    fixture$shell_qmd,
    status = "draft",
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml,
    recalculate_fields = TRUE
  )

  # The step ran on the staged file, before the render was accepted.
  expect_true(all(.is_staged(recalculated)))
  expect_identical(basename(recalculated), basename(result$draft))
})

test_that("recalculate_fields = FALSE (the default) never calls styling_recalculate_fields()", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)

  local_mocked_bindings(
    styling_recalculate_fields = function(...) stop("styling_recalculate_fields() should not run by default")
  )

  expect_no_error(render_report(
    fixture$shell_qmd,
    status = "draft",
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml
  ))
})

test_that("a failing styling_recalculate_fields() only warns, and the render still succeeds", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)
  .mock_soffice_present()

  local_mocked_bindings(
    styling_recalculate_fields = function(docx, timeout = 120, soffice_bin = NULL) stop("boom")
  )

  result <- NULL
  expect_warning(
    result <- render_report(
      fixture$shell_qmd,
      status = "draft",
      reference_doc = fixture$reference_doc,
      standard_footnotes_yaml = fixture$standard_footnotes_yaml,
      config_yaml = fixture$config_yaml,
      recalculate_fields = TRUE
    ),
    "styling_recalculate_fields\\(\\) failed"
  )
  expect_false(is.null(result$draft))
})

test_that("resolve_same_page_crossrefs = TRUE runs styling_resolve_same_page_crossrefs() on each produced docx", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)
  .mock_soffice_present()

  resolved <- character(0)
  local_mocked_bindings(
    styling_resolve_same_page_crossrefs = function(docx, timeout = 120, soffice_bin = NULL) {
      resolved <<- c(resolved, docx)
      invisible(docx)
    }
  )

  result <- render_report(
    fixture$shell_qmd,
    status = "draft",
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml,
    resolve_same_page_crossrefs = TRUE
  )

  expect_true(all(.is_staged(resolved)))
  expect_identical(basename(resolved), basename(result$draft))
})

test_that("a failing styling_resolve_same_page_crossrefs() only warns, and the render still succeeds", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)
  .mock_soffice_present()

  local_mocked_bindings(
    styling_resolve_same_page_crossrefs = function(docx, timeout = 120, soffice_bin = NULL) stop("boom")
  )

  result <- NULL
  expect_warning(
    result <- render_report(
      fixture$shell_qmd,
      status = "draft",
      reference_doc = fixture$reference_doc,
      standard_footnotes_yaml = fixture$standard_footnotes_yaml,
      config_yaml = fixture$config_yaml,
      resolve_same_page_crossrefs = TRUE
    ),
    "styling_resolve_same_page_crossrefs\\(\\) failed"
  )
  expect_false(is.null(result$draft))
})

# --- quarto_timeout / quarto_bin / process-tree cleanup ---------------------

test_that("rejects an invalid quarto_timeout before doing any work", {
  fixture <- .render_report_fixture()
  expect_error(render_report(fixture$shell_qmd, quarto_timeout = -1), "quarto_timeout")
  expect_error(render_report(fixture$shell_qmd, quarto_timeout = "soon"), "quarto_timeout")
})

test_that("passes quarto_timeout and cleanup_tree through to processx::run()", {
  fixture <- .render_report_fixture()
  seen <- new.env()
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) invisible(docx)
  )
  local_mocked_bindings(
    run = function(command, args, wd = ".", error_on_status = TRUE, timeout = NULL, cleanup_tree = NULL, ...) {
      if (!identical(args[[1]], "render")) {
        return(list(status = 0, stdout = "1.9.9\n", stderr = ""))
      }
      assign("timeout", timeout, envir = seen)
      assign("cleanup_tree", cleanup_tree, envir = seen)
      output_name <- args[which(args == "--output") + 1]
      dir.create(file.path(wd, "report", "shell"), recursive = TRUE, showWarnings = FALSE)
      file.create(file.path(wd, "report", "shell", output_name))
      list(status = 0, stdout = "", stderr = "")
    },
    .package = "processx"
  )
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(...) invisible(NULL),
    .package = "reportifyr"
  )

  render_report(
    fixture$shell_qmd,
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml,
    quarto_timeout = 42
  )

  expect_identical(seen$timeout, 42)
  expect_true(seen$cleanup_tree)
})

test_that("quarto_bin overrides the command and QUARTO_PATH is honoured as a fallback", {
  fixture <- .render_report_fixture()
  record <- new.env()
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) invisible(docx)
  )
  local_mocked_bindings(run = .mock_quarto_run(record), .package = "processx")
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(...) invisible(NULL),
    .package = "reportifyr"
  )
  args <- list(
    fixture$shell_qmd,
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml
  )

  do.call(render_report, c(args, list(quarto_bin = "/opt/app/quarto")))
  expect_identical(record$quarto_run$command, "/opt/app/quarto")

  withr::local_envvar(QUARTO_PATH = "/env/quarto")
  do.call(render_report, args)
  expect_identical(record$quarto_run$command, "/env/quarto")
})

# A stub `quarto` that hangs, with a long-lived child of its own: the real
# processx::run() is exercised (nothing mocked for the render step) so the
# timeout and cleanup_tree behaviour are verified for real, not assumed.
test_that("a hung quarto is killed on timeout with a classed error and leaves no children behind", {
  # Not run on Windows: the stub quarto and the leak probe are POSIX (`sh`,
  # `sleep`, `pgrep`), and processx's cleanup_tree uses a different mechanism
  # there (job objects) that this test could not exercise anyway. A Windows
  # variant would need its own stub and probe, and can only be validated on a
  # Windows runner.
  skip_on_os("windows")
  skip_if_not_installed("ps")
  fixture <- .render_report_fixture()
  marker <- paste0("quartifyr-timeout-", Sys.getpid(), "-", as.integer(runif(1) * 1e6))
  stub_dir <- withr::local_tempdir()
  stub <- file.path(stub_dir, "quarto")
  writeLines(
    c(
      "#!/bin/sh",
      "echo 'rendering something slow' >&2",
      # `; true` keeps this sh alive (rather than exec'ing sleep) so its own
      # command line, which carries the marker, stays findable by pgrep -f.
      sprintf("sh -c 'sleep 300; true' %s &", marker),
      "sleep 300"
    ),
    stub
  )
  Sys.chmod(stub, "0755")
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(styling_build_abbreviations_tex = function(...) invisible(NULL))

  err <- tryCatch(
    suppressWarnings(render_report(
      fixture$shell_qmd,
      reference_doc = fixture$reference_doc,
      standard_footnotes_yaml = fixture$standard_footnotes_yaml,
      config_yaml = fixture$config_yaml,
      quarto_timeout = 1,
      quarto_bin = stub
    )),
    error = function(e) e
  )

  expect_s3_class(err, "quartifyr_quarto_timeout")
  expect_match(conditionMessage(err), "timed out after 1 seconds")
  expect_match(conditionMessage(err), "rendering something slow")

  # pgrep is run through processx, not system2(): system2() wraps the call in
  # `sh -c "pgrep -f <marker>"`, whose own command line contains the marker,
  # so on Linux pgrep matches that shell and always reports one "survivor".
  # cleanup_tree is best-effort-asynchronous at the OS level; give the kernel
  # a moment to reap before declaring a leak.
  survivors <- function() {
    out <- processx::run("pgrep", c("-f", marker), error_on_status = FALSE)$stdout
    length(Filter(nzchar, strsplit(out, "\n", fixed = TRUE)[[1]]))
  }
  for (i in 1:20) {
    if (survivors() == 0) break
    Sys.sleep(0.25)
  }
  expect_identical(survivors(), 0L)
})

# The leak check above is only meaningful if its probe can see a live child,
# so prove that directly: a process carrying the marker is found, and is gone
# once it exits.
test_that("the leak probe used for the timeout test can see a live child", {
  skip_on_os("windows")
  marker <- paste0("quartifyr-probe-", Sys.getpid(), "-", as.integer(runif(1) * 1e6))
  child <- processx::process$new("sh", c("-c", "sleep 30; true", marker))
  on.exit(child$kill(), add = TRUE)
  Sys.sleep(0.3)

  found <- processx::run("pgrep", c("-f", marker), error_on_status = FALSE)$stdout
  expect_match(found, "^[0-9]+")

  child$kill()
  child$wait()
  Sys.sleep(0.3)
  gone <- processx::run("pgrep", c("-f", marker), error_on_status = FALSE)$stdout
  expect_identical(trimws(gone), "")
})

# --- Structured result, strict mode (job contract) --------------------------

# Everything external mocked as in the orchestration tests above; `build`
# lets a test shape what pass 2 leaves behind (write the draft docx, append
# to a reportifyr log, ...) and `unfilled` stands in for the docx scan.
.run_render <- function(fixture, status = "draft", build = function(doc_dirs) NULL,
                        unfilled = character(0), .mock_env = parent.frame(), .python_env = NULL, ...) {
  if (!is.null(.python_env)) {
    withr::local_options(quartifyr.python_env = .python_env, .local_envir = .mock_env)
  }
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL), .env = .mock_env)
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) invisible(docx),
    .scan_unfilled_placeholders = function(docx) unfilled,
    .env = .mock_env
  )
  record <- new.env()
  local_mocked_bindings(run = .mock_quarto_run(record), .package = "processx", .env = .mock_env)
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(docx_in, docx_out, ...) {
      dir.create(dirname(docx_out), recursive = TRUE, showWarnings = FALSE)
      writeLines("draft", docx_out)
      build(list(doc_in = docx_in, doc_draft = docx_out))
      invisible(NULL)
    },
    finalize_document = function(docx_in, docx_out, ...) {
      dir.create(dirname(docx_out), recursive = TRUE, showWarnings = FALSE)
      writeLines("final", docx_out)
      invisible(NULL)
    },
    .package = "reportifyr",
    .env = .mock_env
  )
  render_report(
    fixture$shell_qmd,
    status = status,
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml,
    ...
  )
}

test_that("a clean render returns status ok, artifact hashes and stays backward-compatible", {
  fixture <- .render_report_fixture()
  result <- .run_render(fixture, status = "final")

  expect_s3_class(result, "quartifyr_render_result")
  expect_identical(result$status, "ok")
  expect_identical(result$unfilled_placeholders, character(0))
  expect_identical(result$missing_metadata, character(0))
  expect_true(file.exists(result$shell))
  expect_true(file.exists(result$draft))
  expect_true(file.exists(result$final))

  expect_identical(result$artifacts$role, c("shell", "draft", "final"))
  expect_true(all(grepl("^[0-9a-f]{64}$", result$artifacts$sha256)))
  expect_identical(
    result$artifacts$sha256[result$artifacts$role == "draft"],
    .sha256_file(result$draft)
  )
  expect_identical(result$log_dir, file.path(dirname(normalizePath(fixture$shell_qmd)), ".rpfy-logs"))
})

test_that("unfilled placeholders make the status error and are listed", {
  fixture <- .render_report_fixture()
  result <- .run_render(fixture, unfilled = "{rpfy}:missing.png")

  expect_identical(result$status, "error")
  expect_identical(result$unfilled_placeholders, "{rpfy}:missing.png")
})

test_that("strict = TRUE signals quartifyr_render_incomplete, carrying the result", {
  fixture <- .render_report_fixture()

  err <- tryCatch(.run_render(fixture, unfilled = "{rpfy}:missing.png", strict = TRUE), error = function(e) e)

  expect_s3_class(err, "quartifyr_render_incomplete")
  expect_match(conditionMessage(err), "missing.png")
  expect_identical(err$result$status, "error")
  expect_identical(err$result$unfilled_placeholders, "{rpfy}:missing.png")
})

test_that("strict = TRUE on a clean render returns normally", {
  fixture <- .render_report_fixture()
  expect_identical(.run_render(fixture, strict = TRUE)$status, "ok")
})

test_that("a present figure with no metadata sidecar is listed in missing_metadata", {
  fixture <- .render_report_fixture()
  writeLines(c("# shell", "", "{rpfy}:fig.png", "", "text"), fixture$shell_qmd)
  figs <- file.path(fixture$project_dir, "OUTPUTS", "figures")
  dir.create(figs, recursive = TRUE)
  file.create(file.path(figs, "fig.png"))

  result <- .run_render(fixture)
  expect_identical(result$missing_metadata, "fig.png")
  expect_identical(result$status, "warning")

  expect_error(.run_render(fixture, strict = TRUE), class = "quartifyr_render_incomplete")

  writeLines("{}", file.path(figs, "fig_png_metadata.json"))
  expect_identical(.run_render(fixture)$status, "ok")
})

test_that("only this run's reportifyr log lines count toward missing_metadata", {
  fixture <- .render_report_fixture()
  log_dir <- file.path(fixture$project_dir, ".rpfy-logs")
  dir.create(log_dir)
  log_file <- file.path(log_dir, "2026-01-01-00-00-00-rpfy.log")
  writeLines("2026-01-01 00:00:00 [py] [WARNING] Metadata file not found for: stale-from-last-run", log_file)

  result <- .run_render(fixture, build = function(doc_dirs) {
    cat(
      "2026-01-01 00:00:05 [py] [WARNING] Figure file not found: /p/OUTPUTS/figures/gone.png\n",
      "2026-01-01 00:00:05 [py] [WARNING] Metadata file not found for: no-sidecar.png\n",
      file = log_file, append = TRUE, sep = ""
    )
  })

  expect_identical(result$missing_metadata, "no-sidecar.png")
  expect_match(result$warnings, "gone.png")
  expect_identical(result$status, "warning")
})

test_that("a failing LibreOffice step still warns, and makes the result not ok", {
  fixture <- .render_report_fixture()
  .mock_soffice_present()
  local_mocked_bindings(styling_recalculate_fields = function(...) stop("soffice hung"))

  expect_warning(
    result <- .run_render(fixture, recalculate_fields = TRUE),
    "styling_recalculate_fields\\(\\) failed"
  )
  expect_identical(result$status, "error")
  expect_match(result$errors, "soffice hung")

  expect_error(
    suppressWarnings(.run_render(fixture, recalculate_fields = TRUE, strict = TRUE)),
    class = "quartifyr_render_incomplete"
  )
})

test_that("a draft that pass 2 never wrote is reported as an error", {
  fixture <- .render_report_fixture()
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) invisible(docx)
  )
  record <- new.env()
  local_mocked_bindings(run = .mock_quarto_run(record), .package = "processx")
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(...) invisible(NULL),
    .package = "reportifyr"
  )

  result <- render_report(
    fixture$shell_qmd,
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml
  )

  expect_identical(result$status, "error")
  expect_match(result$errors, "was not produced")
  expect_identical(result$artifacts$role, "shell")
})

test_that("a pass-2 failure names the missing metadata sidecars and carries them on the condition", {
  fixture <- .render_report_fixture()
  writeLines(c("# shell", "", "{rpfy}:fig.png", "", "text"), fixture$shell_qmd)
  figs <- file.path(fixture$project_dir, "OUTPUTS", "figures")
  dir.create(figs, recursive = TRUE)
  file.create(file.path(figs, "fig.png"))

  err <- tryCatch(
    .run_render(fixture, build = function(doc_dirs) stop("Figure footnotes script failed.")),
    error = function(e) e
  )

  expect_s3_class(err, "quartifyr_pass2_failed")
  expect_identical(err$missing_metadata, "fig.png")
  expect_match(conditionMessage(err), "Figure footnotes script failed")
  expect_match(conditionMessage(err), "Missing metadata sidecar for: fig.png")
})

test_that("a pass-2 failure unrelated to sidecars passes through unchanged", {
  fixture <- .render_report_fixture()
  err <- tryCatch(
    .run_render(fixture, build = function(doc_dirs) stop("python exploded")),
    error = function(e) e
  )

  expect_false(inherits(err, "quartifyr_pass2_failed"))
  expect_match(conditionMessage(err), "python exploded")
})

test_that("rejects an invalid quarto_bin before doing any work", {
  fixture <- .render_report_fixture()
  expect_error(render_report(fixture$shell_qmd, quarto_bin = ""), "quarto_bin")
  expect_error(render_report(fixture$shell_qmd, quarto_bin = c("a", "b")), "quarto_bin")
  expect_error(render_report(fixture$shell_qmd, quarto_bin = 1), "quarto_bin")
})

# --- A failed render leaves no stale outputs ---------------------------------

# A first, successful render of `fixture` (shell, draft and final on disk).
.first_render <- function(fixture, env = parent.frame()) {
  result <- .run_render(fixture, status = "final", .mock_env = env)
  expect_true(all(file.exists(c(result$shell, result$draft, result$final))))
  result
}

# After a failed second render: nothing from the first one (or from the
# failed one) is left in the live folders, and the first one's files are kept
# under report/.previous/.
.expect_outputs_moved_aside <- function(fixture, first) {
  expect_false(file.exists(first$shell))
  expect_false(file.exists(first$draft))
  expect_false(file.exists(first$final))
  previous <- file.path(fixture$project_dir, "report", ".previous")
  expect_identical(readLines(file.path(previous, "draft", basename(first$draft))), "draft")
  expect_identical(readLines(file.path(previous, "final", basename(first$final))), "final")
  expect_true(file.exists(file.path(previous, "shell", basename(first$shell))))
}

.render_again <- function(fixture, ...) {
  render_report(
    fixture$shell_qmd,
    status = "final",
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml,
    ...
  )
}

test_that("a Quarto timeout on a second render leaves no draft or final from the first", {
  fixture <- .render_report_fixture()
  first <- .first_render(fixture)
  local_mocked_bindings(
    run = function(...) list(status = NA_integer_, timeout = TRUE, stdout = "", stderr = "slow"),
    .package = "processx"
  )

  expect_error(suppressWarnings(.render_again(fixture, quarto_timeout = 5)), class = "quartifyr_quarto_timeout")
  .expect_outputs_moved_aside(fixture, first)
})

test_that("a failing Quarto render on a second render leaves no draft or final from the first", {
  fixture <- .render_report_fixture()
  first <- .first_render(fixture)
  local_mocked_bindings(
    run = function(...) list(status = 1L, timeout = FALSE, stdout = "", stderr = "boom"),
    .package = "processx"
  )

  expect_error(suppressWarnings(.render_again(fixture)), "quarto render failed")
  .expect_outputs_moved_aside(fixture, first)
})

test_that("a pass-2 failure on a second render leaves no draft or final from the first", {
  fixture <- .render_report_fixture()
  first <- .first_render(fixture)
  local_mocked_bindings(build_report = function(...) stop("python exploded"), .package = "reportifyr")

  expect_error(.render_again(fixture), "python exploded")
  # Pass 1 had already written this render's own shell, but into staging.
  .expect_outputs_moved_aside(fixture, first)
  expect_true(file.exists(file.path(fixture$project_dir, "report", ".failed", "shell", "report.docx")))
})

test_that("a second successful render replaces the outputs and refreshes .previous/", {
  fixture <- .render_report_fixture()
  first <- .first_render(fixture)
  second <- .run_render(fixture, status = "final", build = function(doc_dirs) NULL)

  expect_identical(second$status, "ok")
  expect_true(all(file.exists(c(second$shell, second$draft, second$final))))
  expect_true(file.exists(file.path(fixture$project_dir, "report", ".previous", "final", basename(first$final))))
})

test_that("project check failures touch no existing output", {
  fixture <- .render_report_fixture()
  first <- .first_render(fixture)

  expect_error(
    render_report(fixture$shell_qmd, reference_doc = file.path(fixture$project_dir, "missing.docx")),
    "reference-doc not found"
  )
  expect_true(all(file.exists(c(first$shell, first$draft, first$final))))
  expect_false(dir.exists(file.path(fixture$project_dir, "report", ".previous")))
})

test_that("an output older than the render's start is reported as not produced, and not listed", {
  fixture <- .render_report_fixture()
  result <- .run_render(fixture, build = function(doc_dirs) {
    Sys.setFileTime(doc_dirs$doc_draft, Sys.time() - 3600)
  })

  expect_identical(result$status, "error")
  expect_match(result$errors, "Expected output was not produced")
  expect_identical(result$artifacts$role, "shell")
  expect_identical(basename(result$draft), "report-draft.docx")
})

test_that("a previous output that can't be moved aside stops the render", {
  skip_on_os("windows")
  fixture <- .render_report_fixture()
  first <- .first_render(fixture)
  # .previous/draft is a file, so nothing can be moved into it. The shell is
  # moved first (shell, draft, final), and must be put back.
  previous <- file.path(fixture$project_dir, "report", ".previous")
  unlink(previous, recursive = TRUE)
  dir.create(previous)
  file.create(file.path(previous, "draft"))
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))

  expect_error(
    suppressWarnings(.render_again(fixture)),
    "Could not move the previous output"
  )
  expect_true(all(file.exists(c(first$shell, first$draft, first$final))))
  expect_false(dir.exists(file.path(fixture$project_dir, "report", ".failed")))
})

test_that(".move_previous_outputs() moves only what exists and reports where it went", {
  project <- withr::local_tempdir()
  expect_identical(.move_previous_outputs(project, "report"), character(0))
  expect_false(dir.exists(file.path(project, "report", ".previous")))

  paths <- .render_output_paths(project, "report")
  for (p in c(paths$shell, paths$draft[c(1, 4)])) {
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    writeLines(basename(p), p)
  }
  moved <- .move_previous_outputs(project, "report")

  expect_setequal(basename(moved), c("report.docx", "report-clean.docx", "report-draft.docx"))
  expect_true(all(file.exists(moved)))
  expect_false(any(file.exists(c(paths$shell, paths$draft))))
  expect_true(all(grepl("[/\\\\]report[/\\\\]\\.previous[/\\\\](shell|draft)[/\\\\]", moved)))
})

test_that(".move_previous_outputs() replaces an older .previous copy", {
  project <- withr::local_tempdir()
  paths <- .render_output_paths(project, "report")
  dir.create(dirname(paths$final[[1]]), recursive = TRUE)
  writeLines("old", paths$final[[1]])
  .move_previous_outputs(project, "report")
  writeLines("new", paths$final[[1]])
  .move_previous_outputs(project, "report")

  kept <- file.path(project, "report", ".previous", "final", "report-final.docx")
  expect_identical(readLines(kept), "new")
})

test_that(".render_output_paths() agrees with reportifyr::make_doc_dirs()", {
  skip_if_not_installed("reportifyr")
  project <- withr::local_tempdir()
  paths <- .render_output_paths(project, "report")
  dir.create(dirname(paths$shell), recursive = TRUE)
  file.create(paths$shell)
  theirs <- withr::with_dir(project, reportifyr::make_doc_dirs(paths$shell))

  expect_setequal(
    # (the metadata sidecar next to the final docx is quartifyr's addition)
    normalizePath(c(paths$shell, paths$draft, paths$final[[1]]), mustWork = FALSE),
    normalizePath(unlist(theirs, use.names = FALSE), mustWork = FALSE)
  )
})

test_that(".produced_since() needs the file to exist and be recent", {
  path <- withr::local_tempfile()
  now <- Sys.time()
  expect_false(.produced_since(path, now))
  file.create(path)
  expect_true(.produced_since(path, now))
  Sys.setFileTime(path, now - 3600)
  expect_false(.produced_since(path, now))
})

# --- Provenance and path resolution ------------------------------------------

test_that("the result records inputs, tool versions and timestamps", {
  fixture <- .render_report_fixture()
  writeLines(c("# shell", "", "{rpfy}:fig.png", "", "text"), fixture$shell_qmd)
  figs <- file.path(fixture$project_dir, "OUTPUTS", "figures")
  dir.create(figs, recursive = TRUE)
  writeLines("png", file.path(figs, "fig.png"))
  writeLines("{}", file.path(figs, "fig_png_metadata.json"))

  result <- .run_render(fixture)

  expect_setequal(
    result$inputs$role,
    c("shell_qmd", "quarto_yml", "standard_footnotes", "config", "reference_doc", "figure", "sidecar")
  )
  expect_identical(
    result$inputs$sha256[result$inputs$role == "figure"],
    .sha256_file(file.path(figs, "fig.png"))
  )
  expect_identical(result$versions$quarto, "1.9.9")
  expect_identical(result$versions$quartifyr, as.character(utils::packageVersion("quartifyr")))
  expect_match(result$started_at, "^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$")
  expect_gte(result$finished_at, result$started_at)
})

test_that("a reference-doc configured in Quarto is recorded among the inputs", {
  fixture <- .render_report_fixture()
  file.copy(fixture$reference_doc, file.path(fixture$project_dir, "configured.docx"))
  local_mocked_bindings(
    quarto_inspect = function(...) list(formats = list(docx = list(pandoc = list(`reference-doc` = "configured.docx")))),
    .package = "quarto"
  )
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) invisible(docx)
  )
  local_mocked_bindings(run = .mock_quarto_run(new.env()), .package = "processx")
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(docx_in, docx_out, ...) {
      dir.create(dirname(docx_out), recursive = TRUE, showWarnings = FALSE)
      writeLines("draft", docx_out)
    },
    .package = "reportifyr"
  )

  result <- render_report(
    fixture$shell_qmd,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml
  )

  ref <- result$inputs$path[result$inputs$role == "reference_doc"]
  expect_identical(basename(ref), "configured.docx")
})

# A relative path from `from` to `path`, without needing an extra package.
fs_relative <- function(path, from) {
  path <- strsplit(normalizePath(path, winslash = "/"), "/", fixed = TRUE)[[1]]
  from <- strsplit(normalizePath(from, winslash = "/"), "/", fixed = TRUE)[[1]]
  common <- 0L
  while (common < min(length(path), length(from)) && path[common + 1L] == from[common + 1L]) {
    common <- common + 1L
  }
  paste(c(rep("..", length(from) - common), path[seq_len(length(path) - common) + common]), collapse = "/")
}

test_that("a relative shell path with a working directory outside the project resolves inside the project", {
  fixture <- .render_report_fixture()
  outside <- withr::local_tempdir()
  relative_shell <- fs_relative(fixture$shell_qmd, outside)
  expect_false(file.exists(file.path(outside, "report.qmd")))

  seen <- new.env()
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(yaml, out) {
      assign("footnotes_for_abbrevs", yaml, envir = seen)
      invisible(NULL)
    },
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) invisible(docx)
  )
  local_mocked_bindings(run = .mock_quarto_run(new.env()), .package = "processx")
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(docx_in, docx_out, figures_path, tables_path, standard_footnotes_yaml, config_yaml) {
      assign("paths", list(figures_path, tables_path, standard_footnotes_yaml, config_yaml), envir = seen)
      dir.create(dirname(docx_out), recursive = TRUE, showWarnings = FALSE)
      writeLines("draft", docx_out)
    },
    .package = "reportifyr"
  )

  withr::with_dir(outside, render_report(relative_shell, reference_doc = fixture$reference_doc))

  project <- normalizePath(fixture$project_dir)
  expect_true(all(startsWith(normalizePath(unlist(seen$paths), mustWork = FALSE), project)))
  expect_identical(
    normalizePath(seen$footnotes_for_abbrevs),
    normalizePath(fixture$standard_footnotes_yaml)
  )
})

# --- Offline-safe render -------------------------------------------------------

# Runs a mocked render and reports what the environment looked like at each
# external boundary (the places a real uv call would inherit it from).
.render_and_snapshot_env <- function(fixture, ...) {
  snapshot <- function() {
    c(
      Sys.getenv(c("UV_OFFLINE", "UV_NO_INDEX", "UV_PYTHON_DOWNLOADS", "UV_NO_SYNC"), unset = "<unset>"),
      option = as.character(getOption("quartifyr.offline", "<unset>"))
    )
  }
  seen <- new.env()
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) {
      assign("layout", snapshot(), envir = seen)
      invisible(docx)
    }
  )
  local_mocked_bindings(run = .mock_quarto_run(new.env()), .package = "processx")
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(docx_in, docx_out, ...) {
      assign("pass2", snapshot(), envir = seen)
      dir.create(dirname(docx_out), recursive = TRUE, showWarnings = FALSE)
      writeLines("draft", docx_out)
    },
    .package = "reportifyr"
  )
  render_report(
    fixture$shell_qmd,
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml,
    ...
  )
  as.list(seen)
}

.offline_env <- c(
  UV_OFFLINE = "1", UV_NO_INDEX = "1", UV_PYTHON_DOWNLOADS = "never", UV_NO_SYNC = "1", option = "TRUE"
)

test_that("offline = TRUE sets the uv variables for the whole render, reportifyr included, then restores them", {
  fixture <- .render_report_fixture()
  withr::local_envvar(UV_OFFLINE = NA, UV_NO_INDEX = NA, UV_PYTHON_DOWNLOADS = NA, UV_NO_SYNC = NA)
  withr::local_options(quartifyr.offline = NULL)

  seen <- .render_and_snapshot_env(fixture, offline = TRUE)

  expect_identical(seen$layout, .offline_env)
  expect_identical(seen$pass2, .offline_env)
  expect_identical(Sys.getenv("UV_NO_SYNC", "<unset>"), "<unset>")
  expect_null(getOption("quartifyr.offline"))
})

test_that("offline = NULL follows quartifyr.offline and UV_OFFLINE; offline = FALSE sets nothing", {
  fixture <- .render_report_fixture()
  withr::local_envvar(UV_OFFLINE = NA, UV_NO_INDEX = NA, UV_PYTHON_DOWNLOADS = NA, UV_NO_SYNC = NA)
  withr::local_options(quartifyr.offline = NULL)

  expect_identical(.render_and_snapshot_env(fixture)$pass2[["UV_NO_SYNC"]], "<unset>")

  withr::with_options(list(quartifyr.offline = TRUE), {
    expect_identical(.render_and_snapshot_env(fixture)$pass2, .offline_env)
  })
  withr::with_envvar(c(UV_OFFLINE = "1"), {
    expect_identical(.render_and_snapshot_env(fixture)$pass2[["UV_NO_SYNC"]], "1")
    expect_identical(.render_and_snapshot_env(fixture, offline = FALSE)$pass2[["UV_NO_SYNC"]], "<unset>")
  })
})

test_that("rejects an invalid offline argument before doing any work", {
  fixture <- .render_report_fixture()
  expect_error(render_report(fixture$shell_qmd, offline = "yes"), "offline must be")
  expect_error(render_report(fixture$shell_qmd, offline = NA), "offline must be")
  expect_error(render_report(fixture$shell_qmd, offline = c(TRUE, FALSE)), "offline must be")
})

test_that("offline, a pass-2 uv failure is a quartifyr_offline_failure naming pass 2", {
  fixture <- .render_report_fixture()
  err <- suppressMessages(tryCatch(
    .run_render(
      fixture, offline = TRUE,
      build = function(doc_dirs) stop("error: Failed to fetch: https://pypi.org/simple/lxml/")
    ),
    error = function(e) e
  ))

  expect_s3_class(err, "quartifyr_offline_failure")
  expect_match(conditionMessage(err), "fill the shell with reportifyr \\(pass 2\\)")
})

test_that("offline, an ordinary pass-2 failure is not relabelled", {
  fixture <- .render_report_fixture()
  err <- tryCatch(
    .run_render(fixture, offline = TRUE, build = function(doc_dirs) stop("python exploded")),
    error = function(e) e
  )

  expect_false(inherits(err, "quartifyr_offline_failure"))
  expect_match(conditionMessage(err), "python exploded")
})

# --- soffice_bin / QUARTIFYR_SOFFICE_BIN -------------------------------------

test_that("soffice_bin wins over QUARTIFYR_SOFFICE_BIN, which wins over PATH", {
  seen <- character(0)
  local_mocked_bindings(
    styling_recalculate_fields = function(docx, timeout = 120, soffice_bin = NULL) {
      seen <<- c(seen, soffice_bin)
      invisible(docx)
    },
    .resolve_soffice = function(command) command
  )

  withr::with_envvar(c(QUARTIFYR_SOFFICE_BIN = "/env/soffice"), {
    .run_render(.render_report_fixture(), recalculate_fields = TRUE, soffice_bin = "/arg/soffice")
    .run_render(.render_report_fixture(), recalculate_fields = TRUE)
  })
  withr::with_envvar(c(QUARTIFYR_SOFFICE_BIN = NA), {
    .run_render(.render_report_fixture(), recalculate_fields = TRUE)
  })

  expect_identical(seen, c("/arg/soffice", "/env/soffice", "soffice"))
})

test_that("both LibreOffice steps get the same executable", {
  seen <- list()
  local_mocked_bindings(
    styling_recalculate_fields = function(docx, timeout = 120, soffice_bin = NULL) {
      seen$recalculate <<- soffice_bin
      invisible(docx)
    },
    styling_resolve_same_page_crossrefs = function(docx, timeout = 120, soffice_bin = NULL) {
      seen$crossrefs <<- soffice_bin
      invisible(docx)
    },
    .resolve_soffice = function(command) command
  )
  .run_render(
    .render_report_fixture(),
    recalculate_fields = TRUE, resolve_same_page_crossrefs = TRUE, soffice_bin = "/opt/lo/soffice"
  )
  expect_identical(seen, list(crossrefs = "/opt/lo/soffice", recalculate = "/opt/lo/soffice"))
})

test_that("an unusable LibreOffice fails before the render starts and touches nothing", {
  fixture <- .render_report_fixture()
  live <- file.path(fixture$project_dir, "report", "draft", "report-draft.docx")
  dir.create(dirname(live), recursive = TRUE)
  writeLines("previous render", live)
  record <- new.env()
  .base_render_report_mocks(record)

  expect_error(
    render_report(
      fixture$shell_qmd,
      reference_doc = fixture$reference_doc,
      standard_footnotes_yaml = fixture$standard_footnotes_yaml,
      config_yaml = fixture$config_yaml,
      recalculate_fields = TRUE,
      soffice_bin = file.path(fixture$project_dir, "no", "such", "soffice")
    ),
    "LibreOffice executable not found"
  )
  expect_null(record$quarto_run)
  expect_true(file.exists(live))
  expect_false(dir.exists(file.path(fixture$project_dir, "report", ".previous")))
})

test_that("an unusable LibreOffice is ignored when no LibreOffice step is requested", {
  fixture <- .render_report_fixture()
  result <- .run_render(fixture, soffice_bin = "/no/such/soffice")
  expect_null(result$versions$libreoffice)
})

test_that("a malformed soffice_bin is rejected", {
  fixture <- .render_report_fixture()
  expect_error(render_report(fixture$shell_qmd, soffice_bin = ""), "soffice_bin")
  expect_error(render_report(fixture$shell_qmd, soffice_bin = c("a", "b")), "soffice_bin")
  expect_error(render_report(fixture$shell_qmd, soffice_bin = 1), "soffice_bin")
})

test_that("the render result records which LibreOffice ran", {
  local_mocked_bindings(
    styling_recalculate_fields = function(docx, timeout = 120, soffice_bin = NULL) invisible(docx),
    .resolve_soffice = function(command) if (startsWith(command, "/")) command else paste0("/resolved/", command),
    .soffice_info = function(command) list(path = .resolve_soffice(command), version = "LibreOffice 26.2.5.2 abc")
  )
  result <- .run_render(.render_report_fixture(), recalculate_fields = TRUE, soffice_bin = "soffice")
  expect_identical(result$versions$libreoffice$path, "/resolved/soffice")
  expect_identical(result$versions$libreoffice$version, "LibreOffice 26.2.5.2 abc")

  json <- jsonlite::fromJSON(as.character(.render_result_json(result)))
  expect_identical(json$versions$libreoffice$path, "/resolved/soffice")
})

test_that(".check_soffice() and .resolve_soffice() handle paths, bare names and non-executables", {
  dir <- withr::local_tempdir()
  script <- file.path(dir, "soffice")
  writeLines("#!/bin/sh", script)

  expect_s3_class(.check_soffice(file.path(dir, "missing")), "data.frame")
  expect_s3_class(.check_soffice("definitely-not-a-real-soffice"), "data.frame")
  expect_equal(.resolve_soffice("definitely-not-a-real-soffice"), "")

  skip_on_os("windows")
  Sys.chmod(script, "644")
  expect_s3_class(.check_soffice(script), "data.frame")
  Sys.chmod(script, "755")
  expect_null(.check_soffice(script))
  expect_identical(.resolve_soffice(script), script)
  expect_identical(.resolve_soffice(dir), "") # a directory isn't an executable
})

test_that(".soffice_info() reports the first line of `soffice --version`", {
  skip_on_os("windows")
  dir <- withr::local_tempdir()
  script <- file.path(dir, "soffice")
  writeLines(c("#!/bin/sh", "echo 'LibreOffice 26.2.5.2 deadbeef'", "echo second line"), script)
  Sys.chmod(script, "755")
  info <- .soffice_info(script)
  expect_identical(info$path, script)
  expect_identical(info$version, "LibreOffice 26.2.5.2 deadbeef")
  expect_null(.soffice_info(file.path(dir, "missing")))
})

# --- Stage and swap: only an accepted render reaches report/{draft,final} ----

.live_docx <- function(fixture) {
  list.files(
    file.path(fixture$project_dir, "report", c("shell", "draft", "final")),
    pattern = "\\.docx$", full.names = TRUE, recursive = TRUE
  )
}

test_that("a strict render with an unfilled placeholder leaves no docx in report/draft or report/final", {
  fixture <- .render_report_fixture()
  err <- tryCatch(
    .run_render(fixture, status = "final", strict = TRUE, unfilled = "gone.png"),
    error = function(e) e
  )

  expect_s3_class(err, "quartifyr_render_incomplete")
  expect_identical(.live_docx(fixture), character(0))

  # The rejected render is kept for diagnosis, and the error's result says where.
  failed <- file.path(fixture$project_dir, "report", ".failed")
  expect_true(file.exists(file.path(failed, "final", "report-final.docx")))
  expect_match(paste(readLines(file.path(failed, "FAILED")), collapse = "\n"), "strict")
  expect_identical(
    normalizePath(err$result$final),
    normalizePath(file.path(failed, "final", "report-final.docx"))
  )
  expect_true(all(file.exists(err$result$artifacts$path)))
})

test_that("a pass-2 failure after the draft was written leaves no draft in report/draft", {
  fixture <- .render_report_fixture()
  err <- tryCatch(
    .run_render(fixture, build = function(doc_dirs) stop("pass 2 died after writing the draft")),
    error = function(e) e
  )

  expect_match(conditionMessage(err), "pass 2 died")
  expect_identical(.live_docx(fixture), character(0))
  expect_false(file.exists(file.path(fixture$project_dir, "report", "draft", "report-draft.docx")))
  failed <- file.path(fixture$project_dir, "report", ".failed")
  expect_true(file.exists(file.path(failed, "draft", "report-draft.docx")))
  expect_match(paste(readLines(file.path(failed, "FAILED")), collapse = "\n"), "pass 2 died")
  expect_identical(list.files(file.path(fixture$project_dir, "report"), pattern = "^\\.staging-"), character(0))
})

test_that("success, then a failure after partial writes, then success keeps the first render in .previous", {
  fixture <- .render_report_fixture()
  gen <- function(label) function(doc_dirs) writeLines(label, doc_dirs$doc_draft)

  first <- .run_render(fixture, build = gen("gen1"))
  expect_identical(readLines(first$draft), "gen1")

  expect_error(
    .run_render(fixture, build = function(doc_dirs) {
      writeLines("partial", doc_dirs$doc_draft)
      stop("second render died")
    }),
    "second render died"
  )
  previous_draft <- file.path(fixture$project_dir, "report", ".previous", "draft", "report-draft.docx")
  expect_identical(readLines(previous_draft), "gen1")
  expect_identical(.live_docx(fixture), character(0))

  third <- .run_render(fixture, build = gen("gen3"))
  expect_identical(readLines(third$draft), "gen3")
  # The failed second render's partial output never displaced the first.
  expect_identical(readLines(previous_draft), "gen1")
})

test_that("a non-strict incomplete render is still delivered, with status error", {
  fixture <- .render_report_fixture()
  result <- .run_render(fixture, unfilled = "gone.png")

  expect_identical(result$status, "error")
  expect_true(file.exists(result$draft))
  expect_identical(
    normalizePath(dirname(result$draft)),
    normalizePath(file.path(fixture$project_dir, "report", "draft"))
  )
  expect_false(dir.exists(file.path(fixture$project_dir, "report", ".failed")))
})

test_that("the staging folder is gone after a successful render", {
  fixture <- .render_report_fixture()
  .run_render(fixture, status = "final")
  expect_identical(list.files(file.path(fixture$project_dir, "report"), pattern = "^\\.staging-"), character(0))
})

test_that("a staging folder left by a killed render is discarded by the next one", {
  fixture <- .render_report_fixture()
  stale <- file.path(fixture$project_dir, "report", ".staging-deadbeef0000", "final")
  dir.create(stale, recursive = TRUE)
  writeLines("from a killed render", file.path(stale, "report-final.docx"))

  result <- .run_render(fixture, status = "final")

  expect_false(dir.exists(dirname(stale)))
  expect_identical(readLines(result$final), "final")
})

test_that("a failed render's folder is replaced by the next failure, not accumulated", {
  fixture <- .render_report_fixture()
  fail_with <- function(msg) {
    try(.run_render(fixture, build = function(doc_dirs) stop(msg)), silent = TRUE)
  }
  fail_with("first failure")
  fail_with("second failure")
  failed <- file.path(fixture$project_dir, "report", ".failed")
  expect_match(paste(readLines(file.path(failed, "FAILED")), collapse = "\n"), "second failure")
  expect_false(grepl("first failure", paste(readLines(file.path(failed, "FAILED")), collapse = "\n")))
})

test_that("reportifyr's metadata sidecar is repointed from the staging folder to report/final", {
  fixture <- .render_report_fixture()
  # Build what finalize_document() leaves in a staged final/ folder.
  stage <- .new_stage(fixture$project_dir)
  staged_docx <- file.path(stage$final_dir, "report-final.docx")
  writeLines("final", staged_docx)
  staged_rel <- file.path("report", basename(stage$root), "final", "report-final.docx")
  writeLines(
    sprintf('{"object_meta": {"path": "%s", "hash": "abc"}}', staged_rel),
    file.path(stage$final_dir, "report-final_docx_metadata.json")
  )

  .promote_stage(fixture$project_dir, stage)

  meta <- readLines(file.path(fixture$project_dir, "report", "final", "report-final_docx_metadata.json"))
  expect_match(meta, "\"path\": \"report/final/report-final.docx\"", fixed = TRUE)
  expect_false(grepl(".staging-", meta, fixed = TRUE))
  expect_false(dir.exists(stage$root))
})

test_that(".promote_stage() undoes its moves when one of them fails", {
  project <- withr::local_tempdir()
  dir.create(file.path(project, "report"))
  stage <- .new_stage(project)
  writeLines("shell", file.path(stage$shell_dir, "report.docx"))
  writeLines("draft", file.path(stage$draft_dir, "report-draft.docx"))
  # report/draft is a file, so the draft can't be moved in after the shell was.
  file.create(file.path(project, "report", "draft"))

  expect_error(suppressWarnings(.promote_stage(project, stage)), "Could not move the staged output")
  expect_true(file.exists(file.path(stage$shell_dir, "report.docx")))
  expect_false(file.exists(file.path(project, "report", "shell", "report.docx")))
})

test_that(".with_stage() keeps the staged files under .failed when the run errors or is interrupted", {
  project <- withr::local_tempdir()
  dir.create(file.path(project, "report"))
  try(.with_stage(project, "report", function(stage, outcome) {
    writeLines("x", file.path(stage$draft_dir, "report-draft.docx"))
    stop("kaboom")
  }), silent = TRUE)
  failed <- file.path(project, "report", ".failed")
  expect_true(file.exists(file.path(failed, "draft", "report-draft.docx")))
  expect_match(paste(readLines(file.path(failed, "FAILED")), collapse = "\n"), "kaboom")

  value <- .with_stage(project, "report", function(stage, outcome) {
    outcome$accepted <- TRUE
    "fine"
  })
  expect_identical(value, "fine")
})

test_that("the render's quarto call points at the staging folder", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)
  render_report(
    fixture$shell_qmd,
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml
  )
  args <- record$quarto_run$args
  expect_match(args[which(args == "--output-dir") + 1], "^report/\\.staging-[0-9a-f]+/shell$")
})


# --- Relative reference_doc / style / override; inputs hashed up front -------

test_that("a relative reference_doc, style and override resolve against the caller's directory, not the project's", {
  fixture <- .render_report_fixture()
  outside <- withr::local_tempdir()
  for (name in c("ref.docx", "style.yaml", "override.yaml")) {
    file.create(file.path(outside, name))
  }
  seen <- new.env()
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
    styling_apply_layout = function(docx, qmd, status, style = NULL, override = NULL) {
      assign("layout", list(style = style, override = override), envir = seen)
      invisible(docx)
    }
  )
  local_mocked_bindings(run = .mock_quarto_run(seen), .package = "processx")
  local_mocked_bindings(
    make_doc_dirs = .mock_make_doc_dirs,
    build_report = function(docx_in, docx_out, ...) {
      dir.create(dirname(docx_out), recursive = TRUE, showWarnings = FALSE)
      writeLines("draft", docx_out)
    },
    .package = "reportifyr"
  )

  result <- withr::with_dir(outside, render_report(
    fixture$shell_qmd,
    reference_doc = "ref.docx", style = "style.yaml", override = "override.yaml",
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml
  ))

  args <- seen$quarto_run$args
  expect_identical(
    normalizePath(args[which(args == "--reference-doc") + 1]),
    normalizePath(file.path(outside, "ref.docx"))
  )
  expect_identical(normalizePath(seen$layout$style), normalizePath(file.path(outside, "style.yaml")))
  expect_identical(normalizePath(seen$layout$override), normalizePath(file.path(outside, "override.yaml")))

  # What was checked and hashed is what was used.
  expect_identical(
    normalizePath(result$inputs$path[result$inputs$role == "reference_doc"]),
    normalizePath(file.path(outside, "ref.docx"))
  )
  expect_identical(
    normalizePath(result$inputs$path[result$inputs$role == "style"]),
    normalizePath(file.path(outside, "style.yaml"))
  )
})

test_that("a relative reference_doc that only exists in the caller's directory is found", {
  fixture <- .render_report_fixture()
  outside <- withr::local_tempdir()
  file.create(file.path(outside, "ref.docx"))
  .mock_all <- function() {
    local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL), .env = parent.frame())
  }
  expect_error(
    withr::with_dir(outside, render_report(fixture$shell_qmd, reference_doc = "missing.docx")),
    "reference-doc not found: .*missing\\.docx"
  )
})

test_that("inputs are hashed before the render, so a file changed during it keeps its starting hash", {
  fixture <- .render_report_fixture()
  before <- .sha256_file(fixture$config_yaml)
  result <- .run_render(fixture, build = function(doc_dirs) writeLines("changed during the render", fixture$config_yaml))

  expect_false(identical(.sha256_file(fixture$config_yaml), before))
  expect_identical(result$inputs$sha256[result$inputs$role == "config"], before)
})

test_that("inputs list _quarto.yml, the style and override YAMLs and each Quarto extension", {
  fixture <- .render_report_fixture()
  style <- file.path(fixture$project_dir, "style.yaml")
  override <- file.path(fixture$project_dir, "override.yaml")
  writeLines("a: 1", style)
  writeLines("b: 2", override)
  ext <- file.path(fixture$project_dir, "_extensions", "acme", "thing")
  dir.create(ext, recursive = TRUE)
  writeLines("title: thing", file.path(ext, "_extension.yml"))
  writeLines("-- filter", file.path(ext, "filter.lua"))

  result <- .run_render(fixture, style = style, override = override)
  rows <- result$inputs[result$inputs$role %in% c("quarto_yml", "style", "override", "extension"), ]

  expect_setequal(rows$role, c("quarto_yml", "style", "override", "extension"))
  expect_identical(basename(rows$path[rows$role == "extension"]), "thing")
  expect_identical(rows$sha256[rows$role == "style"], .sha256_file(style))

  hash_before <- rows$sha256[rows$role == "extension"]
  writeLines("-- a different filter", file.path(ext, "filter.lua"))
  again <- .run_render(fixture, style = style, override = override)
  expect_false(identical(again$inputs$sha256[again$inputs$role == "extension"], hash_before))
  expect_true(.validate_render_json(.render_result_json(again)))
})

test_that(".extension_table() has one row per extension directory and none without any", {
  expect_identical(nrow(.extension_table(NULL)), 0L)
  empty <- withr::local_tempdir()
  expect_identical(nrow(.extension_table(empty)), 0L)

  dir.create(file.path(empty, "a", "one"), recursive = TRUE)
  dir.create(file.path(empty, "two"))
  writeLines("x", file.path(empty, "a", "one", "_extension.yml"))
  writeLines("y", file.path(empty, "two", "_extension.yaml"))
  table <- .extension_table(empty)
  expect_identical(sort(basename(table$path)), c("one", "two"))
  expect_true(all(grepl("^[0-9a-f]{64}$", table$sha256)))
})

# --- Offline: pass-2 uv failures through the real reportifyr/pyro chain -------

# A `uv` first on PATH that fails the way uv does with no index to reach: the
# error goes to stderr, nothing to stdout, non-zero exit.
.fake_failing_uv <- function(env = parent.frame()) {
  bin <- withr::local_tempdir(.local_envir = env)
  script <- file.path(bin, "uv")
  writeLines(c(
    "#!/bin/sh",
    "echo 'error: Failed to fetch: `https://pypi.org/simple/lxml/`' >&2",
    "exit 2"
  ), script)
  Sys.chmod(script, "755")
  withr::local_path(bin, action = "prefix", .local_envir = env)
  bin
}

# A mocked build_report() that runs one of reportifyr's real Python calls
# (the real wrapper over the real pyro::run_python_script, or the real
# validate_docx()) so the failure that comes back is the one a real offline
# render would see, with nothing stubbed between uv and the error.
.run_real_reportifyr_call <- function(fixture, which, ...) {
  dir.create(file.path(fixture$project_dir, ".venv"))
  withr::local_options(venv_dir = fixture$project_dir)
  withr::local_options(rpfy.no_log = TRUE)
  .run_render(
    fixture, offline = TRUE,
    build = function(doc_dirs) {
      ns <- asNamespace("reportifyr")
      if (which == "script") {
        get("run_python_script", ns)(c("run", "-m", "reportipyr.cli", "remove-footnotes"), "Remove footnotes script")
      } else {
        get("validate_docx", ns)(doc_dirs$doc_in, NULL)
      }
    },
    ...
  )
}

test_that("offline, a uv failure inside reportifyr's real python wrapper is a quartifyr_offline_failure", {
  skip_on_os("windows")
  skip_if_not_installed("reportifyr")
  fixture <- .render_report_fixture()
  .fake_failing_uv()
  err <- suppressMessages(tryCatch(.run_real_reportifyr_call(fixture, "script"), error = function(e) e))

  expect_s3_class(err, "quartifyr_offline_failure")
  expect_match(conditionMessage(err), "fill the shell with reportifyr \\(pass 2\\)")
  # The condition reportifyr/pyro raised only says "failed."; uv's own words
  # come from what pass 2 printed.
  expect_match(paste(format(err), conditionMessage(err), collapse = "\n"), "Failed to fetch")
})

test_that("offline, reportifyr's validate step (which discards uv's stderr) is still recognised, by asking uv", {
  skip_on_os("windows")
  skip_if_not_installed("reportifyr")
  fixture <- .render_report_fixture()
  .fake_failing_uv()
  err <- suppressMessages(tryCatch(.run_real_reportifyr_call(fixture, "validate"), error = function(e) e))

  expect_s3_class(err, "quartifyr_offline_failure")
  expect_match(paste(format(err), collapse = "\n"), "Failed to fetch")
})

test_that("offline, an unrelated failure with a healthy uv is left alone even after the probe", {
  skip_on_os("windows")
  skip_if_not_installed("reportifyr")
  fixture <- .render_report_fixture()
  bin <- withr::local_tempdir()
  writeLines(c("#!/bin/sh", "exit 0"), file.path(bin, "uv"))
  Sys.chmod(file.path(bin, "uv"), "755")
  withr::local_path(bin, action = "prefix")
  dir.create(file.path(fixture$project_dir, ".venv"))
  withr::local_options(venv_dir = fixture$project_dir)

  err <- tryCatch(
    .run_render(fixture, offline = TRUE, build = function(doc_dirs) stop("validate-docx failed -- check log file")),
    error = function(e) e
  )
  expect_false(inherits(err, "quartifyr_offline_failure"))
  expect_match(conditionMessage(err), "validate-docx failed")
})

test_that("online, a pass-2 uv-looking failure is never relabelled and pass 2 isn't wrapped", {
  fixture <- .render_report_fixture()
  err <- tryCatch(
    .run_render(fixture, offline = FALSE, build = function(doc_dirs) stop("error: Failed to fetch: https://pypi.org/")),
    error = function(e) e
  )
  expect_false(inherits(err, "quartifyr_offline_failure"))
})

test_that(".tee_stdout() collects what is printed and still passes the value through", {
  into <- new.env()
  into$lines <- character(0)
  out <- utils::capture.output(value <- .tee_stdout(function() { cat("one\ntwo\n"); 42 }, into))
  expect_identical(value, 42)
  expect_identical(into$lines, c("one", "two"))
  expect_identical(out, c("one", "two")) # still shown as it happened
  expect_identical(sink.number(), 0L)

  try(.tee_stdout(function() { cat("before\n"); stop("boom") }, into), silent = TRUE)
  expect_identical(sink.number(), 0L)
  expect_true("before" %in% into$lines)
})

test_that("offline, an interpreter that doesn't match the project's pin is reported in the result", {
  fixture <- .render_report_fixture()
  dir.create(file.path(fixture$project_dir, ".venv"))
  writeLines("version = 3.12.3", file.path(fixture$project_dir, ".venv", "pyvenv.cfg"))
  writeLines("3.12.16", file.path(fixture$project_dir, ".python-version"))
  withr::local_options(venv_dir = NULL, quartifyr.python_env = NULL)
  withr::local_envvar(QUARTIFYR_PYTHON_ENV = NA)

  result <- .run_render(fixture, offline = TRUE)
  expect_identical(result$status, "warning")
  expect_match(result$warnings, "runs Python 3.12.3, but the project pins 3.12.16")
  expect_true(.validate_render_json(.render_result_json(result)))

  # Online, uv would recreate the environment itself, so nothing is said.
  online <- .run_render(fixture, offline = FALSE)
  expect_identical(online$status, "ok")

  # And strict turns it into a failure.
  expect_error(.run_render(fixture, offline = TRUE, strict = TRUE), class = "quartifyr_render_incomplete")
})

# --- One Python environment for both passes (#85) ----------------------------

test_that("render_report() runs pass 2 against the python_env and creates nothing in the project", {
  .mock_python_env()
  fixture <- .render_report_fixture()
  venv <- .make_venv(withr::local_tempdir())
  withr::local_options(venv_dir = NULL)
  withr::local_envvar(UV_PROJECT_ENVIRONMENT = NA, UV_NO_SYNC = NA, QUARTIFYR_PYTHON_ENV = NA)
  seen <- new.env()

  .run_render(
    fixture,
    build = function(doc_dirs) {
      assign("venv_dir", getOption("venv_dir"), envir = seen)
      assign("uv", Sys.getenv(c("UV_PROJECT_ENVIRONMENT", "UV_NO_SYNC"), unset = "<unset>"), envir = seen)
    },
    .python_env = venv
  )

  expect_true(file.exists(file.path(seen$venv_dir, ".venv", "pyvenv.cfg")))
  expect_identical(unname(seen$uv[1:2]), c(venv, "1"))
  expect_false(any(file.exists(file.path(fixture$project_dir, c(".venv", "uv.lock", "pyproject.toml")))))
  expect_null(getOption("venv_dir"))
})

test_that("a python_env missing a module reportifyr needs fails before anything is rendered", {
  fixture <- .render_report_fixture()
  local_mocked_bindings(.verify_python_env = function(env, modules = NULL) {
    cli::cli_abort("missing pillow", class = "quartifyr_python_env_invalid", call = NULL)
  })
  record <- new.env()
  .base_render_report_mocks(record)
  withr::local_options(quartifyr.python_env = withr::local_tempdir())

  expect_error(
    render_report(
      fixture$shell_qmd,
      reference_doc = fixture$reference_doc,
      standard_footnotes_yaml = fixture$standard_footnotes_yaml,
      config_yaml = fixture$config_yaml
    ),
    class = "quartifyr_python_env_invalid"
  )
  expect_null(record$quarto_run)
})

# --- Failure and rollback branches of the stage/swap machinery ----------------

# Replaces .rename_file() with one that fails for moves whose destination
# matches `fail_to` (a regex) and otherwise really renames.
.fail_renames_to <- function(fail_to, env = parent.frame()) {
  local_mocked_bindings(
    .rename_file = function(from, to) if (grepl(fail_to, to)) FALSE else file.rename(from, to),
    .env = env
  )
}

test_that(".move_previous_outputs() puts everything back, replaced .previous copies included, when a move fails", {
  project <- withr::local_tempdir()
  paths <- .render_output_paths(project, "report")
  for (p in c(paths$shell, paths$final[[1]])) {
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    writeLines(paste("live", basename(p)), p)
  }
  # An older .previous shell, which moving the live one in replaces (and must restore).
  older <- file.path(project, "report", ".previous", "shell", "report.docx")
  dir.create(dirname(older), recursive = TRUE)
  writeLines("older previous", older)
  .fail_renames_to("[/\\\\]final[/\\\\]report-final\\.docx$")

  expect_error(.move_previous_outputs(project, "report"), "Could not move the previous output")

  expect_identical(readLines(paths$shell), "live report.docx")
  expect_identical(readLines(paths$final[[1]]), "live report-final.docx")
  expect_identical(readLines(older), "older previous")
  expect_identical(list.files(dirname(older), all.files = TRUE, no.. = TRUE), "report.docx") # no .replaced-* left
})

test_that(".move_previous_outputs() restores the replaced copy when the move into place itself fails", {
  project <- withr::local_tempdir()
  paths <- .render_output_paths(project, "report")
  dir.create(dirname(paths$shell), recursive = TRUE)
  writeLines("live", paths$shell)
  older <- file.path(project, "report", ".previous", "shell", "report.docx")
  dir.create(dirname(older), recursive = TRUE)
  writeLines("older previous", older)
  # The live file's move to .previous fails, after the old copy was set aside.
  local_mocked_bindings(.rename_file = function(from, to) {
    # Only the live file's move into .previous (not the set-aside of the old copy).
    if (!grepl("\\.previous", from) && grepl("[/\\\\]shell[/\\\\]report\\.docx$", from) &&
      grepl("\\.previous", to)) {
      return(FALSE)
    }
    file.rename(from, to)
  })

  expect_error(.move_previous_outputs(project, "report"), "Could not move the previous output")
  expect_identical(readLines(older), "older previous")
  expect_identical(readLines(paths$shell), "live")
})

test_that(".move_previous_outputs() stops, touching nothing, when the old .previous copy can't be set aside", {
  project <- withr::local_tempdir()
  paths <- .render_output_paths(project, "report")
  dir.create(dirname(paths$shell), recursive = TRUE)
  writeLines("live", paths$shell)
  older <- file.path(project, "report", ".previous", "shell", "report.docx")
  dir.create(dirname(older), recursive = TRUE)
  writeLines("older previous", older)
  .fail_renames_to("\\.replaced-")

  expect_error(.move_previous_outputs(project, "report"), "Could not move the previous output")
  expect_identical(readLines(paths$shell), "live")
  expect_identical(readLines(older), "older previous")
})

test_that(".retire_stage() has nothing to keep when the staging folder is already gone", {
  project <- withr::local_tempdir()
  dir.create(file.path(project, "report"))
  stage <- list(root = file.path(project, "report", ".staging-abc"))
  expect_null(.retire_stage(project, stage, "whatever", "report"))
  expect_false(dir.exists(file.path(project, "report", ".failed")))
})

test_that(".retire_stage() keeps the files where they are when they can't be renamed to .failed", {
  project <- withr::local_tempdir()
  dir.create(file.path(project, "report"))
  stage <- .new_stage(project)
  writeLines("partial", file.path(stage$draft_dir, "report-draft.docx"))
  .fail_renames_to("\\.failed$")

  kept <- .retire_stage(project, stage, "disk said no", "report")

  expect_identical(kept, stage$root)
  expect_true(file.exists(file.path(stage$root, "FAILED")))
  expect_true(file.exists(file.path(stage$draft_dir, "report-draft.docx")))
})

test_that(".promote_stage() merges into an existing intermediate_files folder instead of replacing it", {
  project <- withr::local_tempdir()
  live_intermediate <- file.path(project, "report", "draft", "intermediate_files")
  dir.create(live_intermediate, recursive = TRUE)
  writeLines("from an earlier render", file.path(live_intermediate, "report-clean.docx"))
  stage <- .new_stage(project)
  staged_intermediate <- file.path(stage$draft_dir, "intermediate_files")
  dir.create(staged_intermediate)
  writeLines("new", file.path(staged_intermediate, "report-tabs.docx"))
  writeLines("draft", file.path(stage$draft_dir, "report-draft.docx"))

  .promote_stage(project, stage)

  expect_setequal(list.files(live_intermediate), c("report-clean.docx", "report-tabs.docx"))
  expect_true(file.exists(file.path(project, "report", "draft", "report-draft.docx")))
})

test_that(".rebase_path() moves staged paths and leaves other paths and NULL alone", {
  stage <- list(root = "/p/report/.staging-abc")
  expect_null(.rebase_path(NULL, stage, "/p/report"))
  expect_identical(.rebase_path("/p/report/.staging-abc/draft/a.docx", stage, "/p/report"), "/p/report/draft/a.docx")
  expect_identical(.rebase_path("/elsewhere/a.docx", stage, "/p/report"), "/elsewhere/a.docx")
  expect_identical(.rebase_path("/p/report/.staging-abc/draft/a.docx", stage, NULL), "/p/report/.staging-abc/draft/a.docx")
})

test_that(".soffice_info() reports no version when `soffice --version` fails", {
  skip_on_os("windows")
  dir <- withr::local_tempdir()
  script <- file.path(dir, "soffice")
  writeLines(c("#!/bin/sh", "exit 3"), script)
  Sys.chmod(script, "755")
  info <- .soffice_info(script)
  expect_identical(info$path, script)
  expect_null(info$version)
})

# --- Intermediate files, extension hashes, soffice path -----------------------

test_that("a successful render's intermediate_files are moved aside by the next render, and not left live after a rejection", {
  fixture <- .render_report_fixture()
  keep_intermediate <- function(doc_dirs) {
    inter <- file.path(dirname(doc_dirs$doc_draft), "intermediate_files")
    dir.create(inter, showWarnings = FALSE)
    writeLines("near-complete", file.path(inter, "report-tabsfigs.docx"))
  }
  first <- .run_render(fixture, build = keep_intermediate)
  live <- file.path(fixture$project_dir, "report", "draft", "intermediate_files", "report-tabsfigs.docx")
  expect_identical(readLines(live), "near-complete")

  # A strict rejection of the next render: nothing from the first one is live.
  expect_error(.run_render(fixture, strict = TRUE, unfilled = "gone.png"), class = "quartifyr_render_incomplete")

  expect_false(file.exists(live))
  previous <- file.path(fixture$project_dir, "report", ".previous", "draft", "intermediate_files", "report-tabsfigs.docx")
  expect_identical(readLines(previous), "near-complete")
  expect_identical(
    list.files(file.path(fixture$project_dir, "report", "draft", "intermediate_files")),
    character(0)
  )
})

test_that(".render_output_paths() lists the intermediate files and .previous keeps them apart from the draft folder", {
  paths <- .render_output_paths("/p", "report")
  expect_setequal(
    basename(paths$intermediate),
    c("report-clean.docx", "report-tabs.docx", "report-tabsfigs.docx", "report-draft.docx")
  )
  expect_true(all(grepl("intermediate_files", paths$intermediate, fixed = TRUE)))
  expect_identical(.previous_subdir("intermediate"), file.path("draft", "intermediate_files"))
  expect_identical(.previous_subdir("shell"), "shell")
})

test_that("an extension's hash doesn't depend on the locale's sort order", {
  dir <- withr::local_tempdir()
  for (name in c("a", "B")) {
    dir.create(file.path(dir, name))
    writeLines("x", file.path(dir, name, "_extension.yml"))
  }
  writeLines("1", file.path(dir, "a", "z.lua"))
  writeLines("2", file.path(dir, "a", "B.lua"))
  table <- .extension_table(dir)
  # C-locale order: upper case before lower case, whatever LC_COLLATE says.
  expect_identical(basename(table$path), c("B", "a"))

  files <- c("B.lua", "_extension.yml", "z.lua")
  expected_lines <- paste(files, vapply(file.path(dir, "a", files), .sha256_file, character(1), USE.NAMES = FALSE), sep = "  ")
  expect_identical(
    # (list.files() reports forward slashes; the temporary directory may not.)
    table$sha256[basename(table$path) == "a"],
    paste(as.character(unclass(openssl::sha256(paste(expected_lines, collapse = "\n")))), collapse = "")
  )
})

test_that("the LibreOffice steps get an absolute path, even for a relative soffice_bin and a different cwd", {
  skip_on_os("windows")
  fixture <- .render_report_fixture()
  outside <- withr::local_tempdir()
  tools_dir <- file.path(outside, "tools")
  dir.create(tools_dir)
  writeLines(c("#!/bin/sh", "echo LibreOffice test"), file.path(tools_dir, "soffice"))
  Sys.chmod(file.path(tools_dir, "soffice"), "755")
  seen <- NULL
  local_mocked_bindings(
    styling_recalculate_fields = function(docx, timeout = 120, soffice_bin = NULL) {
      seen <<- soffice_bin
      invisible(docx)
    }
  )

  result <- withr::with_dir(outside, .run_render(fixture, recalculate_fields = TRUE, soffice_bin = "tools/soffice"))

  expect_identical(normalizePath(seen), normalizePath(file.path(tools_dir, "soffice")))
  expect_true(grepl("^(/|[A-Za-z]:)", seen))
  expect_identical(normalizePath(result$versions$libreoffice$path), normalizePath(seen))
})

test_that("a bare soffice name is resolved through PATH once, and that path is what runs and is recorded", {
  skip_on_os("windows")
  fixture <- .render_report_fixture()
  bin <- withr::local_tempdir()
  writeLines(c("#!/bin/sh", "echo LibreOffice on path"), file.path(bin, "soffice"))
  Sys.chmod(file.path(bin, "soffice"), "755")
  withr::local_path(bin, action = "prefix")
  withr::local_envvar(QUARTIFYR_SOFFICE_BIN = NA)
  seen <- NULL
  local_mocked_bindings(
    styling_resolve_same_page_crossrefs = function(docx, timeout = 120, soffice_bin = NULL) {
      seen <<- soffice_bin
      invisible(docx)
    }
  )
  result <- .run_render(fixture, resolve_same_page_crossrefs = TRUE)
  expect_identical(normalizePath(seen), normalizePath(file.path(bin, "soffice")))
  expect_identical(normalizePath(result$versions$libreoffice$path), normalizePath(seen))
})


# --- Table fitting --------------------------------------------------------------

test_that("fit_tables (the default) runs styling_fit_tables() on each produced docx, before the LibreOffice steps", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)
  .mock_soffice_present()

  calls <- character(0)
  local_mocked_bindings(
    styling_fit_tables = function(docx) {
      calls <<- c(calls, paste0("fit:", basename(docx)))
      invisible(list(path = docx, fitted = 1L, shrunk = list(), overflowing = list()))
    },
    styling_recalculate_fields = function(docx, timeout = 120, soffice_bin = NULL) {
      calls <<- c(calls, "recalculate")
      invisible(docx)
    }
  )

  result <- render_report(
    fixture$shell_qmd,
    status = "draft",
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml,
    recalculate_fields = TRUE
  )

  expect_identical(calls, c(paste0("fit:", basename(result$draft)), "recalculate"))
})

test_that("fit_tables = FALSE never calls styling_fit_tables()", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)
  local_mocked_bindings(styling_fit_tables = function(...) stop("styling_fit_tables() should not run"))

  expect_no_error(render_report(
    fixture$shell_qmd,
    status = "draft",
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml,
    fit_tables = FALSE
  ))
})

test_that("a failing styling_fit_tables() only warns, is recorded as an error, and the render still succeeds", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)
  local_mocked_bindings(styling_fit_tables = function(docx) stop("boom"))

  result <- NULL
  expect_warning(
    result <- render_report(
      fixture$shell_qmd,
      status = "draft",
      reference_doc = fixture$reference_doc,
      standard_footnotes_yaml = fixture$standard_footnotes_yaml,
      config_yaml = fixture$config_yaml
    ),
    "styling_fit_tables\\(\\) failed"
  )
  expect_false(is.null(result$draft))
  expect_identical(result$status, "error")
  expect_match(result$errors, "styling_fit_tables\\(\\) failed", all = FALSE)
})

test_that("a table still too wide at the minimum font size is a warning in the result", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)
  local_mocked_bindings(
    styling_fit_tables = function(docx) invisible(list(path = docx, fitted = 2L, shrunk = list(1L, 2L), overflowing = list(2L)))
  )

  result <- render_report(
    fixture$shell_qmd,
    status = "draft",
    reference_doc = fixture$reference_doc,
    standard_footnotes_yaml = fixture$standard_footnotes_yaml,
    config_yaml = fixture$config_yaml
  )

  expect_match(result$warnings, "Table\\(s\\) 2 .* too wide at the minimum font size", all = FALSE)
})
