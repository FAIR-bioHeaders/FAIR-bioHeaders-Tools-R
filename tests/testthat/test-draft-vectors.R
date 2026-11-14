# The FHT development suite, run natively through the rule V7 lane.
#
# These 66 vectors are published by FHT-Specification, not by the shared specification;
# their manifest states its expectations are "derived from the rule text, never from an
# implementation under test". They are draft evidence: a pass here says what this build
# does with the pinned unreleased bytes, never that FHT is supported. They are never
# counted toward the shared 291 (bh_conformance() runs the shared suite only, and its
# supported-subset guard is fixed at the 228 released vectors).

test_that("the pinned FHT suite runs in full, through the lane, with the pinned bytes", {
  pins <- bh_draft_pins()
  expect_true(all(pins$digest_ok))
  x <- bh_draft_vectors()
  expect_equal(x$vectors, 66L)
  expect_equal(sum(x$results$status == "pass"), 66L)
  expect_equal(sum(x$results$status %in% c("fail", "error", "missing-fixture")), 0L)
  expect_true(x$ok)
  expect_false(isTRUE(x$limited))
  # the label keeps draft evidence from being mistaken for the shared run
  expect_match(x$label, "not part of the 291")
  # the C1 rule labels (the renamed T1-T3 of FHT-Specification#38) are what ran
  expect_gt(sum(grepl("C1", x$results$rules)), 0L)
  # rules the run cannot verify are reported, not hidden: C2 (draft citation breadth)
  # is named on the vectors that lean on it
  gap_rows <- x$results[nzchar(x$results$rule_gaps), ]
  expect_true(all(grepl("C2|C3", gap_rows$rule_gaps)))
  cat("draft lane: 66/66 FHT development vectors pass against the pinned draft\n")
})

test_that("a draft suite whose bytes moved off the pin is refused before any vector runs", {
  prov <- FAIRbioHeadersTools:::.bh_vendored()
  bad <- prov
  bad$draft_vectors$manifest_sha256 <- strrep("b", 64)
  assign("vendored", bad, envir = .bh_state)
  on.exit(rm(vendored, envir = .bh_state), add = TRUE)
  expect_error(bh_draft_vectors(), "not the suite this package was pinned to",
    class = "bh_conformance"
  )
})

test_that("the shared run is unaffected by the draft lane existing: default off", {
  # with the lane closed (the default), the shared acceptance numbers are exactly what
  # they were before the lane existed - the same 228 supported vectors run, none of the
  # 66 draft vectors is anywhere in the accounting, and no draft warning is emitted
  warns <- character()
  x <- withCallingHandlers(
    bh_conformance(),
    warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  expect_equal(x$vectors, 291L)
  expect_equal(sum(x$results$status == "pass"), 228L)
  expect_equal(sum(x$results$status == "not-run"), 63L)
  expect_equal(sum(x$results$format == "fht-fasta"), 0L)
  expect_false(any(grepl("unreleased draft", warns)))
})
