# Bundled Quarto extensions

| Directory | What it is | Installed to |
| --- | --- | --- |
| `quartifyr/` | quartifyr's own extension (this repository's code) | `_extensions/quartifyr/` via `install_quartifyr_extension()` |
| `quarto-plus/` | A copy of [A2-ai/quarto-plus](https://github.com/A2-ai/quarto-plus), which quartifyr's filters layer on top of | `_extensions/A2-ai/quarto-plus/` via `install_quarto_extensions()` |

## quarto-plus: provenance and licence

`quarto-plus/` is an unmodified copy of the `_extensions/quarto-plus/`
directory of A2-ai/quarto-plus at commit
`be6ac444a1c8b4cde6f980459c1670b3da720115` (2026-03-27). It is bundled so a
project can be set up with no network access (`quarto add` fetches from
GitHub).

The upstream repository is MIT-licensed (Copyright (c) 2024 Posit Software,
PBC). MIT permits redistribution, including inside a GPL-3-or-later package,
provided the copyright and permission notice stay with the copy, so the
upstream `LICENSE` is kept inside `quarto-plus/` and travels with it into each
project's `_extensions/A2-ai/quarto-plus/`.

To update the copy, replace the files from a newer upstream commit, update the
commit above, and run `python3 scripts/sync_demo_extension.py` to refresh the
two examples' copies.
