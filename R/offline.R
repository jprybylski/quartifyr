# Offline / pre-provisioned operation (no network during init or render).
#
# quartifyr itself only needs the network in three places, all during setup:
# provisioning its Python dependency group through pyro/uv, fetching a
# template with `from_repo`, and installing a Quarto extension with
# `quarto add`. This file holds the pieces that let each of them be replaced
# with something local, and that name the step when one can't be.

# TRUE when quartifyr should assume no network: the `quartifyr.offline`
# option, or uv's own UV_OFFLINE environment variable (which uv itself
# honours, so a user who already set it gets consistent behaviour).
.offline_mode <- function() {
  isTRUE(getOption("quartifyr.offline")) ||
    tolower(Sys.getenv("UV_OFFLINE")) %in% c("1", "true", "yes", "on")
}

# Signals an error of class `quartifyr_offline_failure` saying which step
# needed the network, which resource it was after, and how to provide that
# locally. `step`, `resource` and `how` are cli templates evaluated in `env`
# (the caller's frame by default), so they can use {.arg}/{.path} markup and
# the caller's own variables; `how` may be a character vector, one bullet
# each.
.abort_offline <- function(step, resource, how, parent = NULL, env = parent.frame()) {
  cli::cli_abort(
    c(
      "x" = paste0("Cannot ", step, " without network access."),
      "!" = paste0("It needs ", resource, "."),
      stats::setNames(how, rep("i", length(how)))
    ),
    class = "quartifyr_offline_failure",
    call = NULL,
    parent = parent,
    .envir = env
  )
}

# The pre-provisioned Python environment to use instead of a pyro/uv one:
# an explicit argument, else `options(quartifyr.python_env)`, else the
# QUARTIFYR_PYTHON_ENV environment variable. Returns NULL when none is set.
.configured_python_env <- function(python_env = NULL) {
  env <- python_env
  if (is.null(env)) {
    env <- getOption("quartifyr.python_env")
  }
  if (is.null(env) || !nzchar(env)) {
    env <- Sys.getenv("QUARTIFYR_PYTHON_ENV")
  }
  if (is.null(env) || !nzchar(env)) {
    return(NULL)
  }
  env
}

# Makes a path absolute without resolving symlinks. That matters for a
# venv's `bin/python`: it is usually a symlink to the base interpreter, and
# Python finds its `pyvenv.cfg` (hence its site-packages) from the path it was
# *invoked* as, so normalizePath() -- which follows symlinks -- would run the
# base interpreter and make every module in the venv look missing.
.absolute_path <- function(path, dir = getwd()) {
  path <- path.expand(path)
  if (grepl("^(/|[A-Za-z]:[/\\\\])", path)) path else file.path(dir, path)
}

# The interpreter inside an environment directory: a venv itself, or a
# project directory that holds a `.venv`.
.python_exe <- function(env) {
  env <- .absolute_path(env)
  candidates <- c(
    file.path(env, "bin", "python"),
    file.path(env, "Scripts", "python.exe"),
    file.path(env, ".venv", "bin", "python"),
    file.path(env, ".venv", "Scripts", "python.exe")
  )
  found <- candidates[file.exists(candidates)]
  if (length(found) == 0) {
    cli::cli_abort(
      c(
        "x" = "No Python interpreter found in the configured Python environment {.path {env}}.",
        "i" = paste(
          "Expected {.path {candidates[1]}} (or {.path {candidates[2]}}), or the same under",
          "{.file .venv/} if this is a project directory."
        )
      ),
      class = "quartifyr_python_env_invalid",
      call = NULL
    )
  }
  found[[1]]
}

# What a pre-provisioned environment has to be able to import, and the PyPI
# distribution that provides each module.
.required_python_modules <- c(docx = "python-docx", yaml = "pyyaml", quartifyr_styling = "quartifyr_styling")

