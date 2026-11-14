# Pinned digest vectors for the vendored core.
#
# Two sources, deliberately independent of this package:
#
#  * the NIST CVL worked example "Secure Hash Algorithm, Message Digest Length = 512/256"
#    (https://csrc.nist.gov/csrc/media/Projects/Cryptographic-Standards-and-Guidelines/
#    documents/examples/SHA512_256.pdf, retrieved 2026-11-14), which lists the SHA-512/256
#    initial hash value and the digests of its one-block and two-block sample messages;
#    this package's compiled self-test checks the same two values at load time; and
#  * the shared conformance suite, whose valid sequence vectors state the SHA-512/256 of
#    their own bytes - that comparison lives in test-digest-fixtures.R.
#
# The inputs are the FIPS 180-4 sample messages. Where a value below was produced by
# `openssl dgst -sha512-256` and by CPython hashlib.new("sha512_256") on the host this
# package was written on, rather than read out of the NIST document, it says so: that is
# the difference between a published constant and a locally generated one, and the
# distinction is the whole point of the digest decision.

.vectors_512_256 <- function() {
  list(
    list(
      label = "empty message (locally generated: hashlib and openssl agree)",
      bytes = raw(0),
      hex = "c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a",
      b64 = "xnK40e9W7Sirh8NiLFEUBpvdOte4+XN0mNDAHs7wlno="
    ),
    list(
      label = "FIPS 180-4 message 1 \"abc\" (published in the NIST CVL 512/256 example)",
      bytes = charToRaw("abc"),
      hex = "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23",
      b64 = "UwSOJoGUHvmbLim3a0x9q+TC0MY0/G1G4OLxMQfnryM="
    ),
    list(
      label = paste0(
        "FIPS 180-4 message 2, 112 characters (published in the NIST CVL 512/256 ",
        "example as 3928E184 FB8690F8 40DA3988 121D31BE 65CB9D3E F83EE614 6FEAC861 ",
        "E19B563A)"
      ),
      bytes = charToRaw(paste0(
        "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno",
        "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
      )),
      hex = "3928e184fb8690f840da3988121d31be65cb9d3ef83ee6146feac861e19b563a",
      b64 = "OSjhhPuGkPhA2jmIEh0xvmXLnT74PuYUb+rIYeGbVjo="
    ),
    list(
      label = "FIPS 180-4 message 3, 1,000,000 x 'a' (locally generated; 128-bit length field in use)",
      bytes = rep(as.raw(97L), 1000000L),
      hex = "9a59a052930187a97038cae692f30708aa6491923ef5194394dc68d56c74fb21",
      b64 = "mlmgUpMBh6lwOMrmkvMHCKpkkZI+9RlDlNxo1Wx0+yE="
    )
  )
}

# Length-boundary corpus: every length at which SHA-512's 128-byte block or the 112/128
# padding split changes shape, plus multi-block cases. Values computed by
# hashlib.new("sha512_256") and confirmed identical from `openssl dgst -sha512-256` on the
# same host; the input is (97 + i mod 26) so a byte-order or length bug cannot hide.
.boundary_corpus <- function() {
  list(
    lens = c(0L, 1L, 2L, 55L, 56L, 57L, 63L, 64L, 65L, 111L, 112L, 113L, 119L, 120L,
             121L, 127L, 128L, 129L, 200L, 1000L),
    hex = c(
      "c672b8d1ef56ed28ab87c3622c5114069bdd3ad7b8f9737498d0c01ecef0967a",
      "455e518824bc0601f9fb858ff5c37d417d67c2f8e0df2babe4808858aea830f8",
      "22d4d37ec6370571af7109fb12eae79673d5f7c83e6e677083faa3cfac3b2c14",
      "1631ab824c392524395a7ab899178167868bf977df94a5916267a36525c8c5c4",
      "628f52514c2425d7384436eaf38eab6aeb938f90a01a5fa947f38d86d4f17573",
      "2cbe7689933c2b5af0ba224b19c9f1bd2a5674c51dcc672a7ae7d34f96dd4442",
      "ce78a11aca854b472244e6fbc09f7ce1c140a666b28bb2c61dad13f2395a10c2",
      "191be90c8a80b7c2337e97e33fba48c1592d13f93376202437550ccad25f8ba8",
      "29f501750e205c012ddec390d4f699edd121008e317f2d70078f49fbab347912",
      "619f97dc7182097f5f158863cd05d164b9ba91e178db0908353f6ce5842a005a",
      "f95ea66e19cd5f0e977f5017d07f7906a7e829dfee984e3ff8da383902db6dde",
      "273b66be18a6b0503fc7cd9af8d458915c4a590a2c3f7b1699cedb71e2fa9a13",
      "bb1008e640f74534158b8ffd6f25df0652a3fd0105e1048309e45a5a6ed00c74",
      "860dc33e6ba800fa17ec35e381b6875c5ddbd89c41e9f0e7f6f63fc357a26bab",
      "3b90030aae115eb5f8100399b3f3729a9e88559dd8400e823e606378052bb686",
      "5d92312a28a0b793b3f8f5e43a2e97e8513391538177ad17c9a9069de090db9e",
      "8e7b3f63a5dc33e4dd50624c720426ed3d184cda38afa86bf4449a054d09fe24",
      "4c35635ae147bd8239e2e9016b59faf18ed55d11e855c2295fce023adb71b397",
      "d1adaf271c20f729ecbe006d714d2f6bc8df4fa4973a2c0188ea6bb4a65ffa74",
      "a95139bc0e40401f633eea005a320a909047611fbfb043707f9d44133eee667b"
    )
  )
}

