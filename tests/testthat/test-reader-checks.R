# Reader checks around the record: the container rule, the checksum line's binding to the
# record, the strict gzip transport, and selection details. Expected verdicts are the
# Python reference's (fair-bioheaders 0.12.0).

fhgff3_base <- sub("https://w3id.org/fair-bioheaders/fhr/v0.6.0",
  "https://w3id.org/fair-bioheaders/fhgff3/v0.6.0", .bh_fhr_base, fixed = TRUE)
fhp_base <- sub("https://w3id.org/fair-bioheaders/fhr/v0.6.0",
  "https://w3id.org/fair-bioheaders/fhp/v0.6.0", .bh_fhr_base, fixed = TRUE)

family_issue <- function(path) {
  r <- suppressWarnings(bh_read(path))
  any(grepl("cannot carry", r$issues))
}

test_that("a header type the container cannot carry makes the file invalid (H2)", {
  wrong <- list(
    list(fhgff3_base, ".fasta"), list(fhgff3_base, ".gfa"),
    list(fhp_base, ".gfa"), list(fhp_base, ".gff3"), list(.bh_fhr_base, ".gff3")
  )
  for (w in wrong) {
    p <- .bh_write_header_file(base = w[[1L]], ext = w[[2L]])
    expect_true(family_issue(p), info = paste(w[[2L]], substr(w[[1L]], 1, 60)))
    expect_false(suppressWarnings(bh_read(p))$valid)
  }
  # the pairs the specification allows are not touched by the rule
  for (w in list(list(.bh_fhr_base, ".fasta"), list(.bh_fhr_base, ".gfa"),
                 list(fhp_base, ".fasta"), list(fhp_base, ".fhp.fasta"))) {
    p <- .bh_write_header_file(base = w[[1L]], ext = w[[2L]])
    expect_false(family_issue(p), info = w[[2L]])
  }
  expect_identical(.bh_family_issue(list(header_type = "FHGFF3", status = "released"),
    "fhgff3"), character())
  expect_identical(.bh_family_issue(list(header_type = "FHT", status = "draft"),
    "fasta"), character())
  expect_match(.bh_family_issue(list(header_type = "FHT", status = "draft"), "gfa"),
    "expected FHR metadata")
  # an unsupported citation is rule V4's, not the container rule's
  expect_identical(.bh_family_issue(list(header_type = "FHGFF3", status = "unsupported"),
    "fasta"), character())
})

test_that("the verified checksum line must be the record's own checksum (H5)", {
  hidden <- function(open, close) {
    # the real checksum key comes after a value that swallows a checksum-shaped line
    paste0("x-note: ", open, "\n")
  }
  make <- function(open, close) {
    # the hashed file excludes the hidden line; the record's checksum is the later key
    p <- tempfile(fileext = ".fasta")
    hdr <- paste0(paste0(";~", strsplit(.bh_fhr_base, "\n")[[1L]], "\n"), collapse = "")
    head <- paste0(hdr, ";~x-note: ", open, "\n")
    tail <- paste0(";~", close, "\n;~\"checksum\": ", strrep("A", 43), "=\n>c1\nACGT\n")
    digest <- bh_sha512_256_b64(charToRaw(paste0(head, tail)))
    writeBin(charToRaw(paste0(head, ";~checksum: ", digest, "\n", tail)), p)
    p
  }
  for (q in list(c("\"start", "end\""), c("'start", "end'"), c("{a: 1,", "}"))) {
    p <- make(q[[1L]], q[[2L]])
    r <- suppressWarnings(bh_read(p))
    expect_true(isTRUE(r$checksum$valid), info = q[[1L]]) # the bytes do match the line
    expect_false(r$valid, info = q[[1L]])
    expect_true(any(grepl("not the record's checksum", r$issues)), info = q[[1L]])
  }
  # an ordinary file is unaffected
  expect_true(suppressWarnings(bh_read(.bh_write_header_file()))$valid)
})

gz_of <- function(bytes) {
  p <- tempfile(fileext = ".gz")
  con <- gzfile(p, "wb")
  writeBin(bytes, con)
  close(con)
  readBin(p, "raw", file.size(p))
}

write_gz <- function(raw) {
  p <- tempfile(fileext = ".fhr.fasta.gz")
  writeBin(raw, p)
  p
}

