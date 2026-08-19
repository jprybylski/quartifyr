#' Deep-merge an update onto an existing style YAML, in place
#'
#' A `modifyList()`-style edit of one section of a style YAML (issue
#' #27), without hand-copying the rest of the file.
#'
#' Requires `yes = TRUE`: there's no live stdin to confirm over via this R
#' wrapper (it always calls the underlying CLI with `--json`, a
#' non-interactive/piped invocation, same as [styling_sync_reportifyr_config()]),
#' and this always has *something* to change (unlike that function, which
#' can no-op) -- passing `yes = TRUE` is this function's explicit
#' acknowledgement that rewriting the file via `yaml.safe_dump` drops any
#' comments/formatting it had.
#'
#' @param updates A (possibly nested) list of the values to change, e.g.
#'   `list(heading = list(all_caps = TRUE))`.
#' @param file The style YAML to update, in place.
#' @param yes Must be `TRUE` to actually write -- see above.
#' @return The style YAML's full merged content, as a nested list
#'   (invisibly).
#' @export
styling_update_style <- function(updates, file, yes = FALSE) {
  if (!isTRUE(yes)) {
    stop(
      "styling_update_style() overwrites `file` and drops any comments/formatting it had -- ",
      "pass yes = TRUE to confirm and proceed.",
      call. = FALSE
    )
  }
  updates_json <- withr::local_tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(updates, auto_unbox = TRUE, null = "null"), updates_json)

  result <- .run_quartifyr_styling_cli(c("update-style", "--file", file, "--updates-json", updates_json, "--yes"))
  invisible(result$style)
}
