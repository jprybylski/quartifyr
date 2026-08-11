#' Render a quartifyr report shell (Quarto pass 1) and fill it via reportifyr (pass 2)
#'
#' @description
#' Two-pass report generation in one call: (1) regenerates
#' `abbreviations.tex` from `standard_footnotes.yaml` and renders `shell_qmd`
#' with Quarto against a quartifyr docx reference-template, then (2) hands
#' the resulting shell to `reportifyr::build_report()` to fill in tables,
#' figures, and footnotes from `OUTPUTS/`, and (when `status = "final"`)
#' `reportifyr::finalize_document()` on top of that.
#'
#' @param shell_qmd Path to the shell `.qmd`. Must live in a `report/shell/`
#'   directory (e.g. `.../report/shell/report.qmd`) -- `reportifyr::make_doc_dirs()`
#'   derives the draft/final output paths by substring-replacing "shell"
#'   with "draft"/"final" in the containing directory, so this isn't just a
#'   convention, it's load-bearing.
#' @param status `"draft"` or `"final"`. Sets the title page's DRAFT/FINAL
#'   stamp (via Quarto's `-M document-status:`) and, when `"final"`, also
#'   runs `reportifyr::finalize_document()` to produce a `report/final/`
#'   output alongside the `report/draft/` one.
#' @param toolkit_root Root of the quartifyr checkout (contains `templates/`,
#'   `_extensions/`, `.venv/`). Defaults to the git repo root.
#' @param reference_doc Path to the docx reference-template. See `styling/`.
#' @param standard_footnotes_yaml,config_yaml,figures_path,tables_path
#'   Passed through to reportifyr; default to the standard project layout
#'   `reportifyr::initialize_report_project()` creates, alongside `shell_qmd`.
#' @param venv_bin Path to the `styling/` venv's `bin/` directory (holds the
#'   `quartifyr-styling` CLI used for the abbreviations bridge).
#' @param recalculate_fields Whether to run `quartifyr-styling
#'   recalculate-fields` (headless LibreOffice) on each produced docx
#'   afterward, so the delivered file's ToC page numbers/entries are
#'   already resolved instead of showing "Right-click to update field".
#'   Default `FALSE`: this step has been observed to hang intermittently in
#'   some environments for reasons not yet root-caused (see
#'   `recalculate_fields.py`'s docstring and `r/README.md`) -- opt in once
#'   you've confirmed it's reliable in your own environment. A failure here
#'   only warns, it never fails the overall render (the doc is still fully
#'   usable, just needs a manual "select all, F9" in Word).
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
  toolkit_root = here::here(),
  reference_doc = file.path(toolkit_root, "templates", "org-reference.docx"),
  standard_footnotes_yaml = file.path(dirname(dirname(shell_qmd)), "standard_footnotes.yaml"),
  config_yaml = file.path(dirname(dirname(shell_qmd)), "config.yaml"),
  figures_path = file.path(dirname(dirname(dirname(shell_qmd))), "OUTPUTS", "figures"),
  tables_path = file.path(dirname(dirname(dirname(shell_qmd))), "OUTPUTS", "tables"),
  venv_bin = file.path(toolkit_root, ".venv", "bin"),
  recalculate_fields = FALSE
) {
  status <- match.arg(status)

  if (!file.exists(shell_qmd)) {
    stop("shell_qmd not found: ", shell_qmd)
  }
  if (!grepl("[/\\\\]report[/\\\\]shell([/\\\\]|$)", dirname(shell_qmd))) {
    stop(
      "shell_qmd must live under a report/shell/ directory (reportifyr::make_doc_dirs() ",
      "derives draft/final paths from that convention): ", shell_qmd
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
  # with withr::with_dir(), regardless of the caller's ambient cwd.
  project_dir <- dirname(dirname(dirname(normalizePath(shell_qmd, mustWork = TRUE))))
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
      "\nBuild it first, e.g.: quartifyr-styling build --style styling/styles/default.yaml --out ",
      reference_doc
    )
  }
  if (!file.exists(standard_footnotes_yaml)) {
    stop("standard_footnotes_yaml not found: ", standard_footnotes_yaml)
  }

  quartifyr_styling_bin <- file.path(venv_bin, "quartifyr-styling")
  if (!file.exists(quartifyr_styling_bin)) {
    stop(
      "quartifyr-styling not found at ", quartifyr_styling_bin,
      "\nSet up the venv first: uv venv .venv --python 3.12 && uv pip install -e \"./styling[dev]\""
    )
  }

  shell_qmd <- normalizePath(shell_qmd, mustWork = TRUE)

  # Regenerate abbreviations.tex next to the shell .qmd -- that's where
  # quarto-plus's terms_and_abbreviations.lua looks for it by default -- so
  # it's always in sync with standard_footnotes.yaml rather than a
  # separately-maintained file that can silently go stale.
  abbreviations_tex <- file.path(dirname(shell_qmd), "abbreviations.tex")
  abbrevs_result <- processx::run(
    command = quartifyr_styling_bin,
    args = c("abbrevs", "--footnotes", standard_footnotes_yaml, "--out", abbreviations_tex),
    error_on_status = FALSE
  )
  if (abbrevs_result$status != 0) {
    stop("quartifyr-styling abbrevs failed:\n", abbrevs_result$stderr)
  }

  # --- Pass 1: render the shell with Quarto -------------------------------
  shell_docx <- sub("\\.qmd$", ".docx", basename(shell_qmd))
  quarto_result <- processx::run(
    command = "quarto",
    args = c(
      "render", basename(shell_qmd),
      "--to", "docx",
      "--reference-doc", reference_doc,
      "--output", shell_docx,
      "-M", paste0("document-status:", toupper(status))
    ),
    wd = dirname(shell_qmd),
    error_on_status = FALSE
  )
  if (quarto_result$status != 0) {
    stop("quarto render failed:\n", quarto_result$stderr)
  }
  shell_docx <- file.path(dirname(shell_qmd), shell_docx)

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

  if (recalculate_fields) {
    outputs <- Filter(Negate(is.null), list(result$draft, result$final))
    for (output_path in outputs) {
      recalc_result <- tryCatch(
        processx::run(
          command = quartifyr_styling_bin,
          args = c("recalculate-fields", "--docx", output_path),
          error_on_status = FALSE,
          timeout = 150
        ),
        error = function(e) {
          warning("quartifyr-styling recalculate-fields errored on ", output_path, ": ", conditionMessage(e))
          NULL
        }
      )
      if (!is.null(recalc_result) && recalc_result$status != 0) {
        warning("quartifyr-styling recalculate-fields failed on ", output_path, ":\n", recalc_result$stderr)
      }
    }
  }

  result
}
