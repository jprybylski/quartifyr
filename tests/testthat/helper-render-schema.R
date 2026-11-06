# Shared by the render-result tests: validate a result's JSON against the
# shipped v1 schema (skipped when jsonvalidate isn't installed).
.validate_render_json <- function(json) {
  skip_if_not_installed("jsonvalidate")
  schema_path <- system.file("schemas", "render-result-v1.schema.json", package = "quartifyr")
  skip_if(!nzchar(schema_path), "schema not installed")
  validator <- jsonvalidate::json_validator(schema_path, engine = "ajv")
  validator(as.character(json), verbose = TRUE, greedy = TRUE)
}
