# The schema-engine pin, and the measurement that justifies it.
#
# The released contracts are draft/2020-12 and depend on constructs only that dialect
# evaluates correctly. jsonvalidate handles them with engine = "ajv"; its *default* engine,
# "imjv", mis-verifies some of them, in both directions at once. That was the finding of
# docs/CAPABILITY.md, and it is why the engine is a constant in this package rather than an
# argument, why [bh_dialect_probe()] runs before every validation, and why the contrast is
# pinned below: if a future jsonvalidate makes imjv correct, the contrast test fails and
# someone re-reads this file before relaxing anything.
#
# The probe records are not invented. Each one is the record of a released shared-suite
# vector, and the expected verdict is that vector's `expected` field in
# tests/conformance/manifest.json - upstream's claim, not this package's opinion. The
# vector ids below were chosen because each exercises one of the constructs at issue: a
# version-gated if/then, contains with minContains, a $defs reference, or a format
# assertion.

# (vector id, construct it exercises)
.bh_probe_vectors <- list(
  c("fasta-extension-fields", "version-gated if/then: x- keys allowed from FHR 2.1"),
  c("fasta-extension-older-version", "version-gated if/then: x- keys invalid at 2.0"),
  c("fasta-extension-older-release", "release-gated: the v0.4.0 contract has no x- keys"),
  c("fasta-extension-nested", "nested objects stay closed: propertyNames/not/pattern"),
  c("fasta-extension-key-uppercase-prefix", "the extension key pattern"),
  c("fhp-fasta-extension-fields", "FHP version gate at 1.1/1.2"),
  c("fhp-fasta-extension-older-version", "FHP version gate rejects x- at 1.0"),
  c("fhp-fasta-busco-lineage-dotted", "$defs Completeness pattern, widened in 1.2"),
  c("fhp-fasta-busco-lineage-trailing-dot", "the same pattern, malformed"),
  c("fhgff3-extension-fields", "FHGFF3 version gate at 1.1/1.2"),
  c("fhgff3-extension-older-version", "FHGFF3 version gate rejects x- at 1.0"),
  c("fhgff3-two-annotates", "contains + minContains: not two annotates parents"),
  c("fhgff3-both-links", "contains + the annotates $ref conditional, valid form"),
  c("fhgff3-minimal-checksum-link", "items: {if: {$ref: AnnotatesAny}, then: headerType"),
  c("fhgff3-annotates-fhp", "the same conditional rejects an FHP parent"),
  c("fasta-date-and-uri", "format assertions: date and uri"),
  c("fhp-fasta-database-source", "the FHP source/sourceType definitions"),
  c("fhgff3-fhr-only-key", "additionalProperties false against the wrong type's keys")
)

.bh_probe_data <- function() {
  out <- list()
  for (pv in .bh_probe_vectors) {
    id <- pv[[1L]]
    v <- tryCatch(.bh_vector(id), error = function(e) NULL)
    if (is.null(v)) next # a vector the pinned baseline does not have
    a <- .bh_capture(.bh_analyze(.bh_vector_path(id), format = v$format,
      validate_contract = FALSE
    ))
    if (!is.null(a$error) || is.null(a$value$record)) next
    sel <- bh_select(a$value$record$schema,
      schema_version = a$value$record$schemaVersion
    )
    if (is.na(.bh_c(sel$file, NA_character_))) next
    out[[length(out) + 1L]] <- list(
      id = id, construct = pv[[2L]], text = rawToChar(.bh_read_all(sel$file)),
      data = .bh_json(a$value$record), expect = identical(v$expected, "valid"),
      type = sel$header_type, version = sel$schema_version
    )
  }
  out
}

test_that("the engine is pinned in code, not by configuration", {
  expect_identical(FAIRbioHeadersTools:::.bh_engine, "ajv")
  ns <- asNamespace("FAIRbioHeadersTools")
  nms <- ls(ns, all.names = TRUE)
  funs <- nms[vapply(nms, function(nm) is.function(get(nm, envir = ns)), logical(1L))]
  takes <- funs[vapply(funs, function(nm) "engine" %in% names(formals(get(nm, envir = ns))),
    logical(1L)
  )]
  expect_equal(setdiff(takes, "json_validator"), character())
  expect_true(any(grepl(".bh_engine", deparse(ns$.bh_validator), fixed = TRUE)))
})

