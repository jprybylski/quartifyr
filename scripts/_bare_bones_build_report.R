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
#' A separate .R file (not inlined `Rscript -e` string in the Python
#' caller) so paths pass through as plain command-line arguments instead
#' of being embedded into R source text, which would need careful
#' cross-platform quoting/escaping to be safe.
#'
#' Usage: Rscript _bare_bones_build_report.R <reportifyr_project_dir> <docx_in> <docx_out> <docx_final>

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4) {
  stop("usage: Rscript _bare_bones_build_report.R <reportifyr_project_dir> <docx_in> <docx_out> <docx_final>")
}
reportifyr_project_dir <- args[[1]]
docx_in <- args[[2]]
docx_out <- args[[3]]
docx_final <- args[[4]]

# setwd(), not withr::with_dir(), to avoid depending on withr being
# installed in whatever R environment runs this -- reportifyr/pyro
# locate their Python venv and project config by walking up from R's
# current working directory (see r/R/render_report.R's own comment on
# this), so this cwd change is only for their sake; the docx_* paths
# below are otherwise ordinary absolute paths, unrelated to it.
setwd(reportifyr_project_dir)

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
