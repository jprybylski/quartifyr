# quartifyr_styling

Code-first generation of the docx `reference-doc` used when rendering a
quartifyr report shell with Quarto; the abbreviations YAML →
`abbreviations.tex` bridge consumed by `quarto-plus`; and headless Word
field recalculation via LibreOffice.

This is the Python engine the `quartifyr` R package calls via `pyro`
(`R/run-python.R`'s `.run_quartifyr_styling_cli()`, and the `styling_*()`
wrapper functions) -- see the repo-root `pyproject.toml`, which points
`[tool.setuptools.packages.find] where = ["inst/python"]` at this same
source tree so it's both bundled inside the R package and independently
pip/uv-installable.

## Setup (standalone, without the R package)

```bash
uv venv .venv --python 3.12   # from the repo root
source .venv/bin/activate
uv pip install -e '.[dev]'
```

## Usage

```bash
quartifyr-styling build \
  --style /path/to/inst/python/styles/default.yaml \
  --out org-reference.docx
```

Add `--override /path/to/<org>.yaml` with just the keys that differ
from the default preset (fonts, colors, page setup, ...) to brand a new
organization; see "Customizing the style YAML" below for what every key
controls, `styles/schema.json` for a machine-readable schema (types,
enums, hex-color/positive-number constraints), and
`quartifyr_styling/schema.py` for the validation those constraints
enforce at load time.

### Customizing the style YAML

`styles/default.yaml` carries a
`# yaml-language-server: $schema=./schema.json` header, so an editor with
the [YAML language server](https://github.com/redhat-developer/yaml-language-server)
(the VS Code YAML extension bundles it) gets autocomplete/inline
validation against `styles/schema.json` automatically; point an org
override YAML at the same schema (adjust the relative path to wherever
you copied it, e.g. the installed package's `inst/python/styles/schema.json`)
to get the same for it. An override, being a partial file by design (only
the keys that differ from the base), will still show the editor's
"missing required property" warnings for whatever it deliberately leaves
out -- expected for a deep-merge override, not a sign anything's wrong;
those keys just aren't required to be present in that specific file, only
in the merged result `StyleConfig.load()` actually validates.

Top-level sections, matching `schema.py`'s dataclasses:

| Key | Controls |
| --- | --- |
| `fonts` | Body/heading/monospace font family and every font size (title, subtitle, per-heading-level, caption, footnote, ToC). `monospace` styles code blocks (see `code` below). |
| `colors` | Every hex color the reference-doc uses: body/heading/title/caption text, table header fill, table border, and the rule under the title. |
| `page` | Page size (`letter`/`a4`) and margins. |
| `paragraph` | Body text line spacing, space-after, and alignment. |
| `heading` | Bold, spacing before/after, keep-with-next, and `all_caps` (a visual-only transform, not a string mutation) for `Heading 1`-`6`. |
| `table` | The `Table Grid` style's border style, header bold, and banding. |
| `synopsis` | The synopsis section's definition-list look (label/value spacing, value indent, optional alignment override). |
| `title_page` | Whether to show a rule under the title, and which fields appear (as an ordered list -- see `styles/default.yaml`'s own comment on why this is a list, not a map). |
| `footer` | Page number visibility and optional static footer text. |
| `code` | Fenced-code-block/inline-code font size, background color, and padding (vertical spacing only -- see `code.padding_pt`'s own description in `schema.json`). |
| `equation` | The docx-wide default math font (applied post-render by `apply-layout`, not `build` -- see that command's own docs above). |

`--style`/`--override`/`--out` are plain file paths, not fixed locations.
See the repo-root README's "Style YAML and reference-doc" section for how
an org can keep its style YAML and built reference-doc anywhere, and how
most project authors can skip running `build` entirely by reusing an
already-built `.docx`.

The generated reference-doc also sets `<w:updateFields w:val="true"/>` in
`word/settings.xml`, so Word automatically recalculates every field (ToC,
`SEQ`, `REF`, `PAGE`, ...) the moment a delivered document is opened; no
manual "select all, F9", no LibreOffice involved. See the repo-root
README's "Status and known limitations" section for how this relates to
`recalculate-fields` below (this covers real Word opening the file
interactively; `recalculate-fields` covers headless/non-interactive
pipelines that never open it in an application at all).

The generated docx becomes Quarto's `reference-doc:` for the shell render:

```bash
quarto render report.qmd --to docx --reference-doc org-reference.docx
```

Convert a project's `standard_footnotes.yaml` into the `abbreviations.tex`
`quarto-plus` reads:

```bash
quartifyr-styling abbrevs --footnotes report/standard_footnotes.yaml --out report/shell/abbreviations.tex
```

Recalculate a rendered docx's Word ToC (page numbers, entries) in place via
headless LibreOffice -- see the repo-root README's "Status and known
limitations" section for what this does and does not cover, and a known
reliability caveat:

```bash
quartifyr-styling recalculate-fields --docx path/to/report-final.docx
```

Apply a dynamic page header and footer, and (if the `.qmd` uses `{{<
body-start >}}`) split the rendered docx into title-page/front-matter/body
OOXML sections so the whole front matter numbers in lowercase roman
(starting at "i" on the title page itself) and the body restarts at
arabic "1" -- run this on the shell docx right after the Quarto render,
before `reportifyr`'s pass-2 fill (this is what `render_report()` does
automatically):

```bash
quartifyr-styling apply-layout --docx report/shell/report.docx --qmd report.qmd --status draft
```

Reads `--qmd`'s frontmatter for `header-format:` (a `"{project} -
{report_number}"`-style template, resolved against any frontmatter keys
plus `{status}` from `--status`) and applies it to the header's left
zone on every page -- the header's right zone always shows the
draft/final status once a header is enabled. Also reads `confidentiality:`
for the footer's left-side label (the same field `title_page.lua` renders
on the title page). A `.qmd` with no `header-format:` and no `{{<
body-start >}}` is left untouched -- both are opt-in.

Optional `--style`/`--override` (deep-merged the same way as `build`,
above): when given, applies that style's `equation.font` to the rendered
docx's document-wide default math font (`word/settings.xml`'s
`m:mathPr/m:mathFont`) -- pandoc's docx writer doesn't carry this setting
through from a reference-doc built by `build`, so it has to be reapplied
here, post-render. Omit `--style` to leave the rendered docx's math font
untouched.

Also reads `crossref-hyperlinks:` (default `true`) -- `false` strips the
`\h` hyperlink switch from every figure/table/appendix cross-reference's
`REF` field, document-wide, regardless of whether `quarto-plus`'s
`crossref` shortcode or this extension's own `appendix_crossref` emitted
it. `"same-page"` can't be resolved here (no real pagination exists yet
on the pass-1 shell) -- it just marks each crossref for a separate,
opt-in, post-reportifyr step; see the next command and
`../extensions/quartifyr/README.md`'s "Figures, tables, and
cross-references" section.