# What reportifyr's pass 2 imports on top of the bundled `reportipyr` package
# (which it puts on PYTHONPATH itself): the same two, plus Pillow for figures.
# quartifyr_styling isn't needed by reportifyr, but the bundled source is on
# the path whenever quartifyr runs it.
.reportifyr_python_modules <- c(docx = "python-docx", yaml = "pyyaml", PIL = "pillow")

# PYTHONPATH for running the bundled quartifyr_styling source (inst/python)
# with an interpreter that doesn't have it installed.
.python_src <- function() {
  python_src <- system.file("python", package = "quartifyr")
  if (!nzchar(python_src)) {
    stop(
      "quartifyr's bundled Python source (inst/python) was not found in ",
      "the installed package -- reinstall the quartifyr R package.",
      call. = FALSE
    )
  }
  python_src
}

.python_env_vars <- function() {
  existing <- Sys.getenv("PYTHONPATH")
  c("current", PYTHONPATH = if (nzchar(existing)) paste(.python_src(), existing, sep = .Platform$path.sep) else .python_src())
}

# Checks that `env` provides every module quartifyr needs, naming what is
# missing. quartifyr_styling counts as present because the bundled source is
# put on PYTHONPATH. Returns the interpreter path.
.verify_python_env <- function(env, modules = .required_python_modules) {
  python <- .python_exe(env)
  probe <- paste(
    "import importlib.util",
    sprintf("mods = %s", paste0("[", paste0("'", names(modules), "'", collapse = ", "), "]")),
    "print(','.join(m for m in mods if importlib.util.find_spec(m) is None))",
    sep = "\n"
  )
  res <- processx::run(python, c("-c", probe), env = .python_env_vars(), error_on_status = FALSE)
  if (!isTRUE(res$status == 0)) {
    cli::cli_abort(
      c(
        "x" = "The Python interpreter {.path {python}} could not be run.",
        "i" = "Underlying error: {trimws(res$stderr)}"
      ),
      class = "quartifyr_python_env_invalid",
      call = NULL
    )
  }
  missing <- Filter(nzchar, strsplit(trimws(res$stdout), ",", fixed = TRUE)[[1]])
  if (length(missing) > 0) {
    packages <- unname(modules[missing])
    cli::cli_abort(
      c(
        "x" = "The Python environment {.path {env}} is missing required module{?s}: {.val {missing}}.",
        "i" = paste(
          "Install {.val {packages}} into it, for example",
          "{.code pip install --no-index --find-links <wheel-dir> python-docx pyyaml}."
        )
      ),
      class = "quartifyr_python_env_invalid",
      call = NULL
    )
  }
  python
}

# pyro runs uv_setup.sh through processx and lets the failure propagate as
# "System command 'uv_setup.sh' failed", with the script's stderr -- the part
# that says what uv actually objected to -- only on the condition object.
# Pull it out (last lines are the useful ones) so errors can show it.
.process_error_detail <- function(e, max_lines = 12) {
  for (cond in list(e, e$parent)) {
    text <- cond$stderr
    if (is.character(text) && nzchar(trimws(paste(text, collapse = "")))) {
      lines <- strsplit(paste(text, collapse = "\n"), "\n", fixed = TRUE)[[1]]
      lines <- lines[nzchar(trimws(lines))]
      return(paste(utils::tail(lines, max_lines), collapse = "\n"))
    }
  }
  conditionMessage(e)
}

# What an error says, including the stderr pyro hides on the processx
# condition (see .process_error_detail()).
.error_text <- function(e) {
  paste(conditionMessage(e), .process_error_detail(e), sep = "\n")
}

# Whether an error looks like uv failing to sync, resolve or download
# something, as opposed to the step's own logic failing. Deliberately narrow:
# a render-time error is only re-labelled `quartifyr_offline_failure` when it
# reads like a network or environment problem, never for an ordinary failure
# such as a bad figure.
.looks_like_uv_failure <- function(text) {
  # Phrases uv and the network stack actually use, not bare words: the text
  # searched can include reportifyr's log lines, which carry file paths, and a
  # project under a folder called `offline-study/` or `network-model/` must not
  # turn every ordinary error into "cannot ... without network access".
  grepl(
    paste(
      "no solution found", "failed to fetch", "failed to download",
      "network (is )?unreachable", "network connectivity is disabled",
      "was not found in the cache", "temporary failure in name resolution",
      "connect(ion)? (refused|error|timed out|reset)", "tcp connect error",
      "dns error", "error sending request", "not found in the package registry",
      "no matching distribution", "uv_setup\\.sh",
      sep = "|"
    ),
    text,
    ignore.case = TRUE
  )
}

