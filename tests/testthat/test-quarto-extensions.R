# --- quartifyr_quarto_extensions registry -----------------------------------

test_that("quartifyr_quarto_extensions has the expected shape", {
  expect_s3_class(quartifyr_quarto_extensions, "data.frame")
  expect_setequal(names(quartifyr_quarto_extensions), c("id", "required", "reason"))
  expect_true("A2-ai/quarto-plus" %in% quartifyr_quarto_extensions$id)
  expect_true(quartifyr_quarto_extensions$required[quartifyr_quarto_extensions$id == "A2-ai/quarto-plus"])
})

# --- check_quarto_extensions() ----------------------------------------------

test_that("passes silently when every required extension is installed", {
  local_mocked_bindings(
    quarto_list_extensions = function() {
      data.frame(Id = "A2-ai/quarto-plus", Version = "1.0", Contributes = "filters", stringsAsFactors = FALSE)
    },
    .package = "quarto"
  )

  result <- check_quarto_extensions(withr::local_tempdir())

  expect_true(result$installed[result$id == "A2-ai/quarto-plus"])
})

test_that("errors by default when a required extension is missing", {
  local_mocked_bindings(
    quarto_list_extensions = function() data.frame(),
    .package = "quarto"
  )

  expect_error(
    check_quarto_extensions(withr::local_tempdir()),
    "Required Quarto extension"
  )
})

test_that("only warns for a missing required extension when error = FALSE", {
  local_mocked_bindings(
    quarto_list_extensions = function() data.frame(),
    .package = "quarto"
  )

  expect_warning(
    result <- check_quarto_extensions(withr::local_tempdir(), error = FALSE),
    "Required Quarto extension"
  )
  expect_false(result$installed[result$id == "A2-ai/quarto-plus"])
})

test_that("a missing optional extension always warns, never errors, regardless of `error`", {
  local_mocked_bindings(
    quarto_list_extensions = function() {
      data.frame(Id = "A2-ai/quarto-plus", Version = "1.0", Contributes = "filters", stringsAsFactors = FALSE)
    },
    .package = "quarto"
  )
  extra <- rbind(
    quartifyr_quarto_extensions,
    data.frame(id = "someorg/nice-to-have", required = FALSE, reason = "optional", stringsAsFactors = FALSE)
  )

  expect_warning(
    result <- check_quarto_extensions(withr::local_tempdir(), extensions = extra, error = TRUE),
    "Suggested Quarto extension"
  )
  expect_false(result$installed[result$id == "someorg/nice-to-have"])
  expect_true(result$installed[result$id == "A2-ai/quarto-plus"])
})

test_that("finds an installed extension even when read.table's column-shift bug hides its id in a rowname", {
  # Reproduces the documented quarto_list_extensions() parsing gotcha: a
  # Contributes value with an embedded space ("filters, shortcodes") makes
  # read.table() treat the id as a row name instead of the Id column,
  # shifting Version/Contributes left. check_quarto_extensions() must still
  # find the extension by searching row names too.
  shifted <- data.frame(Id = "filters, shortcodes", Version = "1.0", stringsAsFactors = FALSE)
  rownames(shifted) <- "A2-ai/quarto-plus"

  local_mocked_bindings(
    quarto_list_extensions = function() shifted,
    .package = "quarto"
  )

  result <- check_quarto_extensions(withr::local_tempdir())

  expect_true(result$installed[result$id == "A2-ai/quarto-plus"])
})

test_that("re-raises a quarto_list_extensions() CLI failure with an actionable message", {
  local_mocked_bindings(
    quarto_list_extensions = function() {
      stop("Uncaught (in promise) Error: Include directive failed.\ncould not find file scripts/01_analysis.R")
    },
    .package = "quarto"
  )

  expect_error(
    check_quarto_extensions(withr::local_tempdir()),
    "Quarto CLI failed while listing extensions"
  )
})

test_that("matches on the short id (owner/repo suffix) too", {
  local_mocked_bindings(
    quarto_list_extensions = function() {
      data.frame(Id = "quarto-plus", Version = "1.0", stringsAsFactors = FALSE)
    },
    .package = "quarto"
  )

  result <- check_quarto_extensions(withr::local_tempdir())

  expect_true(result$installed[result$id == "A2-ai/quarto-plus"])
})
