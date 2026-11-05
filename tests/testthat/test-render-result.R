# Pure helpers behind render_report()'s structured result.

.write_docx <- function(document_xml, footnotes_xml = NULL) {
  skip_if(Sys.which("zip") == "", "no `zip` binary to build a test docx with")
  build <- withr::local_tempdir(.local_envir = parent.frame())
  dir.create(file.path(build, "word"))
  writeLines(document_xml, file.path(build, "word", "document.xml"))
  if (!is.null(footnotes_xml)) {
    writeLines(footnotes_xml, file.path(build, "word", "footnotes.xml"))
  }
  out <- file.path(withr::local_tempdir(.local_envir = parent.frame()), "t.docx")
  withr::with_dir(build, utils::zip(out, list.files(recursive = TRUE), flags = "-qr0X"))
  out
}

test_that(".scan_unfilled_placeholders rebuilds text split across runs and decodes entities", {
  docx <- .write_docx(
    paste0(
      "<w:document><w:body>",
      "<w:p><w:r><w:t>{rpfy}:fig</w:t></w:r><w:r><w:t>.png&lt;width: 3&gt;</w:t></w:r></w:p>",
      "<w:p><w:r><w:t>ordinary text, no magic string</w:t></w:r></w:p>",
      "<w:p><w:r><w:t>{rpfy}:tab.csv</w:t></w:r></w:p>",
      "</w:body></w:document>"
    ),
    footnotes_xml = "<w:footnotes><w:p><w:r><w:t>{rpfy}:note.png</w:t></w:r></w:p></w:footnotes>"
  )

  expect_setequal(
    .scan_unfilled_placeholders(docx),
    c("{rpfy}:fig.png<width: 3>", "{rpfy}:tab.csv", "{rpfy}:note.png")
  )
})

# reportifyr keeps the `{rpfy}:` paragraph in a filled draft and records the
# fill in the inserted object's alt text -- that, not the paragraph's
# absence, is what distinguishes filled from unfilled.
test_that(".scan_unfilled_placeholders treats a placeholder with an alt-text hash marker as filled", {
  docx <- .write_docx(
    paste0(
      "<w:document><w:body>",
      "<w:p><w:r><w:t>{rpfy}:filled.png&lt;width: 4&gt;</w:t></w:r></w:p>",
      "<w:p><w:r><w:drawing><wp:docPr id=\"1\" descr=\"{rpfy}:filled.png&lt;width: 4&gt; [hash:abc123]\"/></w:drawing></w:r></w:p>",
      "<w:p><w:r><w:t>{rpfy}:table.csv</w:t></w:r></w:p>",
      "<w:tbl><w:tblPr><w:tblDescription w:val=\"{rpfy}:table.csv [hash:def456][grid:xyz]\"/></w:tblPr></w:tbl>",
      "<w:p><w:r><w:t>{rpfy}:never-filled.png</w:t></w:r></w:p>",
      "<w:p><w:r><w:t>text</w:t></w:r></w:p>",
      "</w:body></w:document>"
    )
  )

  expect_identical(.scan_unfilled_placeholders(docx), "{rpfy}:never-filled.png")
})

test_that(".scan_unfilled_placeholders counts repeats: one fill doesn't cover two placeholders", {
  docx <- .write_docx(
    paste0(
      "<w:document><w:body>",
      "<w:p><w:r><w:t>{rpfy}:twice.png</w:t></w:r></w:p>",
      "<w:p><w:r><w:drawing><wp:docPr descr=\"{rpfy}:twice.png [hash:aa]\"/></w:drawing></w:r></w:p>",
      "<w:p><w:r><w:t>{rpfy}:twice.png</w:t></w:r></w:p>",
      "</w:body></w:document>"
    )
  )

  expect_identical(.scan_unfilled_placeholders(docx), "{rpfy}:twice.png")
})

test_that(".scan_unfilled_placeholders finds nothing in a filled document, a missing file or a non-docx", {
  docx <- .write_docx("<w:document><w:body><w:p><w:r><w:t>all filled in</w:t></w:r></w:p></w:body></w:document>")
  expect_identical(.scan_unfilled_placeholders(docx), character(0))
  expect_identical(.scan_unfilled_placeholders(file.path(withr::local_tempdir(), "nope.docx")), character(0))
  expect_identical(.scan_unfilled_placeholders(NULL), character(0))

  not_a_docx <- withr::local_tempfile(fileext = ".docx")
  writeLines("not a zip", not_a_docx)
  expect_identical(.scan_unfilled_placeholders(not_a_docx), character(0))
})

