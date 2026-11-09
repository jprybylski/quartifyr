test_that("styling_fit_tables() builds the right CLI args and returns the step's result", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "ok", path = "report.docx", fitted = 2L, shrunk = list(1L), overflowing = list())
    }
  )

  result <- styling_fit_tables("report.docx")

  expect_identical(captured_args, c("fit-tables", "--docx", "report.docx"))
  expect_identical(result$fitted, 2L)
  expect_identical(result$shrunk, list(1L))
})
