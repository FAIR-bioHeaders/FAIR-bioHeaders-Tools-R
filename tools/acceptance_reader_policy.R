#!/usr/bin/env Rscript
# MPL-2.0. Supplementary shared runtime policy corpus, never part of the 291.
suppressPackageStartupMessages(library(FAIRbioHeadersTools))
args <- commandArgs(TRUE)
if (length(args) != 1L || !file.exists(file.path(args[1], "cases.json"))) stop("name the exact reader-policy corpus directory")
root <- normalizePath(args[1], mustWork = TRUE)
manifest <- jsonlite::fromJSON(file.path(root, "cases.json"), simplifyVector = FALSE)
stopifnot(length(manifest$cases) == 64L)
probe <- jsonlite::fromJSON(file.path(root,manifest$cases[[1L]]$file),simplifyVector=FALSE)
probe[["x-probe"]] <- list(checksum=paste0(strrep("B",43),"="))
stopifnot(isTRUE(FAIRbioHeadersTools:::.bh_validate_record(probe,bh_select(probe$schema,probe$schemaVersion))$valid))
failed <- 0L
for (case in manifest$cases) {
  file <- file.path(root, case$file)
  stopifnot(identical(digest::digest(file = file, algo = "sha256"), case$sha256))
  valid <- tryCatch({
    if (identical(case$operation, "metadata")) {
      if (identical(case$serialization, "yaml")) {
        parsed <- FAIRbioHeadersTools:::.bh_parse_record(readLines(file, warn = FALSE))
        if (!parsed$ok) FALSE else {
          rec <- parsed$record
          sel <- bh_select(rec$schema, rec$schemaVersion)
          isTRUE(FAIRbioHeadersTools:::.bh_validate_record(rec, sel)$valid)
        }
      } else {
        rec <- jsonlite::fromJSON(file, simplifyVector = FALSE)
        sel <- bh_select(rec$schema, rec$schemaVersion)
        isTRUE(FAIRbioHeadersTools:::.bh_validate_record(rec, sel)$valid)
      }
    } else isTRUE(suppressWarnings(bh_read(file, format = case$format)$valid))
  }, bh_error = function(e) FALSE)
  ok <- identical(valid, identical(case$expected, "valid"))
  cat(case$id, if (ok) "PASS" else "FAIL", "\n")
  failed <- failed + !ok
}
cat(sprintf("reader-policy: compared=64 failed=%d not-run=0\n", failed))
if (failed) quit(status = 1L)

# The staged current carrier ledger has explicit canonical-parent counterparts;
# it is separate from the immutable v0.6.0 291 and its historical expectation overlay.
carrier_root <- dirname(root)
carriers <- jsonlite::fromJSON(file.path(carrier_root, "manifest.json"), simplifyVector = FALSE)
ran <- failed <- not_run <- 0L
for (case in carriers$vectors) {
  if (!case$format %in% c("fasta","gfa","fhp-fasta","fhgff3")) {not_run <- not_run + 1L; next}
  result <- tryCatch(suppressWarnings(FAIRbioHeadersTools:::.bh_analyze(
    file.path(carrier_root,case$file),format=case$format)), bh_error=function(e) list(valid=FALSE))
  ok <- identical(isTRUE(result$valid), identical(case$expected,"valid"))
  ran <- ran+1L; failed <- failed+!ok
  if (!ok) cat(case$id,"FAIL\n")
}
cat(sprintf("current carriers: compared=%d failed=%d not-run=%d (JSON-LD/microdata unsupported)\n",ran,failed,not_run))
stopifnot(ran==254L,failed==0L,not_run==65L)
