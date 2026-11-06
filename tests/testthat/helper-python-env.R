# A minimal fake venv (a directory with a pyvenv.cfg), for the python_env tests.
.make_venv <- function(dir, name = ".venv") {
  venv <- file.path(dir, name)
  dir.create(file.path(venv, "bin"), recursive = TRUE)
  writeLines("home = /usr/bin", file.path(venv, "pyvenv.cfg"))
  venv
}

.mock_python_env <- function(env = parent.frame()) {
  local_mocked_bindings(.verify_python_env = function(env, ...) "python", .env = env)
}
