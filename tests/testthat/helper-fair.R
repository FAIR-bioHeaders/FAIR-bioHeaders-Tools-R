# Shared helpers for the test suite. Files named helper-*.R are loaded by testthat
# before any test file, so the fixtures below are available in every test.

.bhc <- new.env(parent = emptyenv())

.bh_conf <- function() {
  if (is.null(.bhc$suite)) .bhc$suite <- .bh_suite_dir()
  .bhc$suite
}

.bh_manifest <- function() {
  if (is.null(.bhc$man)) {
    .bhc$man <- jsonlite::fromJSON(file.path(.bh_conf(), "manifest.json"),
      simplifyVector = FALSE
    )
  }
  .bhc$man
}

.bh_vector <- function(id) {
  v <- Filter(function(x) identical(x$id, id), .bh_manifest()$vectors)
  if (!length(v)) stop("no such vector id: ", id)
  v[[1L]]
}

.bh_vector_path <- function(id) file.path(.bh_conf(), .bh_vector(id)$file)

#' The parsed record of a valid vector, as a mutable base for schema probes.
#'
#' Using released vectors rather than invented records keeps the "should be accepted"
#' half of every probe anchored upstream: the suite already states these bytes are valid.
.bh_base_record <- function(id) {
  if (is.null(.bhc[[id]])) {
    a <- .bh_capture(.bh_analyze(.bh_vector_path(id),
      format = .bh_vector(id)$format, validate_contract = FALSE
    ))
    if (!is.null(a$error)) stop("base vector ", id, " failed to analyze: ", a$error)
    .bhc[[id]] <- a$value$record
  }
  .bhc[[id]]
}

.bh_contract <- function(type, version) {
  jsonlite::fromJSON(.bh_contract_text(type, version), simplifyVector = FALSE)
}

.bh_contract_text <- function(type, version) {
  rawToChar(.bh_read_all(.bh_inst("schemas", paste0(type, "-", version, ".json"))))
}

.bh_current_release <- function() FAIRbioHeadersTools:::.bh_registry()$current

# The JSON the validator consumes, spelled once and identical to the package's own path.
.bh_json <- function(x) FAIRbioHeadersTools:::.bh_record_json(x)

# Runs one record against one contract text with an explicit engine. Test-only: the
# package itself never takes an engine argument.
.bh_verdict <- function(schema_text, data_json, engine) {
  v <- jsonvalidate::json_validator(schema_text, engine = engine)
  isTRUE(suppressWarnings(v(data_json)))
}
