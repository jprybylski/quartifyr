#!/usr/bin/env Rscript
# Noninteractive entry point for quartifyr::check_report_project(): a
# render-free preflight for CI, scripts and launchers. With --json it prints
# {schema_version, findings[{check, severity, path, message}]} on stdout.
# Exits 0 when there are no error findings, 1 when there are, 2 on bad usage.
#
# Run it with the report project as the working directory, as for render.R:
#
#   cd path/to/project
#   Rscript "$(Rscript -e 'cat(system.file("scripts", "check.R", package = "quartifyr"))')" \
#     --project . --shell report.qmd --json
#
# The JSON shape is documented in inst/schemas/check-result-v1.schema.json.
quit(status = quartifyr:::.check_cli(commandArgs(trailingOnly = TRUE)), save = "no")