.bh_corpus_bytes <- function(n) as.raw(97L + (seq_len(n) - 1L) %% 26L)

test_that("the compiled core reproduces the published SHA-512/256 digests", {
  for (v in .vectors_512_256()) {
    expect_identical(bh_sha512_256(v$bytes, "hex"), v$hex, info = v$label)
    expect_identical(bh_sha512_256_b64(v$bytes), v$b64, info = v$label)
    expect_identical(bh_sha512_256(v$bytes, "raw"), as.raw(strtoi(
      substring(v$hex, seq(1, 63, by = 2), seq(2, 64, by = 2)), 16L
    )), info = v$label)
  }
})

test_that("the SHA-512/256 initial hash value is the 512/256 one, not SHA-512's", {
  # FIPS 180-4 5.3.8, listed the same way in the NIST CVL example. If the core ever picks
  # up the SHA-512 words by mistake, "abc" comes out as ddaf35a1..., which is a real
  # SHA-512 digest and would pass no file in the federation.
  expect_equal(substr(bh_sha512_256(charToRaw("abc"), "hex"), 1, 8), "53048e26")
  expect_equal(substr(bh_sha512(charToRaw("abc"), "hex"), 1, 8), "ddaf35a1")
})

test_that("the length-boundary corpus matches, one-shot and in every chunking", {
  bc <- .boundary_corpus()
  for (i in seq_along(bc$lens)) {
    n <- bc$lens[[i]]
    bytes <- .bh_corpus_bytes(n)
    expect_identical(bh_sha512_256(bytes, "hex"), bc$hex[[i]], info = paste0("n=", n))
    for (chunk in c(1L, 3L, 64L, 111L, 112L, 128L, 999L)) {
      s <- bh_digest_stream()
      pos <- 1L
      while (pos <= n) {
        take <- min(chunk, n - pos + 1L)
        bh_stream_update(s, bytes[seq.int(pos, pos + take - 1L)])
        pos <- pos + take
      }
      expect_identical(bh_stream_value(s, "hex")$hex, bc$hex[[i]],
        info = paste0("n=", n, " chunk=", chunk)
      )
    }
  }
})

test_that("SHA-512 truncated is NOT SHA-512/256 - the trap this decision is about", {
  sha512 <- bh_sha512(charToRaw("abc"), "hex")
  truncated <- substr(sha512, 1, 64)
  real <- bh_sha512_256(charToRaw("abc"), "hex")
  expect_false(identical(truncated, real))
  expect_equal(nchar(truncated), 64L) # it is the right shape, and that is what makes
  expect_equal(nchar(real), 64L) # it dangerous: only the digits differ
  # and on a byte range taken from a real file, not just on "abc"
  kept <- .bh_corpus_bytes(300)
  expect_false(identical(
    bh_sha512_256_b64(kept),
    paste(jsonlite::base64_enc(bh_sha512(kept, "raw")[1:32]), collapse = "")
  ))
})

test_that("the checksum encoding is canonical padded base64 (rule R4)", {
  b <- bh_sha512_256_b64(charToRaw("abc"))
  expect_equal(nchar(b), 44L)
  expect_match(b, "^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$")
})

