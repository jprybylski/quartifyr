---
layout: default
title: Templated Workflows
nav_order: 8
---

# Templated workflows: scaffolding new projects with spackle

Standing up a new quartifyr project ([the repo README's "Standing up a
new project" walks through this by hand](https://github.com/jprybylski/quartifyr#standing-up-a-new-project))
means copying a handful of files into a consistent shape: `_extensions/`,
a `_quarto.yml` with `output-dir: report/shell`, a shell `.qmd` with the
right frontmatter, and `reportifyr`'s own `report/standard_footnotes.yaml`/
`report/config.yaml`. That's a good fit for a project-template filler
rather than copy-paste-and-edit; this page is a **suggested pattern**,
not a maintained quartifyr integration. Nothing described here is bundled
with the repo.

[A2-ai/spackle](https://github.com/A2-ai/spackle) is exactly that kind of
tool, from the same organization behind `reportifyr`, `pyro`, and `rv`: a
`spackle.toml` at a template's root declares a set of *slots* (prompted
values, with types and defaults), and any file with a `.j2`/`.tera`
extension in the template gets rendered through [Tera](https://keats.github.io/tera/)
with those slots in scope; `spackle fill` walks the template, prompts
for each slot, and writes the filled-in project to a target directory.

## Sketch: a quartifyr report starter

A `spackle.toml` for a quartifyr report template might declare the
handful of values that actually vary per project; everything else
(the extension copies, the filter list, the `output-dir` convention)
stays fixed:

```toml
# spackle.toml
[slots.org_name]
type = "string"
description = "Organization name, shown on the title page"

[slots.reference_doc]
type = "string"
description = "Path to the org's built reference-doc"
default = "../../templates/org-reference.docx"

[slots.project_code]
type = "string"
description = "Project/protocol code (e.g. ACME-001)"

[slots.report_number]
type = "string"
description = "Report number (e.g. RPT-2026-014)"

[slots.lead_scientist]
type = "string"
description = "Lead scientist name and credentials"
```

And a templated shell, `report.qmd.tera`, pre-filling the frontmatter a
new project always needs while leaving the body for the author to write:

{% raw %}
```markdown
---
title: "{{ project_code }} Report"
document-status: "draft"
lead-scientist: "{{ lead_scientist }}"
project: "{{ project_code }}"
report_number: "{{ report_number }}"
header-format: "{project} - {report_number}"
title-page-extra:
  - label: "Sponsor"
    value: "{{ org_name }}"
format: docx
filters:
  - quarto-plus
  - quartifyr
---

{{< toc >}}

# Introduction

{{< body-start >}}
```
{% endraw %}

`_quarto.yml` (setting `project: {output-dir: report/shell}`) and the
physical `_extensions/` copies can be plain, unfilled files in the same
template; spackle only runs slots through files with a `.j2`/`.tera`
extension, so anything that doesn't need per-project values just gets
copied as-is.

## Why this pairs well with quartifyr specifically

- **The values that vary are small in number**: org name,
  project code, report number, lead scientist, exactly the shape
  spackle's slot model is built for, rather than a general-purpose
  scaffolding tool that would be overkill here.
- **quartifyr already treats "one project = one directory with a fixed
  shape" as load-bearing** (the `report/shell` convention
  `render_report()` depends on; see [Architecture](architecture.html)).
  A template filler that reproduces that shape exactly, every time,
  removes a whole class of "forgot to set `output-dir`" mistakes.
- **An org's reference-doc rarely changes** once built (see
  [Styling](styling.html)), so `reference_doc` is a good candidate for a
  slot with a `default`; most new projects accept it as-is, but a
  project reusing a different org's styling can override it at fill
  time.

## Trying it

```bash
# spackle itself: see https://github.com/A2-ai/spackle for install instructions
spackle info /path/to/your-template
spackle fill /path/to/your-template --out my-new-report
```

Then follow the rest of [Standing up a new
project](https://github.com/jprybylski/quartifyr#standing-up-a-new-project)
(installing the extensions, running
`reportifyr::initialize_report_project()`) against the filled-in
directory.
