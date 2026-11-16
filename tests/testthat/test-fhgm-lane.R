# The FHGM draft lane: a type that is not a header type, validated on the suite FHGM
# publishes for it. Expectations come from that suite's own manifest, which records four
# independent layers per vector; this package compares the layers it can actually evaluate
# and names the rules it cannot.
#
# The three controls at the bottom of this file are the reason the run means something:
# a byte moved inside checksum coverage, a recorded pin zeroed, and a model checker made
# to accept everything. Each one turns a labelled draft run red. If any of them goes green,
# the acceptance evidence above is not being checked, it is being asserted.

.fhgm <- NULL
.bh_fhgm_path <- function(rel) file.path(.bh_fhgm_suite_dir(), rel)

.fhgm_run <- function() {
  if (is.null(.bhc$fhgm)) .bhc$fhgm <<- suppressWarnings(bh_draft_fhgm_vectors())
  .bhc$fhgm
}

test_that("the FHGM draft vectors are vendored with their own provenance and count", {
  pinned <- FAIRbioHeadersTools:::.bh_vendored()$draft_fhgm_vectors
  expect_equal(pinned$vectors, 43L)
  expect_match(pinned$manifest_sha256, "^[0-9a-f]{64}$")
  expect_match(pinned$commit, "^[0-9a-f]{40}$")
  expect_equal(pinned$files, 28L)
  expect_equal(pinned$examples, 30L)
  dir <- .bh_fhgm_suite_dir()
  expect_identical(.bh_sha256_hex(.bh_read_all(file.path(dir, "manifest.json"))),
    pinned$manifest_sha256
  )
  # every per-vector file the manifest cites is present, including the ones that live in
  # the examples tree rather than the suite directory
  man <- jsonlite::fromJSON(file.path(dir, "manifest.json"), simplifyVector = FALSE)
  cited <- vapply(man$vectors, function(v) normalizePath(
    file.path(dir, v$file), mustWork = FALSE
  ), "")
  expect_equal(sum(file.exists(cited)), 43L)
  # the generator and checker scripts stay upstream; the data does not
  expect_false(any(grepl("[.]py$", list.files(dir, recursive = TRUE))))
  # and the record contract the lane validates against is the pinned draft, not a copy
  pins <- bh_draft_pins()
  row <- pins[pins$header_type == "FHGM", ]
  expect_true(isTRUE(row$digest_ok))
  expect_equal(row$bytes, 9564L)
})

test_that("base and checksum layers agree with the suite on every vector", {
  y <- .fhgm_run()
  expect_equal(y$vectors, 43L)
  expect_equal(sum(y$results$got_base == y$results$expected_base), 43L)
  expect_equal(sum(y$results$got_checksum == y$results$expected_checksum), 43L)
  expect_equal(y$failures, 0L)
  cat(paste0(
    "FHGM draft suite: ", nrow(y$results), " vectors | base ",
    sum(y$results$got_base == y$results$expected_base), "/43 | checksum ",
    sum(y$results$got_checksum == y$results$expected_checksum), "/43 | model layer ",
    "compared and agreeing ", sum(y$results$status == "pass"),
    " | not-run with named rules ", sum(y$results$status == "not-run"), "\n"
  ))
})

