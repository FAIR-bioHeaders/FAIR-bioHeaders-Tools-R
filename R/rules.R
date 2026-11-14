#' Rule accounting: which rule labels a run actually checks
#'
#' A vector's `rules` field names every rule it is evidence about. Reporting only the
#' valid/invalid verdict would hide the case where a file reaches the expected verdict for a
#' reason this package does not check. The clearest instance is the FHT development suite's
#' rule C3, which asks for a *parent* file's checksum to be recomputed and compared - an
#' operation [bh_capability()] declares not implemented. So the rule labels of every vector
#' that runs are matched against the tables below, and anything the run cannot check is
#' reported per vector and in aggregate.
#'
#' This is a declaration of coverage, not a claim of correctness: the correctness evidence
#' is the vector verdicts in [bh_conformance()].
#'
#' @name rules
NULL

# Rules this package checks natively, for the serializations it reads.
.bh_rules_checked <- c(
  "R1", "R2", "R3", "R4", "R5", "R6", "R7", "R8", "R10", "R12", "R13", "R14", "R15",
  "P1", "P2", "G1", "G2", "G3", "V1", "V2", "V3", "V4", "V5", "V6", "V7", "C1", "C3"
)

# Rules whose check needs an operation this package does not implement, with the reason the
# runner reports them as gaps.
.bh_rules_unverified <- list(
  C2 = paste0(
    "the FHT development rule C2 covers which schema citations the draft accepts; the ",
    "native lane recognises only the raw-main citation, as V7 allows"
  ),
  K1 = "the FHGM model-level checker (K1-K6) is not ported; see bh_capability()",
  K2 = "the FHGM model-level checker (K1-K6) is not ported; see bh_capability()",
  K3 = "the FHGM model-level checker (K1-K6) is not ported; see bh_capability()",
  K4 = "the FHGM model-level checker (K1-K6) is not ported; see bh_capability()",
  K5 = "the FHGM model-level checker (K1-K6) is not ported; see bh_capability()",
  K6 = "the FHGM model-level checker (K1-K6) is not ported; see bh_capability()",
  R9 = "the microdata reader is not implemented",
  J1 = "the JSON-LD reader is not implemented",
  J2 = "the JSON-LD reader is not implemented",
  J3 = "the JSON-LD reader is not implemented",
  J4 = "the JSON-LD reader is not implemented",
  J5 = "the JSON-LD reader is not implemented",
  J6 = "the JSON-LD reader is not implemented",
  J7 = "the JSON-LD reader is not implemented",
  J8 = "the JSON-LD reader is not implemented",
  J9 = "the JSON-LD reader is not implemented",
  M1 = "the microdata reader is not implemented",
  M2 = "the microdata reader is not implemented",
  M3 = "the microdata reader is not implemented",
  M4 = "the microdata reader is not implemented",
  M5 = "the microdata reader is not implemented"
)

# Rules the specification asks a validator only to report, never to reject. They are not
# gaps and not rejections: the runner counts them separately so a pass that also produced
# the required warning reads differently from a pass that checked nothing.
.bh_rules_warning_only <- c(R11 = TRUE, R14 = TRUE)

.bh_rule_gaps <- function(rules) {
  unverified <- character()
  for (r in setdiff(rules, names(.bh_rules_warning_only))) { # reported, not unchecked
    if (r %in% names(.bh_rules_unverified)) {
      unverified <- c(unverified, paste0(r, ": ", .bh_rules_unverified[[r]]))
    } else if (!r %in% .bh_rules_checked) {
      unverified <- c(unverified, paste0(r, ": not in this package's checked set"))
    }
  }
  unverified
}

#' The rules this package checks, and the rules a run cannot check
#'
#' @return A list with `checked` (rule labels this package evaluates), `reported` (rule
#'   labels the specification asks a validator only to report) and `unverified` (a named
#'   character vector; each value is the reason that rule needs an operation this package
#'   does not implement).
#' @export
bh_rule_coverage <- function() {
  list(
    checked = .bh_rules_checked,
    reported = names(.bh_rules_warning_only),
    unverified = unlist(.bh_rules_unverified, use.names = TRUE)
  )
}
