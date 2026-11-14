#!/usr/bin/env Rscript
#' Native acceptance run: the shared v0.6.0 suite plus the default-behavior golden.
#'
#' This is the script CI calls. It needs only R, this package (installed from source)
#' and the data vendored in the repository: no Python, no reference toolkit, no other
#' implementation anywhere in this path. It exits nonzero on any failure and writes a
#' key=value receipt to the path given by BH_ACCEPTANCE_RECEIPT (the ledger) and
#' BH_GOLDEN_RECEIPT (the golden comparison), so CI can assert what actually ran
#' rather than trusting a green build.

suppressMessages(library(FAIRbioHeadersTools))
fails <- 0L
say <- function(...) cat(..., "\n", sep = "")

# 1. The shared suite, lane closed: all 291 accounted for, none failing.
#    (CI runs tools/check_vendoring.R as its own step before this script.)
x <- bh_conformance()
print(x)
res <- x$results
fmt_line <- function(f) {
  d <- res[res$format == f, ]
  sprintf("%d/%d passed, %d not run", sum(d$status == "pass"), nrow(d),
    sum(d$status == "not-run")
  )
}
ledger <- list(
  available = tolower(as.character(x$vectors == 291L && x$ok)),
  vectorsTotal = 291L,
  vectorsRun = sum(res$status %in% c("pass", "fail", "error", "missing-fixture")),
  vectorsPassed = sum(res$status == "pass"),
  vectorsFailed = sum(res$status %in% c("fail", "error", "missing-fixture")),
  vectorsNotRun = sum(res$status == "not-run"),
  vectorsDeclaredNotRunWithReason = sum(res$status == "not-run" & nzchar(res$reason)),
  fasta = fmt_line("fasta"), gfa = fmt_line("gfa"),
  `fhp-fasta` = fmt_line("fhp-fasta"), fhgff3 = fmt_line("fhgff3"),
  microdata = fmt_line("microdata"), jsonld = fmt_line("jsonld")
)
FAIRbioHeadersTools:::.bh_receipt("BH_ACCEPTANCE_RECEIPT", ledger)
for (nm in names(ledger)) say(nm, "=", ledger[[nm]])
if (!isTRUE(ledger$available == "true")) fails <- fails + 1L

# 3. The default-behavior golden: what the default reading does must be what was
#    accepted, field by field, across every vector and every selection probe.
want <- jsonlite::fromJSON(FAIRbioHeadersTools:::.bh_golden_path(),
  simplifyVector = FALSE
)
got_txt <- jsonlite::toJSON(FAIRbioHeadersTools:::.bh_fingerprint(), auto_unbox = TRUE,
  null = "null", na = "null"
)
got <- jsonlite::fromJSON(got_txt, simplifyVector = FALSE)
want <- jsonlite::fromJSON(jsonlite::toJSON(want, auto_unbox = TRUE, null = "null",
  na = "null"
), simplifyVector = FALSE)
diffs <- FAIRbioHeadersTools:::.bh_golden_diff(got, want)
golden_receipt <- list(
  vectorsCompared = length(got$vectors),
  documentsCompared = sum(vapply(got$vectors, function(v) isTRUE(v$ran), logical(1L))),
  selectionCasesCompared = length(got$selectionProbes),
  goldenDifferences = length(diffs)
)
FAIRbioHeadersTools:::.bh_receipt("BH_GOLDEN_RECEIPT", golden_receipt)
for (nm in names(golden_receipt)) say(nm, "=", golden_receipt[[nm]])
if (length(diffs)) {
  say("GOLDEN DIFFERENCES (default behaviour changed):")
  for (d in head(diffs, 25L)) say("  ", d)
  fails <- fails + 1L
}

if (fails > 0L) {
  say("native acceptance: FAIL (", fails, " problem group(s))")
  quit(status = 1L, save = "no")
}
say("native acceptance: all checks passed")