test_that("a vector whose model verdict needs a checker rule is not-run, never passed", {
  y <- .fhgm_run()
  nr <- y$results[y$results$status == "not-run", ]
  expect_equal(nrow(nr), 34L)
  expect_true(all(nzchar(nr$reason)))
  expect_true(all(grepl("does not implement", nr$reason)))
  # and each such vector names at least one rule outside this package's model layer
  expect_true(all(nzchar(nr$rule_gaps)))
  # and no not-run row is here because the suite omitted its label: that case is reported,
  # never counted as in-scope (see vectorsNotRunUnlabelled in tools/acceptance_fhgm.R)
  expect_equal(sum(!nzchar(nr$rules)), 0L)
  # the pass column is not carrying acceptances only: six of the nine compared vectors
  # are expected rejections, and this package rejects them
  cmp <- y$results[y$results$status == "pass", ]
  expect_equal(nrow(cmp), 9L)
  expect_gte(sum(cmp$expected_model == "reject"), 1L)
  expect_gte(sum(cmp$expected_model == "pass"), 1L)
  expect_true(all(cmp$got_model == cmp$expected_model))
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

test_that("a suite path that is named is the suite that runs, or nothing runs", {
  bogus <- file.path(tempdir(), "bh-no-fhgm-suite-here")
  dir.create(bogus, showWarnings = FALSE)
  withr::with_options(list(bh.fhgm_dir = bogus), {
    expect_error(.bh_fhgm_suite_dir(), "holds no manifest.json",
      class = "bh_conformance"
    )
    expect_error(bh_draft_fhgm_vectors(), "holds no manifest.json",
      class = "bh_conformance"
    )
  })
  # named and right -> that path is used
  real <- .bh_fhgm_suite_dir()
  expect_equal(withr::with_options(list(bh.fhgm_dir = real), .bh_fhgm_suite_dir()), real)
  # nothing named -> the vendored copy is found
  expect_true(nzchar(.bh_fhgm_suite_dir()))
  expect_error(.bh_search("definitely-not-here", "FHGM development suite"), "Looked in",
    class = "bh_conformance"
  )
})

test_that("a case-mangled suite path fails where the filesystem is case-sensitive", {
  # A positive control for the control above, measured rather than assumed: APFS resolves
  # a case-mangled path, ext4 does not. On the case-insensitive leg this test asserts the
  # filesystem really is the thing rescuing the path - it does not skip, so a macOS green
  # cannot be mistaken for the guard having passed.
  real <- .bh_fhgm_suite_dir()
  probe <- file.path(tempdir(), paste0("bhcase", as.integer(Sys.time()), sample.int(999L, 1L)))
  dir.create(probe, showWarnings = FALSE, recursive = TRUE)
  on.exit(unlink(probe, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(probe, "probe.txt"))
  case_sensitive <- !file.exists(file.path(probe, "PROBE.txt"))
  # mangle the suite directory's own name, not some other component of the path
  mangled <- file.path(dirname(real), toupper(basename(real)))
  expect_false(identical(mangled, real))
  if (case_sensitive) {
    cat(paste0(
      "case-sensitivity control: this filesystem is case-sensitive, so '", mangled,
      "' must not resolve, and the named-path guard is asserted here\n"
    ))
    withr::with_options(list(bh.fhgm_dir = mangled), {
      expect_error(.bh_fhgm_suite_dir(), "holds no manifest.json",
        class = "bh_conformance"
      )
    })
  } else {
    # the trap, named: on this filesystem the mangled path resolves to the real suite, so
    # this leg cannot prove the guard and says so in the test output instead of a skip
    cat(paste0(
      "case-sensitivity control: this filesystem is case-insensitive, so '", mangled,
      "' resolves to the real suite. The guard is proven on the case-sensitive (Linux) ",
      "CI leg, not here.\n"
    ))
    expect_true(file.exists(file.path(mangled, "manifest.json")))
  }
})

test_that("the run refuses to report when the recorded suite pin no longer matches", {
  prov <- FAIRbioHeadersTools:::.bh_vendored()
  bad <- prov
  bad$draft_fhgm_vectors$manifest_sha256 <- strrep("0", 64)
  assign("vendored", bad, envir = .bh_state)
  on.exit(rm(vendored, envir = .bh_state), add = TRUE)
  # an abort, not a not-run, not a pass: and no receipt is written by a run that never began
  receipt <- tempfile()
  withr::with_envvar(c(BH_FHGM_RECEIPT = receipt), {
    out <- tryCatch(bh_draft_fhgm_vectors(), condition = function(e) e)
    # `error` first: a *successful* run also returns a bh_conformance object, so the class
    # alone would pass on the very outcome this control is meant to rule out
    expect_true(inherits(out, "error"))
    expect_s3_class(out, "bh_conformance")
    expect_match(conditionMessage(out), "pinned")
    cat(paste0(
      "control 2 (recorded suite digest zeroed): the run refused - ",
      substr(conditionMessage(out), 1L, 90L), "... - and wrote no receipt (",
      file.exists(receipt), ")\n"
    ))
  })
  expect_false(file.exists(receipt))
})

test_that("one byte moved inside checksum coverage turns the labelled draft run red", {
  # The same suite, the same manifest, one fixture changed outside the header block and
  # inside the bytes the file checksum covers. The base layer must still accept (nothing
  # about the header moved), the checksum layer must say stale, and the vector must fail.
  src <- .bh_fhgm_suite_dir()
  root <- tempfile("fhgm-tamper")
  dir.create(root, recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  # the vectors cite ../examples/... relative to the suite, so the sibling tree comes too;
  # a recursive file.copy lands the directory inside an existing target directory
  file.copy(src, root, recursive = TRUE)
  file.copy(file.path(dirname(src), "examples"), root, recursive = TRUE)
  suite <- file.path(root, basename(src))
  target <- file.path(suite, "vectors/valid/supplied-external-model-id.fhgff3.gff3")
  before <- .bh_read_all(target)
  lines <- readLines(target)
  i <- grep("^toy\tpilot\tgene\t10", lines)
  expect_length(i, 1L)
  lines[i] <- sub("ID=toy-a", "ID=toy-A", lines[i])
  writeLines(lines, target)
  after <- .bh_read_all(target)
  # the mutation landed: prove it on bytes, because a control that changed nothing is a
  # pass that means nothing
  expect_false(identical(before, after))
  expect_equal(abs(length(after) - length(before)), 0L)
  expect_equal(sum(as.integer(after) != as.integer(before)), 1L)

  y <- suppressWarnings(bh_draft_fhgm_vectors(suite = suite))
  expect_equal(y$vectors, 43L)
  expect_equal(y$failures, 1L)
  row <- y$results[y$results$status == "fail", ]
  cat(paste0(
    "control 1 (one byte inside checksum coverage): ", y$vectors, " vectors evaluated, ",
    y$failures, " failure (", row$id, ": got_base=", row$got_base,
    " got_checksum=", row$got_checksum, ") - the labelled draft run goes red\n"
  ))
  expect_equal(row$id, "supplied-external-model-id")
  expect_equal(row$got_base, "accept") # base still fine: the header did not move
  expect_equal(row$got_checksum, "stale")
  expect_match(row$reason, "checksum stale vs expected verify")
  # and the untouched vendored suite is untouched: 0 failures there
  expect_equal(suppressWarnings(bh_draft_fhgm_vectors())$failures, 0L)
})

test_that("a model checker that accepts everything is caught, not thanked", {
  # The neutered-loop control, as a standing test. bh_validate_fhgm() is replaced with a
  # version that reports every record valid - the exact failure mode a schema-only port
  # would have - and the run must turn the four comparable expected-rejection vectors into
  # failures instead of passing them.
  y <- .fhgm_run()
  expect_equal(y$failures, 0L)
  cmp_reject <- sum(y$results$status == "pass" & y$results$expected_model == "reject")
  expect_gte(cmp_reject, 1L)

  neutered <- function(path, format = "fhgff3", compressed = NA) {
    list(
      records = data.frame(index = 1L, valid = TRUE, errors = "", modelId = NA_character_,
        stringsAsFactors = FALSE
      ),
      all_valid = TRUE, n_records = 1L, warnings = character(),
      contract = list(commit = NA_character_, sha256 = NA_character_), present = TRUE,
      transport_ok = TRUE
    )
  }
  local_mocked_bindings(bh_validate_fhgm = neutered, .package = "FAIRbioHeadersTools")
  # the mock is live on the path the runner uses - without this line the control below
  # would prove nothing about the runner and everything about a binding nobody called
  expect_true(isTRUE(FAIRbioHeadersTools::bh_validate_fhgm(
    .bh_fhgm_path("vectors/invalid/record-unknown-key.fhgff3.gff3")
  )$all_valid))
  z <- suppressWarnings(bh_draft_fhgm_vectors())
  expect_equal(z$vectors, 43L)
  expect_equal(z$failures, cmp_reject)
  bad <- z$results[z$results$status == "fail", ]
  cat(paste0(
    "control 3 (model checker neutered to accept everything): ", z$failures,
    " of ", cmp_reject, " comparable expected-rejection vectors now disagree - ",
    paste(bad$id, collapse = ", "), " - each reporting 'model pass vs expected reject'\n"
  ))
  expect_setequal(bad$id, y$results$id[y$results$status == "pass" &
    y$results$expected_model == "reject"])
  expect_true(all(grepl("model pass vs expected reject", bad$reason)))
  # base and checksum layers still agree: only the model verdict moved
  expect_equal(sum(bad$got_base == bad$expected_base), nrow(bad))
  expect_equal(sum(bad$got_checksum == bad$expected_checksum), nrow(bad))
})

test_that("a one-item sequence inside a record keeps the shape its bytes gave it", {
  # R's yaml returns an atomic vector for a single-item sequence, which would reach the
  # pinned record contract as a scalar and reject a record whose bytes say array. This is
  # not a hypothetical: the suite's own s6k fixture writes "deposit":["doi:..."] and the
  # record contract declares deposit an array, so an unrepaired read is a false rejection.
  f <- file.path(dirname(.bh_fhgm_suite_dir()), "examples", "s6k",
    "DanaCAF1_S6k.fhgm-models.fhgff3.gff3"
  )
  expect_true(file.exists(f))
  d <- suppressWarnings(bh_fhgm_models(f, draft = "FHGM"))
  expect_equal(d$count, 1L)
  txt <- FAIRbioHeadersTools:::.bh_record_json(d$records[[1]])
  expect_match(txt, '"deposit":\\["doi:10.22002/e86gh-a7p16"\\]', perl = TRUE)
  v <- suppressWarnings(bh_validate_fhgm(f))
  expect_true(v$all_valid)
  expect_equal(v$n_records, 1L)
  # and the flow scanner is what did it, reading the text rather than the contract
  keys <- FAIRbioHeadersTools:::.bh_fhgm_flow_scalar_keys(
    'x-fhgm-models: [{"publication":{"article":"10.1","deposit":["doi:x"]}}]'
  )
  expect_equal(keys, "deposit")
  expect_equal(FAIRbioHeadersTools:::.bh_fhgm_flow_scalar_keys(
    'x-fhgm-models: [{"publication":{"article":"10.1","deposit":["doi:x","doi:y"]}}]'
  ), character())
})

test_that("the repair never invents an array the bytes did not write", {
  # the same fixture with the brackets removed: a genuine scalar must still be rejected by
  # K2, or the shape repair would be contract-driven coercion wearing a different name.
  src <- file.path(dirname(.bh_fhgm_suite_dir()), "examples", "s6k",
    "DanaCAF1_S6k.fhgm-models.fhgff3.gff3"
  )
  tmp <- tempfile(fileext = ".fhgff3.gff3")
  on.exit(unlink(tmp), add = TRUE)
  l <- readLines(src)
  hit <- grep("x-fhgm-models", l, fixed = TRUE)
  expect_length(hit, 1L)
  l[hit] <- sub('"deposit":\\["doi:10.22002/e86gh-a7p16"\\]',
    '"deposit":"doi:10.22002/e86gh-a7p16"', l[hit], perl = TRUE
  )
  writeLines(l, tmp)
  # the mutation, proven on bytes: two characters gone (the bracket pair), the scalar form
  # present, the array form absent
  before <- .bh_read_all(src)
  after <- .bh_read_all(tmp)
  expect_equal(length(after), length(before) - 2L)
  expect_true(grepl('"deposit":"doi:10.22002/e86gh-a7p16"', rawToChar(after), fixed = TRUE))
  expect_false(grepl('"deposit":[', rawToChar(after), fixed = TRUE))
  v <- suppressWarnings(bh_validate_fhgm(tmp))
  expect_false(v$all_valid)
  expect_match(v$records$errors[[1]], "rejected|additionalProperties|type")
})

test_that("a rule label this build has no note for is still reported as a gap", {
  # upstream may add a rule to its vocabulary; the runner must not crash and must not
  # read an unmapped label as covered
  note <- FAIRbioHeadersTools:::.bh_fhgm_rule_note
  expect_match(note("K9"), "K9")
  expect_match(note("K9"), "no note recorded")
  expect_match(note("K3"), "modelId uniqueness")
})