test_that("the dialect self-check passes on this jsonvalidate", {
  expect_true(all(unlist(bh_dialect_probe())))
})

test_that("rule R13 is enforced by the reader, not by the schema, and the reader says so", {
  # docs/SCHEMA-VERSIONS.md, "Values the schema does not check": JSON cannot represent NaN
  # and `minimum`/`maximum` comparisons with NaN are false, so a range check does not catch
  # it. A validator that only ran the schema would call this record valid; this package
  # rejects it in the YAML layer. That is why the vector is not in the schema-layer set.
  v <- .bh_vector("fasta-extension-nan")
  expect_equal(v$expected, "invalid")
  schema_only <- .bh_capture(.bh_analyze(.bh_vector_path("fasta-extension-nan"),
    format = v$format, validate_contract = FALSE, verify_checksum = FALSE
  ))
  expect_match(paste(schema_only$value$issues, collapse = " "), "R13")
  full <- bh_validate(.bh_vector_path("fasta-extension-nan"))
  expect_false(full$valid)
})

test_that("ajv reproduces the manifest's own verdict on every pinned vector record", {
  ps <- .bh_probe_data()
  expect_gte(length(ps), 15L)
  wrong <- character()
  for (p in ps) {
    if (.bh_verdict(p$text, p$data, "ajv") != p$expect) wrong <- c(wrong, p$id)
  }
  expect_equal(wrong, character())
  cat("ajv matched the manifest on", length(ps) - length(wrong), "of", length(ps),
      "contract-layer vectors\n")
})

test_that("the default imjv engine mis-verifies these same constructs", {
  ps <- .bh_probe_data()
  got <- vapply(ps, function(p) .bh_verdict(p$text, p$data, "imjv"), logical(1L))
  want <- vapply(ps, function(p) p$expect, logical(1L))
  ids <- vapply(ps, function(p) p$id, "")
  wrong <- got != want
  silent <- ids[wrong & got] # the contract rejects, imjv accepts
  rejected <- ids[wrong & !got] # the contract accepts, imjv rejects
  cat("imjv mis-verifies", sum(wrong), "of", length(ps), "vectors\n")
  cat("  silent accepts:", paste(sQuote(silent), collapse = ", "), "\n")
  cat("  false rejects :", paste(sQuote(rejected), collapse = ", "), "\n")
  # the guard: the pin exists because imjv gets *both* directions wrong on upstream data.
  # If a future jsonvalidate fixes imjv, this fails and the pin can be re-examined - by
  # measurement, not by assumption.
  expect_gte(sum(wrong), 1L)
  expect_true(length(silent) > 0L || length(rejected) > 0L)
})

test_that("bh_validate names the contract a verdict came from", {
  ok <- bh_validate(.bh_vector_path("fasta-lf"))
  expect_true(ok$valid)
  expect_equal(ok$contract$header_type, "FHR")
  expect_equal(ok$contract$rule, "V3")
  bad <- bh_validate(.bh_vector_path("fasta-unknown-key"))
  expect_false(bad$valid)
  expect_gt(length(bad$errors), 0L)
  unsup <- bh_validate(.bh_vector_path("fasta-schema-unknown-release"))
  expect_false(unsup$valid)
  expect_match(paste(unsup$issues, collapse = " "), "unsupported schema version")
})

test_that("a contract that does not declare draft/2020-12 is refused, not guessed at", {
  d <- file.path(tempdir(), "bh-dialect")
  dir.create(d, showWarnings = FALSE)
  f <- file.path(d, "draft07.json")
  writeLines('{"$schema":"https://json-schema.org/draft-07/schema#","type":"object"}', f)
  expect_error(FAIRbioHeadersTools:::.bh_validator(f), "not draft/2020-12",
    class = "bh_dialect"
  )
  g <- file.path(d, "no-dialect.json")
  writeLines('{"type":"object"}', g)
  expect_error(FAIRbioHeadersTools:::.bh_validator(g), "no \\$schema", class = "bh_dialect")
})
