#!/usr/bin/env Rscript
# Renders this demo project end to end via the quartifyr R package.
#
# Usage: Rscript render.R [--final]
#
# Run from anywhere -- this script locates its own directory regardless of
# the caller's working directory. Requires the quartifyr package installed
# (see the repo-root README's Quick Start).

args <- commandArgs(trailingOnly = TRUE)
status <- if ("--final" %in% args) "final" else "draft"

this_file <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
project_dir <- if (length(this_file) > 0) dirname(normalizePath(this_file)) else getwd()

library(quartifyr)

result <- render_report(
  shell_qmd = file.path(project_dir, "report.qmd"),
  status = status
)

cat("shell: ", result$shell, "\n", sep = "")
cat("draft: ", result$draft, "\n", sep = "")
if (!is.null(result$final)) {
  cat("final: ", result$final, "\n", sep = "")
}