# What to show of a failure whose cause was found in `text` rather than in the
# condition itself: the lines that read like uv's complaint, else the tail.
.uv_failure_detail <- function(text, max_lines = 12) {
  lines <- strsplit(paste(text, collapse = "\n"), "\n", fixed = TRUE)[[1]]
  lines <- trimws(lines[nzchar(trimws(lines))])
  hits <- lines[vapply(lines, .looks_like_uv_failure, logical(1)) | grepl("^error", lines, ignore.case = TRUE)]
  paste(utils::tail(if (length(hits) > 0) unique(hits) else lines, max_lines), collapse = "\n")
}

# Runs `fn()` with everything it prints to stdout also collected in
# `into$lines`, still shown as it happens. reportifyr/pyro send uv's stderr
# through a callback that `cat()`s it, so this is where a pass-2 uv error
# becomes readable at all: pyro's own error carries only "<script> failed.".
.tee_stdout <- function(fn, into) {
  connection <- textConnection("captured_lines", "w", local = TRUE)
  sink(connection, split = TRUE)
  on.exit({
    sink()
    into$lines <- c(into$lines, textConnectionValue(connection))
    close(connection)
  })
  fn()
}

# Ask uv itself why it can't run reportifyr's Python module offline, by
# running the cheapest command pass 2 would (`uv run -m reportipyr.cli
# --help`) the way reportifyr does. reportifyr's `validate_docx()` -- the first
# thing pass 2 runs -- throws away uv's stderr, so when that is what failed
# there is otherwise nothing to read. Returns uv's stderr when the probe
# fails, NULL when it works (so the original failure wasn't uv's) or can't be
# run.
.probe_uv <- function(project_dir) {
  tryCatch(
    withr::with_dir(project_dir, {
      venv_dir <- if (is.null(getOption("venv_dir"))) getwd() else getOption("venv_dir")
      if (!dir.exists(file.path(venv_dir, ".venv"))) {
        return(NULL) # nothing for uv to run in; pyro would only log an error
      }
      withr::with_options(list(venv_dir = venv_dir), {
        paths <- pyro::get_venv_uv_paths()
        res <- processx::run(
          paths$uv, c("run", "-m", "reportipyr.cli", "--help"),
          env = c("current", VIRTUAL_ENV = paths$venv, PYTHONPATH = system.file("python", package = "reportifyr")),
          error_on_status = FALSE, timeout = 60
        )
        if (isTRUE(res$status == 0)) NULL else paste(res$stderr, collapse = "\n")
      })
    }),
    error = function(e) NULL
  )
}

# Runs `expr`; in offline mode, turns a failure that looks like uv reaching
# for the network into a `quartifyr_offline_failure` naming `step`. Errors
# that already say what is wrong (a missing sidecar, an earlier offline
# failure) and ones that don't look like uv pass through unchanged.
#
# The condition itself often can't say: pyro reports only "<script> failed."
# and reportifyr only "validate-docx failed". So `evidence()` supplies what the
# step printed while it ran (uv's stderr, where it was shown at all), and
# `probe()` -- consulted only when that still doesn't explain it -- asks uv
# directly.
.with_offline_context <- function(expr, step, evidence = NULL, probe = NULL) {
  tryCatch(
    expr,
    error = function(e) {
      if (!.offline_mode() || inherits(e, c("quartifyr_pass2_failed", "quartifyr_offline_failure"))) {
        stop(e)
      }
      text <- .error_text(e)
      if (!is.null(evidence)) {
        text <- paste(c(text, evidence()), collapse = "\n")
      }
      if (!.looks_like_uv_failure(text) && !is.null(probe)) {
        probed <- probe()
        if (!is.null(probed)) {
          text <- paste(c(text, probed), collapse = "\n")
        }
      }
      if (!.looks_like_uv_failure(text)) {
        stop(e)
      }
      detail <- .uv_failure_detail(text)
      .abort_offline(
        step = step,
        resource = "uv to sync or download the project's Python environment, which a render in offline mode never does",
        how = c(
          "Provision the environment before rendering: run {.fn initialize_quartifyr_project} and {.code reportifyr::initialize_report_project()} once, with a populated uv cache or wheels.",
          "The error was: {detail}"
        ),
        parent = e
      )
    }
  )
}

