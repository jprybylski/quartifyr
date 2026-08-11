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

pk_summary <- aggregate(
  conc ~ Subject,
  data = Theoph,
  FUN = function(x) c(Cmax = max(x), Cmin = min(x), Cavg = mean(x))
)
pk_summary <- data.frame(
  Subject = pk_summary$Subject,
  round(pk_summary$conc, 2)
)

write_csv_with_metadata(
  object = pk_summary,
  file = file.path("OUTPUTS", "tables", "pk-summary.csv"),
  config_yaml = config_yaml,
  row.names = FALSE
)

figures_path <- file.path("OUTPUTS", "figures")
plot_file <- file.path(figures_path, "conc-time.png")

g <- ggplot(Theoph, aes(x = Time, y = conc, group = Subject)) +
  geom_line(alpha = 0.6) +
  geom_point(size = 1) +
  labs(x = "Time (h)", y = "Concentration (mg/L)") +
  theme_bw()

ggsave_with_metadata(
  filename = plot_file,
  plot = g,
  width = 6,
  height = 4,
  config_yaml = config_yaml
)

cat("Wrote:\n")
cat(" -", file.path("OUTPUTS", "tables", "pk-summary.csv"), "\n")
cat(" -", plot_file, "\n")
