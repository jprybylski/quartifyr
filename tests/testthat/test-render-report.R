# render_report() is the orchestration driver chaining quarto render ->
# styling_apply_layout() -> reportifyr::build_report()/finalize_document().
# These tests never invoke the real `quarto` CLI, Python venv, or reportifyr
# pass 2 -- every external boundary is mocked, so this file runs on any
# machine with just the R package dependencies installed (see test-wiring.R
# for the real end-to-end round-trip, which skips without the full
# toolchain).

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
.mock_quarto_run <- function(record_into) {
  function(command, args, wd = ".", error_on_status = TRUE, ...) {
    assign("quarto_run", list(command = command, args = args, wd = wd), envir = record_into)
    output_name <- args[which(args == "--output") + 1]
    dir.create(file.path(wd, "report", "shell"), recursive = TRUE, showWarnings = FALSE)
    file.create(file.path(wd, "report", "shell", output_name))
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
  expect_identical(normalizePath(record$apply_layout$docx), normalizePath(result$shell))

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

  expect_identical(result$draft, record$build_report$docx_out)
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
  expect_identical(result$final, record$finalize$docx_out)
  expect_identical(record$finalize$docx_in, result$draft)
})

# --- Opt-in post-processing steps --------------------------------------------

.base_render_report_mocks <- function(record) {
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL), .env = parent.frame())
  local_mocked_bindings(
    styling_build_abbreviations_tex = function(...) invisible(NULL),
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

test_that("recalculate_fields = TRUE runs styling_recalculate_fields() on each produced docx", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)

  recalculated <- character(0)
  local_mocked_bindings(
    styling_recalculate_fields = function(docx, timeout = 120) {
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

  expect_identical(recalculated, result$draft)
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

  local_mocked_bindings(
    styling_recalculate_fields = function(docx, timeout = 120) stop("boom")
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

  resolved <- character(0)
  local_mocked_bindings(
    styling_resolve_same_page_crossrefs = function(docx, timeout = 120) {
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

  expect_identical(resolved, result$draft)
})

test_that("a failing styling_resolve_same_page_crossrefs() only warns, and the render still succeeds", {
  fixture <- .render_report_fixture()
  record <- new.env()
  .base_render_report_mocks(record)

  local_mocked_bindings(
    styling_resolve_same_page_crossrefs = function(docx, timeout = 120) stop("boom")
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
