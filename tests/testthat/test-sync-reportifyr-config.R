test_that("styling_sync_reportifyr_config() omits --override and --yes when not supplied", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "ok", changed = TRUE)
    }
  )

  result <- styling_sync_reportifyr_config("style.yaml")

  expect_identical(
    captured_args,
    c("sync-reportifyr-config", "--style", "style.yaml", "--config", "report/config.yaml")
  )
  expect_true(result)
})

test_that("styling_sync_reportifyr_config() includes --override when supplied", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "ok", changed = TRUE)
    }
  )

  styling_sync_reportifyr_config("style.yaml", override = "acme.yaml")

  expect_identical(
    captured_args,
    c("sync-reportifyr-config", "--style", "style.yaml", "--override", "acme.yaml", "--config", "report/config.yaml")
  )
})

test_that("styling_sync_reportifyr_config() uses config_yaml and --yes when supplied", {
  captured_args <- NULL
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) {
      captured_args <<- args
      list(status = "ok", changed = TRUE)
    }
  )

  styling_sync_reportifyr_config("style.yaml", config_yaml = "custom/config.yaml", yes = TRUE)

  expect_identical(
    captured_args,
    c("sync-reportifyr-config", "--style", "style.yaml", "--config", "custom/config.yaml", "--yes")
  )
})

test_that("styling_sync_reportifyr_config() returns FALSE when already in sync", {
  local_mocked_bindings(
    .run_quartifyr_styling_cli = function(args) list(status = "ok", changed = FALSE)
  )

  result <- styling_sync_reportifyr_config("style.yaml")

  expect_false(result)
})
