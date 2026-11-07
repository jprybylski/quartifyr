# A render works in `report/.staging-<id>/{shell,draft,final}/` and only a
# finished, accepted render is moved into `report/{shell,draft,final}/`. That
# is what makes the live folders trustworthy: whatever Quarto and reportifyr
# write while a render is under way (or leave behind when it fails, is
# rejected by `strict`, or the R process is killed) never sits where a caller
# would take it for a delivered document.
#
# The id is hex on purpose: reportifyr's make_doc_dirs() derives the draft and
# final folders by substituting the *first* "shell" / "draft" in the whole
# path, so an id containing either word would send its output elsewhere.

.staging_pattern <- "^\\.staging-"

.new_stage <- function(project_dir) {
  id <- paste(as.character(unclass(openssl::rand_bytes(6))), collapse = "")
  root <- file.path(project_dir, "report", paste0(".staging-", id))
  dirs <- file.path(root, c("shell", "draft", "final"))
  for (dir in dirs) {
    dir.create(dir, recursive = TRUE)
  }
  list(
    root = root,
    shell_dir = dirs[[1]],
    draft_dir = dirs[[2]],
    final_dir = dirs[[3]],
    # What `quarto render --output-dir` gets: relative to the project.
    quarto_shell_dir = file.path("report", basename(root), "shell")
  )
}

# A staging folder that is still there when a render starts belongs to a
# render that was killed (nothing else removes it). Renders of one project
# must not run concurrently anyway.
.discard_stale_staging <- function(project_dir) {
  report_dir <- file.path(project_dir, "report")
  stale <- list.files(report_dir, pattern = .staging_pattern, all.files = TRUE, full.names = TRUE)
  unlink(stale, recursive = TRUE)
  invisible(stale)
}

# Keep a render that did not make it, for diagnosis, in `report/.failed/`
# (only the most recent one) with a FAILED file saying why. Never throws: it
# runs while an error is already unwinding. Returns the folder it is in, or
# NULL when there was nothing to keep.
.retire_stage <- function(project_dir, stage, reason, stem) {
  if (!dir.exists(stage$root)) {
    return(NULL)
  }
  failed <- file.path(project_dir, "report", ".failed")
  tryCatch(
    {
      unlink(failed, recursive = TRUE)
      kept <- if (.rename_file(stage$root, failed)) failed else stage$root
      writeLines(
        c(
          paste0("This render of ", stem, ".qmd did not complete and was not delivered."),
          "Its files are kept here only to help find out why; nothing in report/shell,",
          "report/draft or report/final came from it.",
          paste0("time: ", .timestamp_utc()),
          paste0("reason: ", reason)
        ),
        file.path(kept, "FAILED")
      )
      kept
    },
    error = function(e) NULL
  )
}

# Move everything a finished render staged into the live folders, undoing the
# moves already made if one of them fails. Returns the folder the staged
# `shell/`, `draft/` and `final/` now live under (`report/`).
.promote_stage <- function(project_dir, stage) {
  report_dir <- file.path(project_dir, "report")
  done <- list()
  undo <- function() {
    for (op in rev(done)) {
      .rename_file(op$to, op$from)
    }
  }
  move <- function(from, to) {
    unlink(to, recursive = TRUE)
    if (!.rename_file(from, to)) {
      stop("Could not move the staged output ", from, " to ", to, ".", call. = FALSE)
    }
    done[[length(done) + 1L]] <<- list(from = from, to = to)
  }
  tryCatch(
    {
      for (role in c("shell", "draft", "final")) {
        src_dir <- file.path(stage$root, role)
        dest_dir <- file.path(report_dir, role)
        dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
        for (entry in list.files(src_dir, all.files = TRUE, no.. = TRUE, full.names = TRUE)) {
          dest <- file.path(dest_dir, basename(entry))
          if (basename(entry) == "intermediate_files" && dir.exists(dest)) {
            # reportifyr keeps one such folder across renders: merge into it.
            for (inner in list.files(entry, all.files = TRUE, no.. = TRUE, full.names = TRUE)) {
              move(inner, file.path(dest, basename(inner)))
            }
          } else {
            move(entry, dest)
          }
        }
      }
    },
    error = function(e) {
      undo()
      stop(e)
    }
  )
  .repoint_staged_metadata(project_dir, stage, report_dir)
  unlink(stage$root, recursive = TRUE)
  report_dir
}

# reportifyr's finalize_document() writes `<final>_docx_metadata.json` with
# the docx's path relative to the project, which for a staged file names the
# staging folder. Point it at where the file now is.
.repoint_staged_metadata <- function(project_dir, stage, report_dir) {
  staged_rel <- file.path("report", basename(stage$root))
  sidecars <- list.files(
    file.path(report_dir, c("shell", "draft", "final")),
    pattern = "_metadata\\.json$", full.names = TRUE
  )
  for (sidecar in sidecars) {
    text <- paste(readLines(sidecar, warn = FALSE), collapse = "\n")
    role <- basename(dirname(sidecar))
    fixed <- gsub(
      file.path(staged_rel, role), file.path("report", role), text,
      fixed = TRUE
    )
    if (!identical(fixed, text)) {
      writeLines(fixed, sidecar)
    }
  }
  invisible(NULL)
}

# `path` with the staging root swapped for `dest_root` (NULL stays NULL).
.rebase_path <- function(path, stage, dest_root) {
  if (is.null(path) || is.null(dest_root)) {
    return(path)
  }
  vapply(path, function(p) {
    if (startsWith(p, stage$root)) paste0(dest_root, substring(p, nchar(stage$root) + 1L)) else p
  }, character(1), USE.NAMES = FALSE)
}

# Runs `run(stage, outcome)` in a fresh staging folder. If it ends without
# marking `outcome$accepted` or `outcome$retired` (an error, an interrupt, a
# quarto timeout), the staged files are kept under report/.failed/ with a
# FAILED marker rather than left where they would pass for a result.
.with_stage <- function(project_dir, stem, run) {
  stage <- .new_stage(project_dir)
  outcome <- new.env(parent = emptyenv())
  outcome$accepted <- FALSE
  outcome$retired <- FALSE
  outcome$reason <- "the render did not finish"
  on.exit(
    if (!outcome$accepted && !outcome$retired) {
      .retire_stage(project_dir, stage, outcome$reason, stem)
    },
    add = TRUE
  )
  withCallingHandlers(
    run(stage, outcome),
    error = function(e) outcome$reason <- conditionMessage(e),
    interrupt = function(e) outcome$reason <- "interrupted"
  )
}
