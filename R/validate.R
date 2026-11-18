#' Contract validation, with the schema engine pinned
#'
#' The released contracts declare
#' `"$schema": "https://json-schema.org/draft/2020-12/schema"` and rely on constructs only
#' that dialect evaluates correctly - version-gated `if`/`then` blocks, `contains` with
#' `minContains`, `prefixItems`, `$defs` references. `jsonvalidate` handles them, but only
#' with `engine = "ajv"`: its *default* engine (`"imjv"`) was measured wrong on 8 of 32
#' probes against the released contracts, mis-verifying in both directions - accepting
#' records that must be rejected and rejecting valid ones. That is why the engine is a
#' constant here rather than an argument, and why [bh_dialect_probe()] re-checks the
#' 2020-12-only constructs before every validation and refuses to report a verdict when
#' they stop firing.
#'
#' `format` is asserted, as docs/SCHEMA-VERSIONS.md requires of a conforming validator:
#' draft 2020-12 treats `format` as an annotation, and a validator that cannot assert it
#' must say so rather than call the record valid.
#'
#' @name validate
NULL

# The one place the engine is named. Nothing in this package takes it as an argument.
.bh_engine <- "ajv"

.bh_validators <- new.env(parent = emptyenv())

.bh_dialect_uri <- "https://json-schema.org/draft/2020-12/schema"

.bh_validator <- function(file) {
  key <- normalizePath(file, mustWork = TRUE)
  hit <- get0(key, envir = .bh_validators, inherits = FALSE)
  if (!is.null(hit)) return(hit)
  txt <- rawToChar(.bh_read_all(file))
  parsed <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  dialect <- parsed[["$schema"]]
  if (!identical(dialect, .bh_dialect_uri)) {
    bh_abort("dialect", paste0(
      "the contract ", basename(file), " declares ",
      .bh_c(dialect, "no $schema"), ", not draft/2020-12; this package validates the ",
      "released dialect only and will not silently apply another engine to it"
    ))
  }
  v <- jsonvalidate::json_validator(txt, engine = .bh_engine)
  assign(key, v, envir = .bh_validators)
  v
}

#' The engine and dialect self-check
#'
#' Builds the constructs that separate a draft/2020-12 engine from a draft-07 one - a
#' version-gated `if`/`then`, a `contains` with `minContains`, `prefixItems`, and the
#' `format` assertions - and checks each behaves as the 2020-12 specification says. A
#' regression to `engine = "imjv"`, or an upstream change that stops honouring `$schema`,
#' fails here rather than quietly mis-verifying metadata.
#'
#' @return A named list of logical results, invisibly; raises a `bh_dialect` error when
#'   any probe fails.
#' @export
bh_dialect_probe <- function() {
  cached <- get0("dialect_probe", envir = .bh_state, inherits = FALSE)
  if (!is.null(cached)) return(invisible(cached))

  gated <- '{
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "schemaVersion": {"type": "string"},
      "genome": {"type": "string"},
      "version": {"type": "string"},
      "x-anything": {"type": "string"}
    },
    "required": ["genome", "version", "schemaVersion"],
    "if": {"properties": {"schemaVersion": {"const": "2.0"}}, "required": ["schemaVersion"]},
    "then": {"propertyNames": {"not": {"pattern": "^x-"}}}
  }'
  old_with_ext <- '{"schemaVersion": "2.0", "genome": "g", "version": "1", "x-anything": "v"}'
  new_with_ext <- '{"schemaVersion": "2.1", "genome": "g", "version": "1", "x-anything": "v"}'

  contains <- '{
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {"a": {"type": "array"}},
    "if": {"properties": {"a": {"contains": {"const": "x"}, "minContains": 2}}},
    "then": false
  }'
  two_xs <- '{"a": ["x", "x"]}'
  one_x <- '{"a": ["x"]}'

  prefix <- '{
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "array",
    "prefixItems": [{"type": "string"}],
    "items": false
  }'
  good_tuple <- '["s"]'
  bad_tuple <- '[1]'

  fmt <- '{
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "type": "object",
    "properties": {
      "u": {"type": "string", "format": "uri"},
      "d": {"type": "string", "format": "date"}
    }
  }'
  bad_uri <- '{"u": "not a URI"}'
  bad_date <- '{"d": "2022-13-45"}'
  good_fmt <- '{"u": "https://example.org/a", "d": "2020-01-02"}'

  ok <- function(schema, data) {
    v <- jsonvalidate::json_validator(schema, engine = .bh_engine)
    isTRUE(suppressWarnings(v(data)))
  }

  res <- list(
    engine_is_ajv = identical(.bh_engine, "ajv"),
    dialect_declared = TRUE,
    gated_if_then_rejects_extension_at_2_0 = !ok(gated, old_with_ext),
    gated_if_then_allows_extension_at_2_1 = ok(gated, new_with_ext),
    contains_min_contains_fires = !ok(contains, two_xs) && ok(contains, one_x),
    prefix_items_is_2020_12 = ok(prefix, good_tuple) && !ok(prefix, bad_tuple),
    format_uri_asserted = !ok(fmt, bad_uri),
    format_date_asserted = !ok(fmt, bad_date),
    format_accepts_valid = ok(fmt, good_fmt)
  )
  failed <- names(res)[!vapply(res, isTRUE, logical(1L))]
  if (length(failed)) {
    bh_abort("dialect", paste0(
      "the schema engine failed the draft/2020-12 probes (",
      paste(sQuote(failed), collapse = ", "),
      "). This package validates with engine = \"ajv\" for a measured reason: the ",
      "default \"imjv\" engine mis-verifies these constructs in both directions. ",
      "Refusing to report validity from a quietly wrong engine."
    ))
  }
  assign("dialect_probe", res, envir = .bh_state)
  invisible(res)
}

