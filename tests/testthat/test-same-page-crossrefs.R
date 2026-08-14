test_that("styling_resolve_same_page_crossrefs() builds the right CLI args, coercing timeout to an integer string", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "success", path = "report.docx")
    }
  )

  result <- styling_resolve_same_page_crossrefs("report.docx", timeout = 45.2)

  expect_identical(
    captured_args,
    c("resolve-same-page-crossrefs", "--docx", "report.docx", "--timeout", "45")
  )
  expect_identical(result, "report.docx")
})

test_that("styling_resolve_same_page_crossrefs() defaults timeout to 120", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "success", path = "report.docx")
    }
  )

  styling_resolve_same_page_crossrefs("report.docx")

  expect_identical(captured_args[length(captured_args)], "120")
})
