# The default-behavior golden: the claim "the default reading did not move" made
# checkable.
#
# The golden at reference/default-behavior-v0.6.0.json fingerprints what bh_read()
# (lane closed) does with every shared v0.6.0 vector - verdict, computed checksum,
# byte count, selection outcome, issue and warning codes, and the SHA-256 of the exact
# JSON handed to the contract validator - plus the V1-V6 selection probes, including
# the rule V5 landing of the FHT raw-main URL with the lane closed. It was generated
# once, from the implementation that passed all 228 released-format vectors, by
# tools/golden_dump.R; no test here ever rewrites it. Regeneration is a deliberate,
# reviewed change with a stated reason (see the header of that script and
# docs/NATIVE-ACCEPTANCE.md).
#
# Honest limitation: the Java library's golden was generated from its pre-registry
# commit (237da6c), so it proves a refactor changed nothing. This package had no prior
# implementation - main was an empty stub when this work started - so the golden
# cannot prove equivalence to a past version. It pins the default behaviour accepted
# at v0.6.0 so that the draft lane, the parent-link work and every later change must
# pass through it unchanged, and so a future refactor CAN be proven additive the way
# Java's was.

test_that("the golden file is the one this test suite ships with", {
  path <- FAIRbioHeadersTools:::.bh_golden_path()
  expect_match(basename(path), "^default-behavior-v0\\.6\\.0\\.json$")
  # the golden is pinned by its own digest: a swapped file is caught even when its
  # structure passes muster, and regeneration (tools/golden_dump.R) must update this
  # line in the same reviewed commit
  expect_identical(.bh_sha256_hex(.bh_read_all(path)),
    "055da14f6dcbdb8ae9e5fc3880fb5bb56d510defb2e12639bde056edc820a525"
  )
  want <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  expect_equal(want$fingerprintVersion, 1L)
  expect_equal(want$suite$manifest_sha256,
    FAIRbioHeadersTools:::.bh_vendored()$conformance$manifest_sha256
  )
  expect_equal(want$suite$vectors, 291L)
  expect_equal(want$suite$ran, 228L)
  expect_identical(want$engine, "ajv")
})

test_that("the default reading equals the golden, field by field", {
  want <- jsonlite::fromJSON(FAIRbioHeadersTools:::.bh_golden_path(),
    simplifyVector = FALSE
  )
  # parse the same way in both directions so JSON round-trip artifacts (character(0)
  # against list(), NA against null) cannot masquerade as behaviour changes
  got_txt <- jsonlite::toJSON(FAIRbioHeadersTools:::.bh_fingerprint(),
    auto_unbox = TRUE, null = "null", na = "null"
  )
  got <- jsonlite::fromJSON(got_txt, simplifyVector = FALSE)
  diffs <- FAIRbioHeadersTools:::.bh_golden_diff(got, want)
  if (length(diffs)) {
    print(head(diffs, 20L))
  }
  expect_equal(length(diffs), 0L)

  # the run is only evidence if it compared the whole suite: assert the receipt
  # numbers even when CI does not collect the file itself
  expect_equal(length(got$vectors), 291L)
  expect_equal(sum(vapply(got$vectors, function(v) isTRUE(v$ran), logical(1L))), 228L)
  expect_gte(length(got$selectionProbes), 30L)
  receipt <- list(
    vectorsCompared = length(got$vectors),
    documentsCompared = sum(vapply(got$vectors, function(v) isTRUE(v$ran), logical(1L))),
    selectionCasesCompared = length(got$selectionProbes),
    goldenDifferences = length(diffs)
  )
  FAIRbioHeadersTools:::.bh_receipt("BH_GOLDEN_RECEIPT", receipt)
})

test_that("the golden actually bites: a changed verdict differs from it", {
  # positive control for the negative control: flip one vector's observed verdict in a
  # copy of the fingerprint and show the comparator reports exactly that difference.
  want <- jsonlite::fromJSON(FAIRbioHeadersTools:::.bh_golden_path(),
    simplifyVector = FALSE
  )
  got_txt <- jsonlite::toJSON(FAIRbioHeadersTools:::.bh_fingerprint(),
    auto_unbox = TRUE, null = "null", na = "null"
  )
  got <- jsonlite::fromJSON(got_txt, simplifyVector = FALSE)
  got$vectors[[1L]]$observed <- if (identical(got$vectors[[1L]]$observed, "valid")) {
    "invalid"
  } else {
    "valid"
  }
  diffs <- FAIRbioHeadersTools:::.bh_golden_diff(got, want)
  expect_gte(length(diffs), 1L)
  expect_true(any(grepl("observed", diffs, fixed = TRUE)))
})
