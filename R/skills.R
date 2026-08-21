#' Export quartifyr's bundled coding-agent skill files
#'
#' Copies the package's bundled coding-agent skill files (Claude
#' Skills-format `SKILL.md`s) into `directory`: one skill for authoring a
#' style YAML (org-level typography/page/table configuration), and one for
#' authoring a shell `.qmd` (front matter, appendices, captions, magic-string
#' placeholders). Each lands under its own `<directory>/<skill-name>/SKILL.md`
#' subdirectory, since a `SKILL.md` file's name is fixed by the Skills
#' convention -- point `directory` at `.claude/skills` for Claude Code to
#' auto-discover them, or anywhere else for a different coding agent/tool, or
#' just to inspect the content.
#'
#' @param directory Target directory. Defaults to the current directory.
#' @param force Overwrite an existing `SKILL.md` at the destination.
#'   Default `FALSE`.
#' @return A list describing the created files (invisibly).
#' @examples
#' \dontrun{
#' styling_export_skills(".claude/skills")
#' }
#' @export
styling_export_skills <- function(directory = ".", force = FALSE) {
  args <- c("skills", directory)
  if (isTRUE(force)) {
    args <- c(args, "--force")
  }
  invisible(.run_quartifyr_styling_cli(args))
}
