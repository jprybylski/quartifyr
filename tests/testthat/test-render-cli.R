# The noninteractive entry point behind inst/scripts/render.R. render_report()
# itself is mocked: these tests cover argument handling, the stdout/stderr
# split and the exit-code contract.

.fake_result <- function(status = "ok", unfilled = character(0)) {
  shell <- withr::local_tempfile(fileext = ".docx", .local_envir = parent.frame())
  writeLines("x", shell)
  .new_render_result(shell, NULL, NULL, unfilled_placeholders = unfilled, errors = if (status == "error" && length(unfilled) == 0) "boom")
}

.run_cli <- function(args) {
  out <- textConnection("out_lines", "w", local = TRUE)
  err <- textConnection("err_lines", "w", local = TRUE)
  on.exit({ close(out); close(err) })
  code <- .render_cli(args, out = out, err = err)
  flush(out); flush(err)
  list(code = code, out = out_lines, err = err_lines)
}

test_that("a clean render prints only the JSON result on stdout and exits 0", {
  local_mocked_bindings(render_report = function(shell_qmd, ...) {
    cat("stray progress output\n")
    .fake_result()
  })

  res <- .run_cli(c("--project", "/p", "--shell", "report.qmd", "--json"))

  expect_identical(res$code, 0L)
  parsed <- jsonlite::fromJSON(paste(res$out, collapse = "\n"))
  expect_identical(parsed$status, "ok")
  expect_match(res$err, "stray progress output", all = FALSE)
})

test_that("options reach render_report() with the right types", {
  seen <- NULL
  local_mocked_bindings(render_report = function(...) {
    seen <<- list(...)
    .fake_result()
  })

  .run_cli(c(
    "--project", "/p", "--shell", "report.qmd", "--status=final", "--strict",
    "--quarto-timeout", "30", "--quarto-bin", "/opt/quarto", "--recalculate-fields"
  ))

  expect_identical(seen$shell_qmd, "/p/report.qmd")
  expect_identical(seen$status, "final")
  expect_true(seen$strict)
  expect_identical(seen$quarto_timeout, 30)
  expect_identical(seen$quarto_bin, "/opt/quarto")
  expect_true(seen$recalculate_fields)
  expect_false(seen$resolve_same_page_crossrefs)
})

test_that("any render error exits 1 with a JSON error object naming its class", {
  local_mocked_bindings(render_report = function(...) {
    stop(structure(
      class = c("quartifyr_quarto_timeout", "error", "condition"),
      list(message = "quarto render timed out after 1 seconds", call = NULL)
    ))
  })

  res <- .run_cli(c("--project", "/p", "--shell", "report.qmd", "--json"))

  expect_identical(res$code, 1L)
  parsed <- jsonlite::fromJSON(paste(res$out, collapse = "\n"))
  expect_identical(parsed$status, "error")
  expect_identical(parsed$error_class, "quartifyr_quarto_timeout")
  expect_match(parsed$errors, "timed out")
  expect_match(res$err, "timed out", all = FALSE)
  # A failed render reports no output at all, so nothing can be mistaken for one.
  expect_null(parsed$artifacts)
  expect_null(parsed$draft)
  expect_null(parsed$final)
})

test_that("a strict incomplete render exits 1 and still reports the whole result", {
  local_mocked_bindings(render_report = function(...) {
    .abort_incomplete(.fake_result("error", unfilled = "{rpfy}:gone.png"))
  })

  res <- .run_cli(c("--project", "/p", "--shell", "report.qmd", "--json", "--strict"))

  expect_identical(res$code, 1L)
  parsed <- jsonlite::fromJSON(paste(res$out, collapse = "\n"))
  expect_identical(parsed$status, "error")
  expect_identical(parsed$unfilled_placeholders, "{rpfy}:gone.png")
  expect_identical(parsed$error_class, "quartifyr_render_incomplete")
})

test_that("without --json the errors still go to stderr and stdout stays empty", {
  local_mocked_bindings(render_report = function(...) stop("nope"))
  res <- .run_cli(c("--project", "/p", "--shell", "report.qmd"))

  expect_identical(res$code, 1L)
  expect_identical(res$out, character(0))
  expect_match(res$err, "nope", all = FALSE)
})

test_that("bad usage exits 2 without rendering", {
  local_mocked_bindings(render_report = function(...) stop("must not render"))

  expect_identical(.run_cli(c("--shell", "report.qmd"))$code, 2L)
  expect_identical(.run_cli(c("--project", "/p", "--shell", "r.qmd", "--bogus"))$code, 2L)
  expect_identical(.run_cli(c("--project", "/p", "--shell", "r.qmd", "--quarto-timeout", "soon"))$code, 2L)
  expect_identical(.run_cli(c("--project"))$code, 2L)
  expect_identical(.run_cli("--help")$code, 0L)
})

test_that("a pass-2 failure over missing sidecars lists them in the JSON error", {
  local_mocked_bindings(render_report = function(...) {
    stop(structure(
      class = c("quartifyr_pass2_failed", "error", "condition"),
      list(message = "build_report stopped", call = NULL, missing_metadata = c("a.png", "b.csv"))
    ))
  })

  res <- .run_cli(c("--project", "/p", "--shell", "report.qmd", "--json"))

  parsed <- jsonlite::fromJSON(paste(res$out, collapse = "\n"))
  expect_identical(res$code, 1L)
  expect_identical(parsed$missing_metadata, c("a.png", "b.csv"))
  expect_identical(parsed$error_class, "quartifyr_pass2_failed")
})

test_that("--reference-doc, --style and --override reach render_report()", {
  seen <- NULL
  local_mocked_bindings(render_report = function(...) {
    seen <<- list(...)
    .fake_result()
  })

  .run_cli(c(
    "--project", "/p", "--shell", "report.qmd",
    "--reference-doc", "/r.docx", "--style", "/s.yaml", "--override", "/o.yaml"
  ))

  expect_identical(seen$reference_doc, "/r.docx")
  expect_identical(seen$style, "/s.yaml")
  expect_identical(seen$override, "/o.yaml")
})

test_that("a stray positional argument is bad usage", {
  local_mocked_bindings(render_report = function(...) stop("must not render"))
  res <- .run_cli(c("--project", "/p", "--shell", "report.qmd", "extra"))

  expect_identical(res$code, 2L)
  expect_match(res$err, "Unexpected argument: extra", all = FALSE)
})
