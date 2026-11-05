# check_report_project() is render-free: nothing here needs Quarto, Python
# or reportifyr, only the files a project is made of.

.sidecar_json <- function(abbreviations = list("PK"), meta_type = "conc-time-trajectories") {
  jsonlite::toJSON(
    list(object_meta = list(
      meta_type = meta_type,
      footnotes = list(equations = list(), notes = list("A note."), abbreviations = abbreviations)
    )),
    auto_unbox = TRUE
  )
}

.check_fixture <- function(env = parent.frame()) {
  dir <- withr::local_tempdir(.local_envir = env)
  writeLines(c("project:", "  output-dir: report/shell"), file.path(dir, "_quarto.yml"))
  writeLines(
    c(
      "---",
      "title: Fixture",
      "synopsis:",
      "  - label: Figure",
      "    value:",
      "      - image: synopsis.png",
      "---",
      "",
      "# Results",
      "",
      "{rpfy}:fig.png<width: 4>",
      "",
      "Text after the figure.",
      "",
      "{rpfy}:tab.csv",
      "",
      "More text after the table.",
      "",
      "<!-- {rpfy}:commented-out.png -->",
      "",
      "```",
      "{rpfy}:in-a-code-block.png",
      "```"
    ),
    file.path(dir, "report.qmd")
  )
  file.create(file.path(dir, ".report_init.json"))
  dir.create(file.path(dir, "report"))
  writeLines(
    c(
      "abbreviations:", "  PK: pharmacokinetics",
      "figure_footnotes:", "  conc-time-trajectories: Figure footnote.",
      "table_footnotes:", "  summary: Table footnote."
    ),
    file.path(dir, "report", "standard_footnotes.yaml")
  )
  ext <- file.path(dir, "_extensions", "A2-ai", "quarto-plus")
  dir.create(ext, recursive = TRUE)
  writeLines("title: quarto-plus", file.path(ext, "_extension.yml"))
  file.create(file.path(dir, "ref.docx"))

  figs <- file.path(dir, "OUTPUTS", "figures")
  tabs <- file.path(dir, "OUTPUTS", "tables")
  dir.create(figs, recursive = TRUE)
  dir.create(tabs, recursive = TRUE)
  for (f in c("fig.png", "synopsis.png")) {
    file.create(file.path(figs, f))
    writeLines(.sidecar_json(), file.path(figs, sub("\\.png$", "_png_metadata.json", f)))
  }
  file.create(file.path(tabs, "tab.csv"))
  writeLines(.sidecar_json(meta_type = "summary"), file.path(tabs, "tab_csv_metadata.json"))

  list(dir = dir, qmd = file.path(dir, "report.qmd"), figs = figs, tabs = tabs, ref = file.path(dir, "ref.docx"))
}

.check <- function(fx, ...) check_report_project(fx$qmd, reference_doc = fx$ref, ...)

test_that("a complete project has no findings", {
  fx <- .check_fixture()
  findings <- .check(fx)

  expect_s3_class(findings, "quartifyr_findings")
  expect_identical(names(findings), c("check", "severity", "path", "message"))
  expect_identical(nrow(findings), 0L)
})

test_that("placeholders in comments and code blocks are ignored, synopsis images are not", {
  fx <- .check_fixture()
  placeholders <- .scan_placeholders(fx$qmd)

  expect_setequal(placeholders$name, c("fig.png", "tab.csv", "synopsis.png"))
  expect_identical(placeholders$source[placeholders$name == "synopsis.png"], "synopsis")
})

test_that("a missing shell .qmd is the only finding", {
  findings <- check_report_project(file.path(withr::local_tempdir(), "missing.qmd"))
  expect_identical(findings$check, "shell-qmd")
  expect_match(findings$message, "shell_qmd not found")
})

test_that("removing a figure gives exactly one error", {
  fx <- .check_fixture()
  file.remove(file.path(fx$figs, "fig.png"))
  findings <- .check(fx)

  expect_identical(nrow(findings), 1L)
  expect_identical(findings$check, "missing-artifact")
  expect_identical(findings$severity, "error")
  expect_match(findings$message, "fig.png")
})

test_that("removing a sidecar gives exactly one error", {
  fx <- .check_fixture()
  file.remove(file.path(fx$tabs, "tab_csv_metadata.json"))
  findings <- .check(fx)

  expect_identical(nrow(findings), 1L)
  expect_identical(findings$check, "missing-sidecar")
  expect_match(findings$message, "tab_csv_metadata.json")
})

test_that("an unparseable sidecar is an error", {
  fx <- .check_fixture()
  writeLines("{ not json", file.path(fx$figs, "fig_png_metadata.json"))
  findings <- .check(fx)

  expect_identical(findings$check, "invalid-sidecar")
})

test_that("deleting the init marker gives exactly one error", {
  fx <- .check_fixture()
  file.remove(file.path(fx$dir, ".report_init.json"))
  findings <- .check(fx)

  expect_identical(nrow(findings), 1L)
  expect_identical(findings$check, "init-marker")
  expect_match(findings$message, "initialize_report_project")
})

test_that("breaking output-dir gives exactly one error", {
  fx <- .check_fixture()
  writeLines(c("project:", "  output-dir: build"), file.path(fx$dir, "_quarto.yml"))
  findings <- .check(fx)

  expect_identical(nrow(findings), 1L)
  expect_identical(findings$check, "output-dir")
  expect_match(findings$message, "output-dir: report/shell")
})

