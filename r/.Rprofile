options(repos = c(
  "a2-ai" = "https://a2-ai.r-universe.dev",
  CRAN = "https://cloud.r-project.org"
))
# R's default 60s download timeout is tight for slow/proxied links and has
# been observed causing curl error 28 against a2-ai.r-universe.dev.
options(timeout = max(600, getOption("timeout")))
source("renv/activate.R")