# --- Is the environment the project's pin would accept? -----------------------
#
# Offline, uv runs with --no-sync semantics (UV_NO_SYNC): it uses the project's
# environment exactly as it is. If that environment's interpreter doesn't
# satisfy the project's pin, uv only prints "Using incompatible environment
# (`.venv`) due to `--no-sync`" and carries on, which is how a render ends up
# on an interpreter the project never asked for (and why the environment used
# to be recreated on every call online). So say so in the result.

.parse_py_version <- function(text) {
  hit <- regmatches(text, regexpr("[0-9]+(\\.[0-9]+){0,2}", text))
  if (length(hit) == 0) NULL else as.integer(strsplit(hit, ".", fixed = TRUE)[[1]])
}

.pad_version <- function(v, n = 3L) c(v, rep(0L, max(0L, n - length(v))))[seq_len(n)]

# -1, 0 or 1
.compare_versions <- function(a, b) {
  a <- .pad_version(a)
  b <- .pad_version(b)
  for (i in seq_along(a)) {
    if (a[[i]] != b[[i]]) {
      return(if (a[[i]] < b[[i]]) -1L else 1L)
    }
  }
  0L
}

# Whether `version` (integer vector) satisfies a PEP 440 `requires-python`
# specifier such as ">=3.10,<3.14". NA when the specifier uses something this
# doesn't understand, so an exotic pin never produces a false alarm.
.satisfies_requires_python <- function(version, spec) {
  parts <- trimws(strsplit(spec, ",", fixed = TRUE)[[1]])
  parts <- parts[nzchar(parts)]
  if (length(parts) == 0) {
    return(NA)
  }
  results <- vapply(parts, function(part) {
    m <- regmatches(part, regexec("^(>=|<=|==|!=|~=|>|<)\\s*([0-9]+(?:\\.[0-9]+)*)(\\.\\*)?$", part))[[1]]
    if (length(m) == 0) {
      return(NA)
    }
    op <- m[[2]]
    wanted <- as.integer(strsplit(m[[3]], ".", fixed = TRUE)[[1]])
    wildcard <- nzchar(m[[4]])
    prefix_equal <- function(n) identical(.pad_version(version)[seq_len(n)], .pad_version(wanted)[seq_len(n)])
    switch(op,
      ">=" = .compare_versions(version, wanted) >= 0,
      ">" = .compare_versions(version, wanted) > 0,
      "<=" = .compare_versions(version, wanted) <= 0,
      "<" = .compare_versions(version, wanted) < 0,
      "==" = if (wildcard) prefix_equal(length(wanted)) else .compare_versions(version, wanted) == 0L,
      "!=" = if (wildcard) !prefix_equal(length(wanted)) else .compare_versions(version, wanted) != 0L,
      "~=" = .compare_versions(version, wanted) >= 0 && prefix_equal(max(1L, length(wanted) - 1L))
    )
  }, logical(1))
  if (anyNA(results)) NA else all(results)
}

# The same, for an interpreter version known only to `length(version)`
# components (uv writes `version_info = 3.12` to pyvenv.cfg). A missing
# component isn't zero: it could be anything. Evaluates the specifier at both
# ends of what the version could be and answers only when they agree.
.satisfies_partial_version <- function(version, spec) {
  if (length(version) >= 3L) {
    return(.satisfies_requires_python(version, spec))
  }
  low <- .satisfies_requires_python(c(version, rep(0L, 3L - length(version))), spec)
  high <- .satisfies_requires_python(c(version, rep(9999L, 3L - length(version))), spec)
  if (!is.na(low) && !is.na(high) && identical(low, high)) low else NA
}