.bh_validate_record <- function(record, selection) {
  if (identical(selection$status, "unsupported")) {
    return(list(
      valid = FALSE, errors = selection$message, warnings = selection$warnings,
      contract = NULL
    ))
  }
  bh_dialect_probe()
  contract <- jsonlite::fromJSON(rawToChar(.bh_read_all(selection$file)),
    simplifyVector = FALSE
  )
  v <- .bh_validator(selection$file)
  json <- .bh_record_json(record)
  res <- tryCatch(
    suppressWarnings(v(json, verbose = TRUE)),
    error = function(e) {
      bh_abort("schema", paste0(
        "the validator could not evaluate ", selection$header_type, ": ",
        conditionMessage(e)
      ))
    }
  )
  errors <- character()
  if (!isTRUE(res)) {
    errs <- .bh_drop_empty_uri_errors(attr(res, "errors"))
    if (is.data.frame(errs) && !nrow(errs)) res <- TRUE
  }
  if (!isTRUE(res)) {
    errors <- if (is.data.frame(errs) && nrow(errs)) {
      col <- function(nm) {
        v <- errs[[nm]]
        if (is.null(v)) rep("", nrow(errs)) else vapply(v, function(x) .bh_c(as.character(x), ""), "")
      }
      paste0(col("instancePath"), " ", col("keyword"), ": ", col("message"))
    } else {
      "the selected contract rejected the record"
    }
  }
  list(
    valid = isTRUE(res), errors = errors, warnings = selection$warnings,
    contract = contract
  )
}

#' The `format: uri` failures that RFC 3986 does not support.
#'
#' A URI may have an empty path, so `doi:` with nothing after the scheme is a URI, and the
#' Python reference accepts it (and warns under R14). ajv's `uri` format rejects it. Only
#' that case is dropped here - a bare scheme and a colon - so every other `uri` verdict
#' stays ajv's. R14 still reports the value: its scheme has nothing after it.
#' @noRd
.bh_drop_empty_uri_errors <- function(errs) {
  if (!is.data.frame(errs) || !nrow(errs) || !"keyword" %in% names(errs)) return(errs)
  data <- if ("data" %in% names(errs)) errs$data else rep(list(NULL), nrow(errs))
  fmt <- if ("params" %in% names(errs) && is.data.frame(errs$params)) errs$params$format else NULL
  if (is.null(fmt) && "format" %in% names(errs)) fmt <- errs$format
  if (is.null(fmt)) return(errs)
  bare <- vapply(seq_len(nrow(errs)), function(i) {
    d <- if (is.list(data)) data[[i]] else data[[i]]
    identical(errs$keyword[[i]], "format") && identical(fmt[[i]], "uri") &&
      is.character(d) && length(d) == 1L && grepl("^[A-Za-z][A-Za-z0-9+.-]*:$", d)
  }, NA)
  errs[!bare, , drop = FALSE]
}
