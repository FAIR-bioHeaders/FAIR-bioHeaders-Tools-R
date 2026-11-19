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

test_that("an unparsable compressed stream scores only on independently detected truncation, never on its own declaration", {
  # The R1 reading (unchanged from the first version of this test): a truncated gzip
  # stream has no decompressed bytes for R1 to hash, so the file is rejected before any
  # checksum question. What changed after review: the ground is .bh_gz_stream_truncated()
  # re-reading the cited bytes - the manifest's selfChecksum label may NARROW the
  # exception but never licenses it. A vector may not certify its own unreachability
  # (maintainer ruling, 2026-11-18, round-13 P-6 review recorded on this repository's
  # PR #22; no org issue number records it - the Tools#146/spec#139 citations in earlier
  # drafts were verified wrong and are withdrawn: #146 is a Zenodo DOI PR, spec#139 is
  # the voucher-specimens issue. Verified adjacent implementations of the same
  # discipline: Java commit 2c35d938 requires unreachable vectors to report the
  # line-shape rejection, "nothing passes for the wrong reason"; FHT-Specification#37
  # finalizes the selfChecksum field's semantics).
  dir <- .bh_draft_suite_dir()
  scratch_suite <- function() {
    s <- tempfile("fhtdecl")
    dir.create(s)
    file.copy(list.files(dir, full.names = TRUE, all.files = TRUE), s, recursive = TRUE)
    s
  }
  run_scratch <- function(s) {
    suppressWarnings(FAIRbioHeadersTools:::.bh_run_suite(s, list(), lane = "FHT",
      formats = NULL, limit = NULL, label = "scratch", run_formats = "fht-fasta"
    ))
  }
  gz_plain <- .bh_read_all(file.path(dir, "valid", "fht-fasta-gzip.fht.fasta.gz"))
  expect_true(length(gz_plain) > 10L) # an empty read is a failed measurement

  # (1) the pinned run: the real vector passes and says on the record what grounded it
  x <- bh_draft_vectors()
  row <- x$results[x$results$id == "fht-fasta-gzip-truncated", ]
  expect_equal(row$status, "pass")
  expect_equal(row$observed, "invalid")
  expect_match(row$diagnostics, "independently re-read")
  expect_match(row$diagnostics, "selfChecksum=unreachable")
  # the probe itself, three ways: truncated is detected, whole is not, whole+garbage
  # is not (a refusal to frame is not the same condition as an unfinished member)
  probe <- FAIRbioHeadersTools:::.bh_gz_stream_truncated
  tf <- tempfile(fileext = ".gz")
  writeBin(gz_plain[seq_len(length(gz_plain) - 6L)], tf)
  expect_true(probe(tf))
  expect_false(probe(file.path(dir, "valid", "fht-fasta-gzip.fht.fasta.gz")))
  tg <- tempfile(fileext = ".gz")
  writeBin(c(gz_plain, charToRaw("GARBAGE")), tg)
  expect_false(probe(tg))
  tp <- tempfile(fileext = ".fasta")
  writeBin(charToRaw("not gzip at all\n"), tp)
  expect_false(probe(tp))

  # (2) the reviewer's false-pass repro, red at 2a6343f: the R2 missing-checksum
  # vector's fixture is REPLACED with truncated-gzip bytes. That vector declares
  # selfChecksum=unreachable too - under the old rule it passed, scoring a rejection
  # whose required check (R2) was never reached. Now: not R1-labelled -> error.
  s <- scratch_suite()
  tgt <- file.path(s, "invalid", "fht-fasta-missing-checksum.fht.fasta")
  before <- .bh_read_all(tgt)
  writeBin(gz_plain[seq_len(length(gz_plain) - 6L)], tgt)
  expect_false(identical(before, .bh_read_all(tgt))) # the mutation landed
  r2row <- run_scratch(s)$results
  hit <- r2row[r2row$id == "fht-fasta-missing-checksum", ]
  expect_equal(hit$status, "error")
  expect_match(hit$reason, "native reader errored")
  unlink(s, recursive = TRUE)

  # (3) a refusal that is NOT the R1 condition: trailing non-gzip bytes after a whole
  # member, parked on the R1-labelled truncated vector. Old rule scored it pass; the
  # probe says the member is complete, so the exception does not fire: error.
  s2 <- scratch_suite()
  tgt2 <- file.path(s2, "invalid", "fht-fasta-gzip-truncated.fht.fasta.gz")
  writeBin(c(gz_plain, charToRaw("GARBAGE")), tgt2)
  hit2 <- run_scratch(s2)$results
  g2 <- hit2[hit2$id == "fht-fasta-gzip-truncated", ]
  expect_equal(g2$status, "error")
  expect_match(g2$reason, "native reader errored")
  unlink(s2, recursive = TRUE)

  # (4) the declaration still buys nothing on its own: removing it from the manifest
  # turns the genuine vector into an error - kept from the first version of this test.
  s3 <- scratch_suite()
  mp <- file.path(s3, "manifest.json")
  man <- jsonlite::fromJSON(mp, simplifyVector = FALSE)
  hit3 <- vapply(man$vectors, function(v) identical(v$id, "fht-fasta-gzip-truncated"),
    logical(1L)
  )
  expect_equal(sum(hit3), 1L)
  man$vectors[[which(hit3)]]$selfChecksum <- NULL
  writeLines(jsonlite::toJSON(man, auto_unbox = TRUE, pretty = TRUE, null = "null"), mp)
  d3 <- run_scratch(s3)$results
  expect_equal(d3[d3$id == "fht-fasta-gzip-truncated", ]$status, "error")
  unlink(s3, recursive = TRUE)

  # (5) the 2026-11-18 re-review's counterexample, red-first at 09241ade: the live
  # R1-labelled vector's bytes are replaced with a COMPLETE, readable gzip - the valid
  # payload plus one newline, recorded checksum untouched. The reader then RETURNS a
  # verdict (an R4 checksum mismatch) instead of erroring, and the generic
  # observed==expected path passed it as the truncation rejection. Now bound on the
  # normal-return path too: bytes that parsed cannot evidence an unreachable stream.
  s4 <- scratch_suite()
  tgt4 <- file.path(s4, "invalid", "fht-fasta-gzip-truncated.fht.fasta.gz")
  con <- gzfile(file.path(dir, "valid", "fht-fasta-gzip.fht.fasta.gz"), "rb")
  payload <- readBin(con, "raw", n = 1e6)
  close(con)
  expect_gt(length(payload), 100L) # an empty read is a failed measurement
  gzc <- gzfile(tgt4, "wb")
  writeBin(c(payload, charToRaw("\n")), gzc)
  close(gzc)
  # prove the substitution: bytes changed, the gzip is COMPLETE (the probe says so), and
  # the analyzer returns a verdict rather than erroring - an R4 checksum mismatch
  expect_false(identical(.bh_read_all(tgt4), .bh_read_all(
    file.path(dir, "invalid", "fht-fasta-gzip-truncated.fht.fasta.gz")
  )))
  expect_false(FAIRbioHeadersTools:::.bh_gz_stream_truncated(tgt4))
  a4 <- FAIRbioHeadersTools:::.bh_capture(
    FAIRbioHeadersTools:::.bh_analyze(tgt4, format = "fht-fasta", draft = "FHT")
  )
  expect_true(is.null(a4$error))
  expect_false(isTRUE(a4$value$valid))
  expect_true(any(grepl("^R4:", a4$value$issues)))
  d4 <- run_scratch(s4)$results
  row4 <- d4[d4$id == "fht-fasta-gzip-truncated", ]
  expect_equal(row4$status, "error")
  expect_match(row4$reason, "requires bytes no reader can reach")
  expect_match(row4$reason, "not evidence of a truncated stream")
  unlink(s4, recursive = TRUE)
  # and nothing outside the scratch trees moved: the pinned suite is still green
  expect_true(bh_draft_vectors()$ok)
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
