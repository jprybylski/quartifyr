test_that("styling_apply_layout() builds the right CLI args and returns the docx path", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "success", path = "report.docx")
    }
  )

  result <- styling_apply_layout("report.docx", "report.qmd", status = "draft")

  expect_identical(
    captured_args,
    c("apply-layout", "--docx", "report.docx", "--qmd", "report.qmd", "--status", "draft")
  )
  expect_identical(result, "report.docx")
})

test_that("styling_apply_layout() passes status through unchanged", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "success", path = "report.docx")
    }
  )

  styling_apply_layout("report.docx", "report.qmd", status = "final")

  expect_identical(captured_args[length(captured_args)], "final")
})
