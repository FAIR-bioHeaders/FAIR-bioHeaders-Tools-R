# Parent-link verification against released vectors' own recorded digests.
#
# No released manifest vector carries a parentLink, so the operation is tested by
# composing released bytes: a real suite file serves as the parent (its checksum is
# the one the shared manifest records upstream), and a temporary GFF3 child cites
# either that stated checksum (match) or a mutated one (mismatch). Every digest here
# is real; nothing is invented. The unchecked path is the one the shared suite's own
# instruction cares most about: a link nobody resolved must never read as a pass.

.fhr_parent <- function() {
  dir <- .bh_suite_dir()
  parent <- file.path(dir, "valid", "fasta-lf.fhr.fasta")
  list(path = parent, stated = .bh_vector("fasta-lf")$checksum)
}

.gff3_child <- function(stated_checksum, dir = tempdir()) {
  # a minimal, fully well-formed FHGFF3 file (G1 first line, header block, checksum
  # last) citing the parent through derivedFrom. The checksum line is computed over
  # exactly the bytes rule R3 leaves covered, so the child verifies against itself
  # and the test isolates the LINK verdict from any fixture sloppiness.
  head_lines <- paste0("#~", c(
    "schema: https://w3id.org/fair-bioheaders/fhgff3/v0.6.0",
    "schemaVersion: '1.2'",
    "analysis: 'Synthetic link-test annotation'",
    "dateCreated: '2026-11-14'",
    "project: 'link-test'",
    "software: 'FAIRbioHeadersTools tests'",
    "source: 'test'",
    "derivedFrom:",
    "- relationship: 'annotates'",
    "  genome:",
    "    headerType: FHR",
    "    accession: 'GCA_000000000.1'",
    sprintf("    checksum: '%s'", stated_checksum)
  ))
  first <- "##gff-version 3"
  # the file as it will exist MINUS the checksum line and its terminator = the bytes
  # R3 says the checksum covers (the covered region is contiguous here because the
  # checksum line sits at the end of the header block)
  covered <- paste0(c(first, head_lines), collapse = "\n")
  pre <- tempfile(fileext = ".fhgff3.gff3")
  writeBin(charToRaw(paste0(covered, "\n")), pre)
  cs <- bh_sha512_256_file(pre)
  tmp <- file.path(dir, basename(pre))
  final <- paste0(c(first, head_lines, paste0("#~checksum: ", cs$digest)), collapse = "\n")
  writeBin(charToRaw(paste0(final, "\n")), tmp)
  tmp
}

test_that("a cited parent checksum that recomputes matches, natively", {
  p <- .fhr_parent()
  child <- .gff3_child(p$stated, dir = tempdir())
  on.exit(unlink(child), add = TRUE)
  expect_true(bh_verify(child)) # the synthesized child is internally consistent first
  links <- bh_parent_links(child)
  expect_equal(nrow(links), 1L)
  expect_equal(links$header_type, "FHR")
  expect_equal(links$relationship, "annotates")
  v <- bh_verify_links(child, parent = p$path)
  expect_equal(v$links$verdict, "match")
  expect_equal(v$links$computed, p$stated)
  expect_true(v$all_matched)
  expect_equal(v$unchecked, 0L)
})

test_that("a tampered citation is reported as a mismatch, not swallowed", {
  p <- .fhr_parent()
  bad <- substring(p$stated, 1L, 42L)
  flip <- if (substring(bad, 1L, 1L) == "A") "B" else "A"
  bad <- paste0(flip, substring(bad, 2L))
  child <- .gff3_child(bad, dir = tempdir())
  on.exit(unlink(child), add = TRUE)
  v <- bh_verify_links(child, parent = p$path)
  expect_equal(v$links$verdict, "mismatch")
  expect_equal(v$mismatched, 1L)
  expect_false(v$all_matched)
})

test_that("a link with no supplied parent file stays unchecked and never passes", {
  p <- .fhr_parent()
  child <- .gff3_child(p$stated, dir = tempdir())
  on.exit(unlink(child), add = TRUE)
  v <- bh_verify_links(child) # no parent supplied
  expect_equal(v$links$verdict, "unchecked")
  expect_equal(v$unchecked, 1L)
  # unchecked is not failed either: the point is it cannot be mistaken for a pass
  expect_true(v$all_matched)
  expect_false(identical(v$links$computed, p$stated))
  # a named vector that does not cover the cited type also stays unchecked
  v2 <- bh_verify_links(child, parent = c(FHP = p$path))
  expect_equal(v2$links$verdict, "unchecked")
  # a named vector that does cover it resolves
  v3 <- bh_verify_links(child, parent = c(FHR = p$path))
  expect_equal(v3$links$verdict, "match")
  # a nonexistent parent path is reported, not silently unchecked
  v4 <- bh_verify_links(child, parent = file.path(tempdir(), "no-such-parent.fna"))
  expect_equal(v4$links$verdict, "missing-parent-file")
})
