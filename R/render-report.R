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
#' @param reference_doc Path to the docx reference-template. `NULL`
#'   (default) checks `shell_qmd`'s own frontmatter and the project's
#'   `_quarto.yml` (via `quarto::quarto_inspect()`, so this follows Quarto's
#'   own frontmatter-over-project merge precedence) for an already-configured
#'   `format: {docx: {reference-doc: ...}}` and, if found, leaves it alone --
#'   `quarto render` picks it up on its own, same as a plain `quarto render`
#'   would. Only when neither sets one does this fall back to the template
#'   bundled with this package (`inst/templates/org-reference.docx`, built
#'   from `inst/python/styles/default.yaml`), with a one-time notice
#'   pointing at `styling_build_reference_docx()` to build a custom one
#'   instead. Pass an explicit path here to always use it regardless of any
#'   Quarto-level setting.
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
#'   The failure is recorded in the result (`status` becomes `"error"`, see
#'   `strict`).
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
#' @param strict If `TRUE`, signal an error of class
#'   `quartifyr_render_incomplete` (carrying the result as `$result`) when
#'   the render finished but the result's `status` is not `"ok"`: unfilled
#'   `{rpfy}:` placeholders, missing metadata sidecars, or a requested
#'   LibreOffice step that failed. Default `FALSE`, which returns the result
#'   either way so existing callers keep working; use `TRUE` in CI and
#'   background jobs where an incomplete document must not look like
#'   success. With `strict = TRUE` the result carried on the condition has
#'   `status = "error"`, with the reason added to `errors`, even if the
#'   render itself only warned. Without it, a returned result (and the
#'   script's exit status 0) only means the render finished, not that it was
#'   complete: check `status`.
#' @param offline Whether to render without any network access. `NULL`
#'   (default) follows offline mode as set by `options(quartifyr.offline =
#'   TRUE)` or the `UV_OFFLINE` environment variable (see
#'   `vignette("offline")`). When on, `render_report()` sets `UV_OFFLINE=1`,
#'   `UV_NO_INDEX=1`, `UV_PYTHON_DOWNLOADS=never` and `UV_NO_SYNC=1` for the
#'   whole call, so quartifyr's styling steps and reportifyr's pass 2 use the
#'   already-provisioned Python environment as it is: nothing is synced,
#'   recreated or downloaded, and a cold uv cache is fine. The environment must
#'   have been provisioned beforehand, by `initialize_quartifyr_project()` and
#'   `reportifyr::initialize_report_project()`. A uv failure then signals an
#'   error of class `quartifyr_offline_failure` naming the step. `FALSE` sets
#'   nothing. Renders of one project must not run concurrently: they share its
#'   `.venv` and `report/` folders.
#' @param quarto_timeout Seconds to allow the `quarto render` subprocess
#'   before killing it and signalling an error of class
#'   `quartifyr_quarto_timeout`. Default `600`; `Inf` disables the limit.
#'   The whole process tree is cleaned up on timeout or interrupt (Quarto
#'   spawns Deno, Pandoc and possibly R/knitr children that would otherwise
#'   outlive it). Only this step is bounded: `quarto inspect`,
#'   `quarto list extensions`, the Python styling step and reportifyr's pass 2
#'   have no timeout of their own, so a caller that needs a hard limit on the
#'   whole job must enforce it itself.
#' @param quarto_bin Path to the Quarto executable. `NULL` (default) uses
#'   the `QUARTO_PATH` environment variable if set, else `quarto` on
#'   `PATH`. When given, it is also exported as `QUARTO_PATH` for the
#'   duration of the call, so the `quarto` R package's own helpers
#'   (`quarto_inspect()`, `quarto_list_extensions()`) use the same binary.
#' @param soffice_bin Path to the LibreOffice executable used by
#'   `recalculate_fields` and `resolve_same_page_crossrefs`. `NULL` (default)
#'   uses the `QUARTIFYR_SOFFICE_BIN` environment variable if set, else
#'   `soffice` on `PATH`. When either step is requested the executable is
#'   checked before anything is rendered, and the path and `soffice
#'   --version` that ran are recorded in the result's `versions$libreoffice`.
#'
#' @return An object of class `quartifyr_render_result`, a list with:
#' \describe{
#'   \item{`shell`, `draft`, `final`}{Paths to the docx files (`final` is
#'     `NULL` unless `status = "final"`).}
#'   \item{`status`}{`"ok"`, `"warning"` or `"error"`. `"error"` means the
#'     delivered document is incomplete: placeholders were left unfilled,
#'     or a requested LibreOffice step failed. `"warning"` means it is
#'     complete but reportifyr flagged something (e.g. a missing metadata
#'     sidecar).}
#'   \item{`artifacts`}{Data frame of the files that exist: `role`, `path`,
#'     `sha256`, `bytes`.}
#'   \item{`unfilled_placeholders`}{`{rpfy}:` magic strings still present
#'     in the draft/final docx.}
#'   \item{`missing_metadata`}{Artifacts the shell references that have no
#'     `<stem>_<ext>_metadata.json` sidecar (from the project files, plus
#'     reportifyr's own log for this run).}
#'   \item{`warnings`, `errors`}{Messages behind a non-`"ok"` status.}
#'   \item{`log_dir`}{reportifyr's log directory for the project.}
#'   \item{`inputs`}{Data frame (`role`, `path`, `sha256`, `bytes`) of the
#'     files the render read: the shell `.qmd`, each figure, table and metadata
#'     sidecar it references, `standard_footnotes.yaml`, `config.yaml` and the
#'     reference-doc.}
#'   \item{`versions`}{List of the quartifyr, reportifyr, Quarto,
#'     `quartifyr_styling` (Python) and R versions; `NULL` where one could not
#'     be determined.}
#'   \item{`started_at`, `finished_at`}{UTC timestamps (ISO 8601) of the
#'     render.}
#' }
#' Everything before pass 2 (a failed Quarto render, a timeout, a failed
#' precondition) signals an ordinary error instead. The same fields are
#' available as JSON, with a `schema_version` field, from the
#' `inst/scripts/render.R` script (see
#' `system.file("schemas", "render-result-v1.schema.json", package =
#' "quartifyr")` for the shape). Within a schema version, new optional fields
#' may appear, so consumers should ignore fields they don't know; removing or
#' renaming a field bumps the version.
#'
#' @section After a failed render:
#' A render works in `report/.staging-<id>/` and only reaches `report/shell`,
#' `report/draft` and `report/final` once it has finished and been accepted
#' (`strict = TRUE` rejects anything whose status is not `"ok"`; otherwise a
#' finished render is delivered as it is, with `status` saying whether it is
#' complete). So the live folders only ever hold delivered renders, whatever
#' Quarto and reportifyr were doing when a render went wrong.
#'
#' Once the project checks pass and a render starts, the outputs it is about
#' to regenerate (`report/shell/<name>.docx`, `report/draft/<name>-*.docx`,
#' `report/final/<name>-final.docx` and its `_docx_metadata.json`, and what
#' reportifyr leaves in `report/draft/intermediate_files/`) are moved
#' to `report/.previous/` first, replacing the copy already there, all or
#' nothing. After a render that fails, times out, is rejected by `strict` or
#' is interrupted:
#'
#' * `report/shell`, `report/draft` and `report/final` hold nothing from this
#'   render, or from the earlier one;
#' * `report/.previous/` holds the last delivered outputs, and is not touched
#'   by a failed render (a failure followed by another render never pushes
#'   the last good outputs out of it);
#' * the failed render's own files, partial ones included, are kept in
#'   `report/.failed/` with a `FAILED` file giving the reason, until the next
#'   failure replaces them. For a `strict` rejection the error's `result`
#'   points at the files there;
#' * a failure in the project checks that run first touches nothing.
#'
#' If the R process is killed outright (SIGKILL, a closed session), nothing
#' can clean up: the render's files are left in `report/.staging-<id>/`, the
#' live folders hold nothing from it, and the next render deletes that folder.
#' Add `report/.previous/`, `report/.failed/` and `report/.staging-*/` to
#' `.gitignore`. `abbreviations.tex` next to the shell `.qmd` is regenerated
#' regardless, and an output counts as produced only if it was written after
#' the render began. Renders of one project must not run concurrently.
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
#' @examples
#' \dontrun{
#' # Requires Quarto, a reportifyr-initialized project, and a provisioned
#' # quartifyr Python environment (see initialize_quartifyr_project()) --
#' # not something to run against arbitrary setup/resource usage here.
#' render_report("path/to/project/report.qmd", status = "draft")
#' render_report("path/to/project/report.qmd", status = "final")
#' }
#' @export
render_report <- function(
  shell_qmd,
  status = c("draft", "final"),
  reference_doc = NULL,
  style = NULL,
  override = NULL,
  standard_footnotes_yaml = file.path(dirname(shell_qmd), "report", "standard_footnotes.yaml"),
  config_yaml = file.path(dirname(shell_qmd), "report", "config.yaml"),
  figures_path = file.path(dirname(shell_qmd), "OUTPUTS", "figures"),
  tables_path = file.path(dirname(shell_qmd), "OUTPUTS", "tables"),
  recalculate_fields = FALSE,
  resolve_same_page_crossrefs = FALSE,
  quarto_timeout = 600,
  quarto_bin = NULL,
  soffice_bin = NULL,
  strict = FALSE,
  offline = NULL
) {
  status <- match.arg(status)

  if (!is.null(offline) && !(is.logical(offline) && length(offline) == 1 && !is.na(offline))) {
    stop("offline must be NULL, TRUE or FALSE.")
  }
  # Offline mode for the whole render, set once here so every uv call below
  # inherits it, reportifyr's pass 2 included (it runs `uv run` many times and
  # would otherwise re-sync, and re-resolve against the index, on each one):
  # no index, no managed-Python download, and no re-sync of an environment
  # initialisation already provisioned. `quartifyr.offline` is what the
  # styling bridge and the error handling below look at.
  if (is.null(offline)) {
    offline <- .offline_mode()
  }
  if (offline) {
    withr::local_options(quartifyr.offline = TRUE)
    withr::local_envvar(
      UV_OFFLINE = "1", UV_NO_INDEX = "1", UV_PYTHON_DOWNLOADS = "never", UV_NO_SYNC = "1"
    )
  }

  # A pre-provisioned python_env serves both passes: point pyro (reportifyr's
  # pass 2) and uv at it for the whole render. See R/python-env-pass2.R.
  .use_python_env_for_pass2()

  if (!is.numeric(quarto_timeout) || length(quarto_timeout) != 1 || is.na(quarto_timeout) || quarto_timeout <= 0) {
    stop("quarto_timeout must be a single positive number of seconds (or Inf).")
  }
  if (!is.null(quarto_bin)) {
    if (!is.character(quarto_bin) || length(quarto_bin) != 1 || !nzchar(quarto_bin)) {
      stop("quarto_bin must be a single path to a Quarto executable.")
    }
    withr::local_envvar(QUARTO_PATH = quarto_bin)
  }
  .check_soffice_bin_arg(soffice_bin)
  soffice_command <- .soffice_command(soffice_bin)
  quarto_command <- if (!is.null(quarto_bin)) {
    quarto_bin
  } else if (nzchar(Sys.getenv("QUARTO_PATH"))) {
    Sys.getenv("QUARTO_PATH")
  } else {
    "quarto"
  }

  # The project preconditions below are shared with check_report_project()
  # (R/check-report-project.R), so the render-free preflight and the render
  # itself can't disagree about what a valid project looks like.
  .stop_on_finding(.check_shell_qmd(shell_qmd))

  # Resolve every path against the caller's working directory *now*. The
  # defaults below are derived from `shell_qmd`, and everything after this
  # point runs inside withr::with_dir(project_dir, ...), where a relative path
  # would silently mean something else.
  shell_qmd <- normalizePath(shell_qmd, mustWork = TRUE)
  standard_footnotes_yaml <- .absolute_path(standard_footnotes_yaml)
  config_yaml <- .absolute_path(config_yaml)
  figures_path <- .absolute_path(figures_path)
  tables_path <- .absolute_path(tables_path)
  # A relative reference_doc/style/override means "relative to where the caller
  # is", exactly like the paths above, and must keep meaning that inside
  # with_dir(project_dir, ...) and when it is handed to quarto and Python.
  if (!is.null(reference_doc)) reference_doc <- .absolute_path(reference_doc)
  if (!is.null(style)) style <- .absolute_path(style)
  if (!is.null(override)) override <- .absolute_path(override)
  quarto_yml <- file.path(dirname(shell_qmd), "_quarto.yml")
  .stop_on_finding(.check_output_dir(dirname(shell_qmd)))

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
  .stop_on_finding(.check_init_marker(project_dir))
  # reference_doc_arg is what (if anything) gets passed as `quarto render
  # --reference-doc` below. When the caller passes reference_doc explicitly,
  # it always wins. Otherwise, ask quarto itself (quarto::quarto_inspect(),
  # which applies Quarto's own frontmatter-over-_quarto.yml merge precedence)
  # whether a docx reference-doc is already configured -- if so, leave
  # reference_doc_arg NULL and let `quarto render` pick it up on its own,
  # same as a plain `quarto render` would (see #30: previously this
  # function's own default silently overrode a project's existing Quarto-
  # level reference-doc setting with the package one). Only fall back to the
  # bundled package default, with a one-time notice, when neither is set.
  reference_doc_arg <- reference_doc
  reference_doc_used <- reference_doc
  if (is.null(reference_doc)) {
    configured <- tryCatch(
      quarto::quarto_inspect(shell_qmd)$formats$docx$pandoc$`reference-doc`,
      error = function(e) NULL
    )
    if (is.character(configured) && length(configured) == 1 && nzchar(configured)) {
      reference_doc_arg <- NULL
      reference_doc_used <- .absolute_path(configured, project_dir)
    } else {
      reference_doc_arg <- system.file("templates", "org-reference.docx", package = "quartifyr")
      reference_doc_used <- reference_doc_arg
      cli::cli_inform(c(
        "i" = paste(
          "No {.field reference-doc} set in {.path {quarto_yml}} or {.file {basename(shell_qmd)}}",
          "-- using the quartifyr package default reference-doc."
        ),
        ">" = paste0(
          "See {.help [quartifyr::styling_build_reference_docx()]",
          "(quartifyr::styling_build_reference_docx)} to build a project-specific one."
        )
      ))
    }
  }
  .stop_on_finding(.check_reference_doc(reference_doc_arg))
  .stop_on_finding(.check_footnotes_yaml(standard_footnotes_yaml))
  uses_libreoffice <- isTRUE(recalculate_fields) || isTRUE(resolve_same_page_crossrefs)
  if (uses_libreoffice) {
    .stop_on_finding(.check_soffice(soffice_command))
    # Hand the steps the absolute path that was checked: they run from the
    # project directory (a relative path would mean something else there) and
    # a PATH lookup could find a different LibreOffice than the one recorded
    # in the result.
    soffice_command <- .resolve_soffice(soffice_command)
  }

  # Fail fast with an actionable message (which Quarto extension is
  # missing, and the exact quarto::quarto_add_extension() call to fix it)
  # instead of the much less specific "could not find executable" error
  # `quarto render` itself raises when a filters:/shortcodes: entry in the
  # .qmd's frontmatter resolves to a missing _extensions/ directory.
  check_quarto_extensions(project_dir)

  # Everything above only validates the project, and a failure there means no
  # render was attempted, so nothing on disk has been touched. From here on a
  # render is under way: move the previous render's outputs aside, so that if
  # this one fails, times out or is killed, the live report/{shell,draft,final}
  # folders hold nothing that could pass for its result. The render itself
  # then works in report/.staging-<id>/ and only reaches those folders once it
  # has finished and been accepted (R/render-stage.R).
  stem <- sub("\\.qmd$", "", basename(shell_qmd))
  started_at <- Sys.time()
  # Offline, uv won't fix an environment whose interpreter the project's pin
  # rejects; it only prints a warning. Put it in the result.
  python_env_warnings <- if (offline) {
    .python_env_mismatch(project_dir, .render_python_env(project_dir))
  }
  # Hashed now, before the render can change anything, so `inputs` records
  # what this render started from.
  inputs <- .input_table(
    shell_qmd, figures_path, tables_path, standard_footnotes_yaml, config_yaml, reference_doc_used,
    quarto_yml = quarto_yml, style = style, override = override,
    extensions_dir = file.path(project_dir, "_extensions")
  )
  .discard_stale_staging(project_dir)
  .move_previous_outputs(project_dir, stem)

  # Regenerate abbreviations.tex next to the shell .qmd -- that's where
  # quarto-plus's terms_and_abbreviations.lua looks for it by default -- so
  # it's always in sync with standard_footnotes.yaml rather than a
  # separately-maintained file that can silently go stale.
  abbreviations_tex <- file.path(dirname(shell_qmd), "abbreviations.tex")
  withr::with_dir(project_dir, {
    styling_build_abbreviations_tex(standard_footnotes_yaml, out = abbreviations_tex)
  })

  .with_stage(project_dir, stem, function(stage, outcome) {
    # --- Pass 1: render the shell with Quarto -------------------------------
    # _quarto.yml's `project: {output-dir: report/shell}` (validated above)
    # is what normally redirects the rendered docx into report/shell/;
    # --output only fixes the filename, and --output-dir points this render at
    # its staging folder instead.
    shell_docx_name <- sub("\\.qmd$", ".docx", basename(shell_qmd))
    quarto_result <- processx::run(
      command = quarto_command,
      args = c(
        "render", basename(shell_qmd),
        "--to", "docx",
        if (!is.null(reference_doc_arg)) c("--reference-doc", reference_doc_arg),
        "--output", shell_docx_name,
        "--output-dir", stage$quarto_shell_dir,
        "-M", paste0("document-status:", toupper(status))
      ),
      wd = project_dir,
      error_on_status = FALSE,
      # Bound the render and kill its whole process tree (Deno/Pandoc/knitr
      # children) on timeout or interrupt, so a hung Quarto can't block CI or
      # a background job indefinitely, or leave orphans behind.
      timeout = quarto_timeout,
      cleanup_tree = TRUE
    )
    # cat() straight to stderr rather than folding the subprocess's stderr
    # into stop()'s own condition message -- R's default top-level handler
    # truncates printed error messages to getOption("warning.length")
    # (1000 chars), which has been observed to silently cut off the actual
    # failure reason from a long subprocess stderr, leaving only a
    # generic-looking partial dump in CI logs.
    if (isTRUE(quarto_result$timeout)) {
      cat(quarto_result$stderr, file = stderr())
      stderr_lines <- strsplit(paste(quarto_result$stderr, collapse = "\n"), "\n", fixed = TRUE)[[1]]
      stderr_tail <- if (length(stderr_lines) > 20) stderr_lines[(length(stderr_lines) - 19):length(stderr_lines)] else stderr_lines
      stop(structure(
        class = c("quartifyr_quarto_timeout", "error", "condition"),
        list(
          message = paste0(
            "quarto render timed out after ", format(quarto_timeout), " seconds and was killed ",
            "(raise `quarto_timeout`, or pass Inf to disable). Last stderr lines:\n",
            paste(stderr_tail, collapse = "\n")
          ),
          call = NULL,
          timeout = quarto_timeout,
          stderr_tail = stderr_tail
        )
      ))
    }
    if (!isTRUE(quarto_result$status == 0)) {
      cat(quarto_result$stderr, file = stderr())
      stop("quarto render failed (see stderr above)")
    }
    shell_docx <- file.path(stage$shell_dir, shell_docx_name)

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
    #
    # In reportifyr 0.4.0 a missing *figure* is only a logged warning: the
    # `{rpfy}:` placeholder stays in the output and build_report() returns
    # normally. A missing metadata *sidecar* makes build_report() fail by
    # default, with a generic message (see .with_missing_metadata_context()).
    # Snapshot its log files first so this run's lines can be read back.
    log_dir <- file.path(project_dir, ".rpfy-logs")
    log_snapshot <- .rpfy_log_snapshot(log_dir)
    run_pass2 <- function() {
      withr::with_dir(project_dir, {
        # shell_docx is in the staging folder, so the draft and final paths
        # reportifyr derives from it are in its draft/ and final/ siblings.
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
    }
    # In offline mode keep what pass 2 prints: it is the only place uv's own
    # error text ever shows up (see .with_offline_context()).
    pass2_output <- new.env(parent = emptyenv())
    pass2_output$lines <- character(0)
    paths <- .with_offline_context(
      .with_missing_metadata_context(
        if (offline) .tee_stdout(run_pass2, pass2_output) else run_pass2(),
        project_dir = project_dir, shell_qmd = shell_qmd,
        figures_path = figures_path, tables_path = tables_path
      ),
      step = "fill the shell with reportifyr (pass 2)",
      evidence = function() c(pass2_output$lines, .rpfy_log_new_lines(log_dir, log_snapshot)),
      probe = function() .probe_uv(project_dir)
    )

    # --- What pass 2 left behind ----------------------------------------------
    produced <- Filter(Negate(is.null), list(paths$draft, paths$final))
    run_errors <- character(0)
    run_warnings <- as.character(python_env_warnings)

    not_produced <- character(0)
    for (output_path in produced) {
      if (!.produced_since(output_path, started_at)) {
        not_produced <- c(not_produced, output_path)
        run_errors <- c(run_errors, paste0("Expected output was not produced: ", output_path))
      }
    }
    unfilled <- unique(unlist(lapply(produced, .scan_unfilled_placeholders)))
    missing_metadata <- withr::with_dir(
      project_dir,
      .missing_sidecars(shell_qmd, figures_path, tables_path)
    )
    logged <- .parse_rpfy_log(.rpfy_log_new_lines(log_dir, log_snapshot))
    missing_metadata <- unique(c(missing_metadata, logged$missing_metadata))
    if (length(logged$missing_figures) > 0) {
      run_warnings <- c(
        run_warnings,
        paste0("reportifyr could not find figure file(s): ", paste(logged$missing_figures, collapse = ", "))
      )
    }

    # Note: pyro::run_python_script() (unlike the old direct processx::run()
    # call this replaces) doesn't expose its own subprocess-level timeout, so
    # the only timeout control left is the CLI's own `--timeout` below (the
    # old code additionally wrapped that in an outer processx timeout = 150,
    # a small safety margin beyond the CLI's internal 120s default -- passing
    # 150 here directly preserves that same margin, just as the CLI's own
    # timeout rather than a second, outer one).
    #
    # A failure in either LibreOffice step never aborts the render (the docx
    # is still usable), but it is recorded so the result isn't "ok" and
    # `strict = TRUE` can fail on it.
    run_libreoffice_step <- function(step_fn, step_name) {
      for (output_path in produced) {
        tryCatch(
          withr::with_dir(
            project_dir,
            step_fn(output_path, timeout = 150, soffice_bin = soffice_command)
          ),
          error = function(e) {
            msg <- paste0(step_name, "() failed on ", output_path, ": ", conditionMessage(e))
            warning(msg, call. = FALSE)
            run_errors <<- c(run_errors, msg)
          }
        )
      }
    }
    if (resolve_same_page_crossrefs) {
      run_libreoffice_step(styling_resolve_same_page_crossrefs, "styling_resolve_same_page_crossrefs")
    }
    if (recalculate_fields) {
      run_libreoffice_step(styling_recalculate_fields, "styling_recalculate_fields")
    }

    # --- Accept or reject what was staged ------------------------------------
    # Strict mode rejects anything that isn't "ok". Otherwise the render is
    # delivered as it is, with the status saying whether it is complete.
    status_now <- .result_status(run_warnings, run_errors, unfilled, missing_metadata)
    accepted <- !(isTRUE(strict) && status_now != "ok")
    dest_root <- if (accepted) {
      .promote_stage(project_dir, stage)
    } else {
      outcome$retired <- TRUE
      outcome$reason <- "rejected by strict = TRUE: the render is incomplete"
      .retire_stage(project_dir, stage, outcome$reason, stem)
    }
    outcome$accepted <- accepted
    where <- function(path) .rebase_path(path, stage, dest_root)

    result <- .new_render_result(
      shell = where(paths$shell),
      draft = where(paths$draft),
      final = where(paths$final),
      warnings = run_warnings,
      errors = run_errors,
      unfilled_placeholders = unfilled,
      missing_metadata = missing_metadata,
      log_dir = log_dir,
      not_produced = where(not_produced),
      inputs = inputs,
      versions = .tool_versions(quarto_command, if (uses_libreoffice) soffice_command),
      started_at = .timestamp_utc(started_at),
      finished_at = .timestamp_utc()
    )

    if (!accepted) {
      .abort_incomplete(result)
    }

    result
  })
}
