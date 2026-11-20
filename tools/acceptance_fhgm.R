#!/usr/bin/env Rscript
#' Rule V7 draft-lane acceptance: the FHGM development suite, run natively, layer by layer.
#'
#' Separate, labelled, and never merged into the shared ledger: these 62 vectors are
#' published by FHGM-Specification against an UNRELEASED model contract (rule V7). FHGM is
#' not a header type - its records are transported inside an FHGFF3 header under
#' `x-fhgm-models` and carry no `schema` field - so this run compares the layers that suite
#' records per vector: `base` (the released FHGFF3 contract), `checksum` (the file-bound
#' SHA-512/256), and the `model` layer only where a vector's own rule labels are inside the
#' scope this package evaluates (K1 transport, K2 record contract). A vector whose verdict
#' turns on K3, K4, K5, K6 or B1 is reported `not-run` with the rule named: never passed on
#' the strength of the schema layer. A vector with no rule label at all is `not-run` too,
#' because an absent label does not establish scope.
#'
#' A pass here says the pinned draft bytes behave as their own suite expects through this
#' reader, for the rules in scope. It is not, and never becomes, a claim that FHGM is
#' supported: FHGM has no schemaVersion, no registry row and no w3id URL (see
#' docs/CAPABILITY-MATRIX.md).
#'
#' This script needs only R, this package and the data vendored in the repository. It exits
#' nonzero on any failure and writes a receipt to BH_FHGM_RECEIPT.

suppressMessages(library(FAIRbioHeadersTools))
say <- function(...) cat(..., "\n", sep = "")

pins <- bh_draft_pins()
fhgm <- pins[pins$header_type == "FHGM", ]
if (nrow(fhgm) != 1L || !isTRUE(fhgm$digest_ok)) {
  say("the pinned FHGM draft contract bytes failed their digest check")
  quit(status = 1L, save = "no")
}
pinned <- FAIRbioHeadersTools:::.bh_vendored()$draft_fhgm_vectors
if (is.null(pinned)) {
  say("no FHGM draft vectors are vendored in this build")
  quit(status = 1L, save = "no")
}

x <- bh_draft_fhgm_vectors()
print(x)
res <- x$results
base_ok <- sum(res$got_base == res$expected_base)
sum_ok <- sum(res$got_checksum == res$expected_checksum)
receipt <- list(
  vectorsInManifest = pinned$vectors,
  vectorsEvaluated = nrow(res),
  vectorsRan = sum(res$status %in% c("pass", "fail", "error", "missing-fixture")),
  vectorsPassed = sum(res$status == "pass"),
  vectorsFailed = sum(res$status %in% c("fail", "error", "missing-fixture")),
  vectorsNotRun = sum(res$status == "not-run"),
  vectorsNotRunWithReason = sum(res$status == "not-run" & nzchar(res$reason)),
  # an unlabelled vector must never be counted as in-scope: the guard in
  # bh_draft_fhgm_vectors() reports it not-run, and this line proves the pinned manifest
  # needed no such report. If it ever moves, the model layer grew on the strength of a
  # missing field, and that is a finding, not a wider pass.
  vectorsNotRunUnlabelled = sum(res$status == "not-run" & !nzchar(res$rules)),
  baseLayerAgreement = paste0(base_ok, "/", nrow(res)),
  checksumLayerAgreement = paste0(sum_ok, "/", nrow(res)),
  modelLayerCompared = sum(res$status %in% c("pass", "fail") & !nzchar(res$rule_gaps)),
  contractCommit = fhgm$commit,
  contractSha256 = fhgm$sha256,
  suiteCommit = pinned$commit,
  suiteManifestSha256 = pinned$manifest_sha256,
  lane = paste0(
    "rule V7, opt-in, warned on every record read; draft evidence, not support; ",
    "not part of the 291"
  ),
  note = ""
)
FAIRbioHeadersTools:::.bh_receipt("BH_FHGM_RECEIPT", receipt)
for (nm in names(receipt)) say(nm, "=", receipt[[nm]])

# The run is only evidence if it actually compared what it claims to compare: every vector
# accounted for, the two layers that are in scope for all of them agreeing on all of them,
# and not one vector more or less judged at the model layer. The counts below are the
# re-pinned expectations for manifest e41f05fd8bb8b8ec... (62 vectors): 19 compared at the
# model layer, 43 not-run with the rule that keeps them out named. They move together with
# the workflow's pinned literals, deliberately, and only when the suite is re-pinned by
# reading what moved.
n_eval <- 62L
n_model <- 19L
bad <- 0L
if (receipt$vectorsFailed > 0L) {
  say("FAIL: ", receipt$vectorsFailed, " vector(s) disagreed with the published layers")
  bad <- bad + 1L
}
if (receipt$vectorsEvaluated != n_eval || receipt$vectorsInManifest != n_eval) {
  say("FAIL: ", receipt$vectorsEvaluated, " evaluated, manifest pins ", n_eval)
  bad <- bad + 1L
}
if (base_ok != n_eval || sum_ok != n_eval) {
  say("FAIL: the base or checksum layer did not agree on every vector")
  bad <- bad + 1L
}
if (receipt$vectorsPassed + receipt$vectorsNotRun != n_eval) {
  say("FAIL: every vector must be either compared at the model layer or not-run with a rule")
  bad <- bad + 1L
}
if (receipt$modelLayerCompared != n_model) {
  say("FAIL: the model layer compared ", receipt$modelLayerCompared,
      " vectors, expected ", n_model,
      " - the scope this package claims (K1/K2) and the workflow's",
      " pinned literals move together, deliberately")
  bad <- bad + 1L
}
if (receipt$vectorsNotRunWithReason != receipt$vectorsNotRun) {
  say("FAIL: a not-run vector without a reason is a hole, not a report")
  bad <- bad + 1L
}
if (receipt$vectorsNotRunUnlabelled != 0L) {
  say("FAIL: ", receipt$vectorsNotRunUnlabelled,
      " not-run vector(s) carry no rule label - scope was assumed, not read")
  bad <- bad + 1L
}
if (bad > 0L) {
  say("FHGM draft-lane acceptance: FAIL")
  quit(status = 1L, save = "no")
}
say(
  "FHGM draft-lane acceptance: ", n_eval, " vectors, base ", n_eval, "/", n_eval,
  ", checksum ", n_eval, "/", n_eval, ", model layer ",
  "compared and agreeing on ", receipt$vectorsPassed, ", the other ",
  receipt$vectorsNotRun, " not-run naming the checker rule they need"
)
