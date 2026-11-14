# The rule V7 draft lane.
#
# Four things are pinned here, matching docs/SCHEMA-VERSIONS.md V7 clause by clause: the
# lane is never the default; release-shaped URLs for unregistered types stay V5 with the
# lane open or shut; the bytes are pinned by commit and SHA-256 and a mismatch is refused
# rather than read; and every record read through the lane carries the warning naming the
# draft, the commit and the digest.

.fht_raw <- "https://raw.githubusercontent.com/FAIR-bioHeaders/FHT-Specification/main/fht.json"

test_that("the bundled drafts are pinned by commit and digest, and the bytes match", {
  pins <- bh_draft_pins()
  expect_equal(nrow(pins), 2L)
  expect_true(all(pins$digest_ok))
  expect_match(pins$commit, "^[0-9a-f]{40}$")
  expect_match(pins$sha256, "^[0-9a-f]{64}$")
  # the FHT draft is the transcriptome contract bytes, 29,430 of them, and FHGM is the
  # nested model contract, not a header contract
  expect_equal(pins$bytes[pins$header_type == "FHT"], 29430L)
  expect_equal(pins$bytes[pins$header_type == "FHGM"], 9564L)
})

test_that("with the lane closed, a draft citation is selected exactly as V5 always did", {
  near_miss <- c(
    .fht_raw,
    "https://w3id.org/fair-bioheaders/fht/v0.7.0", # a release number nobody registered
    "https://w3id.org/fair-bioheaders/fht/v9.9.9",
    "https://raw.githubusercontent.com/FAIR-bioHeaders/FHT-Specification/v0.7.0/fht.json",
    "https://raw.githubusercontent.com/FAIR-bioHeaders/FHGM-Specification/main/fhgm.json"
  )
  for (u in near_miss) {
    off <- bh_select(u)
    expect_equal(off$rule, "V5", info = u)
    expect_equal(off$header_type, "FHR", info = u)
    expect_equal(off$release, .bh_current_release(), info = u)
    expect_equal(off$status, "released", info = u)
    expect_equal(off$warnings, character(), info = u)
    # the documented default-off path, through the public helper
    same <- bh_draft_default_off(u)
    expect_identical(same[names(off)], off[names(same)], info = u)
  }
})

test_that("with the lane open, the owning repository's raw-main URL is the only draft hit", {
  on.exit(bh_draft_lane(FALSE), add = TRUE)
  s <- bh_select(.fht_raw, draft = "FHT")
  expect_equal(s$rule, "V7")
  expect_equal(s$status, "draft")
  expect_equal(s$header_type, "FHT")
  expect_true(is.na(s$release)) # no release is invented for a draft
  expect_true(is.na(s$schema_version))
  expect_match(paste(s$warnings, collapse = " "), "unreleased draft")
  expect_match(paste(s$warnings, collapse = " "), "^[^|]*FHT: warning:")
  expect_match(paste(s$warnings, collapse = " "), "sha256 [0-9a-f]{64}")
  expect_match(paste(s$warnings, collapse = " "), "commit [0-9a-f]{40}")
  # the w3id and raw-tag forms are still not the lane, even now it is open
  for (u in c("https://w3id.org/fair-bioheaders/fht/v0.7.0",
              "https://raw.githubusercontent.com/FAIR-bioHeaders/FHT-Specification/v0.7.0/fht.json")) {
    x <- bh_select(u, draft = TRUE)
    expect_equal(x$rule, "V5", info = u)
    expect_false(x$status == "draft")
  }
})

