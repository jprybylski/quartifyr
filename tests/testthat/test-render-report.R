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
                        unfilled = character(0), .mock_env = parent.frame(), ...) {
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

# After a failed second render: nothing from the first one is left in the
# live folders, and its files are kept under report/.previous/.
.expect_outputs_moved_aside <- function(fixture, first, shell_rendered = FALSE) {
  expect_identical(file.exists(first$shell), shell_rendered)
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
  # Pass 1 had already written this render's own shell by then.
  .expect_outputs_moved_aside(fixture, first, shell_rendered = TRUE)
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
  blocker <- file.path(fixture$project_dir, "report", ".previous", "draft", basename(first$draft))
  dir.create(blocker, recursive = TRUE)
  file.create(file.path(blocker, "keep"))
  local_mocked_bindings(check_quarto_extensions = function(...) invisible(NULL))

  expect_error(
    suppressWarnings(.render_again(fixture)),
    "Could not move the previous output"
  )
  expect_true(file.exists(first$draft))
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
  dir.create(dirname(paths$final), recursive = TRUE)
  writeLines("old", paths$final)
  .move_previous_outputs(project, "report")
  writeLines("new", paths$final)
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
    normalizePath(c(paths$shell, paths$draft, paths$final), mustWork = FALSE),
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
