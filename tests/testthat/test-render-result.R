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

test_that("the JSON form matches the shipped schema's required shape", {
  shell <- withr::local_tempfile(fileext = ".docx")
  writeLines("x", shell)
  result <- .new_render_result(
    shell, NULL, NULL,
    unfilled_placeholders = "{rpfy}:a.png", log_dir = "/p/.rpfy-logs"
  )
  json <- jsonlite::fromJSON(as.character(.render_result_json(result)), simplifyVector = FALSE)
  schema_path <- system.file("schemas", "render-result.schema.json", package = "quartifyr")
  skip_if(!nzchar(schema_path), "schema not installed")
  schema <- jsonlite::fromJSON(schema_path, simplifyVector = FALSE)

  expect_true(all(schema$required %in% names(json)))
  expect_true(json$status %in% unlist(schema$properties$status$enum))
  expect_true(all(names(json) %in% names(schema$properties)))
  expect_null(json$final)
  expect_identical(json$unfilled_placeholders, list("{rpfy}:a.png"))
  expect_identical(json$warnings, list())
  expect_match(json$artifacts[[1]]$sha256, "^[0-9a-f]{64}$")
  expect_true(all(schema$properties$artifacts$items$required %in% names(json$artifacts[[1]])))
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
