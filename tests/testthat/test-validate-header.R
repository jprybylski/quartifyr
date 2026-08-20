.write_qmd <- function(frontmatter_lines, dir = withr::local_tempdir(.local_envir = parent.frame())) {
  path <- file.path(dir, "report.qmd")
  writeLines(c("---", frontmatter_lines, "---", "", "Body."), path)
  path
}

test_that(".read_qmd_frontmatter() parses the block between the first two `---` lines", {
  path <- .write_qmd(c('title: "Test"', "version: 1.0"))
  fm <- .read_qmd_frontmatter(path)
  expect_identical(fm$title, "Test")
  expect_identical(fm$version, 1)
})

test_that(".read_qmd_frontmatter() returns an empty list when there's no frontmatter block", {
  dir <- withr::local_tempdir()
  path <- file.path(dir, "report.qmd")
  writeLines(c("# Just a heading", "body text"), path)
  expect_identical(.read_qmd_frontmatter(path), list())
})

test_that("validate_header() reads project: without going through Quarto's reserved-key handling", {
  # See R/validate-header.R's file-header comment: `project:` is a
  # reserved Quarto config key that quarto::quarto_inspect() silently
  # drops from parsed metadata, even though examples/demo-report's own
  # header-format: references {project} and it resolves fine via
  # apply-layout's raw-YAML read. validate_header() must not flag this as
  # an unresolved placeholder.
  dir <- withr::local_tempdir()
  path <- .write_qmd(
    c(
      'title: "Test"', 'project: "ACME-001"', 'report_number: "RPT-1"',
      'header-format: "{project} - {report_number}"',
      "filters:", "  - quarto-plus", "  - quartifyr", "format: docx"
    ),
    dir = dir
  )
  writeLines(c("project:", "  output-dir: report/shell"), file.path(dir, "_quarto.yml"))

  res <- validate_header(path, quiet = TRUE)
  expect_false("header-format-placeholders" %in% res$problems$id)
})

test_that("validate_header() flags a header-format placeholder with no matching key", {
  dir <- withr::local_tempdir()
  path <- .write_qmd(
    c(
      'title: "Test"', 'header-format: "{project} - {oops}"',
      "filters:", "  - quarto-plus", "  - quartifyr", "format: docx"
    ),
    dir = dir
  )
  writeLines(c("project:", "  output-dir: report/shell"), file.path(dir, "_quarto.yml"))

  res <- validate_header(path, quiet = TRUE)
  expect_true("header-format-placeholders" %in% res$problems$id)
  msg <- res$problems$message[res$problems$id == "header-format-placeholders"]
  expect_match(msg, "\\{project\\}, \\{oops\\}")
})

test_that("validate_header() flags both title: and memo: set, and neither set", {
  dir <- withr::local_tempdir()

  both <- .write_qmd(c('title: "T"', "memo:", '  to: "X"', "filters:", "  - quartifyr", "format: docx"), dir = dir)
  res_both <- validate_header(both, quiet = TRUE)
  expect_true("title-memo-conflict" %in% res_both$problems$id)

  neither <- .write_qmd(c("filters:", "  - quartifyr", "format: docx"), dir = dir)
  res_neither <- validate_header(neither, quiet = TRUE)
  expect_true("no-cover" %in% res_neither$problems$id)
})

test_that("validate_header() flags a missing quartifyr filter and a missing quarto-plus filter separately", {
  dir <- withr::local_tempdir()

  no_quartifyr <- .write_qmd(c('title: "T"', "filters:", "  - quarto-plus", "format: docx"), dir = dir)
  res1 <- validate_header(no_quartifyr, quiet = TRUE)
  expect_true("quartifyr-filter-missing" %in% res1$problems$id)

  no_quarto_plus <- .write_qmd(c('title: "T"', "filters:", "  - quartifyr", "format: docx"), dir = dir)
  res2 <- validate_header(no_quarto_plus, quiet = TRUE)
  expect_false("quartifyr-filter-missing" %in% res2$problems$id)
  expect_true("quarto-plus-filter-missing" %in% res2$problems$id)
})

