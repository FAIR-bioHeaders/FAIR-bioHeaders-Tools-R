# Rule R1 line framing, rule R2/R5 root indentation, and the trap that sits on the
# shortest path to both.

test_that("rule R1: LF, CRLF and a lone CR each end a line, terminator included", {
  b <- charToRaw("a\nb\r\nc\rd")
  l <- .bh_split_lines(b)
  expect_equal(l$n, 4L)
  # 1:a 2:LF | 3:b 4:CR 5:LF (CRLF is one terminator) | 6:c 7:CR (lone CR ends) | 8:d
  expect_equal(l$start, c(1L, 3L, 6L, 8L))
  expect_equal(l$end, c(2L, 5L, 7L, 8L))
  # a CR that is not followed by LF ends the line; the LF of CRLF does not start one
  b2 <- charToRaw("x\r\ny")
  l2 <- .bh_split_lines(b2)
  expect_equal(l2$n, 2L)
  expect_equal(l2$start, c(1L, 4L))
})

test_that("the root indent is measured with regexpr, and the sub() variants are pinned", {
  line <- ";~  checksum: ABC="
  m <- regexpr("^;~ *", line)
  expect_equal(nchar(regmatches(line, m)) - 2L, 2L)
  expect_equal(nchar(regmatches("  checksum: x", regexpr("^ *", "  checksum: x"))), 2L)

  # docs/CAPABILITY.md records a sub() trap and told the next reader to use regexpr. The
  # direction is measured here rather than repeated: on R 4.6.1 the POSIX back-reference
  # is right for a single-line input, and it is the perl=TRUE variant that returns the
  # whole string when the input still carries a terminator, because $ then matches only
  # at the end of the string. regexpr is unambiguous in both cases, which is why the
  # reader uses it; the two expectations below exist to fail if either behaviour changes.
  one_line <- "  checksum: x"
  expect_equal(nchar(sub("^( *).*$", "\\1", one_line)), 2L) # POSIX: correct here
  with_term <- "  a\n  b\n"
  expect_equal(nchar(sub("^( *).*$", "\\1", with_term)), 2L) # POSIX
  expect_equal(nchar(sub("^( *).*$", "\\1", with_term, perl = TRUE)), 8L) # the trap
  expect_equal(nchar(regmatches(with_term, regexpr("^ *", with_term))), 2L)
})

test_that("R2: a nested checksum is not the root checksum line", {
  txt <- c(
    ";~schema: https://w3id.org/fair-bioheaders/fhr/v0.6.0",
    ";~taxon:",
    ";~  checksum: Z1p/siczUlN/N+lDB5Kg6vFRrztGErgLw9H4MfVfZeU=",
    ";~genome: g"
  )
  frame <- .bh_frame(
    charToRaw(paste0(txt, "\n", collapse = "")), "fasta", complete = TRUE
  )
  got <- .bh_find_checksum(frame)
  expect_false(got$ok)
  expect_match(paste(got$why, collapse = " "), "R2")
})

test_that("R2: two root-level checksum lines are refused", {
  txt <- c(
    ";~genome: g",
    ";~checksum: Z1p/siczUlN/N+lDB5Kg6vFRrztGErgLw9H4MfVfZeU=",
    ";~checksum: Z1p/siczUlN/N+lDB5Kg6vFRrztGErgLw9H4MfVfZeU="
  )
  frame <- .bh_frame(charToRaw(paste0(txt, "\n", collapse = "")), "fasta", TRUE)
  got <- .bh_find_checksum(frame)
  expect_false(got$ok)
  expect_match(paste(got$why, collapse = " "), "2 root-level")
})

