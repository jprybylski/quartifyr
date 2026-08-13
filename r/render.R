#!/usr/bin/env Rscript
# Thin CLI wrapper around render_report() (see R/render_report.R), so a
# report author runs one command instead of composing the Quarto render +
# reportifyr calls by hand.
#
# Usage: Rscript render.R <shell_qmd> [--final] [--toolkit-root PATH] [--reference-doc PATH]

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0 || any(args %in% c("-h", "--help"))) {
  cat(
    "Usage: Rscript render.R <shell_qmd> [--final] [--toolkit-root PATH] [--reference-doc PATH]\n\n",
    "  <shell_qmd>       Path to the shell .qmd (must live under report/shell/)\n",
    "  --final           Also produce report/final/ output (default: draft only)\n",
    "  --toolkit-root    Root of the quartifyr checkout (default: git repo root)\n",
    "  --reference-doc   Org docx reference-doc (default: <toolkit-root>/templates/org-reference.docx)\n",
    sep = ""
  )
  quit(status = if (length(args) == 0) 1 else 0)
}

shell_qmd <- NULL
status <- "draft"
toolkit_root <- NULL
reference_doc <- NULL

i <- 1
while (i <= length(args)) {
  arg <- args[[i]]
  if (arg == "--final") {
    status <- "final"
    i <- i + 1
  } else if (arg == "--toolkit-root") {
    if (i == length(args)) stop("--toolkit-root requires a value")
    toolkit_root <- args[[i + 1]]
    i <- i + 2
  } else if (arg == "--reference-doc") {
    if (i == length(args)) stop("--reference-doc requires a value")
    reference_doc <- args[[i + 1]]
    i <- i + 2
  } else if (!startsWith(arg, "--") && is.null(shell_qmd)) {
    shell_qmd <- arg
    i <- i + 1
  } else {
    stop("Unrecognized argument: ", arg, " (see --help)")
  }
}

if (is.null(shell_qmd)) {
  stop("shell_qmd is required. See --help.")
}

# Locate this script's own directory regardless of the caller's working
# directory, so `source()` below finds R/render_report.R reliably whether
# invoked as `Rscript render.R ...` from r/ or `Rscript r/render.R ...`
# from the repo root.
this_file <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
script_dir <- if (length(this_file) > 0) dirname(normalizePath(this_file)) else getwd()

source(file.path(script_dir, "R", "render_report.R"))

render_args <- list(shell_qmd = shell_qmd, status = status)
if (!is.null(toolkit_root)) {
  render_args$toolkit_root <- toolkit_root
}
if (!is.null(reference_doc)) {
  render_args$reference_doc <- reference_doc
}

result <- do.call(render_report, render_args)

cat("shell: ", result$shell, "\n", sep = "")
cat("draft: ", result$draft, "\n", sep = "")
if (!is.null(result$final)) {
  cat("final: ", result$final, "\n", sep = "")
}