test_that(".new_render_result derives status from what was found", {
  shell <- withr::local_tempfile(fileext = ".docx")
  writeLines("x", shell)
  make <- function(...) .new_render_result(shell, NULL, NULL, ...)

  expect_identical(make()$status, "ok")
  expect_identical(make(warnings = "w")$status, "warning")
  expect_identical(make(missing_metadata = "a.png")$status, "warning")
  expect_identical(make(errors = "e")$status, "error")
  expect_identical(make(unfilled_placeholders = "{rpfy}:a.png")$status, "error")
  expect_identical(make(warnings = "w", errors = "e")$status, "error")
})

test_that(".parse_rpfy_log picks out the two placeholder-left-alone warnings", {
  lines <- c(
    "2026-01-01 00:00:00 [R] [INFO] Processing table file: /p/t.csv",
    "2026-01-01 00:00:01 [py] [WARNING] Figure file not found: /p/f.png",
    "2026-01-01 00:00:01 [py] [WARNING] Metadata file not found for: g.png",
    "2026-01-01 00:00:02 [py] [DEBUG] Skipping h - not found in table directory"
  )
  parsed <- .parse_rpfy_log(lines)

  expect_identical(parsed$missing_figures, "/p/f.png")
  expect_identical(parsed$missing_metadata, "g.png")
  expect_identical(.parse_rpfy_log(character(0))$missing_figures, character(0))
})

.validate_render_json <- function(json) {
  skip_if_not_installed("jsonvalidate")
  schema_path <- system.file("schemas", "render-result-v1.schema.json", package = "quartifyr")
  skip_if(!nzchar(schema_path), "schema not installed")
  validator <- jsonvalidate::json_validator(schema_path, engine = "ajv")
  validator(as.character(json), verbose = TRUE, greedy = TRUE)
}

test_that("the JSON form validates against the full v1 schema", {
  shell <- withr::local_tempfile(fileext = ".docx")
  writeLines("x", shell)
  result <- .new_render_result(
    shell, NULL, NULL,
    unfilled_placeholders = "{rpfy}:a.png", log_dir = "/p/.rpfy-logs",
    inputs = .file_table("shell_qmd", shell),
    versions = list(quartifyr = "0.3.2", reportifyr = NULL, quarto = "1.9.0", quartifyr_styling = "0.1.0", r = "4.5.0"),
    started_at = .timestamp_utc(), finished_at = .timestamp_utc()
  )
  json <- .render_result_json(result)
  expect_true(.validate_render_json(json), info = format(attr(.validate_render_json(json), "errors")))

  parsed <- jsonlite::fromJSON(as.character(json), simplifyVector = FALSE)
  expect_identical(parsed$schema_version, 1L)
  expect_null(parsed$final)
  expect_identical(parsed$unfilled_placeholders, list("{rpfy}:a.png"))
  expect_identical(parsed$warnings, list())
  expect_match(parsed$artifacts[[1]]$sha256, "^[0-9a-f]{64}$")
  expect_identical(parsed$inputs[[1]]$role, "shell_qmd")
  expect_null(parsed$versions$reportifyr)
  expect_true("reportifyr" %in% names(parsed$versions))
})

test_that("a result built without provenance still validates and carries empty provenance", {
  shell <- withr::local_tempfile(fileext = ".docx")
  writeLines("x", shell)
  json <- .render_result_json(.new_render_result(shell, NULL, NULL))
  expect_true(.validate_render_json(json))
  parsed <- jsonlite::fromJSON(as.character(json), simplifyVector = FALSE)
  expect_identical(parsed$inputs, list())
  expect_identical(parsed$versions, structure(list(), names = character(0)))
})

test_that("the early-failure JSON payload validates and carries schema_version", {
  err <- simpleError("quarto render timed out")
  class(err) <- c("quartifyr_quarto_timeout", class(err))
  json <- .render_cli_error_json(err, .timestamp_utc(), .timestamp_utc())
  expect_true(.validate_render_json(json))
  expect_identical(jsonlite::fromJSON(as.character(json))$schema_version, 1L)
})

