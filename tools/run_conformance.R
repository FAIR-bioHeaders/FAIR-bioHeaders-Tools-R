#!/usr/bin/env Rscript
#' Native shared-vector acceptance run, from the command line.
#'
#' This is the report CI publishes; the assertions live in tests/testthat, and the same
#' guards run here so a partial invocation cannot look like a pass. Nothing in this script
#' calls Python or any other implementation: the expected verdicts come from the manifest
#' the specification publishes, and every comparison is against the pinned contract copies
#' and the vendored vector bytes in this repository.
#'
#' Usage, from the package root:
#'
#'   Rscript tools/run_conformance.R                       # the shared 291
#'   Rscript tools/run_conformance.R --report out/dir      # write TSV + JSON there
#'   Rscript tools/run_conformance.R --draft               # the FHT development suite,
#'                                                         # separately labelled
#'   Rscript tools/run_conformance.R --fhgm                # the FHGM development suite,
#'                                                         # reported layer by layer
#'
#' Exit status: 0 when the run is complete and nothing was unexpected; 1 otherwise, and for
#' a missing suite, a provenance mismatch, an unaccounted vector or a zero-vector run.

.options <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default = NULL) {
  i <- match(name, .options)
  if (is.na(i) || i == length(.options)) default else .options[i + 1L]
}
report_dir <- arg("--report")
draft <- "--draft" %in% .options
fhgm <- "--fhgm" %in% .options

if (!requireNamespace("FAIRbioHeadersTools", quietly = TRUE)) {
  stop("install the package first: R CMD INSTALL .")
}
library(FAIRbioHeadersTools)

cat("R ", R.version.string, " | jsonvalidate ",
    as.character(packageVersion("jsonvalidate")), " | V8 ",
    as.character(packageVersion("V8")), " | yaml ",
    as.character(packageVersion("yaml")), "\n", sep = "")
cat("SHA-512/256 available natively: ", bh_sha512_256_available(), "\n", sep = "")
cat("schema engine in use: ajv (pinned); dialect self-check: ")
invisible(bh_dialect_probe())
cat("ok\n\n")

if (fhgm) {
  x <- bh_draft_fhgm_vectors()
  kind <- "draft-fhgm"
} else if (draft) {
  x <- bh_draft_vectors()
  kind <- "draft-fht"
} else {
  x <- bh_conformance()
  kind <- "shared"
}
print(x)

if (!is.null(report_dir)) {
  dir.create(report_dir, showWarnings = FALSE, recursive = TRUE)
  # one line per vector: a diagnostic that contains a newline would otherwise break the TSV
  # and make the report read as fewer vectors than ran
  flat <- x$results
  flat[] <- lapply(flat, function(col) {
    if (is.character(col)) gsub("[\r\n]+", " / ", col) else col
  })
  write.table(
    flat, file.path(report_dir, paste0("vectors-", kind, ".tsv")),
    sep = "\t", quote = FALSE, row.names = FALSE
  )
  writeLines(
    bh_conformance_report(x),
    file.path(report_dir, paste0("conformance-", kind, ".json"))
  )
  writeLines(
    c(
      paste("run:", format(Sys.time())),
      paste("suite:", x$suite),
      paste("label:", x$label),
      paste("vectors accounted for:", x$vectors),
      paste("unexpected results:", x$failures),
      paste("vectors leaving a rule unverified:", x$gap_vectors),
      paste("R:", R.version.string),
      paste("jsonvalidate:", packageVersion("jsonvalidate")),
      paste("V8:", packageVersion("V8")),
      paste("yaml:", packageVersion("yaml"))
    ),
    file.path(report_dir, paste0("conformance-", kind, ".txt"))
  )
  cat("\nreports written to ", normalizePath(report_dir), "\n", sep = "")
}

cat("\nvectors per format and status:\n")
print(x$summary)
if (fhgm) {
  cat("\nper-layer agreement:\n")
  cat("  base    ", sum(x$results$got_base == x$results$expected_base), "/ 31\n")
  cat("  checksum", sum(x$results$got_checksum == x$results$expected_checksum), "/ 31\n")
  cat("  model   ", sum(x$results$got_model == x$results$expected_model), "/ 31 raw;",
      sum(x$results$status == "pass"), " where the comparison is meaningful\n")
}

if (!isTRUE(x$ok)) {
  cat("\nFAIL: ", x$failures, " vector(s) did not match the published expectation\n",
      sep = "")
  quit(status = 1L)
}
if (fhgm) {
  # the FHGM run is only meaningful if it actually compared the layers it claims to
  if (!all(c("got_base", "got_checksum") %in% names(x$results)) ||
      !all(x$results$got_base == x$results$expected_base) ||
      !all(x$results$got_checksum == x$results$expected_checksum)) {
    cat("\nFAIL: the FHGM base or checksum layer did not match on every vector\n")
    quit(status = 1L)
  }
  cat("\nFHGM layers compared: base 31/31, checksum 31/31; model layer comparable on ",
      sum(x$results$status == "pass"), " of 31, the rest not-run with the rule named\n",
      sep = "")
}
if (!isTRUE(draft) && !isTRUE(fhgm) && x$vectors != 291L) {
  cat("\nFAIL: the shared run accounted for ", x$vectors, " vectors, expected 291\n", sep = "")
  quit(status = 1L)
}
cat("\nPASS: ", x$label, "\n", sep = "")