test_that("a file is hashed exactly as its bytes, with the excluded range skipped", {
  p <- tempfile()
  on.exit(unlink(p), add = TRUE)
  writeBin(charToRaw("line1\n;~checksum: AAA=\nline3\n"), p)
  whole <- bh_sha512_256_file(p)
  expect_identical(whole$digest, bh_sha512_256_b64(charToRaw("line1\n;~checksum: AAA=\nline3\n")))
  expect_equal(whole$bytes, 29)
  skipped <- bh_sha512_256_file(p, skip = c(7, 17)) # the line and its LF
  expect_identical(skipped$digest, bh_sha512_256_b64(charToRaw("line1\nline3\n")))
  expect_equal(skipped$bytes, 12)
  # a skip range that straddles a chunk boundary must give the same answer
  expect_identical(bh_sha512_256_file(p, skip = c(7, 17), buffer = 1024L)$digest,
    skipped$digest)
})

test_that("gzip and BGZF transport produce the digest of the decompressed bytes", {
  body <- charToRaw(paste0(
    "line1\n;~checksum: AAA=\nline3\n",
    strrep("abcdefghij\n", 5000) # multi-block, so a padding bug cannot hide
  ))
  p <- tempfile()
  on.exit(unlink(p), add = TRUE)
  con <- gzfile(p, open = "wb")
  writeBin(body, con)
  close(con)
  expect_identical(bh_sha512_256_file(p)$digest, bh_sha512_256_b64(body))
  expect_true(bh_sha512_256_file(p)$bytes > 50000)
})

test_that("the rule R10 line scan counts header lines after the block, across chunks", {
  p <- tempfile()
  on.exit(unlink(p), add = TRUE)
  # lines: "a\n"(1-2) ";~late\n"(3-9) "b\n"(10-11) "c\n"(12-13) ";~late2\n"(14-21)
  # header lines therefore start at byte 3 and byte 14
  writeBin(charToRaw("a\n;~late\nb\nc\n;~late2\n"), p)
  late_from <- function(after) {
    bh_sha512_256_file(p, scan = list(prefix = charToRaw(";~"), after = after)
    )$late_header_lines
  }
  expect_equal(late_from(3), 2L)
  expect_equal(late_from(14), 1L)
  expect_equal(late_from(15), 0L)
  expect_equal(late_from(22), 0L)
  # a prefix in the middle of a line is not a line start
  q <- tempfile()
  on.exit(unlink(q), add = TRUE)
  writeBin(charToRaw("ACGT;~not-a-header\nACGT\n"), q)
  expect_equal(
    bh_sha512_256_file(q, scan = list(prefix = charToRaw(";~"), after = 1))$late_header_lines,
    0L
  )
  # CRLF and lone CR both end a line, per rule R1
  r <- tempfile()
  on.exit(unlink(r), add = TRUE)
  writeBin(charToRaw("a\r\n;~crlf\nb\rc\rcr-only\n"), r)
  expect_equal(
    bh_sha512_256_file(r, scan = list(prefix = charToRaw(";~"), after = 1))$late_header_lines,
    1L
  )
  expect_equal(
    bh_sha512_256_file(r, scan = list(prefix = charToRaw("cr"), after = 1))$late_header_lines,
    1L
  )
  # and the scan does not change the digest
  expect_identical(
    bh_sha512_256_file(r, scan = list(prefix = charToRaw(";~"), after = 1))$digest,
    bh_sha512_256_file(r)$digest
  )
})

test_that("the load-time self-test is wired, and the API rejects nonsense", {
  # the same registered routine object .onLoad uses; a nonzero code means the compiled
  # core does not reproduce the published digests and the package refuses to load
  selftest <- getFromNamespace("C_selftest", "FAIRbioHeadersTools")
  expect_identical(.Call(selftest), 0L)
  expect_true(bh_sha512_256_available())
  expect_error(bh_sha512_256("not raw"), "raw vector")
  expect_error(.bh_algo_number("md5"), "sha512-256")
  expect_error(bh_sha512_256_file(tempfile()), "no such file")
  s <- bh_digest_stream()
  bh_stream_value(s, "hex")
  expect_error(bh_stream_update(s, charToRaw("x")), "already finalized")
  expect_error(bh_stream_value(s, "hex"), "already finalized")
})
