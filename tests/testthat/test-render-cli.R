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
    "--quarto-timeout", "30", "--quarto-bin", "/opt/quarto", "--recalculate-fields",
    "--soffice-bin", "/opt/lo/soffice"
  ))

  expect_identical(seen$shell_qmd, "/p/report.qmd")
  expect_identical(seen$status, "final")
  expect_true(seen$strict)
  expect_identical(seen$quarto_timeout, 30)
  expect_identical(seen$quarto_bin, "/opt/quarto")
  expect_identical(seen$soffice_bin, "/opt/lo/soffice")
  expect_true(seen$recalculate_fields)
  expect_false(seen$resolve_same_page_crossrefs)
  expect_true(seen$fit_tables)
})

test_that("--no-fit-tables turns table fitting off", {
  seen <- NULL
  local_mocked_bindings(render_report = function(...) {
    seen <<- list(...)
    .fake_result()
  })

  .run_cli(c("--project", "/p", "--shell", "report.qmd", "--no-fit-tables"))

  expect_false(seen$fit_tables)
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

test_that("a relative --project and --shell reach render_report() under the project", {
  seen <- NULL
  local_mocked_bindings(render_report = function(...) {
    seen <<- list(...)
    .fake_result()
  })
  .run_cli(c("--project", "proj", "--shell", "report.qmd"))
  expect_identical(seen$shell_qmd, "proj/report.qmd")
})

test_that("a failed render's JSON error carries schema_version and timestamps", {
  local_mocked_bindings(render_report = function(...) stop("nope"))
  res <- .run_cli(c("--project", "/p", "--shell", "report.qmd", "--json"))
  parsed <- jsonlite::fromJSON(paste(res$out, collapse = "\n"))

  expect_identical(parsed$schema_version, 1L)
  expect_match(parsed$started_at, "Z$")
  expect_match(parsed$finished_at, "Z$")
})

test_that("--help says a non-strict exit 0 doesn't mean the render was complete", {
  res <- .run_cli("--help")
  expect_match(paste(res$out, collapse = " "), "exit 0 only means the render finished")
})

test_that("--offline reaches render_report() and is off otherwise", {
  seen <- NULL
  local_mocked_bindings(render_report = function(...) {
    seen <<- list(...)
    .fake_result()
  })

  .run_cli(c("--project", "/p", "--shell", "report.qmd", "--offline"))
  expect_true(seen$offline)
  .run_cli(c("--project", "/p", "--shell", "report.qmd"))
  expect_null(seen$offline)
})

test_that(".cli_shell_path() keeps an existing absolute shell and resolves anything else under the project", {
  shell <- withr::local_tempfile(fileext = ".qmd")
  writeLines("# s", shell)

  expect_identical(.cli_shell_path("/proj", shell), shell)
  expect_identical(.cli_shell_path("/proj", "report.qmd"), "/proj/report.qmd")
  expect_identical(.cli_shell_path("/proj", "/does/not/exist.qmd"), "/proj//does/not/exist.qmd")
})

test_that("an early-error JSON reports the tool versions that could be determined", {
  local_mocked_bindings(render_report = function(...) stop("nope"))
  local_mocked_bindings(
    run = function(command, ...) list(status = 0, stdout = paste0("9.9.9 from ", command, "\n"), stderr = ""),
    .package = "processx"
  )

  res <- .run_cli(c("--project", "/p", "--shell", "report.qmd", "--json", "--quarto-bin", "/opt/quarto"))
  parsed <- jsonlite::fromJSON(paste(res$out, collapse = "\n"))

  expect_identical(parsed$status, "error")
  expect_identical(parsed$versions$quarto, "9.9.9 from /opt/quarto")
  expect_identical(parsed$versions$quartifyr, as.character(utils::packageVersion("quartifyr")))
  expect_true(.validate_render_json(paste(res$out, collapse = "\n")))
})

test_that("a strict rejection's own versions are not overwritten by the early-error fallback", {
  local_mocked_bindings(render_report = function(...) {
    .abort_incomplete(.fake_result("error", unfilled = "{rpfy}:gone.png"))
  })
  local_mocked_bindings(
    run = function(...) list(status = 0, stdout = "7.7.7\n", stderr = ""),
    .package = "processx"
  )
  res <- .run_cli(c("--project", "/p", "--shell", "report.qmd", "--json", "--strict"))
  parsed <- jsonlite::fromJSON(paste(res$out, collapse = "\n"))
  expect_null(parsed$versions$quarto) # the fake result has no versions, and none is invented
})

test_that(".cli_quarto_command() prefers --quarto-bin, then QUARTO_PATH, then quarto", {
  expect_identical(.cli_quarto_command("/opt/quarto"), "/opt/quarto")
  withr::with_envvar(c(QUARTO_PATH = "/env/quarto"), expect_identical(.cli_quarto_command(), "/env/quarto"))
  withr::with_envvar(c(QUARTO_PATH = NA), expect_identical(.cli_quarto_command(), "quarto"))
})