test_that("R5: only the value may sit on the checksum line", {
  one <- function(line) {
    frame <- .bh_frame(charToRaw(paste0(";~genome: g\n", line, "\n")), "fasta", TRUE)
    .bh_find_checksum(frame)
  }
  v <- "Z1p/siczUlN/N+lDB5Kg6vFRrztGErgLw9H4MfVfZeU="
  expect_true(one(paste0(";~checksum: ", v))$ok)
  expect_true(one(paste0(";~checksum:  ", v, "  "))$ok) # R5 allows spaces round the value
  expect_true(one(paste0(';~checksum: "', v, '"'))$ok)
  expect_true(one(paste0(";~checksum: '", v, "'"))$ok)
  expect_false(one(paste0(";~checksum: ", v, " # note"))$ok) # a comment
  expect_false(one(paste0(";~checksum:\n;~  ", v))$ok) # continued on the next line
  expect_false(one(paste0(";~checksum: \"", v))$ok) # unbalanced quote
  # non-canonical base64: the character before "=" must have its two unused bits zero,
  # so "B" there is not a checksum value at all (rule R4 says compare as exact strings,
  # and R5 fixes the grammar that makes a non-canonical value invalid on its face)
  expect_identical(substr(v, 43L, 44L), "U=") # the pinned vector's own tail
  expect_false(one(paste0(";~checksum: ", substr(v, 1, 42), "B="))$ok)
  expect_false(one(paste0(";~checksum: ", substr(v, 1, 42), "A"))$ok) # no padding
  expect_false(one(paste0(";~checksum: ", substr(v, 1, 41), "-U="))$ok) # outside the alphabet
})

test_that("R7: a UTF-8 BOM is refused in FASTA and GFA, and R6 says so for bad bytes", {
  bom <- c(as.raw(c(0xef, 0xbb, 0xbf)), charToRaw(";~genome: g\n"))
  frame <- .bh_frame(bom, "fasta", TRUE)
  expect_match(paste(frame$why, collapse = " "), "R7")
  bad <- charToRaw(";\xfe\xff not utf8\n")
  expect_true(is.na(.bh_decode(bad)))
})

test_that("R10: a header line after the block is reported by the frame and by the scan", {
  b <- charToRaw(paste0(
    ";~schema: https://w3id.org/fair-bioheaders/fhr/v0.6.0\n;~genome: g\n",
    ">seq1\nACGT\n;~checksum: Z1p/siczUlN/N+lDB5Kg6vFRrztGErgLw9H4MfVfZeU=\n"
  ))
  frame <- .bh_frame(b, "fasta", TRUE)
  expect_match(paste(frame$why, collapse = " "), "R10")
  # and the streaming scanner finds it without the file being in memory at all
  p <- tempfile()
  on.exit(unlink(p), add = TRUE)
  writeBin(b, p)
  scan <- bh_sha512_256_file(p, scan = list(prefix = charToRaw(";~"), after = frame$scan_after))
  expect_equal(scan$late_header_lines, 1L)
})

test_that("G1: ##gff-version 3 is line 1 and a #~ line may not precede it", {
  ok <- paste0(
    "##gff-version 3\n#~schema: https://w3id.org/fair-bioheaders/fhgff3/v0.6.0\n",
    "#~checksum: Z1p/siczUlN/N+lDB5Kg6vFRrztGErgLw9H4MfVfZeU=\n"
  )
  expect_equal(length(.bh_frame(charToRaw(ok), "fhgff3", TRUE)$why), 0L)
  bad <- sub("^##gff-version 3\n", "", ok)
  expect_match(paste(.bh_frame(charToRaw(bad), "fhgff3", TRUE)$why, collapse = " "), "G1")
  v31 <- sub("##gff-version 3\n", "##gff-version 3.1\n", ok)
  expect_match(paste(.bh_frame(charToRaw(v31), "fhgff3", TRUE)$why, collapse = " "), "G1")
  v321 <- sub("##gff-version 3\n", "##gff-version 3.2.1\n", ok)
  expect_equal(length(.bh_frame(charToRaw(v321), "fhgff3", TRUE)$why), 0L)
})
