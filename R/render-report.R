#' Render a quartifyr report shell (Quarto pass 1) and fill it via reportifyr (pass 2)
#'
#' @description
#' Two-pass report generation in one call: (1) regenerates
#' `abbreviations.tex` from `standard_footnotes.yaml` and renders `shell_qmd`
#' with Quarto against a quartifyr docx reference-template, (1.5) applies
#' `styling_apply_layout()` to the rendered shell -- a dynamic page header
#' (from `header-format:` frontmatter) and, if the `.qmd` uses
#' `{{< body-start >}}`, splitting front matter from the body into separate
#' OOXML sections so body page numbering restarts at 1 -- then (2) hands
#' the resulting shell to `reportifyr::build_report()` to fill in tables,
#' figures, and footnotes from `OUTPUTS/`, and (when `status = "final"`)
#' `reportifyr::finalize_document()` on top of that.
#'
#' @param shell_qmd Path to the shell `.qmd`, at the project's root
#'   alongside `_extensions/` (standard Quarto project layout -- extensions
#'   are discovered relative to the qmd being rendered; see
#'   `install_quartifyr_extension()`). The project's `_quarto.yml` must set
#'   `project: {output-dir: report/shell}` so the rendered docx lands in
#'   `report/shell/`, matching what `reportifyr::make_doc_dirs()` expects
#'   (it derives `report/draft/`/`report/final/` output paths by
#'   substring-replacing "shell" with "draft"/"final" in the containing
#'   directory of the rendered docx -- not the source qmd -- so this is
#'   load-bearing, not just a convention).
#' @param status `"draft"` or `"final"`. Sets the title page's DRAFT/FINAL
#'   stamp (via Quarto's `-M document-status:`) and, when `"final"`, also
#'   runs `reportifyr::finalize_document()` to produce a `report/final/`
#'   output alongside the `report/draft/` one.
#' @param reference_doc Path to the docx reference-template. Defaults to
#'   the one bundled with this package (`inst/templates/org-reference.docx`,
#'   built from `inst/python/styles/default.yaml` -- see
#'   `styling_build_reference_docx()` to build a custom one).
#' @param style,override Optional style YAML paths -- when `style` is
#'   given, its `equation.font` is applied to the rendered shell's default
#'   math font via `styling_apply_layout()` (see that function; pandoc's
#'   docx writer doesn't carry this setting through from `reference_doc`
#'   itself, so it has to be reapplied here, after rendering). Independent
#'   of `reference_doc` -- if `reference_doc` was itself built from a style
#'   YAML (`styling_build_reference_docx()`), pass the same path here to
#'   keep the two in sync. `NULL` (default) leaves the rendered docx's math
#'   font untouched.
#' @param standard_footnotes_yaml,config_yaml,figures_path,tables_path
#'   Passed through to reportifyr; default to the standard project layout
#'   `reportifyr::initialize_report_project()` creates, alongside `shell_qmd`.
#' @param recalculate_fields Whether to run `styling_recalculate_fields()`
#'   (headless LibreOffice) on each produced docx afterward, so the
#'   delivered file's ToC page numbers/entries are already resolved instead
#'   of showing "Right-click to update field". Default `FALSE`: this step
#'   has been observed to hang intermittently in some environments for
#'   reasons not yet root-caused (see `recalculate_fields.py`'s docstring)
#'   -- opt in once you've confirmed it's reliable in your own environment.
#'   A failure here only warns, it never fails the overall render (the doc
#'   is still fully usable, just needs a manual "select all, F9" in Word).
#' @param resolve_same_page_crossrefs Whether to run
#'   `styling_resolve_same_page_crossrefs()` (headless LibreOffice,
#'   read-only -- it never re-saves the docx itself) on each produced docx
#'   afterward, to resolve any `crossref-hyperlinks: "same-page"` markers
#'   into a final hyperlinked/not decision now that real content and
#'   pagination exist. A no-op (skips LibreOffice entirely) if the `.qmd`
#'   didn't use that setting. Default `FALSE`, same reasoning as
#'   `recalculate_fields` -- it drives the identical headless-LibreOffice
#'   mechanism and inherits its intermittent-hang behavior (see
#'   `same_page_crossrefs.py`'s docstring). If never enabled, a document
#'   using `crossref-hyperlinks: "same-page"` just stays hyperlinked
#'   everywhere -- the same safe fallback `apply-layout` already leaves in
#'   place. A failure here only warns, same as `recalculate_fields`.
#'
#' @return A list with `shell`, `draft`, and (when `status = "final"`) `final`
#'   docx paths.
#'
#' @section Known upstream gotcha:
#' Pandoc's docx writer wraps every `#`-heading section in body-level
#' `bookmarkStart`/`bookmarkEnd` markers (siblings of `<w:p>`, not nested in
#' one). `reportifyr`'s own `build_report()` -> `validate_alt_text_magic_strings()`
#' assumes the paragraph right after any `{rpfy}:` magic string is itself a
#' `<w:p>`, and crashes with an `lxml` "Undefined namespace prefix" error if a
#' magic string is the very last thing in a section (the "next paragraph" it
#' finds is actually that trailing bookmarkEnd, or the closing `<w:sectPr>` at
#' the end of the whole document). Put at least one line of real content (a
#' sentence, a footnote lead-in, anything) after the last magic string in
#' each section to avoid this -- confirmed via a real end-to-end render.
#' @export
render_report <- function(
  shell_qmd,
  status = c("draft", "final"),
  reference_doc = system.file("templates", "org-reference.docx", package = "quartifyr"),
  style = NULL,
  override = NULL,
  standard_footnotes_yaml = file.path(dirname(shell_qmd), "report", "standard_footnotes.yaml"),
  config_yaml = file.path(dirname(shell_qmd), "report", "config.yaml"),
  figures_path = file.path(dirname(shell_qmd), "OUTPUTS", "figures"),
  tables_path = file.path(dirname(shell_qmd), "OUTPUTS", "tables"),
  recalculate_fields = FALSE,
  resolve_same_page_crossrefs = FALSE
) {
  status <- match.arg(status)

  if (!file.exists(shell_qmd)) {
    stop("shell_qmd not found: ", shell_qmd)
  }
  quarto_yml <- file.path(dirname(shell_qmd), "_quarto.yml")
  if (!file.exists(quarto_yml) || !any(grepl("output-dir:\\s*report/shell", readLines(quarto_yml)))) {
    stop(
      "Expected ", quarto_yml, " to set `project: {output-dir: report/shell}` -- ",
      "reportifyr::make_doc_dirs() derives draft/final paths from the rendered docx living in ",
      "report/shell/, and without that _quarto.yml setting the render won't land there."
    )
  }

  # reportifyr/pyro locate their Python venv and project config by walking
  # *up from R's current working directory* looking for a `.*_init.json`
  # marker (reportifyr:::find_project_root(start_path = getwd())) -- they
  # do NOT use any path argument for this. If render_report() is called
  # from an unrelated working directory (a different R session, RStudio
  # pointed elsewhere, etc.), reportifyr will silently resolve the wrong
  # project root -- or seed a stray pyproject.toml/.venv/.rpfy-logs in
  # whatever directory happened to be current. So project_dir is derived
  # here and every reportifyr:: call below is scoped into it explicitly
  # with withr::with_dir(), regardless of the caller's ambient cwd. The
  # styling_*() calls below share this same requirement -- pyro's own
  # get_venv_uv_paths()/run_python_script() resolve the same way -- so
  # they're scoped into project_dir too.
  project_dir <- dirname(normalizePath(shell_qmd, mustWork = TRUE))
  init_marker <- list.files(project_dir, pattern = "^\\.[^.]*_init\\.json$", all.files = TRUE)
  if (length(init_marker) == 0) {
    stop(
      "No reportifyr *_init.json marker found in ", project_dir,
      "\nRun reportifyr::initialize_report_project(project_dir = \"", project_dir, "\") first."
    )
  }
  if (!file.exists(reference_doc)) {
    stop(
      "reference-doc not found: ", reference_doc,
      "\nBuild it first, e.g.: quartifyr::styling_build_reference_docx(",
      "\"inst/python/styles/default.yaml\", out = \"", reference_doc, "\")"
    )
  }
  if (!file.exists(standard_footnotes_yaml)) {
    stop("standard_footnotes_yaml not found: ", standard_footnotes_yaml)
  }

  shell_qmd <- normalizePath(shell_qmd, mustWork = TRUE)

  # Fail fast with an actionable message (which Quarto extension is
  # missing, and the exact quarto::quarto_add_extension() call to fix it)
  # instead of the much less specific "could not find executable" error
  # `quarto render` itself raises when a filters:/shortcodes: entry in the
  # .qmd's frontmatter resolves to a missing _extensions/ directory.
  check_quarto_extensions(project_dir)

  # Regenerate abbreviations.tex next to the shell .qmd -- that's where
  # quarto-plus's terms_and_abbreviations.lua looks for it by default -- so
  # it's always in sync with standard_footnotes.yaml rather than a
  # separately-maintained file that can silently go stale.
  abbreviations_tex <- file.path(dirname(shell_qmd), "abbreviations.tex")
  withr::with_dir(project_dir, {
    styling_build_abbreviations_tex(standard_footnotes_yaml, out = abbreviations_tex)
  })

  # --- Pass 1: render the shell with Quarto -------------------------------
  # _quarto.yml's `project: {output-dir: report/shell}` (validated above)
  # is what actually redirects the rendered docx into report/shell/ --
  # --output here only fixes the filename, not the directory.
  shell_docx_name <- sub("\\.qmd$", ".docx", basename(shell_qmd))
  quarto_result <- processx::run(
    command = "quarto",
    args = c(
      "render", basename(shell_qmd),
      "--to", "docx",
      "--reference-doc", reference_doc,
      "--output", shell_docx_name,
      "-M", paste0("document-status:", toupper(status))
    ),
    wd = project_dir,
    error_on_status = FALSE
  )
  if (quarto_result$status != 0) {
    # cat() straight to stderr rather than folding the subprocess's stderr
    # into stop()'s own condition message -- R's default top-level handler
    # truncates printed error messages to getOption("warning.length")
    # (1000 chars), which has been observed to silently cut off the actual
    # failure reason from a long subprocess stderr, leaving only a
    # generic-looking partial dump in CI logs.
    cat(quarto_result$stderr, file = stderr())
    stop("quarto render failed (see stderr above)")
  }
  shell_docx <- file.path(project_dir, "report", "shell", shell_docx_name)

  # --- Header/footer + page-restart-at-body layout -------------------------
  # Splits shell_docx into front-matter/body OOXML sections at the
  # {{< body-start >}} bookmark (if the .qmd uses it) and applies a dynamic
  # header resolved from the .qmd's `header-format:` frontmatter (if set).
  # Both are opt-in per-project; a .qmd with neither is left untouched by
  # this step. Runs on the shell docx, before reportifyr's pass 2, so the
  # header/footer/section structure is already in place when reportifyr
  # fills in tables/figures/footnotes.
  withr::with_dir(project_dir, {
    styling_apply_layout(shell_docx, shell_qmd, status = status, style = style, override = override)
  })

  # --- Pass 2: fill the shell with reportifyr -----------------------------
  # Scoped to project_dir so reportifyr's cwd-based project/venv detection
  # (see the comment above) resolves correctly no matter the caller's own
  # working directory, and restores the caller's original cwd afterward.
  result <- withr::with_dir(project_dir, {
    doc_dirs <- reportifyr::make_doc_dirs(docx_in = shell_docx)

    reportifyr::build_report(
      docx_in = doc_dirs$doc_in,
      docx_out = doc_dirs$doc_draft,
      figures_path = figures_path,
      tables_path = tables_path,
      standard_footnotes_yaml = standard_footnotes_yaml,
      config_yaml = config_yaml
    )

    out <- list(shell = shell_docx, draft = doc_dirs$doc_draft, final = NULL)

    if (status == "final") {
      reportifyr::finalize_document(
        docx_in = doc_dirs$doc_draft,
        docx_out = doc_dirs$doc_final,
        config_yaml = config_yaml
      )
      out$final <- doc_dirs$doc_final
    }

    out
  })

  # Note: pyro::run_python_script() (unlike the old direct processx::run()
  # call this replaces) doesn't expose its own subprocess-level timeout, so
  # the only timeout control left is the CLI's own `--timeout` below (the
  # old code additionally wrapped that in an outer processx timeout = 150,
  # a small safety margin beyond the CLI's internal 120s default -- passing
  # 150 here directly preserves that same margin, just as the CLI's own
  # timeout rather than a second, outer one).
  if (resolve_same_page_crossrefs) {
    outputs <- Filter(Negate(is.null), list(result$draft, result$final))
    for (output_path in outputs) {
      tryCatch(
        withr::with_dir(project_dir, styling_resolve_same_page_crossrefs(output_path, timeout = 150)),
        error = function(e) {
          warning("styling_resolve_same_page_crossrefs() failed on ", output_path, ": ", conditionMessage(e))
        }
      )
    }
  }

  if (recalculate_fields) {
    outputs <- Filter(Negate(is.null), list(result$draft, result$final))
    for (output_path in outputs) {
      tryCatch(
        withr::with_dir(project_dir, styling_recalculate_fields(output_path, timeout = 150)),
        error = function(e) {
          warning("styling_recalculate_fields() failed on ", output_path, ": ", conditionMessage(e))
        }
      )
    }
  }

  result
}