test_that("validate_header() flags an unrecognized crossref-hyperlinks value as an error", {
  path <- .write_qmd(c(
    'title: "T"', "filters:", "  - quarto-plus", "  - quartifyr", "format: docx",
    'crossref-hyperlinks: "sometimes"'
  ))
  res <- validate_header(path, quiet = TRUE)
  problem <- res$problems[res$problems$id == "crossref-hyperlinks-value", ]
  expect_identical(nrow(problem), 1L)
  expect_identical(problem$severity, "error")
})

test_that("validate_header() flags an unrecognized appendix-numbering value as a warning, not an error", {
  path <- .write_qmd(c(
    'title: "T"', "filters:", "  - quarto-plus", "  - quartifyr", "format: docx",
    'appendix-numbering: "lowercase"'
  ))
  res <- validate_header(path, quiet = TRUE)
  problem <- res$problems[res$problems$id == "appendix-numbering-value", ]
  expect_identical(nrow(problem), 1L)
  expect_identical(problem$severity, "warn")
})

test_that("validate_header() requires signature-note only when signature-mode is note", {
  path <- .write_qmd(c(
    'title: "T"', "filters:", "  - quarto-plus", "  - quartifyr", "format: docx",
    'signature-mode: "note"'
  ))
  res <- validate_header(path, quiet = TRUE)
  expect_true("signature-note" %in% res$missing_required)
})

test_that("validate_header() flags a logo/bibliography path that doesn't exist on disk", {
  path <- .write_qmd(c(
    'title: "T"', "filters:", "  - quarto-plus", "  - quartifyr", "format: docx",
    'logo: "nope.png"', 'bibliography: "nope.bib"'
  ))
  res <- validate_header(path, quiet = TRUE)
  expect_true("logo-file-missing" %in% res$problems$id)
  expect_true("bibliography-file-missing" %in% res$problems$id)
})

test_that("validate_header() requires project: {output-dir: report/shell} in _quarto.yml", {
  dir <- withr::local_tempdir()
  path <- .write_qmd(c('title: "T"', "filters:", "  - quarto-plus", "  - quartifyr", "format: docx"), dir = dir)

  res_missing_file <- validate_header(path, quiet = TRUE)
  expect_true("quarto-yml-output-dir" %in% res_missing_file$problems$id)

  writeLines(c("project:", "  output-dir: report/draft"), file.path(dir, "_quarto.yml"))
  res_wrong_dir <- validate_header(path, quiet = TRUE)
  expect_true("quarto-yml-output-dir" %in% res_wrong_dir$problems$id)

  writeLines(c("project:", "  output-dir: report/shell"), file.path(dir, "_quarto.yml"))
  res_ok <- validate_header(path, quiet = TRUE)
  expect_false("quarto-yml-output-dir" %in% res_ok$problems$id)
})

test_that("validate_header() reports ok = TRUE against the bundled demo/memo examples", {
  skip_if_not(file.exists("../../examples/demo-report/report.qmd"), "not run from tests/testthat")

  res_demo <- validate_header("../../examples/demo-report/report.qmd", quiet = TRUE)
  expect_true(res_demo$ok)

  res_memo <- validate_header("../../examples/memo-example/report.qmd", quiet = TRUE)
  expect_true(res_memo$ok)
})

test_that("validate_header(strict = TRUE) aborts when there are blocking issues", {
  path <- .write_qmd(c("filters:", "  - quartifyr")) # no title/memo, no format
  expect_error(validate_header(path, quiet = TRUE, strict = TRUE), class = "rlang_error")
})

test_that("validate_header() prints a report by default and is silenced by quiet = TRUE", {
  path <- .write_qmd(c('title: "T"', "filters:", "  - quarto-plus", "  - quartifyr", "format: docx"))
  writeLines(c("project:", "  output-dir: report/shell"), file.path(dirname(path), "_quarto.yml"))

  # cli's report goes through message() (stderr), not stdout.
  expect_message(validate_header(path), "quartifyr header validation")
  expect_silent(validate_header(path, quiet = TRUE))
})

test_that("validate_header() errors clearly on a nonexistent shell_qmd", {
  expect_error(validate_header("/does/not/exist.qmd"), "not found")
})
