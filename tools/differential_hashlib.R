#!/usr/bin/env Rscript
#' Compare the vendored digest core with CPython hashlib (see the .py partner).
#' Supplemental evidence, never the acceptance gate.

suppressMessages(library(FAIRbioHeadersTools))
h <- jsonlite::fromJSON("/tmp/hashlib_digests.json")
man <- jsonlite::fromJSON("tests/conformance/manifest.json", simplifyVector = TRUE)
vs <- man$vectors[
  man$vectors$expected == "valid" & !is.na(man$vectors$checksum) &
    man$vectors$format %in% c("fasta", "gfa", "fhp-fasta", "fhgff3"),
  c("id", "file")
]
n <- 0L
mism <- character()
digest_of <- function(id) {
  if (id %in% c("abc", "empty", "112")) {
    msg <- switch(id,
      abc = charToRaw("abc"), empty = raw(0),
      `112` = charToRaw(paste0(
        "abcdefghbcdefghicdefghijdefghijkefghijklmghijklmnhijklmno",
        "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
      ))
    )
    return(bh_sha512_256_b64(msg))
  }
  i <- match(id, vs$id)
  f <- vs$file[[i]]
  b <- FAIRbioHeadersTools:::.bh_read_all(file.path("tests/conformance", f))
  if (grepl("[.]gz$", f)) {
    tf <- tempfile()
    writeBin(b, tf)
    con <- gzfile(tf, "rb")
    b <- readBin(con, "raw", n = 1e8)
    close(con)
  }
  bh_sha512_256_b64(b)
}
for (id in names(h)) {
  got <- digest_of(id)
  n <- n + 1L
  if (!identical(got, h[[id]])) mism <- c(mism, id)
}
cat(sprintf("differential: %d inputs compared (vendored core vs CPython hashlib), %d mismatches\n",
  n, length(mism)
))
if (length(mism)) {
  print(mism)
  quit(status = 1L, save = "no")
}
