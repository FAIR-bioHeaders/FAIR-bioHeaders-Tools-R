#!/usr/bin/env Rscript
#' Supplemental differential: the vendored core against a system OpenSSL client.
#'
#' This is NOT acceptance. Acceptance is the native test suite plus the shared-vector run,
#' which need nothing but R. This script exists to answer one question with an independent
#' implementation - does the vendored core still agree with a second, unrelated SHA-512/256
#' implementation on a spread of inputs? - and it says so plainly when no client is
#' installed rather than pretending to have checked.
#'
#'   Rscript tools/differential_digest.R
#'
#' Exit status is 0 when the core agrees with the client, or when no client is present (the
#' run is then reported as SKIPPED, with the reason). A present client that disagrees is a
#' hard failure.
#'
#' A Python differential is available the same way (hashlib.new("sha512_256")); it is
#' deliberately not part of any job that gates acceptance, per the native-first direction in
#' FAIR-bioHeaders-Specification#211.

if (!requireNamespace("FAIRbioHeadersTools", quietly = TRUE)) stop("install the package first")
library(FAIRbioHeadersTools)

client <- Sys.which("openssl")
if (!nzchar(client)) {
  cat("SKIPPED: no `openssl` client on PATH; nothing to differential against.\n")
  cat("This is a supplemental check only - the native suite and the shared vectors are the\n",
      "acceptance path, and both run without it.\n", sep = "")
  quit(status = 0L)
}
ver <- system2(client, c("version"), stdout = TRUE)
cat("client:", ver, "\n")

digest_cli <- function(bytes) {
  f <- tempfile()
  on.exit(unlink(f), add = TRUE)
  con <- file(f, "wb")
  writeBin(bytes, con)
  close(con)
  o <- system2(client, c("dgst", "-sha512-256", "-r", shQuote(f)), stdout = TRUE)
  hex <- sub(" .*$", "", o[[1L]])
  if (!grepl("^[0-9a-f]{64}$", hex)) stop("client produced no digest: ", o[[1L]])
  hex
}

inputs <- list(
  empty = raw(0),
  abc = charToRaw("abc"),
  m112 = charToRaw(paste0(
    "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno",
    "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
  )),
  m1e6 = rep(as.raw(97L), 1000000L),
  nul = as.raw(c(0x00, 0x01, 0xfe, 0xff, 0x00)),
  block = as.raw(rep_len(seq(0L, 255L), 128L)),
  block_plus = as.raw(rep_len(seq(0L, 255L), 129L)),
  pad_split = as.raw(rep_len(seq(0L, 255L), 112L))
)
lens <- c(55L, 56L, 57L, 111L, 119L, 120L, 121L, 127L, 1000L, 65535L, 65536L)
for (n in lens) inputs[[paste0("cyc", n)]] <- as.raw(97L + (seq_len(n) - 1L) %% 26L)

fails <- 0L
client_count <- 0L
for (nm in names(inputs)) {
  b <- inputs[[nm]]
  mine <- bh_sha512_256(b, "hex")
  theirs <- digest_cli(b)
  client_count <- client_count + 1L
  ok <- identical(mine, theirs)
  if (!ok) fails <- fails + 1L
  cat(sprintf("%-12s %8d bytes  %s  %s\n", nm, length(b), if (ok) "agree" else "DIFFER",
    substr(mine, 1, 24)))
}
# and the whole shared suite's stated checksums, which is the same claim the native test
# makes against pinned data - here against a live second implementation
dir <- tryCatch(FAIRbioHeadersTools:::.bh_suite_dir(), error = function(e) NULL)
if (!is.null(dir)) {
  man <- jsonlite::fromJSON(file.path(dir, "manifest.json"), simplifyVector = FALSE)
  n <- 0L
  for (v in man$vectors) {
    if (!identical(v$expected, "valid") || is.null(v$checksum)) next
    if (!v$format %in% c("fasta", "gfa", "fhp-fasta", "fhgff3")) next
    p <- file.path(dir, v$file)
    a <- suppressWarnings(FAIRbioHeadersTools:::.bh_analyze(p, format = v$format,
      validate_contract = FALSE
    ))
    fr <- FAIRbioHeadersTools:::.bh_frame(
      FAIRbioHeadersTools:::.bh_head(p, compressed = a$compressed)$bytes, v$format, TRUE
    )
    cs <- FAIRbioHeadersTools:::.bh_find_checksum(fr)
    kept <- fr$bytes[-seq.int(fr$lines$start[[cs$index]], fr$lines$end[[cs$index]])]
    n <- n + 1L
    # the manifest states base64, the client here prints hex
    hex <- digest_cli(as.raw(kept))
    theirs <- paste(jsonlite::base64_enc(as.raw(strtoi(
      substring(hex, seq(1, 63, by = 2), seq(2, 64, by = 2)), 16L))), collapse = "")
    if (!identical(theirs, v$checksum)) {
      fails <- fails + 1L
      cat("DIFFER (suite):", v$id, "client", theirs, "manifest", v$checksum, "\n")
    }
  }
  cat("suite vectors cross-checked with the client:", n, "\n")
}
if (fails > 0L) {
  cat("\nFAIL: ", fails, " disagreement(s) with the independent client\n", sep = "")
  quit(status = 1L)
}
cat("\nOK: the vendored core agrees with the independent client on every input above (",
  client_count + n, "comparisons)\n")
