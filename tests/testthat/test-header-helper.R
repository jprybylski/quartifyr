# header_helper() itself only gates on interactive() and then delegates to
# .header_helper_collect()/.header_helper_render() -- both fully testable
# on their own by mocking the two I/O primitives (.header_helper_ask/
# .header_helper_ask_yn) rather than driving a real interactive session.
# See R/header-helper.R's own comments for why it's factored this way.

test_that("header_helper() requires an interactive session", {
  # Always FALSE under testthat/R CMD check -- no mocking needed.
  expect_false(interactive())
  expect_error(header_helper("report"), "interactive session")
})

test_that(".header_helper_ask_yn() defaults on empty input and parses y/n", {
  local_mocked_bindings(.header_helper_ask = function(prompt) "")
  expect_true(.header_helper_ask_yn("Include X?", default = TRUE))
  expect_false(.header_helper_ask_yn("Include X?", default = FALSE))

  local_mocked_bindings(.header_helper_ask = function(prompt) "y")
  expect_true(.header_helper_ask_yn("Include X?", default = FALSE))

  local_mocked_bindings(.header_helper_ask = function(prompt) "no")
  expect_false(.header_helper_ask_yn("Include X?", default = TRUE))
})

test_that(".header_helper_collect_rows() collects label/value rows until declined", {
  answers_yn <- c(TRUE, TRUE, FALSE)
  answers_ask <- c("Sponsor", "Acme Pharma", "Protocol", "ACM-1001")
  yn_i <- 0
  ask_i <- 0
  local_mocked_bindings(
    .header_helper_ask_yn = function(prompt, default = FALSE) {
      yn_i <<- yn_i + 1
      answers_yn[[yn_i]]
    },
    .header_helper_ask = function(prompt) {
      ask_i <<- ask_i + 1
      answers_ask[[ask_i]]
    }
  )

  rows <- .header_helper_collect_rows("extra title-page row")
  expect_identical(rows, list(
    list(label = "Sponsor", value = "Acme Pharma"),
    list(label = "Protocol", value = "ACM-1001")
  ))
})

test_that(".header_helper_collect_rows() collects bare lines when with_label = FALSE", {
  answers_yn <- c(TRUE, TRUE, FALSE)
  answers_ask <- c("Acme Pharma", "123 Main St")
  yn_i <- 0
  ask_i <- 0
  local_mocked_bindings(
    .header_helper_ask_yn = function(prompt, default = FALSE) {
      yn_i <<- yn_i + 1
      answers_yn[[yn_i]]
    },
    .header_helper_ask = function(prompt) {
      ask_i <<- ask_i + 1
      answers_ask[[ask_i]]
    }
  )

  rows <- .header_helper_collect_rows("address line", with_label = FALSE)
  expect_identical(rows, list("Acme Pharma", "123 Main St"))
})

test_that(".header_helper_collect_rows() returns an empty list when immediately declined", {
  local_mocked_bindings(.header_helper_ask_yn = function(prompt, default = FALSE) FALSE)
  expect_identical(.header_helper_collect_rows("synopsis row"), list())
})

test_that(".header_helper_collect_people() collects name/title pairs", {
  answers_yn <- c(TRUE, FALSE)
  answers_ask <- c("Alice Lee", "Medical Director")
  yn_i <- 0
  ask_i <- 0
  local_mocked_bindings(
    .header_helper_ask_yn = function(prompt, default = FALSE) {
      yn_i <<- yn_i + 1
      answers_yn[[yn_i]]
    },
    .header_helper_ask = function(prompt) {
      ask_i <<- ask_i + 1
      answers_ask[[ask_i]]
    }
  )

  people <- .header_helper_collect_people("approver")
  expect_identical(people, list(list(name = "Alice Lee", title = "Medical Director")))
})

