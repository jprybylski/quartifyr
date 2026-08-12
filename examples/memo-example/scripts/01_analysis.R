# Generates this memo's one artifact: a simple timeline figure of the
# proposed Q3 budget review milestones (see report.qmd's "Proposed
# Schedule" section for the same dates in prose/list form). Run from
# this project's root (examples/memo-example/), e.g.:
#
#   cd examples/memo-example && Rscript scripts/01_analysis.R

library(reportifyr)
library(ggplot2)

stopifnot(basename(getwd()) == "memo-example")

config_yaml <- file.path("report", "config.yaml")

milestones <- data.frame(
  milestone = factor(
    c("Submissions Due", "Committee Review", "Consolidated Review", "Final Sign-off"),
    levels = rev(c("Submissions Due", "Committee Review", "Consolidated Review", "Final Sign-off"))
  ),
  start = as.Date(c("2026-08-21", "2026-08-24", "2026-09-02", "2026-09-09")),
  end = as.Date(c("2026-08-21", "2026-08-28", "2026-09-02", "2026-09-09"))
)

figures_path <- file.path("OUTPUTS", "figures")
plot_file <- file.path(figures_path, "budget-timeline.png")

# geom_segment alone would leave the three single-day milestones (where
# start == end) invisible -- a zero-length segment has nothing to draw,
# even with a round line cap. Layering points at both ends on top covers
# both cases: a dot for single-day milestones, dot-bar-dot for the
# multi-day Committee Review window.
g <- ggplot(milestones, aes(y = milestone)) +
  geom_segment(aes(x = start, xend = end, yend = milestone), linewidth = 6, color = "#4472C4", lineend = "round") +
  geom_point(aes(x = start), size = 4, color = "#4472C4") +
  geom_point(aes(x = end), size = 4, color = "#4472C4") +
  labs(x = NULL, y = NULL) +
  theme_bw()

ggsave_with_metadata(
  filename = plot_file,
  plot = g,
  width = 6,
  height = 3,
  config_yaml = config_yaml,
  meta_notes = "Proposed Q3 budget review milestones."
)

cat("Wrote:\n")
cat(" -", plot_file, "\n")