```bash
quartifyr-styling resolve-same-page-crossrefs --docx report/draft/report-draft.docx
```

Resolves the markers `apply-layout`'s `crossref-hyperlinks: "same-page"`
left behind, now that reportifyr's pass 2 has filled in real content and
pagination means something -- run on the *filled* draft/final docx, not
the shell. A no-op (skips LibreOffice entirely) if the document has no
same-page markers. Read-only with respect to LibreOffice: it drives a
headless-LibreOffice macro only to read each marked crossref's and its
target's page number (never to re-save the docx, which stays entirely in
Python's hands) -- see
`quartifyr_styling/same_page_crossrefs.py`'s docstring for why, and for
this feature's own experimental/flaky-headless-LibreOffice caveat
(inherited from, and equivalent to, `recalculate-fields`'s above).

```bash
quartifyr-styling sync-reportifyr-config --style styles/default.yaml --config report/config.yaml
```

reportifyr doesn't read quartifyr's style YAML at all -- its own
`report/config.yaml` scaffolds `footnotes_font`/`footnotes_font_size`
independently (defaulting to "Arial Narrow"/10), which visually clashes
with a style YAML's `fonts.body`/`fonts.sizes.footnote` unless kept in
sync by hand (both bundled examples' `report/config.yaml` carry a comment
to that effect). This updates just those two keys to match, printing the
diff and requiring an interactive `y`/`yes` confirmation before writing
-- pass `--yes` to skip the prompt (required when combined with `--json`,
since there's no interactive stdin to confirm over in that non-interactive
invocation). A no-op if already in sync. Rewrites the whole file via
`yaml.safe_dump`, so any comments/formatting `config.yaml` had are lost.

```bash
quartifyr-styling example-style --base styles/default.yaml --out style.yaml
```

Copies a base style YAML (default: the bundled `default.yaml`) into a
project, printing (`--json`: returning as a field) its parsed content --
a working copy to hand-edit, or edit as an R list
(`quartifyr::styling_example_style()`) and hand to `save-overrides`
below. `--overwrite` to replace an existing `--out`.

```bash
quartifyr-styling save-overrides --base styles/default.yaml --style-json edited.json --out overrides.yaml
```

Saves a (possibly edited) style dict -- as JSON, since a full nested
style doesn't fit as CLI args; the R wrapper handles this transparently
-- back out to `--out`, by default (`--no-deconvolute` to disable) as
just the keys that differ from `--base`: an override YAML meant to be
deep-merged back onto that same base at load time
(`StyleConfig.load(base, override)`), not a second full style YAML to
keep in sync by hand.

```bash
quartifyr-styling update-style --file style.yaml --updates-json changes.json --yes
```

Deep-merges the JSON at `--updates-json` onto `--file`'s existing
content, in place -- a `modifyList()`-style edit of one section of a
style YAML without hand-copying the rest of the file. Requires `--yes`
(there's no interactive prompt with `--json`, and the R wrapper's own
`yes = TRUE` argument is the direct equivalent): rewrites the whole file
via `yaml.safe_dump`, so any comments/formatting it had are lost.

## Tests

```bash
cd /path/to/quartifyr && python -m pytest tests/python -v
```
