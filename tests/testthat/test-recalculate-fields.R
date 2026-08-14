test_that("styling_recalculate_fields() builds the right CLI args, coercing timeout to an integer string", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "success", path = "report.docx")
    }
  )

  result <- styling_recalculate_fields("report.docx", timeout = 90.7)

  expect_identical(
    captured_args,
    c("recalculate-fields", "--docx", "report.docx", "--timeout", "90")
  )
  expect_identical(result, "report.docx")
})

test_that("styling_recalculate_fields() defaults timeout to 120", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "success", path = "report.docx")
    }
  )

  styling_recalculate_fields("report.docx")

  expect_identical(captured_args[length(captured_args)], "120")
})
