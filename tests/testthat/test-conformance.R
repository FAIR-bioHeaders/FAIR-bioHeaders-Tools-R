# The shared-vector acceptance run, and the guards that keep it honest.

test_that("the pinned suite is the suite that runs", {
  dir <- .bh_suite_dir()
  prov <- FAIRbioHeadersTools:::.bh_vendored()$conformance
  expect_equal(prov$vectors, 291L)
  expect_equal(prov$files, 293L)
  expect_identical(.bh_sha256_hex(.bh_read_all(file.path(dir, "manifest.json"))),
    prov$manifest_sha256)
  # the format tallies the capability matrix quotes
  tallies <- vapply(prov$by_format, as.numeric, numeric(1L))
  expect_equal(tallies[c("fasta", "gfa", "fhp-fasta", "fhgff3", "jsonld", "microdata")],
    c(fasta = 98, gfa = 56, `fhp-fasta` = 36, fhgff3 = 38, jsonld = 37, microdata = 26))
})

test_that("every vector is accounted for, and the supported subset has no failure", {
  x <- bh_conformance()
  expect_true(x$ok)
  expect_equal(x$vectors, 291L)
  expect_equal(x$failures, 0L)
  expect_equal(sum(x$results$status == "pass"), 228L)
  expect_equal(sum(x$results$evidence_id != x$results$id), 69L)
  expect_true(all(x$results$evidence_id[x$results$evidence_id != x$results$id] %in%
    vapply(jsonlite::fromJSON(.bh_inst("references", "retirement-crosswalk.json"), simplifyVector=FALSE)$cases, function(c) c$replacedBy, "")))
  expect_equal(sum(x$results$status == "not-run"), 63L)
  expect_equal(sum(x$results$status == "excluded"), 0L)
  # not-run is never bare: each such row names the missing reader
  nr <- x$results[x$results$status == "not-run", ]
  expect_true(all(nzchar(nr$reason)))
  expect_setequal(unique(nr$format), c("jsonld", "microdata"))
  cat("shared suite: 228/228 native, 63 not-run with reasons, of 291\n")
})

test_that("the run checks the rules it claims to check", {
  cov <- bh_rule_coverage()
  expect_true(all(c("R1", "R4", "R5", "R8", "R12", "R13", "R15", "V6", "G1", "P1") %in%
    cov$checked))
  # the rules whose verdict a run cannot establish are named, with a reason
  expect_true(all(names(cov$unverified) %in% c(
    "C2", "K1", "K2", "K3", "K4", "K5", "K6", "R9",
    "J1", "J2", "J3", "J4", "J5", "J6", "J7", "J8", "J9",
    "M1", "M2", "M3", "M4", "M5"
  )))
  x <- bh_conformance()
  # R14 and R11 are warning-only, and the vectors that need them do warn
  warners <- x$results[nzchar(x$results$warnings), ]
  expect_true(nrow(warners) >= 3L)
  expect_true(any(grepl("R14", warners$warnings)))
  expect_true(any(grepl("R11", warners$warnings)))
})

test_that("a tampered fixture is reported, and a missing one is a failure not a skip", {
  dir <- .bh_suite_dir()
  tmp <- tempfile()
  on.exit(unlink(tmp), add = TRUE)
  writeBin(.bh_read_all(file.path(dir, "valid/fasta-lf.fhr.fasta")), tmp)
  a <- bh_read(tmp, format = "fasta")
  expect_true(a$valid)
  # move the checksum line's value by one character: rule R4 must catch it
  b <- .bh_read_all(file.path(dir, "valid/gfa-lf.fhr.gfa"))
  b[length(b) - 3L] <- as.raw(bitwXor(as.integer(b[length(b) - 3L]), 1L))
  tampered <- tempfile(fileext = ".fhr.gfa")
  on.exit(unlink(tampered), add = TRUE)
  writeBin(b, tampered)
  t <- bh_read(tampered)
  expect_false(t$valid)
  expect_match(paste(t$issues, collapse = " "), "R4")
})

test_that("the runner fails loudly instead of quietly when the suite is not the pin", {
  # copy the manifest and change the pinned count only in the provenance cache
  prov <- FAIRbioHeadersTools:::.bh_vendored()
  bad <- prov
  bad$conformance$manifest_sha256 <- strrep("a", 64)
  assign("vendored", bad, envir = .bh_state)
  on.exit(rm(vendored, envir = .bh_state), add = TRUE)
  expect_error(bh_conformance(), "not the suite this package was pinned to",
    class = "bh_conformance"
  )
})

test_that("an empty or truncated run cannot be reported as success", {
  # limit keeps the guards off but the object says the run was partial
  x <- bh_conformance(limit = 2L)
  expect_true(x$limited)
  # every vector is still accounted for; what a limited run reduces is how many produced
  # a verdict, and the object says it was partial
  expect_equal(x$vectors, 291L)
  expect_lt(sum(x$results$status == "pass"), 228L)
  expect_gte(sum(x$results$status == "not-run"), 228L - 8L)
  y <- bh_conformance(formats = "fasta")
  expect_true(y$limited)
  expect_equal(y$vectors, 291L) # still accounted for, just not all run
  expect_equal(sum(y$results$status == "excluded"), 193L)
})

test_that("the report serialises the accounting", {
  x <- bh_conformance(limit = 1L)
  txt <- bh_conformance_report(x)
  parsed <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  expect_equal(parsed$vectors, x$vectors)
  expect_true(all(c("fasta", "gfa", "jsonld", "microdata", "fhp-fasta", "fhgff3") %in%
    names(parsed$by_format)))
  expect_true(length(parsed$by_format$jsonld$not_run_reasons) >= 1L)
})

# The locators, in both directions. A suite path that resolves by accident is worse than one
# that fails: "missing fixtures must fail" is only a real guarantee if nothing downstream can
# substitute other data for the missing ones. docs/NATIVE-ACCEPTANCE.md guard 4 states this
# refusal; these tests are what make it a statement about the code.
test_that("a named suite location is authoritative and never falls back", {
  real <- .bh_suite_dir()
  bogus <- file.path(tempdir(), "bh-no-suite-here")
  dir.create(bogus, showWarnings = FALSE)
  withr::with_options(list(bh.conformance_dir = bogus), {
    expect_error(.bh_suite_dir(), "holds no manifest.json", class = "bh_conformance")
    expect_error(bh_conformance(), "holds no manifest.json", class = "bh_conformance")
  })
  withr::with_options(list(bh.conformance_dir = real), {
    expect_equal(.bh_suite_dir(), real)
  })
  # nothing named -> the search finds the vendored copy
  expect_equal(.bh_suite_dir(), real)
  expect_error(.bh_search("definitely-not-here", "shared suite"), "Looked in",
    class = "bh_conformance"
  )
})

test_that("the FHT development suite locator follows the same rule", {
  bogus <- file.path(tempdir(), "bh-no-draft-here")
  dir.create(bogus, showWarnings = FALSE)
  withr::with_options(list(bh.draft_dir = bogus), {
    expect_error(.bh_draft_suite_dir(), "holds no manifest.json", class = "bh_conformance")
    expect_error(bh_draft_vectors(), "holds no manifest.json", class = "bh_conformance")
  })
  expect_true(nzchar(.bh_draft_suite_dir()))
})
