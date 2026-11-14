# The FHGM draft lane: a type that is not a header type, validated on the suite FHGM
# publishes for it. Expectations come from that suite's own manifest, which records four
# independent layers per vector; this package compares the layers it can actually evaluate
# and names the rules it cannot.

.fhgm <- NULL
.bh_fhgm_path <- function(rel) file.path(.bh_fhgm_suite_dir(), rel)

.fhgm_run <- function() {
  if (is.null(.bhc$fhgm)) .bhc$fhgm <<- suppressWarnings(bh_draft_fhgm_vectors())
  .bhc$fhgm
}

test_that("the FHGM draft vectors are vendored with their own provenance and count", {
  pinned <- FAIRbioHeadersTools:::.bh_vendored()$draft_fhgm_vectors
  expect_equal(pinned$vectors, 31L)
  expect_match(pinned$manifest_sha256, "^[0-9a-f]{64}$")
  expect_match(pinned$commit, "^[0-9a-f]{40}$")
  dir <- .bh_fhgm_suite_dir()
  expect_identical(.bh_sha256_hex(.bh_read_all(file.path(dir, "manifest.json"))),
    pinned$manifest_sha256)
  # the generator and checker scripts stay upstream; the data does not
  expect_false(any(grepl("[.]py$", list.files(dir, recursive = TRUE))))
})

test_that("base and checksum layers agree with the suite on every vector", {
  y <- .fhgm_run()
  expect_equal(y$vectors, 31L)
  expect_equal(sum(y$results$got_base == y$results$expected_base), 31L)
  expect_equal(sum(y$results$got_checksum == y$results$expected_checksum), 31L)
  expect_equal(y$failures, 0L)
  cat(
    "FHGM draft suite:", nrow(y$results), "vectors |",
    "base", sum(y$results$got_base == y$results$expected_base), "/31,",
    "checksum", sum(y$results$got_checksum == y$results$expected_checksum), "/31,",
    "model layer comparable and passing", sum(y$results$status == "pass"), ",",
    "not-run with named rules", sum(y$results$status == "not-run"), "\n"
  )
})

test_that("a vector whose model verdict needs a checker rule is not-run, never passed", {
  y <- .fhgm_run()
  nr <- y$results[y$results$status == "not-run", ]
  expect_gt(nrow(nr), 0L)
  expect_true(all(nzchar(nr$reason)))
  expect_true(all(grepl("does not implement", nr$reason)))
  # and each such vector names at least one rule outside this package's model layer
  expect_true(all(nzchar(nr$rules)))
})

test_that("an FHGFF3 1.1 header transports records; a 1.0 header cannot", {
  good <- .bh_fhgm_path("vectors/valid/both-reference-forms.fhgff3.gff3")
  m <- suppressWarnings(bh_fhgm_models(good, draft = "FHGM"))
  expect_true(m$present)
  expect_equal(m$count, 2L)
  expect_true(all(c("modelId", "featureId", "reference") %in% names(m$records[[1]])))
  v <- suppressWarnings(bh_validate_fhgm(good))
  expect_equal(v$n_records, 2L)
  expect_true(v$all_valid)
  expect_match(v$contract$sha256, "^[0-9a-f]{64}$")
  expect_match(v$contract$commit, "^[0-9a-f]{40}$")

  bad <- .bh_fhgm_path("vectors/invalid/record-unknown-key.fhgff3.gff3")
  v2 <- suppressWarnings(bh_validate_fhgm(bad))
  expect_false(v2$all_valid)
  expect_match(v2$records$errors[[1]], "unexpected|closed|additionalProperties|rejected")

  # the draft notice fires on every use of the lane, and never without it
  warns <- character()
  withCallingHandlers(
    suppressWarnings(bh_validate_fhgm(good)),
    bh_warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  warns2 <- character()
  withCallingHandlers(
    {
      withr::with_options(list(bh.draft_lane = FALSE), {
        bh_read(good, format = "fhgff3")
      })
    },
    bh_warning = function(w) {
      warns2 <<- c(warns2, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  # reading the file as plain FHGFF3, with the lane closed, says nothing about drafts
  expect_equal(length(grep("FHGM", warns2)), 0L)
  # and bh_validate_fhgm always uses the lane, so it always says it
  warns3 <- character()
  withCallingHandlers(
    bh_validate_fhgm(good),
    bh_warning = function(w) {
      warns3 <<- c(warns3, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_match(paste(warns3, collapse = " | "), "unreleased draft")
})

test_that("an empty transport array is a rule-K1 violation, not a vacuous pass", {
  p <- .bh_fhgm_path("vectors/invalid/empty-model-array.fhgff3.gff3")
  v <- suppressWarnings(bh_validate_fhgm(p))
  expect_true(v$present)
  expect_equal(v$n_records, 0L)
  expect_false(v$all_valid)
  expect_match(paste(v$warnings, collapse = " | "), "K1")
})

test_that("a stale file is reported as stale by the checksum layer, separately from model", {
  p <- .bh_fhgm_path("vectors/invalid/tampered-record-bytes.fhgff3.gff3")
  y <- .fhgm_run()
  row <- y$results[y$results$id == "tampered-record-bytes", ]
  expect_equal(row$expected_checksum, "stale")
  expect_equal(row$got_checksum, "stale")
  # the records themselves still have valid shapes: the failure is integrity, not structure,
  # and that is exactly the separation rule B1 states
  v <- suppressWarnings(bh_validate_fhgm(p))
  expect_true(v$all_valid)
  expect_false(bh_verify(p, format = "fhgff3"))
})

test_that("an FHGFF3 1.0 header cannot carry the extension at all", {
  p <- .bh_fhgm_path("vectors/invalid/transport-1-0-extension.fhgff3.gff3")
  # base layer: the released 1.0 contract rejects an unknown key
  base <- bh_validate(p)
  expect_false(base$valid)
  v <- suppressWarnings(bh_validate_fhgm(p))
  expect_false(v$all_valid)
  expect_match(paste(v$records$errors, collapse = " "), "R15|1.0")
})