# The interpreter version recorded in `<env>/pyvenv.cfg`, or NULL. Python's
# own venv writes `version = 3.12.3`; uv writes `version_info`, sometimes with
# fewer components. Takes the most specific one present.
.venv_python_version <- function(env) {
  cfg <- file.path(env, "pyvenv.cfg")
  if (!file.exists(cfg)) {
    return(NULL)
  }
  lines <- readLines(cfg, warn = FALSE)
  hits <- grep("^(version|version_info)\\s*=", lines, value = TRUE)
  versions <- Filter(Negate(is.null), lapply(sub("^[^=]*=", "", hits), .parse_py_version))
  if (length(versions) == 0) {
    return(NULL)
  }
  versions[[which.max(vapply(versions, length, integer(1)))]]
}

# What the project asks of its interpreter: `.python-version` (uv's own pin)
# first, else `requires-python` in pyproject.toml. NULL when there is none or
# it isn't one this can read.
.project_python_pin <- function(project_dir) {
  pin_file <- file.path(project_dir, ".python-version")
  if (file.exists(pin_file)) {
    lines <- trimws(readLines(pin_file, warn = FALSE))
    lines <- lines[nzchar(lines) & !startsWith(lines, "#")]
    wanted <- if (length(lines) > 0) .parse_py_version(lines[[1]]) else NULL
    if (!is.null(wanted)) {
      return(list(source = ".python-version", text = lines[[1]], wanted = wanted))
    }
  }
  pyproject <- file.path(project_dir, "pyproject.toml")
  if (file.exists(pyproject)) {
    hit <- grep("^\\s*requires-python\\s*=", readLines(pyproject, warn = FALSE), value = TRUE)
    if (length(hit) > 0) {
      spec <- gsub("^[^=]*=\\s*[\"']|[\"']\\s*(#.*)?$", "", hit[[1]])
      return(list(source = "requires-python in pyproject.toml", text = spec, spec = spec))
    }
  }
  NULL
}

# NULL when the environment's interpreter suits the project's pin (or either
# can't be determined); otherwise a sentence saying how it doesn't. `env` may
# be the venv or a project directory holding a `.venv`.
.python_env_mismatch <- function(project_dir, env) {
  env <- .python_env_venv(env)
  have <- .venv_python_version(env)
  pin <- .project_python_pin(project_dir)
  if (is.null(have) || is.null(pin)) {
    return(NULL)
  }
  ok <- if (!is.null(pin$wanted)) {
    # A pin names as many components as it names ("3.12" accepts any 3.12.x),
    # and an interpreter version that only names some of them ("3.12") can only
    # be compared on those.
    n <- min(length(pin$wanted), length(have))
    identical(have[seq_len(n)], pin$wanted[seq_len(n)])
  } else {
    .satisfies_partial_version(have, pin$spec)
  }
  if (isTRUE(ok) || is.na(ok)) {
    return(NULL)
  }
  paste0(
    "The Python environment in ", env, " runs Python ", paste(have, collapse = "."),
    ", but the project pins ", pin$text, " (", pin$source, "). Offline, uv uses the environment as it is ",
    "(\"Using incompatible environment\"), so the render ran on an interpreter the project did not ask for. ",
    "Recreate the environment with the pinned interpreter, or relax the pin."
  )
}

# The environment pass 2 and the styling steps will use: the configured
# python_env if there is one, else the project's own `.venv`.
.render_python_env <- function(project_dir) {
  configured <- .configured_python_env()
  if (!is.null(configured)) {
    return(configured)
  }
  venv_dir <- if (is.null(getOption("venv_dir"))) project_dir else getOption("venv_dir")
  file.path(venv_dir, ".venv")
}
