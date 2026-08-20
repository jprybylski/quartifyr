#' Sync reportifyr's config.yaml footnote styling to a quartifyr style YAML
#'
#' reportifyr doesn't read quartifyr's style YAML at all -- its own
#' `report/config.yaml` scaffolds `footnotes_font`/`footnotes_font_size`
#' independently (defaulting to "Arial Narrow"/10), so left untouched they
#' visually clash with whatever `fonts.body`/`fonts.sizes.footnote` a style
#' YAML sets for the rest of the document. This updates just those two
#' keys to match.
#'
#' Requires an interactive `y`/`yes` confirmation before writing unless
#' `yes = TRUE` is passed -- there's no live stdin to confirm over via this
#' R wrapper (it always calls the underlying CLI with `--json`, a
#' non-interactive/piped invocation), so `yes = TRUE` is required whenever
#' `config_yaml`'s footnote keys are actually out of sync; a call that
#' finds nothing to change succeeds either way.
#'
#' @param style Path to the base style YAML.
#' @param override Optional per-org/per-project style YAML, deep-merged over
#'   `style`. `NULL` (default) to skip.
#' @param config_yaml Path to reportifyr's `config.yaml`, modified in place.
#' @param yes Skip the confirmation requirement and write directly.
#' @return `TRUE` if `config_yaml` was changed, `FALSE` if it was already in
#'   sync (invisibly).
#' @export
styling_sync_reportifyr_config <- function(style, override = NULL, config_yaml = "report/config.yaml", yes = FALSE) {
  args <- c("sync-reportifyr-config", "--style", style)
  if (!is.null(override)) {
    args <- c(args, "--override", override)
  }
  args <- c(args, "--config", config_yaml)
  if (yes) {
    args <- c(args, "--yes")
  }
  result <- .run_quartifyr_styling_cli(args)
  invisible(isTRUE(result$changed))
}
