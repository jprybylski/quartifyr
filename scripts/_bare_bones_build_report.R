#!/usr/bin/env Rscript
#' Helper for scripts/bare_bones_integration_test.py.
#'
#' Calls reportifyr::build_report() then reportifyr::finalize_document()
#' directly, with explicit docx_in/docx_out/docx_final paths that have
#' nothing to do with the calling reportifyr project's own directory
#' layout -- proving those functions don't care where the paths live,
#' unlike render_report()'s own make_doc_dirs()-derived
#' report/shell//report/draft//report/final convention. finalize_document()
#' is what actually strips the {rpfy}: magic strings/bookmarks -- a
#' build_report()-only draft legitimately still has them, by reportifyr's
#' own design, not a quartifyr bug.
#'
#' MUST be launched with the reportifyr project directory as the actual
#' process working directory (e.g. subprocess.run(..., cwd=...) on the
#' Python side), not just setwd() from within this script after the fact:
#' rv-managed projects activate their local package library via an
#' .Rprofile that only runs at R startup, based on the directory R was
#' launched from -- a setwd() partway through this script would be too
#' late, and reportifyr wouldn't be found on the library path (confirmed
#' via a real CI failure: "there is no package called 'reportifyr'").
#' reportifyr/pyro also locate their Python venv and project config by
#' walking up from R's current working directory (see
#' r/R/render_report.R's own comment on this), which this satisfies too.
#'
#' A separate .R file (not inlined `Rscript -e` string in the Python
#' caller) so paths pass through as plain command-line arguments instead
#' of being embedded into R source text, which would need careful
#' cross-platform quoting/escaping to be safe.
#'
#' Usage: Rscript _bare_bones_build_report.R <docx_in> <docx_out> <docx_final>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) {
  stop("usage: Rscript _bare_bones_build_report.R <docx_in> <docx_out> <docx_final>")
}
docx_in <- args[[1]]
docx_out <- args[[2]]
docx_final <- args[[3]]

reportifyr::build_report(
  docx_in = docx_in,
  docx_out = docx_out,
  figures_path = "OUTPUTS/figures",
  tables_path = "OUTPUTS/tables",
  standard_footnotes_yaml = "report/standard_footnotes.yaml",
  config_yaml = "report/config.yaml"
)

reportifyr::finalize_document(
  docx_in = docx_out,
  docx_out = docx_final,
  config_yaml = "report/config.yaml"
)
