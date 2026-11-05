# The noninteractive entry point behind inst/scripts/check.R.
# check_report_project() is mocked where a test needs particular findings.

.run_check_cli <- function(args) {
  out <- textConnection("out_lines", "w", local = TRUE)
  err <- textConnection("err_lines", "w", local = TRUE)
  on.exit({ close(out); close(err) })
  code <- .check_cli(args, out = out, err = err)
  flush(out); flush(err)
  list(code = code, out = out_lines, err = err_lines)
}

.validate_check_json <- function(json) {
  skip_if_not_installed("jsonvalidate")
  schema_path <- system.file("schemas", "check-result-v1.schema.json", package = "quartifyr")
  skip_if(!nzchar(schema_path), "schema not installed")
  jsonvalidate::json_validator(schema_path, engine = "ajv")(json, verbose = TRUE)
}

.findings <- function(...) {
  rows <- list(...)
  .as_findings(lapply(rows, function(r) .finding(r[[1]], r[[2]], r[[3]], r[[4]])))
}

test_that("no findings: exit 0, empty findings array, schema-valid JSON", {
  local_mocked_bindings(check_report_project = function(...) .findings())
  res <- .run_check_cli(c("--project", "/p", "--shell", "report.qmd", "--json"))

  expect_identical(res$code, 0L)
  json <- paste(res$out, collapse = "\n")
  parsed <- jsonlite::fromJSON(json, simplifyVector = FALSE)
  expect_identical(parsed$schema_version, 1L)
  expect_identical(parsed$findings, list())
  expect_true(.validate_check_json(json))
})

test_that("an error finding exits 1; a warning alone exits 0", {
  local_mocked_bindings(check_report_project = function(...) {
    .findings(list("missing-sidecar", "error", "/p/a.png", "no sidecar"), list("tail", "warning", NA, "ends section"))
  })
  res <- .run_check_cli(c("--project", "/p", "--shell", "report.qmd", "--json"))
  parsed <- jsonlite::fromJSON(paste(res$out, collapse = "\n"), simplifyVector = FALSE)

  expect_identical(res$code, 1L)
  expect_identical(parsed$findings[[1]]$check, "missing-sidecar")
  expect_null(parsed$findings[[2]]$path)
  expect_true(.validate_check_json(paste(res$out, collapse = "\n")))

  local_mocked_bindings(check_report_project = function(...) .findings(list("tail", "warning", "/p/r.qmd", "w")))
  expect_identical(.run_check_cli(c("--project", "/p", "--shell", "report.qmd"))$code, 0L)
})

test_that("without --json each finding is a line on stdout", {
  local_mocked_bindings(check_report_project = function(...) .findings(list("c1", "error", "/p", "bad thing")))
  res <- .run_check_cli(c("--project", "/p", "--shell", "report.qmd"))
  expect_identical(res$out, "error [c1] bad thing")

  local_mocked_bindings(check_report_project = function(...) .findings())
  expect_identical(.run_check_cli(c("--project", "/p", "--shell", "report.qmd"))$out, "No findings.")
})

test_that("the shell is resolved against --project, like render.R", {
  seen <- NULL
  local_mocked_bindings(check_report_project = function(shell_qmd, ...) {
    seen <<- shell_qmd
    .findings()
  })
  .run_check_cli(c("--project", "proj", "--shell", "report.qmd"))
  expect_identical(seen, "proj/report.qmd")
})

test_that("an unexpected failure becomes an error finding, not a crash", {
  local_mocked_bindings(check_report_project = function(...) stop("kaboom"))
  res <- .run_check_cli(c("--project", "/p", "--shell", "report.qmd", "--json"))
  parsed <- jsonlite::fromJSON(paste(res$out, collapse = "\n"), simplifyVector = FALSE)

  expect_identical(res$code, 1L)
  expect_identical(parsed$findings[[1]]$check, "internal-error")
  expect_match(parsed$findings[[1]]$message, "kaboom")
})

test_that("bad usage exits 2 and --help exits 0", {
  local_mocked_bindings(check_report_project = function(...) stop("must not run"))
  expect_identical(.run_check_cli(c("--shell", "report.qmd"))$code, 2L)
  expect_identical(.run_check_cli(c("--project", "/p"))$code, 2L)
  expect_identical(.run_check_cli(c("--project", "/p", "--shell", "r.qmd", "--strict"))$code, 2L)
  expect_identical(.run_check_cli("--project")$code, 2L)
  help <- .run_check_cli("--help")
  expect_identical(help$code, 0L)
  expect_match(paste(help$out, collapse = " "), "0 no errors, 1 at least one error finding, 2 bad usage")
})

test_that("it runs for real against a project and agrees with check_report_project()", {
  project <- withr::local_tempdir()
  writeLines("# shell", file.path(project, "report.qmd"))
  res <- suppressWarnings(.run_check_cli(c("--project", project, "--shell", "report.qmd", "--json")))
  parsed <- jsonlite::fromJSON(paste(res$out, collapse = "\n"), simplifyVector = FALSE)

  expect_identical(res$code, 1L)
  expect_gt(length(parsed$findings), 0)
  expect_true(.validate_check_json(paste(res$out, collapse = "\n")))
})
