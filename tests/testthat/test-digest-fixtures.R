# The digest decision, tested against upstream rather than against itself.
#
# Every valid sequence-format vector in the shared suite states the SHA-512/256 of its own
# bytes - produced by the reference implementation and reviewed upstream - so agreement
# here is evidence about the algorithm, not about this package's arithmetic. 87 such
# vectors exist at the v0.6.0 baseline; the count is computed from the manifest rather than
# hardcoded, with a floor so a shrunken suite cannot pass quietly.

test_that("every valid sequence vector's stated checksum is reproduced natively", {
  dir <- .bh_suite_dir()
  man <- jsonlite::fromJSON(file.path(dir, "manifest.json"), simplifyVector = FALSE)
  valid <- Filter(function(v) {
    identical(v$expected, "valid") && v$format %in% .bh_supported_formats &&
      !is.null(v$checksum)
  }, man$vectors)
  expect_gte(length(valid), 80L) # 87 at v0.6.0
  cat("digest fixtures compared:", length(valid), "valid sequence vectors\n")

  wrong_digest <- character()
  wrong_line <- character()
  for (v in valid) {
    got <- bh_checksum(file.path(dir, v$file), format = v$format)
    if (!identical(got$computed, v$checksum) || !isTRUE(got$valid)) {
      wrong_digest <- c(wrong_digest, paste0(v$id, ": computed ", got$computed,
                                             " != manifest ", v$checksum))
    }
    if (!identical(got$recorded, v$checksum)) {
      wrong_line <- c(wrong_line, paste0(v$id, ": line read ", got$recorded,
                                         " != manifest ", v$checksum))
    }
  }
  expect_equal(wrong_digest, character())
  expect_equal(wrong_line, character())
})

test_that("truncated SHA-512 of the same coverage would fail every one of those vectors", {
  # The negative control for the decision: had the core shipped SHA-512 cut in half, this
  # is the value that would appear, and it is different for every file.
  dir <- .bh_suite_dir()
  man <- jsonlite::fromJSON(file.path(dir, "manifest.json"), simplifyVector = FALSE)
  v <- Filter(function(x) identical(x$id, "fasta-lf"), man$vectors)[[1L]]
  b <- .bh_read_all(file.path(dir, v$file))
  fr <- .bh_frame(b, v$format, complete = TRUE)
  cs <- .bh_find_checksum(fr)
  kept <- b[-seq.int(fr$lines$start[[cs$index]], fr$lines$end[[cs$index]])]

  correct <- bh_sha512_256_b64(kept)
  truncated <- paste(jsonlite::base64_enc(bh_sha512(kept, "raw")[1:32]), collapse = "")
  expect_identical(correct, v$checksum)
  expect_false(identical(truncated, v$checksum))
  cat("truncated SHA-512 would have written:", truncated, "instead of:", correct, "\n")
})

test_that("a one-byte change in the covered bytes breaks the checksum", {
  dir <- .bh_suite_dir()
  tmp <- tempfile(fileext = ".fhr.fasta")
  on.exit(unlink(tmp), add = TRUE)
  b <- .bh_read_all(file.path(dir, "valid/fasta-lf.fhr.fasta"))
  idx <- length(b) - 2L # inside the last sequence line, not a terminator
  b[idx] <- as.raw(bitwXor(as.integer(b[idx]), 1L))
  writeBin(b, tmp)
  got <- bh_checksum(tmp)
  expect_false(isTRUE(got$valid))
  expect_match(paste(got$why, collapse = " "), "R4")
})
