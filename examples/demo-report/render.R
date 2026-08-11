#!/usr/bin/env Rscript
# Renders this demo project end to end via quartifyr's orchestration driver.
#
# Usage: Rscript render.R [--final]
#
# Run from anywhere -- this script locates its own directory and the
# toolkit root regardless of the caller's working directory.

args <- commandArgs(trailingOnly = TRUE)
status <- if ("--final" %in% args) "final" else "draft"

this_file <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
project_dir <- if (length(this_file) > 0) dirname(normalizePath(this_file)) else getwd()
toolkit_root <- normalizePath(file.path(project_dir, "..", ".."))

source(file.path(toolkit_root, "r", "R", "render_report.R"))

result <- render_report(
  shell_qmd = file.path(project_dir, "report", "shell", "report.qmd"),
  status = status,
  toolkit_root = toolkit_root
)

cat("shell: ", result$shell, "\n", sep = "")
cat("draft: ", result$draft, "\n", sep = "")
if (!is.null(result$final)) {
  cat("final: ", result$final, "\n", sep = "")
}