test_that(".abort_incomplete() reports status error even when the render only warned", {
  shell <- withr::local_tempfile(fileext = ".docx")
  writeLines("x", shell)
  result <- .new_render_result(shell, NULL, NULL, missing_metadata = "a.png")
  expect_identical(result$status, "warning")

  err <- tryCatch(.abort_incomplete(result), error = function(e) e)
  expect_s3_class(err, "quartifyr_render_incomplete")
  expect_identical(err$result$status, "error")
  expect_match(err$result$errors, "missing metadata for: a.png")
  expect_true(.validate_render_json(.render_result_json(err$result)))
})

test_that(".input_table() lists the shell, support files, artifacts and sidecars that exist", {
  project <- withr::local_tempdir()
  figs <- file.path(project, "figs"); tabs <- file.path(project, "tabs")
  dir.create(figs); dir.create(tabs)
  qmd <- file.path(project, "report.qmd")
  writeLines(c("# s", "", "{rpfy}:a.png", "", "text", "", "{rpfy}:t.csv", "", "{rpfy}:gone.png", "", "text"), qmd)
  writeLines("x", file.path(figs, "a.png")); writeLines("{}", file.path(figs, "a_png_metadata.json"))
  writeLines("x", file.path(tabs, "t.csv"))
  yaml <- file.path(project, "fn.yaml"); writeLines("a: 1", yaml)

  inputs <- .input_table(qmd, figs, tabs, yaml, file.path(project, "no-config.yaml"), NULL)

  expect_setequal(inputs$role, c("shell_qmd", "standard_footnotes", "figure", "sidecar", "table"))
  expect_false(any(grepl("gone.png|no-config", inputs$path)))
  expect_true(all(grepl("^[0-9a-f]{64}$", inputs$sha256)))

  with_ref <- .input_table(qmd, figs, tabs, yaml, yaml, yaml)
  expect_true(all(c("config", "reference_doc") %in% with_ref$role))
})

test_that(".tool_versions() reports what it can and NULL for what it cannot", {
  local_mocked_bindings(run = function(...) list(status = 0, stdout = "1.9.9\n", stderr = ""), .package = "processx")
  v <- .tool_versions("quarto")
  expect_identical(v$quarto, "1.9.9")
  expect_identical(v$r, as.character(getRversion()))
  expect_identical(v$quartifyr_styling, "0.1.0")

  local_mocked_bindings(run = function(...) list(status = 1, stdout = "", stderr = "no"), .package = "processx")
  expect_null(.tool_versions("quarto")$quarto)
  local_mocked_bindings(run = function(...) stop("no such executable"), .package = "processx")
  expect_null(.tool_versions("quarto")$quarto)
  expect_match(.timestamp_utc(as.POSIXct("2026-01-02 03:04:05", tz = "UTC")), "^2026-01-02T03:04:05Z$")
})

test_that(".styling_version() is NULL without the bundled source or a version line", {
  expect_null(.styling_version(init = ""))
  init <- withr::local_tempfile(fileext = ".py")
  writeLines("# no version here", init)
  expect_null(.styling_version(init = init))
  writeLines("__version__ = '9.8.7'", init)
  expect_identical(.styling_version(init = init), "9.8.7")
})

test_that("print() summarizes the status, paths, and every kind of problem", {
  shell <- withr::local_tempfile(fileext = ".docx")
  writeLines("x", shell)
  result <- .new_render_result(
    shell, NULL, NULL,
    warnings = "reportifyr could not find figure file(s): gone.png",
    errors = "styling_recalculate_fields() failed",
    unfilled_placeholders = "{rpfy}:gone.png",
    missing_metadata = "no-sidecar.png"
  )

  shown <- capture.output(print(result), type = "message")
  shown <- paste(shown, collapse = "\n")

  expect_match(shown, "quartifyr render: error")
  expect_match(shown, "shell:")
  expect_match(shown, "unfilled placeholder")
  expect_match(shown, "gone.png")
  expect_match(shown, "missing metadata sidecar")
  expect_match(shown, "no-sidecar.png")
  expect_match(shown, "styling_recalculate_fields\\(\\) failed")
  expect_match(shown, "could not find figure")
  expect_identical(invisible(print(result)), result)
})

test_that("print() of a clean result reports ok and nothing else", {
  shell <- withr::local_tempfile(fileext = ".docx")
  writeLines("x", shell)
  shown <- paste(capture.output(print(.new_render_result(shell, NULL, NULL)), type = "message"), collapse = "\n")

  expect_match(shown, "quartifyr render: ok")
  expect_no_match(shown, "unfilled|missing metadata")
})
