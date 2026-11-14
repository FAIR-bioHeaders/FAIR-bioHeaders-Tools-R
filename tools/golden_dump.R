#!/usr/bin/env Rscript
#' Generate the default-behavior golden, ONCE, by explicit action.
#'
#' Usage: Rscript tools/golden_dump.R [--out tests/testthat/reference/default-behavior-v0.6.0.json]
#'
#' This is not part of any test run and never overwrites silently without being asked:
#' the golden's whole value is that regressions move it. Regenerating means the new
#' behaviour was reviewed and the regeneration is part of the commit, with the reason
#' said in the PR. The file records its generation date and the pinned suite manifest
#' digest it was computed against.

suppressMessages(library(FAIRbioHeadersTools))
args <- commandArgs(trailingOnly = TRUE)
out <- if ("--out" %in% args) args[match("--out", args) + 1L] else {
  file.path("tests", "testthat", "reference", "default-behavior-v0.6.0.json")
}
fp <- FAIRbioHeadersTools:::.bh_fingerprint()
txt <- jsonlite::toJSON(unclass(fp), auto_unbox = TRUE, pretty = 2, null = "null",
  na = "null"
)
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
writeLines(txt, out)
cat("wrote", out, "\n")
cat("sha256:", substr(digest::digest(charToRaw(paste0(txt, "\n")), algo = "sha256",
  serialize = FALSE
), 1, 16), "...\n")
