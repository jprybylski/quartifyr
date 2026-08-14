# Adds a2-ai.r-universe.dev (pyro/reportifyr's home -- neither is on CRAN)
# to the effective repos list for any R session started from the repo root,
# including CI's `Rscript {0}` steps.
#
# This is the *actual* fix for pyro/reportifyr dependency resolution, per
# ../deckifyr's own hard-won .Rprofile comment (confirmed there the hard
# way): DESCRIPTION's `Additional_repositories:` field looks like the right
# mechanism (it's what CRAN policy and tools like `remotes::install_deps()`
# use for exactly this case) and is kept there for those tools, but it does
# NOT make `pak`'s dependency solve see the repo -- only `options(repos=)`
# does, which only happens via something like this .Rprofile (or an
# explicit `options()` call).
options(repos = c(a2ai = "https://a2-ai.r-universe.dev", getOption("repos")))
