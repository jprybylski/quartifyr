test_that("styling_build_abbreviations_tex() builds the right CLI args and returns the path", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "success", path = "abbreviations.tex")
    }
  )

  result <- styling_build_abbreviations_tex("standard_footnotes.yaml", out = "abbreviations.tex")

  expect_identical(
    captured_args,
    c("abbrevs", "--footnotes", "standard_footnotes.yaml", "--out", "abbreviations.tex")
  )
  expect_identical(result, "abbreviations.tex")
})

test_that("styling_build_abbreviations_tex() defaults out to abbreviations.tex", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "success", path = "abbreviations.tex")
    }
  )

  styling_build_abbreviations_tex("standard_footnotes.yaml")

  expect_identical(captured_args[length(captured_args)], "abbreviations.tex")
})

test_that("styling_build_abbreviations_tex() returns its result invisibly", {
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) list(status = "success", path = "abbreviations.tex")
  )

  expect_invisible(styling_build_abbreviations_tex("standard_footnotes.yaml"))
})
