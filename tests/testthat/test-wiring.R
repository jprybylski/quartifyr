# Proves the R -> pyro -> bundled-Python bridge actually works, not just
# that the R function signatures exist. Skips (rather than fails) when the
# toolchain isn't present, matching this repo's established convention
# (CLAUDE.md: the R/Python integration tests "skip (exit 0) if
# Rscript/quarto aren't available") -- see also ../deckifyr's
# tests/testthat/test-wiring.R for the identical pattern.

skip_if_not_installed("pyro")

repo_root <- normalizePath(test_path("..", ".."))

# pyro::get_venv_uv_paths() looks for an already-provisioned .venv/ at the
# project root -- it does not create one itself. `uv pip install -e
# '.[dev]'` (see CONTRIBUTING.md/ci.yml) provisions it; this is the same
# .venv/ the tests/python suite uses, not a separate pyro-specific one.
skip_if_not(
  dir.exists(file.path(repo_root, ".venv")),
  "repo .venv/ not provisioned (run `uv pip install -e '.[dev]'` first)"
)

test_that("styling_build_abbreviations_tex() round-trips through the pyro bridge", {
  skip_if_not(nzchar(Sys.which("uv")), "uv not on PATH")

  footnotes <- file.path(repo_root, "examples", "memo-example", "report", "standard_footnotes.yaml")
  skip_if_not(file.exists(footnotes), "fixture standard_footnotes.yaml not found")

  out <- withr::local_tempfile(fileext = ".tex")
  withr::with_dir(repo_root, {
    result_path <- styling_build_abbreviations_tex(footnotes, out = out)
    expect_identical(normalizePath(result_path), normalizePath(out))
  })
  expect_true(file.exists(out))
})

test_that("styling_build_reference_docx() round-trips through the pyro bridge", {
  skip_if_not(nzchar(Sys.which("uv")), "uv not on PATH")

  style <- file.path(repo_root, "inst", "python", "styles", "default.yaml")
  skip_if_not(file.exists(style), "bundled default.yaml style not found")

  out <- withr::local_tempfile(fileext = ".docx")
  withr::with_dir(repo_root, {
    result_path <- styling_build_reference_docx(style, out = out)
    expect_identical(normalizePath(result_path), normalizePath(out))
  })
  expect_true(file.exists(out))
})

test_that(".run_quartifyr_styling_cli() surfaces the JSON error payload on failure", {
  skip_if_not(nzchar(Sys.which("uv")), "uv not on PATH")

  withr::with_dir(repo_root, {
    expect_error(
      styling_build_abbreviations_tex("/nonexistent-standard-footnotes.yaml"),
      "FileNotFoundError"
    )
  })
})

test_that("render_report() runs end to end against examples/demo-report", {
  skip_if_not_installed("reportifyr")
  skip_if_not(nzchar(Sys.which("uv")), "uv not on PATH")
  skip_if_not(nzchar(Sys.which("quarto")), "quarto not on PATH")

  demo_dir <- file.path(repo_root, "examples", "demo-report")
  shell_qmd <- file.path(demo_dir, "report.qmd")
  skip_if_not(file.exists(shell_qmd), "examples/demo-report/report.qmd not found")
  init_marker <- list.files(demo_dir, pattern = "^\\.[^.]*_init\\.json$", all.files = TRUE)
  skip_if_not(
    length(init_marker) > 0,
    "examples/demo-report not reportifyr-initialized -- run reportifyr::initialize_report_project() first"
  )

  # Idempotent: provisions the "quartifyr" pyro dependency group
  # (python-docx/pyyaml) in examples/demo-report's own project-local
  # environment, alongside its existing reportifyr/pyro one, if not
  # already present.
  initialize_quartifyr_project(demo_dir)

  result <- render_report(shell_qmd, status = "final")
  expect_true(file.exists(result$shell))
  expect_true(file.exists(result$draft))
  expect_true(file.exists(result$final))

  # reportifyr::build_report() (draft) intentionally leaves visible {rpfy}:
  # magic-string text in place -- finalize_document() (final) strips that,
  # but *not* the [hash:...]-suffixed image/table descr/tblDescription
  # attributes it uses for its own change-detection tracking, which persist
  # by design even in report/final/ (see ci.yml's action-smoke-test job for
  # the identical caveat/assertion against the composite action's own
  # output). So this must check only visible <w:t> text, not the raw XML.
  final_xml <- unzip(result$final, files = "word/document.xml", exdir = withr::local_tempdir())
  final_lines <- readLines(final_xml, warn = FALSE)
  visible_text <- regmatches(final_lines, gregexpr("<w:t[^>]*>[^<]*</w:t>", final_lines))
  visible_text <- paste(unlist(visible_text), collapse = "")
  expect_false(grepl("\\{rpfy\\}:", visible_text), info = "leftover {rpfy}: magic string in final docx visible text")
})
