test_that("styling_build_reference_docx() omits --override when not supplied", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "success", path = "templates/org-reference.docx")
    }
  )

  result <- styling_build_reference_docx("style.yaml")

  expect_identical(
    captured_args,
    c("build", "--style", "style.yaml", "--out", "templates/org-reference.docx")
  )
  expect_identical(result, "templates/org-reference.docx")
})

test_that("styling_build_reference_docx() includes --override when supplied", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "success", path = "out.docx")
    }
  )

  styling_build_reference_docx("style.yaml", override = "acme.yaml", out = "out.docx")

  expect_identical(
    captured_args,
    c("build", "--style", "style.yaml", "--override", "acme.yaml", "--out", "out.docx")
  )
})
