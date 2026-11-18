# The FHT development suite, run natively through the rule V7 lane.
#
# These 82 vectors are published by FHT-Specification, not by the shared specification;
# their manifest states its expectations are "derived from the rule text, never from an
# implementation under test". They are draft evidence: a pass here says what this build
# does with the pinned unreleased bytes, never that FHT is supported. They are never
# counted toward the shared 291 (bh_conformance() runs the shared suite only, and its
# supported-subset guard is fixed at the 228 released vectors).

test_that("the pinned FHT suite runs in full, through the lane, with the pinned bytes", {
  pins <- bh_draft_pins()
  expect_true(all(pins$digest_ok))
  x <- bh_draft_vectors()
  expect_equal(x$vectors, 82L)
  expect_equal(sum(x$results$status == "pass"), 82L)
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
  cat("draft lane: 82/82 FHT development vectors pass against the pinned draft\n")
})

test_that("the parentLink verdicts the re-pinned FHT suite seals are the verdicts we derive", {
  # C3 accounting, added by the 2026-11-16 re-pin. Every parentLink entry in the pinned
  # manifest states its own sealed outcome (`checked-pass`, `checked-fail`, `unchecked`);
  # the shared runner reads only the cited parent FILE and derives a verdict from the
  # recomputation, so nothing in a green run compares that verdict with the sealed word.
  # This test does, one row per cited link, in the order the header lists them. Draft
  # evidence about pinned unreleased bytes: it is not a claim that FHT parentLink
  # semantics are settled (FHT-Specification #8, boxes 3/4/6/7 remain open; #10 says
  # selfChecksum/parentLink finalize at FHT release).
  dir <- .bh_draft_suite_dir()
  man <- jsonlite::fromJSON(file.path(dir, "manifest.json"), simplifyVector = FALSE)
  stated_all <- character()
  derived_all <- character()
  for (v in man$vectors) {
    pls <- v$parentLink
    if (is.null(pls) || !length(pls)) next
    stated <- vapply(pls, function(pl) {
      r <- pl$result
      if (is.null(r) || !nzchar(r)) fail(paste0("vector ", v$id, " cites a parentLink with no sealed result"))
      as.character(r)
    }, "")
    # a null `file` is the suite's own "no parent handed over" case (the one `unchecked`
    # entry): the runner reads those as NA and passes no parent, and bh_verify_links()
    # reports that link as unchecked rather than guessing at a file
    files <- vapply(pls, function(pl) {
      f <- pl$file
      if (is.null(f) || is.na(f)) NA_character_ else file.path(dir, f)
    }, "")
    lv <- suppressWarnings(bh_verify_links(
      file.path(dir, v$file), parent = files[!is.na(files)], format = v$format, draft = "FHT"
    ))
    expect_equal(nrow(lv$links), length(stated), info = v$id)
    got <- ifelse(
      lv$links$verdict == "mismatch" | lv$links$verdict == "missing-parent-file",
      "checked-fail",
      ifelse(lv$links$verdict == "unchecked", "unchecked", "checked-pass")
    )
    stated_all <- c(stated_all, stated)
    derived_all <- c(derived_all, got)
  }
  # the census is stated so a future revision that adds or removes links moves this test
  # rather than passing quietly: 12 links over 10 vectors at the pinned manifest, one of
  # them with no parent file, which must stay `unchecked` and never become a pass
  expect_equal(length(stated_all), 12L)
  expect_equal(sum(stated_all == "checked-pass"), 7L)
  expect_equal(sum(stated_all == "checked-fail"), 4L)
  expect_equal(sum(stated_all == "unchecked"), 1L)
  expect_identical(derived_all, stated_all)
  cat("draft lane: 12/12 sealed parentLink verdicts reproduced natively (7 pass, 4 fail, 1 unchecked)\n")
})

test_that("an unparsable compressed stream scores as the vector declares, never as a free pass", {
  # `fht-fasta-gzip-truncated` declares its own failure class: selfChecksum=unreachable,
  # "the file is rejected before any checksum comparison". The reader refuses the framing
  # with a classed input error (R/framing.R), and the runner passes it only because the
  # vector says that refusal is the expected rejection. Two halves, both measured:
  # (1) the pinned run passes the vector and says on the record which refusal it accepted;
  x <- bh_draft_vectors()
  row <- x$results[x$results$id == "fht-fasta-gzip-truncated", ]
  expect_equal(row$status, "pass")
  expect_equal(row$observed, "invalid")
  expect_match(row$diagnostics, "selfChecksum=unreachable")
  expect_match(row$diagnostics, "as gzip", fixed = TRUE)
  # (2) the same vector WITHOUT its declared class is an error again. The scratch manifest
  # deliberately bypasses the digest gate by calling the runner with pinned = NULL: the
  # suite bytes stay the pinned ones, only the declaration is deleted, so nothing outside
  # this file's own scoring decision moves.
  dir <- .bh_draft_suite_dir()
  scratch <- tempfile("fht-decl")
  dir.create(scratch)
  on.exit(unlink(scratch, recursive = TRUE), add = TRUE)
  file.copy(list.files(dir, full.names = TRUE, all.files = TRUE), scratch,
    recursive = TRUE
  )
  mp <- file.path(scratch, "manifest.json")
  man <- jsonlite::fromJSON(mp, simplifyVector = FALSE)
  hit <- vapply(man$vectors, function(v) identical(v$id, "fht-fasta-gzip-truncated"), logical(1L))
  expect_equal(sum(hit), 1L)
  man$vectors[[which(hit)]]$selfChecksum <- NULL
  writeLines(jsonlite::toJSON(man, auto_unbox = TRUE, pretty = TRUE, null = "null"), mp)
  y <- FAIRbioHeadersTools:::.bh_run_suite(scratch, list(), lane = "FHT", formats = NULL,
    limit = NULL, label = "scratch", run_formats = "fht-fasta"
  )
  zrow <- y$results[y$results$id == "fht-fasta-gzip-truncated", ]
  expect_equal(zrow$status, "error")
  expect_match(zrow$reason, "native reader errored")
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
  # 82 draft vectors is anywhere in the accounting, and no draft warning is emitted
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
