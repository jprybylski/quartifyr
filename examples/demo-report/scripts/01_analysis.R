# Generates the demo report's artifacts: a PK parameter summary table, a
# wide (14-column) NCA parameter table, a participant demographics table,
# and a concentration-time figure, using
# base R's built-in Theoph dataset (the same one reportifyr's own README/
# examples use). Run from this project's root (examples/demo-report/), e.g.:
#
#   cd examples/demo-report && Rscript scripts/01_analysis.R

library(reportifyr)
library(ggplot2)
library(flextable)
library(officer)

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
  meta_notes = "Values are per-participant summary statistics computed directly from observed concentrations; no imputation or model-based estimation was performed. This table is filled from a plain data frame, so reportifyr renders it in its own default table styling (Arial Narrow) rather than this report's own body font -- contrast with the participant demographics table below, filled from a pre-styled flextable object.",
  meta_abbrevs = "PK",
  row.names = FALSE
)

# A deliberately wide table (14 columns, long header words like "Accumulation"
# next to short ones like "Kel"): the case reportifyr's own fixed 6-inch fit
# handles badly, and what render_report()'s table-fitting step and the
# {{< landscape >}} section in report.qmd exist for. Per-participant
# non-compartmental parameters from the same Theoph data; the terminal
# slope comes from the last three observations, so Kel/half-life/AUCinf
# are rough, which is fine for a layout demonstration. Column names avoid
# spaces and symbols: reportifyr reads the CSV back with read.csv()'s default
# check.names = TRUE, which would turn "Dose (mg)" into "Dose..mg.".
nca_one <- function(d) {
  d <- d[order(d$Time), ]
  auc_last <- sum(diff(d$Time) * (head(d$conc, -1) + tail(d$conc, -1)) / 2)
  tail_n <- tail(seq_len(nrow(d)), 3)
  kel <- -unname(coef(lm(log(conc) ~ Time, data = d[tail_n, ]))[2])
  auc_inf <- auc_last + tail(d$conc, 1) / kel
  dose_mg <- unique(d$Dose) * unique(d$Wt)
  cl_f <- dose_mg / auc_inf
  aumc <- sum(diff(d$Time) * (head(d$Time * d$conc, -1) + tail(d$Time * d$conc, -1)) / 2)
  data.frame(
    Participant = as.character(unique(d$Participant)),
    Dose = dose_mg,
    Cmax = max(d$conc),
    Tmax = d$Time[which.max(d$conc)],
    Cmin = min(d$conc),
    Cavg = auc_last / max(d$Time),
    AUClast = auc_last,
    AUCinf = auc_inf,
    Kel = kel,
    Half_life = log(2) / kel,
    CL_F = cl_f,
    V_F = cl_f / kel,
    MRT = aumc / auc_last,
    Accumulation = 1 / (1 - exp(-kel * 12)),
    check.names = FALSE
  )
}
nca_parameters <- do.call(rbind, lapply(split(theoph, theoph$Participant), nca_one))
nca_parameters[-1] <- lapply(nca_parameters[-1], function(x) signif(x, 3))
nca_parameters <- nca_parameters[order(as.numeric(nca_parameters$Participant)), ]

write_csv_with_metadata(
  object = nca_parameters,
  file = file.path("OUTPUTS", "tables", "nca-parameters.csv"),
  config_yaml = config_yaml,
  meta_notes = "Non-compartmental parameters per participant (dose in mg, CL_F in L/h, V_F in L, times in h); the terminal slope is estimated from the last three observations, so Kel, half-life and AUCinf are approximate. Fourteen columns, shown on a landscape page.",
  meta_abbrevs = "PK",
  row.names = FALSE
)

# A second table, complementing pk_summary above to show reportifyr's two
# ways of filling an rpfy-prefixed table magic string: a plain data frame
# (.csv, above) vs. a pre-built `flextable` object (.rds, here). This matters
# because reportifyr::add_tables() (process_table_file(), R/add_tables.R)
# only runs its own formatting -- format_flextable(), which hardcodes
# Arial Narrow 10pt borders/spacing regardless of the reference-doc's
# actual body font -- on objects that AREN'T already `flextable`s; an
# .rds that already `inherits(data_in, "flextable")` when read back is
# inserted completely as-is, untouched. So pk_summary above (a plain data
# frame) always renders in reportifyr's hardcoded Arial Narrow 10pt no
# matter what this doc's reference-doc sets fonts.body to (Times New
# Roman here, per inst/python/styles/default.yaml -- see report/config.yaml's
# footnotes_font comment for the same clash affecting table *footnotes*,
# fixed there but not fixable for a plain data frame's own table body).
# Building a flextable by hand, styled to match those same values, is the
# only way to escape that -- demonstrated below.
theoph_demographics <- unique(theoph[, c("Participant", "Wt", "Dose")])
theoph_demographics <- theoph_demographics[
  order(as.numeric(as.character(theoph_demographics$Participant))),
]
names(theoph_demographics) <- c("Participant", "Weight (kg)", "Dose (mg/kg)")

demographics_ft <- flextable(theoph_demographics) |>
  set_table_properties(layout = "autofit", width = 1) |>
  align(align = "left", part = "all") |>
  bold(bold = TRUE, part = "header") |>
  bg(bg = "#D9D9D9", part = "header") |>
  border(border = fp_border(color = "#000000"), part = "all") |>
  font(fontname = "Times New Roman", part = "all") |>
  fontsize(size = 11, part = "all") |>
  line_spacing(space = 1.15, part = "all") |>
  padding(padding.bottom = 2, padding.top = 2, part = "all")

save_rds_with_metadata(
  object = demographics_ft,
  file = file.path("OUTPUTS", "tables", "participant-demographics.rds"),
  config_yaml = config_yaml,
  meta_notes = "Body weight and weight-normalized dose for each participant. Unlike the PK summary table above, this table is filled from a pre-built, hand-styled flextable object rather than a plain data frame, so it renders in this report's own reference-doc font (Times New Roman) instead of reportifyr's default table styling."
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
# config.yaml knob controls it): the *first* rpfy-prefixed occurrence of a
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
cat(" -", file.path("OUTPUTS", "tables", "nca-parameters.csv"), "\n")
cat(" -", file.path("OUTPUTS", "tables", "participant-demographics.rds"), "\n")
cat(" -", plot_file, "\n")
cat(" -", synopsis_plot_file, "\n")