test_that("a draft record warns on every read, and not at all with the lane closed", {
  # a published FHT development vector, read as a real file through the public API
  p <- file.path(.bh_draft_suite_dir(), "valid/fht-fasta-minimal.fht.fasta")
  skip_if_not(file.exists(p), "FHT development suite not vendored")

  # --- lane closed (the default): the record is read as FHR under V5, exactly as before
  # the lane existed, and no draft notice is emitted
  warns_closed <- character()
  withr::with_options(list(bh.draft_lane = FALSE, warn = 1), {
    withCallingHandlers(
      r_closed <- bh_read(p, format = "fht-fasta"),
      warning = function(w) {
        warns_closed <<- c(warns_closed, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
  })
  expect_equal(r_closed$selection$rule, "V5")
  expect_equal(r_closed$selection$header_type, "FHR")
  expect_equal(r_closed$selection$status, "released")
  expect_equal(length(grep("unreleased draft", warns_closed)), 0L)
  # and it is not valid, because FHR is the wrong contract for transcriptome metadata: the
  # default path neither recognises the draft nor pretends the record conforms
  expect_false(r_closed$valid)

  # --- lane open: the pinned draft is used and every read warns
  warns_open <- character()
  withr::with_options(list(bh.draft_lane = "FHT", warn = 1), {
    withCallingHandlers(
      {
        r_open <- bh_read(p, format = "fht-fasta")
        r_open2 <- bh_read(p, format = "fht-fasta")
      },
      warning = function(w) {
        warns_open <<- c(warns_open, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
  })
  expect_equal(r_open$selection$status, "draft")
  expect_equal(r_open$selection$rule, "V7")
  expect_equal(r_open$header_type, "FHT")
  expect_true(r_open$valid)
  expect_equal(length(grep("unreleased draft", warns_open)), 2L) # per record, not per session
  expect_match(paste(warns_open, collapse = " | "), "commit [0-9a-f]{40}")
  expect_match(paste(warns_open, collapse = " | "), "sha256 [0-9a-f]{64}")

  # and the closed-lane outcome is identical to a call that never mentions the lane
  plain <- bh_read(p, format = "fht-fasta")
  expect_identical(plain$selection[names(r_closed$selection)],
    r_closed$selection[names(plain$selection)])
  expect_identical(plain$valid, r_closed$valid)
})

test_that("the lane state is explicit and reversible", {
  on.exit(bh_draft_lane(FALSE), add = TRUE)
  expect_false(isTRUE(bh_draft_lane()[["FHT"]]))
  expect_true(bh_draft_lane("FHT")[["FHT"]])
  expect_false(bh_draft_lane()[["FHGM"]]) # one type opened, the other still closed
  bh_draft_lane(TRUE)
  expect_true(all(unlist(bh_draft_lane())))
  bh_draft_lane(FALSE)
  expect_false(any(unlist(bh_draft_lane())))
  expect_error(bh_draft_lane("FHX"), "no draft contract is bundled")
})

test_that("a draft pin whose bytes moved is refused, not quietly re-read", {
  # the refusal path is exercised on a copy of the registry with a wrong digest: nothing
  # on disk is touched
  prov <- FAIRbioHeadersTools:::.bh_vendored()
  i <- which(vapply(prov$files, function(r) {
    identical(r$header_type, "FHT") && identical(r$kind, "draft-contract")
  }, logical(1L)))
  expect_length(i, 1L)
  bad <- prov
  bad$files[[i]]$sha256 <- strrep("0", 64)
  assign("vendored", bad, envir = .bh_state)
  on.exit(rm(vendored, envir = .bh_state), add = TRUE)
  expect_error(bh_select(.fht_raw, draft = "FHT"), "no longer match", class = "bh_draft")
  # and the pin is checked by size too, so a truncated copy cannot pass as the draft
  bad2 <- prov
  bad2$files[[i]]$bytes <- 1L
  assign("vendored", bad2, envir = .bh_state)
  expect_error(bh_select(.fht_raw, draft = "FHT"), "bytes, recorded", class = "bh_draft")
  rm(vendored, envir = .bh_state)
  expect_equal(bh_select(.fht_raw, draft = "FHT")$status, "draft") # restored
})

test_that("FHGM stays what the specification says it is: not a header type", {
  t <- bh_types()
  fhgm <- t[t$header_type == "FHGM", ]
  expect_equal(fhgm$status, "draft")
  expect_false(fhgm$is_header_type)
  expect_match(fhgm$note, "not a header type")
  # and it has no row in the version registry, so no schemaVersion of its own
  reg <- FAIRbioHeadersTools:::.bh_registry()
  expect_null(reg$files$FHGM)
  for (rel in names(reg$releases)) expect_null(reg$releases[[rel]]$FHGM)
  # the draft lane's FHGM contract is a model-record schema, so it has no `schema` slot
  fhgm_schema <- jsonlite::fromJSON(
    rawToChar(.bh_read_all(.bh_inst("drafts", "fhgm-model-draft.schema.json"))),
    simplifyVector = FALSE
  )
  expect_null(fhgm_schema$properties$schema)
  expect_equal(fhgm_schema[["$schema"]], "https://json-schema.org/draft/2020-12/schema")
})

test_that("nothing released claims FHT or FHGM: no registry row, no w3id, no version", {
  reg <- FAIRbioHeadersTools:::.bh_registry()
  expect_null(reg$files$FHT)
  expect_setequal(names(reg$files), c("FHR", "FHP", "FHGFF3"))
  expect_setequal(names(reg$w3id), c("FHR", "FHP", "FHGFF3"))
  for (rel in names(reg$releases)) {
    expect_false("FHT" %in% names(reg$releases[[rel]]))
    # the registry's own current release names three types, and no draft
    expect_setequal(names(reg$releases[[reg$current]]), c("FHR", "FHP", "FHGFF3"))
  }
  cs <- bh_contracts()
  expect_setequal(unique(cs$header_type), c("FHR", "FHP", "FHGFF3"))
})
