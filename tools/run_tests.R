#!/usr/bin/env Rscript
#' Run the testthat suite as CI sees it: results, counts, and hard floors.
#'
#' A green build with quietly skipped tests is not acceptance. This script errors on
#' any failure or error, on ANY skip, and on a test count below BH_MIN_TESTS (CI
#' passes the current real floor; raising it in a PR that adds tests is deliberate,
#' lowering it needs a reason). Writes key=value results to BH_TESTS_RECEIPT.

suppressMessages(library(testthat))
res <- as.data.frame(test_dir("tests/testthat",
  package = "FAIRbioHeadersTools", reporter = "silent", stop_on_failure = FALSE
))
tests <- sum(res$nb)
failed <- sum(res$failed)
errors <- sum(res$error)
skipped <- sum(res$skipped)
floor_n <- as.integer(Sys.getenv("BH_MIN_TESTS", unset = "500"))
cat(sprintf("testthat: tests=%d failed=%d errors=%d skipped=%d (floor %d)\n",
  tests, failed, errors, skipped, floor_n
))
path <- Sys.getenv("BH_TESTS_RECEIPT", unset = "")
if (nzchar(path)) {
  writeLines(c(
    paste0("tests=", tests), paste0("failed=", failed), paste0("errors=", errors),
    paste0("skipped=", skipped)
  ), path)
}
if (failed > 0L || errors > 0L) quit(status = 1L, save = "no")
if (skipped > 0L) {
  cat("skips are not accepted in the primary job; every hole is a declared\n",
    "not-run row in the ledger instead\n",
    sep = ""
  )
  quit(status = 1L, save = "no")
}
if (tests < floor_n) quit(status = 1L, save = "no")