test_that("a missing reference-doc and a missing footnotes YAML are each reported", {
  fx <- .check_fixture()
  file.remove(fx$ref)
  file.remove(file.path(fx$dir, "report", "standard_footnotes.yaml"))
  findings <- .check(fx)

  expect_setequal(findings$check, c("reference-doc", "footnotes-yaml"))
})

test_that("a missing required Quarto extension is an error, and can be skipped", {
  fx <- .check_fixture()
  unlink(file.path(fx$dir, "_extensions"), recursive = TRUE)

  findings <- .check(fx)
  expect_identical(findings$check, "quarto-extension")
  expect_identical(findings$severity, "error")
  expect_match(findings$message, "A2-ai/quarto-plus")

  expect_identical(nrow(.check(fx, check_extensions = FALSE)), 0L)
})

test_that("abbreviations and meta_type that standard_footnotes.yaml doesn't define are errors", {
  fx <- .check_fixture()
  writeLines(.sidecar_json(abbreviations = list("PK", "XYZ")), file.path(fx$figs, "fig_png_metadata.json"))
  writeLines(.sidecar_json(meta_type = "no-such-type"), file.path(fx$tabs, "tab_csv_metadata.json"))
  findings <- .check(fx)

  expect_setequal(findings$check, c("unknown-abbreviation", "unknown-meta-type"))
  expect_match(findings$message[findings$check == "unknown-abbreviation"], "XYZ")
})

test_that("a placeholder that ends its section is a warning", {
  fx <- .check_fixture()
  writeLines(
    c("# One", "", "{rpfy}:fig.png", "", "# Two", "", "Text.", "", "{rpfy}:tab.csv"),
    fx$qmd
  )
  findings <- .check(fx)

  expect_identical(findings$check, c("placeholder-last-in-section", "placeholder-last-in-section"))
  expect_true(all(findings$severity == "warning"))
})

test_that("a project-level reference-doc setting satisfies the reference-doc check", {
  fx <- .check_fixture()
  writeLines(
    c("project:", "  output-dir: report/shell", "format:", "  docx:", "    reference-doc: ref.docx"),
    file.path(fx$dir, "_quarto.yml")
  )
  expect_identical(nrow(check_report_project(fx$qmd)), 0L)

  file.remove(fx$ref)
  expect_identical(check_report_project(fx$qmd)$check, "reference-doc")
})

test_that("magic-string values parse like reportifyr's: args dropped, bracketed lists expanded", {
  expect_identical(.parse_magic_value("a.png<width: 3>"), "a.png")
  expect_identical(.parse_magic_value("[a.png<width: 3, height: 2>, b.csv]"), c("a.png", "b.csv"))
})

test_that("print() summarizes findings", {
  fx <- .check_fixture()
  expect_no_error(print(.check(fx)))
  file.remove(file.path(fx$figs, "fig.png"))
  printed <- capture.output(print(.check(fx)), type = "message")
  expect_true(any(grepl("missing-artifact", printed)))
})

test_that("the demo report has no errors and the check is fast", {
  demo <- normalizePath(file.path(testthat::test_path(), "..", "..", "examples", "demo-report", "report.qmd"), mustWork = FALSE)
  skip_if_not(file.exists(demo), "examples/ is not part of the installed package")

  elapsed <- system.time(findings <- check_report_project(demo))[["elapsed"]]

  expect_false(any(findings$severity == "error"), info = paste(findings$message, collapse = "\n"))
  expect_lt(elapsed, 1)
})

test_that("with no reference-doc configured anywhere the bundled default is used and found", {
  fx <- .check_fixture()
  expect_identical(nrow(check_report_project(fx$qmd)), 0L)
})

test_that("an absolute reference-doc in the front matter is used as given", {
  fx <- .check_fixture()
  writeLines(
    c("---", "title: T", "format:", "  docx:", paste0("    reference-doc: ", fx$ref), "---", "", "# H", "", "text"),
    fx$qmd
  )
  expect_identical(nrow(check_report_project(fx$qmd)), 0L)

  file.remove(fx$ref)
  findings <- check_report_project(fx$qmd)
  expect_identical(findings$check, "reference-doc")
  expect_identical(findings$path, fx$ref)
})

test_that("a standard_footnotes.yaml that doesn't parse is one error, and sidecar details aren't checked against it", {
  fx <- .check_fixture()
  writeLines(c("abbreviations: [unclosed", "  PK: x:"), file.path(fx$dir, "report", "standard_footnotes.yaml"))

  findings <- .check(fx)

  expect_identical(findings$check, "footnotes-yaml-parse")
  expect_match(findings$message, "does not parse as YAML")
})

test_that("a shell with no body placeholders has no placement findings", {
  fx <- .check_fixture()
  writeLines(c("# Only text", "", "Nothing to fill."), fx$qmd)

  expect_identical(nrow(.check(fx)), 0L)
  expect_identical(.check_placeholder_placement(.scan_placeholders(fx$qmd), fx$qmd), list())
})

test_that("print() shows warnings as well as errors", {
  fx <- .check_fixture()
  writeLines(c("# One", "", "{rpfy}:fig.png"), fx$qmd)
  findings <- .check(fx)
  expect_identical(findings$severity, "warning")

  shown <- paste(capture.output(print(findings), type = "message"), collapse = "\n")
  expect_match(shown, "0 errors, 1 warning")
  expect_match(shown, "placeholder-last-in-section")
})
