#!/usr/bin/env Rscript
#' Rule V7 draft-lane acceptance: the FHT development suite, run natively.
#'
#' Separate, labelled, and never merged into the shared ledger: these 66 vectors are
#' published by FHT-Specification against an UNRELEASED contract (rule V7). A pass here
#' says the pinned draft bytes behave as their own suite expects through this package's
#' native reader; it is not, and never becomes, a claim that FHT is supported. FHT has
#' no schemaVersion, no registry row and no w3id URL - see docs/CAPABILITY-MATRIX.md.
#'
#' This script needs only R, this package and the data vendored in the repository.
#' It exits nonzero on any failure and writes a receipt to BH_DRAFT_RECEIPT.

suppressMessages(library(FAIRbioHeadersTools))
say <- function(...) cat(..., "\n", sep = "")

pins <- bh_draft_pins()
fht <- pins[pins$header_type == "FHT", ]
if (nrow(fht) != 1L || !isTRUE(fht$digest_ok)) {
  say("the pinned FHT draft bytes failed their digest check")
  quit(status = 1L, save = "no")
}
x <- bh_draft_vectors()
print(x)
res <- x$results
receipt <- list(
  vectorsInManifest = x$vectors,
  vectorsRan = sum(res$status %in% c("pass", "fail", "error", "missing-fixture")),
  vectorsPassed = sum(res$status == "pass"),
  vectorsFailed = sum(res$status %in% c("fail", "error", "missing-fixture")),
  contractCommit = fht$commit,
  contractSha256 = fht$sha256,
  suiteCommit = FAIRbioHeadersTools:::.bh_vendored()$draft_vectors$commit,
  suiteManifestSha256 = FAIRbioHeadersTools:::.bh_vendored()$draft_vectors$manifest_sha256,
  lane = "rule V7, opt-in, warned on every read; draft evidence, not support",
  note = ""
)
FAIRbioHeadersTools:::.bh_receipt("BH_DRAFT_RECEIPT", receipt)
for (nm in names(receipt)) say(nm, "=", receipt[[nm]])
if (receipt$vectorsFailed > 0L || receipt$vectorsRan != 66L) {
  say("draft-lane acceptance: FAIL")
  quit(status = 1L, save = "no")
}
say("draft-lane acceptance: 66/66 FHT development vectors passed through the lane")
