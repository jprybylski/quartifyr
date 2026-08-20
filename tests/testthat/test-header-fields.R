test_that(".header_field_get() reads nested and missing paths", {
  fm <- list(memo = list(to = "Jane"), title = "Report")
  expect_identical(.header_field_get(fm, "title"), "Report")
  expect_identical(.header_field_get(fm, c("memo", "to")), "Jane")
  expect_null(.header_field_get(fm, c("memo", "from")))
  expect_null(.header_field_get(fm, c("nope", "still-nope")))
  expect_null(.header_field_get(list(), "title"))
})

test_that("every field spec has the expected shape", {
  fields <- .quartifyr_header_fields()
  expect_gt(length(fields), 0)

  keys <- vapply(fields, `[[`, character(1), "key")
  expect_false(anyDuplicated(keys) > 0)

  for (f in fields) {
    expect_type(f$key, "character")
    expect_type(f$label, "character")
    expect_type(f$section, "character")
    expect_type(f$description, "character")
    expect_true(nzchar(f$description))
    expect_true(is.function(f$applies_when))
    expect_true(is.function(f$required))
    expect_true(is.function(f$recommended))
    expect_true(f$kind %in% c("scalar", "structured", "fixed"))
    # Every predicate must tolerate an empty frontmatter without erroring.
    expect_type(f$applies_when(list()), "logical")
    expect_type(f$required(list()), "logical")
    expect_type(f$recommended(list()), "logical")
  }
})

test_that("title is required only when memo: is absent", {
  fields <- .quartifyr_header_fields()
  title <- Filter(function(f) f$key == "title", fields)[[1]]
  expect_true(title$required(list()))
  expect_false(title$required(list(memo = list(to = "x"))))
})

test_that("memo sub-fields only apply once memo: is set", {
  fields <- .quartifyr_header_fields()
  memo_to <- Filter(function(f) f$key == "memo.to", fields)[[1]]
  expect_false(memo_to$applies_when(list()))
  expect_true(memo_to$applies_when(list(memo = list())))
})

test_that("signature-note is required only when signature-mode is note", {
  fields <- .quartifyr_header_fields()
  note <- Filter(function(f) f$key == "signature-note", fields)[[1]]
  expect_false(note$required(list()))
  expect_false(note$required(list(`signature-mode` = "line")))
  expect_true(note$required(list(`signature-mode` = "note")))
})
