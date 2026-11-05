#!/usr/bin/env Rscript
# Noninteractive entry point for quartifyr::render_report(), for CI, scripts
# and background jobs. Prints the result as JSON on stdout (with --json),
# everything else on stderr, and exits non-zero on any error (or, with
# --strict, on any result whose status is not "ok").
#
# Run it with the report project as the working directory, so the project's
# renv library (quartifyr, reportifyr, pyro) activates:
#
#   cd path/to/project
#   Rscript "$(Rscript -e 'cat(system.file("scripts", "render.R", package = "quartifyr"))')" \
#     --project . --shell report.qmd --status draft --json --strict
#
# Run with --help for all options. The JSON shape is documented in
# inst/schemas/render-result-v1.schema.json.
quit(status = quartifyr:::.render_cli(commandArgs(trailingOnly = TRUE)), save = "no")
