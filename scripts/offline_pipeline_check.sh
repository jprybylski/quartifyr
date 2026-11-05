#!/usr/bin/env bash
# Initializes and renders examples/demo-report with the network disabled.
#
# Meant to run inside a network-less namespace, after the project has been
# provisioned while online (renv library, reportifyr's and quartifyr's Python
# environments, so uv's cache holds the wheels) -- see the `offline-pipeline`
# job in .github/workflows/ci.yml, which wraps this in `unshare --net` and
# gives it a fresh, empty HOME. Run it by hand the same way on Linux:
#
#   sudo -E unshare --net -- setpriv --reuid="$(id -u)" --regid="$(id -g)" \
#     --init-groups env PATH="$PATH" HOME="$(mktemp -d)" bash scripts/offline_pipeline_check.sh
#
# Fails if the network is reachable (so it can't pass vacuously), if any
# step needs it, or if anything lands in $HOME/.local/bin (where pyro's
# uv_setup.sh would curl-install uv).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root/examples/demo-report"

if curl --silent --head --max-time 5 https://pypi.org >/dev/null 2>&1; then
  echo "error: the network is reachable; this check only means something without it" >&2
  exit 1
fi

# Fresh HOME, so reportifyr's git-identity lookup needs one.
git config --global user.name "quartifyr offline CI"
git config --global user.email "quartifyr-ci@users.noreply.github.com"

# uv: no index access, and no managed-Python downloads.
export UV_OFFLINE=1 UV_PYTHON_DOWNLOADS=never

# Drop the committed example's copy of quarto-plus so what follows proves the
# bundled one installs.
rm -rf _extensions/A2-ai

echo "== initialize_quartifyr_project(), offline, with bundled extensions"
Rscript -e 'quartifyr::initialize_quartifyr_project(getwd(), install_extensions = TRUE)'
test -f _extensions/A2-ai/quarto-plus/_extension.yml
test -f _extensions/A2-ai/quarto-plus/LICENSE

echo "== check_report_project()"
Rscript -e 'f <- quartifyr::check_report_project("report.qmd"); print(f); stopifnot(!any(f$severity == "error"))'

echo "== render (noninteractive script, strict)"
script="$(Rscript -e 'cat(system.file("scripts", "render.R", package = "quartifyr"))')"
result="$(mktemp)"
Rscript "$script" --project . --shell report.qmd --status final --json --strict > "$result"
cat "$result"
Rscript -e 'r <- jsonlite::fromJSON(commandArgs(TRUE)[[1]]); stopifnot(identical(r$status, "ok"), file.exists(r$final))' "$result"

echo "== same again through a pre-provisioned python_env (no pyro, no uv)"
env_dir="$PWD/.venv"
Rscript -e 'quartifyr::initialize_quartifyr_project(getwd(), python_env = commandArgs(TRUE)[[1]])' "$env_dir"
QUARTIFYR_PYTHON_ENV="$env_dir" Rscript "$script" --project . --shell report.qmd --status draft --json --strict > "$result"
Rscript -e 'r <- jsonlite::fromJSON(commandArgs(TRUE)[[1]]); stopifnot(identical(r$status, "ok"))' "$result"

if [ -e "$HOME/.local/bin" ]; then
  echo "error: something wrote to $HOME/.local/bin:" >&2
  ls -la "$HOME/.local/bin" >&2
  exit 1
fi
echo "offline init + render OK"