test_that("gzip: members, padding, and every corruption is a classed error", {
  plain <- .bh_write_header_file()
  bytes <- readBin(plain, "raw", file.size(plain))
  one <- gz_of(bytes)
  cut <- 200L
  two <- c(gz_of(bytes[seq_len(cut)]), gz_of(bytes[-seq_len(cut)]))

  expect_true(suppressWarnings(bh_read(write_gz(one)))$valid)
  expect_true(suppressWarnings(bh_read(write_gz(two)))$valid)
  expect_true(suppressWarnings(bh_read(write_gz(c(one, as.raw(rep(0, 16))))))$valid)
  expect_true(suppressWarnings(bh_read(write_gz(c(gz_of(raw()), one))))$valid)

  # zero padding follows a complete member; before the first member it is not padding,
  # and the file does not start with a gzip member (as the reference refuses it)
  lead <- write_gz(c(as.raw(c(0, 0)), one))
  e <- tryCatch(bh_read(lead, compressed = TRUE), bh_error = function(e) e)
  expect_s3_class(e, "bh_input")
  expect_match(conditionMessage(e), "does not start with a gzip member")
  e <- tryCatch(bh_sha512_256_file(lead, compressed = TRUE), bh_error = function(e) e)
  expect_s3_class(e, "bh_input")
  # sniffed, the file has no gzip magic, so it is read as plain bytes: no header block
  expect_false(suppressWarnings(bh_read(lead))$valid)

  # a header CRC (FHCRC) is skipped, not checked, as the reference does; a name and a
  # comment field are read past
  stopifnot(one[4] == as.raw(0))
  flagged <- c(one[1:3], as.raw(2 + 8 + 16), one[5:10], charToRaw("n.fa"), as.raw(0),
    charToRaw("c"), as.raw(0), as.raw(c(0xde, 0xad)), one[-(1:10)])
  expect_true(suppressWarnings(bh_read(write_gz(flagged)))$valid)

  bad_crc <- one
  k <- length(bad_crc) - 7L
  bad_crc[k] <- xor(bad_crc[k], as.raw(0xff))
  cases <- list(
    garbage = list(c(one, charToRaw("GARBAGE")), "follow the last gzip member"),
    crc = list(bad_crc, "corrupt"),
    truncated = list(one[seq_len(length(one) - 5L)], "truncated")
  )
  for (nm in names(cases)) {
    p <- write_gz(cases[[nm]][[1L]])
    e <- tryCatch(bh_read(p), bh_error = function(e) e)
    expect_s3_class(e, "bh_input")
    expect_match(conditionMessage(e), cases[[nm]][[2L]], info = nm)
    e <- tryCatch(bh_sha512_256_file(p), bh_error = function(e) e)
    expect_s3_class(e, "bh_input")
  }
  # a gzip-compressed file and its plain bytes hash the same
  expect_identical(bh_sha512_256_file(write_gz(two))$digest,
    bh_sha512_256_file(plain)$digest)
})

test_that("a raw URL with a multi-segment ref is unsupported (V4), not read as current", {
  for (ref in c("refs/heads/main", "refs/tags/v0.6.0", "a/b")) {
    s <- bh_select(paste0(
      "https://raw.githubusercontent.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/",
      ref, "/fhr.json"
    ))
    expect_identical(s$rule, "V4", info = ref)
    expect_identical(s$status, "unsupported", info = ref)
  }
  expect_identical(bh_select(paste0(
    "https://raw.githubusercontent.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/",
    "main/fhr.json"
  ))$rule, "V1")
})

test_that("the V4 message lists every release a schema URL can select", {
  expect_identical(bh_releases("FHR"), c("main (v0.6.0)", "v0.3.0", "v0.3.1", "v0.4.0",
    "v0.4.1", "v0.4.2", "v0.5.0", "v0.6.0"))
  expect_identical(bh_releases("FHP"), c("main (v0.6.0)", "v0.4.0", "v0.4.1", "v0.4.2",
    "v0.5.0", "v0.6.0"))
  expect_identical(bh_releases("FHGFF3"), bh_releases("FHP"))
  m <- bh_select("https://w3id.org/fair-bioheaders/fhr/v9.9.9")$message
  expect_match(m, "main \\(v0.6.0\\), v0.3.0, v0.3.1, v0.4.0, v0.4.1, v0.4.2, v0.5.0, v0.6.0\\)$")
})

test_that("an empty doi: link warns under R14 and stays valid", {
  r <- suppressWarnings(bh_read(.bh_write_header_file("relatedLink:\n- \"doi:\"\n")))
  expect_true(r$valid, info = paste(r$issues, collapse = "; "))
  expect_true(any(grepl("^R14: relatedLink is doi:", r$warnings)))
  # anything ajv rejects for another reason is still rejected
  r <- suppressWarnings(bh_read(.bh_write_header_file("relatedLink:\n- \"not a uri\"\n")))
  expect_false(r$valid)
})

test_that("R11 reports a raw > or @ on a FASTA header line, quoted or not", {
  r <- suppressWarnings(bh_read(.bh_write_header_file("x-a: \"a>b\"\nx-b: c@d\n")))
  expect_true(r$valid)
  expect_identical(sum(grepl("^R11: ", r$warnings)), 2L)
  r <- suppressWarnings(bh_read(.bh_write_header_file("x-a: \"a\\x3Eb\"\n")))
  expect_false(any(grepl("^R11: ", r$warnings)))
  r <- suppressWarnings(bh_read(.bh_write_header_file("x-a: \"a>b\"\n", ext = ".fhr.gfa")))
  expect_false(any(grepl("^R11: ", r$warnings)))
})
