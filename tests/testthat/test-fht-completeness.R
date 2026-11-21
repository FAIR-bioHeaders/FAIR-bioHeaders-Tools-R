# C1 arithmetic is separate from JSON Schema's count types/requiredness.
.fht_counts <- function(single = 4L, duplicated = 1L, fragmented = 2L,
                        missing = 3L, total = 10L) {
  list(lineageDataset = "primates_odb10", completeSingle = single,
    completeDuplicated = duplicated, fragmented = fragmented, missing = missing,
    total = total)
}
.fht_record <- function() suppressWarnings(bh_read(testthat::test_path(
  "..", "draft", "fht", "valid", "fht-fasta-lf.fht.fasta"), draft = "FHT"))$record
.fht_validation <- function(counts) {
  record <- .fht_record()
  record$completeness <- counts
  selection <- bh_select(record$schema, schema_version = record$schemaVersion, draft = "FHT")
  .bh_validate_record(record, selection)
}

test_that("FHT C1 rejects both directions of inconsistent complete BUSCO sums", {
  expect_true(.fht_validation(.fht_counts())$valid)
  for (total in c(9L, 11L)) {
    result <- .fht_validation(.fht_counts(total = total))
    expect_false(result$valid)
    expect_match(paste(result$errors, collapse = " "), "C1:.*sum to total")
  }
  expect_true(.fht_validation(.fht_counts(4, 1, 2, 3, 10))$valid)
})

test_that("FHT C1 defers missing, boolean and fractional counts to schema checks", {
  for (counts in list(.fht_counts(single = NULL), .fht_counts(single = TRUE),
                      .fht_counts(single = 1.5))) {
    expect_length(.bh_fht_completeness_issues(list(completeness = counts)), 0L)
    result <- .fht_validation(counts)
    expect_false(result$valid)
    expect_false(any(grepl("^C1:", result$errors)))
  }
})

test_that("FHT C1 avoids integer overflow and refuses unverifiable large counts", {
  expect_true(.fht_validation(.fht_counts(.Machine$integer.max, 1L, 0L, 0L,
    as.double(.Machine$integer.max) + 1))$valid)
  expect_true(.fht_validation(.fht_counts(2^53 - 2, 1, 0, 0, 2^53 - 1))$valid)
  for (counts in list(.fht_counts(2^53, 1, 0, 0, 2^53),
                      .fht_counts(1e308, 1e308, 0, 0, 1e308))) {
    expect_error(.fht_validation(counts), "consumer precision limit", class = "bh_limit")
  }
})

test_that("raw YAML rounding cannot manufacture an FHT C1 arithmetic pass", {
  parsed <- .bh_parse_record(c("completeness:",
    "  lineageDataset: primates_odb10", "  completeSingle: 9007199254740993",
    "  completeDuplicated: 0", "  fragmented: 0", "  missing: 0",
    "  total: 9007199254740992"))
  counts <- parsed$record$completeness
  # The parser has already lost the one-unit difference: the reader must refuse
  # these counts, not credit their rounded equality as exact arithmetic evidence.
  expect_equal(counts$completeSingle, counts$total)
  expect_error(.fht_validation(counts), "consumer precision limit", class = "bh_limit")
})

test_that("FHT arithmetic does not tighten released FHP validation", {
  baseline <- bh_read(.bh_inst("references", "canonical-counterparts", "valid",
    "fhp-fasta-lf-canonical-parent.fhp.fasta"))
  expect_true(baseline$valid)
  record <- baseline$record
  record$completeness <- .fht_counts(total = 9L)
  selection <- bh_select(record$schema, schema_version = record$schemaVersion)
  expect_true(.bh_validate_record(record, selection)$valid)
})