test_that(".header_field_set() assigns scalar and nested paths without clobbering siblings", {
  fm <- list(memo = list(to = "Jane"))
  fm <- .header_field_set(fm, "title", "Report")
  fm <- .header_field_set(fm, c("memo", "from"), "John")
  expect_identical(fm$title, "Report")
  expect_identical(fm$memo$to, "Jane")
  expect_identical(fm$memo$from, "John")
})

test_that(".header_helper_render() produces a fenced, sensibly-ordered YAML block", {
  fm <- list(
    filters = c("quarto-plus", "quartifyr"),
    format = "docx",
    title = "Population PK Analysis",
    `document-status` = "draft"
  )
  block <- .header_helper_render(fm)

  expect_match(block, "^---\n")
  expect_match(block, "\n---\n$")
  # Registry order (title page before document structure) beats
  # insertion order, matching inst/extensions/quartifyr/README.md's own
  # example layout.
  expect_true(regexpr("title:", block) < regexpr("format:", block))

  parsed <- yaml::yaml.load(block)
  expect_identical(parsed$title, "Population PK Analysis")
  expect_identical(parsed$filters, c("quarto-plus", "quartifyr"))
})

test_that(".header_helper_render() escapes nothing surprising -- round-trips through yaml::yaml.load()", {
  fm <- list(
    filters = c("quarto-plus", "quartifyr"), format = "docx",
    title = "A Report: With a Colon", memo = NULL
  )
  block <- .header_helper_render(fm)
  parsed <- yaml::yaml.load(block)
  expect_identical(parsed$title, "A Report: With a Colon")
})

test_that(".header_helper_collect('report') asks for the required title and skips memo entirely", {
  # Decline every optional scalar/list question; only answer the
  # required "Title" prompt for real. This exercises the full field-
  # registry-driven loop (every scalar field in .quartifyr_header_fields()
  # gets *some* prompt) without needing to hand-order dozens of answers:
  # the mock only special-cases the one required prompt.
  local_mocked_bindings(
    .header_helper_ask = function(prompt) {
      if (grepl("^Title \\(required\\)", prompt)) "Demo Report" else ""
    },
    .header_helper_ask_yn = function(prompt, default = FALSE) FALSE
  )

  fm <- .header_helper_collect("report")
  expect_identical(fm$title, "Demo Report")
  expect_null(fm$memo)
  expect_identical(fm$format, "docx")
  expect_identical(fm$filters, c("quarto-plus", "quartifyr"))
})

test_that(".header_helper_collect('memo') seeds memo: and excludes title: entirely", {
  local_mocked_bindings(
    .header_helper_ask = function(prompt) {
      if (grepl("^Memo: To", prompt)) "Jane Doe, CFO" else ""
    },
    .header_helper_ask_yn = function(prompt, default = FALSE) {
      grepl("^Set Memo: To", prompt)
    }
  )

  fm <- .header_helper_collect("memo")
  expect_null(fm$title)
  expect_identical(fm$memo$to, "Jane Doe, CFO")
  expect_null(fm$memo$from)
})

test_that(".header_helper_collect('memo') drops an empty memo: block if every sub-field is declined", {
  local_mocked_bindings(
    .header_helper_ask = function(prompt) "",
    .header_helper_ask_yn = function(prompt, default = FALSE) FALSE
  )

  fm <- .header_helper_collect("memo")
  expect_null(fm$memo)
})

test_that(".header_helper_collect('report') -> .header_helper_render() output validates cleanly", {
  local_mocked_bindings(
    .header_helper_ask = function(prompt) {
      if (grepl("^Title \\(required\\)", prompt)) "Demo Report" else ""
    },
    .header_helper_ask_yn = function(prompt, default = FALSE) FALSE
  )
  fm <- .header_helper_collect("report")
  block <- .header_helper_render(fm)

  dir <- withr::local_tempdir()
  path <- file.path(dir, "report.qmd")
  writeLines(c(block, "", "Body."), path)
  writeLines(c("project:", "  output-dir: report/shell"), file.path(dir, "_quarto.yml"))

  res <- validate_header(path, quiet = TRUE)
  expect_true(res$ok)
})
