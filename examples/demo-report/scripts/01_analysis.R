# Generates the demo report's artifacts: a PK parameter summary table and a
# concentration-time figure, using base R's built-in Theoph dataset (the
# same one reportifyr's own README/examples use). Run from this project's
# root (examples/demo-report/), e.g.:
#
#   cd examples/demo-report && Rscript scripts/01_analysis.R

library(reportifyr)
library(ggplot2)

stopifnot(basename(getwd()) == "demo-report")

config_yaml <- file.path("report", "config.yaml")

# Theoph's own column is "Subject" -- renamed to "Participant" to match
# current org convention before it reaches any output.
theoph <- Theoph
names(theoph)[names(theoph) == "Subject"] <- "Participant"

pk_summary <- aggregate(
  conc ~ Participant,
  data = theoph,
  FUN = function(x) c(Cmax = max(x), Cmin = min(x), Cavg = mean(x))
)
pk_summary <- data.frame(
  Participant = pk_summary$Participant,
  round(pk_summary$conc, 2)
)

# meta_abbrevs entries are keys looked up in report/standard_footnotes.yaml's
# abbreviations: section (reportifyr errors if a key isn't defined there) --
# free text goes in meta_notes instead. meta_type works the same way against
# that file's table_footnotes:/figure_footnotes: sections, for a canned
# methodology blurb; left unset here since none of the existing table_footnotes
# entries (regression/covariate-model writeups) fit a plain summary table.
write_csv_with_metadata(
  object = pk_summary,
  file = file.path("OUTPUTS", "tables", "pk-summary.csv"),
  config_yaml = config_yaml,
  meta_notes = "Values are per-participant summary statistics computed directly from observed concentrations; no imputation or model-based estimation was performed.",
  meta_abbrevs = "PK",
  row.names = FALSE
)

figures_path <- file.path("OUTPUTS", "figures")
plot_file <- file.path(figures_path, "conc-time.png")

g <- ggplot(theoph, aes(x = Time, y = conc, group = Participant)) +
  geom_line(alpha = 0.6) +
  geom_point(size = 1) +
  labs(x = "Time (h)", y = "Concentration (mg/L)") +
  theme_bw()

# meta_type = "conc-time-trajectories" pulls report/standard_footnotes.yaml's
# existing canned figure_footnotes entry for this exact plot type; meta_notes
# adds a dataset-specific note on top of it.
ggsave_with_metadata(
  filename = plot_file,
  plot = g,
  width = 6,
  height = 4,
  config_yaml = config_yaml,
  meta_type = "conc-time-trajectories",
  meta_notes = "Data are from the built-in Theoph dataset.",
  meta_abbrevs = "PK"
)

# reportifyr's own add_figure_footnotes() dedupes footnotes by filename
# document-wide (a bookmark-name xpath check, unconditional -- no
# config.yaml knob controls it): the *first* `{rpfy}:` occurrence of a
# given filename gets the metadata footnote and every later occurrence of
# that same filename is silently skipped. The synopsis intentionally
# embeds the same plot as a preview ahead of the numbered Figure 1 in the
# body (see report.qmd), so it needs its own copy under a distinct
# filename -- otherwise the synopsis preview would claim the footnote and
# leave the numbered, List-of-Figures-tracked Figure 1 without one.
synopsis_plot_file <- file.path(figures_path, "conc-time-synopsis.png")

ggsave_with_metadata(
  filename = synopsis_plot_file,
  plot = g,
  width = 6,
  height = 4,
  config_yaml = config_yaml,
  meta_type = "conc-time-trajectories",
  meta_notes = "Synopsis preview of the concentration-time profile shown in full as Figure 1.",
  meta_abbrevs = "PK"
)

cat("Wrote:\n")
cat(" -", file.path("OUTPUTS", "tables", "pk-summary.csv"), "\n")
cat(" -", plot_file, "\n")
cat(" -", synopsis_plot_file, "\n")
