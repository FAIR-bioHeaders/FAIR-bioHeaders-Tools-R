#' The capability matrix: type x operation x serialization x contract version
#'
#' This is the published answer to "what does the R library support", and it is written
#' to be read as a table, not as prose. Every cell is one of:
#'
#' * `native` - implemented here, covered by the tests and by the shared-vector run.
#' * `draft-lane` - implemented against pinned unreleased bytes, reachable only with the
#'   rule V7 lane open, warned on every read, and never a released-support claim.
#' * `not-supported-yet` - a gap, with the reason in the `blocker` column and, where one
#'   exists, the issue that tracks it. A cell is never left blank and never implied by a
#'   neighbouring cell.
#' * `not-applicable` - the combination does not exist in the specification, e.g. a
#'   serialization FHGM does not have.
#'
#' @name capability
NULL

#' The capability matrix
#'
#' @param header_type Optional filter, e.g. `c("FHR", "FHT")`.
#' @param operation Optional filter, e.g. `"validate_contract"`.
#' @return A data frame with `header_type`, `type_status`, `operation`, `serialization`,
#'   `contract_versions`, `support`, `blocker` and `tracker`.
#' @export
bh_capability <- function(header_type = NULL, operation = NULL) {
  rows <- .bh_cached("capability", .bh_rows())
  if (!is.null(header_type)) {
    rows <- rows[rows$header_type %in% toupper(header_type), , drop = FALSE]
  }
  if (!is.null(operation)) {
    rows <- rows[rows$operation %in% operation, , drop = FALSE]
  }
  rows
}

.bh_op_released <- function(type, versions, serializations = "native file") {
  lapply(serializations, function(s) data.frame(
    header_type = type, type_status = "released",
    operation = NA_character_, serialization = s, contract_versions = versions,
    support = NA_character_, blocker = NA_character_, tracker = NA_character_,
    stringsAsFactors = FALSE
  ))
}

# One row per (type, operation, serialization). Written out rather than generated so that
# every blocker sentence is specific to its cell.
.bh_rows <- function() {
  R <- function(type, status, op, ser, versions, support, blocker = NA_character_,
                tracker = NA_character_) {
    data.frame(
      header_type = type, type_status = status, operation = op, serialization = ser,
      contract_versions = versions, support = support, blocker = blocker,
      tracker = tracker, stringsAsFactors = FALSE
    )
  }
  rel <- c("FHR 2.1", "FHR 2.0", "FHR 1", "FHP 1.2", "FHP 1.1", "FHP 1.0",
           "FHGFF3 1.2", "FHGFF3 1.1", "FHGFF3 1.0")
  fhr <- "FHR 1, 2.0, 2.1"
  fhp <- "FHP 1.0, 1.1, 1.2"
  fhg <- "FHGFF3 1.0, 1.1, 1.2"
  none_yet <- "no released contract (rule V7)"

  out <- list(
    # --- released types, native file forms ---
    R("FHR", "released", "read_header", "fasta,gfa", fhr, "native"),
    R("FHR", "released", "verify_checksum", "fasta,gfa", fhr, "native"),
    R("FHR", "released", "validate_contract", "fasta,gfa", fhr, "native"),
    R("FHR", "released", "select_schema_V1_V6", "fasta,gfa", fhr, "native"),
    R("FHR", "released", "extract_header_yaml", "fasta,gfa", fhr, "native"),
    R("FHR", "released", "extract_header_json", "fasta,gfa", fhr, "native"),
    R("FHP", "released", "read_header", "fhp-fasta", fhp, "native"),
    R("FHP", "released", "verify_checksum", "fhp-fasta", fhp, "native"),
    R("FHP", "released", "validate_contract", "fhp-fasta", fhp, "native"),
    R("FHP", "released", "select_schema_V1_V6", "fhp-fasta", fhp, "native"),
    R("FHP", "released", "extract_header_yaml", "fhp-fasta", fhp, "native"),
    R("FHP", "released", "extract_header_json", "fhp-fasta", fhp, "native"),
    R("FHGFF3", "released", "read_header", "fhgff3", fhg, "native"),
    R("FHGFF3", "released", "verify_checksum", "fhgff3", fhg, "native"),
    R("FHGFF3", "released", "validate_contract", "fhgff3", fhg, "native"),
    R("FHGFF3", "released", "select_schema_V1_V6", "fhgff3", fhg, "native"),
    R("FHGFF3", "released", "extract_header_yaml", "fhgff3", fhg, "native"),
    R("FHGFF3", "released", "extract_header_json", "fhgff3", fhg, "native"),

    # --- other serializations of the released types ---
    R("FHR", "released", "read_header", "jsonld", fhr, "not-supported-yet",
      "no JSON-LD reader: frame expansion, context handling and rules J1-J9 are unbuilt; 37 shared jsonld vectors stay not-run",
      "FAIR-bioHeaders-Tools-R#3"),
    R("FHR", "released", "read_header", "microdata", fhr, "not-supported-yet",
      "no HTML/microdata reader: implied end tags, itemref/itemid scoping and rules M1-M5 are unbuilt; 26 shared microdata vectors stay not-run",
      "FAIR-bioHeaders-Tools-R#3"),
    R("FHR", "released", "read_header", "yaml", "FHR 1, 2.0, 2.1", "not-supported-yet",
      "standalone metadata files are not read: no checksum applies, so this is metadata validation only and it is not implemented yet",
      "FAIR-bioHeaders-Tools-R#3"),
    R("FHP", "released", "read_header", "jsonld,microdata", fhp, "not-supported-yet",
      "as for FHR: the JSON-LD and microdata readers are unbuilt",
      "FAIR-bioHeaders-Tools-R#3"),
    R("FHGFF3", "released", "read_header", "jsonld,microdata", fhg, "not-supported-yet",
      "as for FHR: the JSON-LD and microdata readers are unbuilt",
      "FAIR-bioHeaders-Tools-R#3"),

    # --- writer side: absent, and said ---
    R("FHR", "released", "combine_header", "fasta,gfa", fhr, "not-supported-yet",
      "no writer: emitting a header means computing a new checksum and choosing canonical YAML quoting, which needs its own tests and its own shared vectors",
      "FAIR-bioHeaders-Tools-R#3"),
    R("FHR", "released", "strip_header", "fasta,gfa", fhr, "not-supported-yet",
      "no writer: strip preserves every other byte, which is a write path, not a read path",
      "FAIR-bioHeaders-Tools-R#3"),
    R("FHR", "released", "convert_serialization", "fasta,gfa to jsonld,microdata,yaml", fhr,
      "not-supported-yet", "no writer, and the target readers are unbuilt too",
      "FAIR-bioHeaders-Tools-R#3"),
    R("FHR", "released", "verify_parent_links", "fasta,gfa against caller-supplied parent files",
      fhr, "native",
      "no automatic resolution: bh_verify_links() recomputes each cited checksum over the parent path the caller supplies, and an entry with no path is reported unchecked rather than passed",
      NA_character_),
    R("FHP", "released", "verify_parent_links", "fhp-fasta against caller-supplied parent files",
      fhp, "native", "as for FHR: bh_verify_links(), no automatic file resolution", NA_character_),
    R("FHGFF3", "released",
      "verify_parent_links", "fhgff3 against caller-supplied parent files", fhg, "native",
      "as for FHR; the annotates and genomeReference forms are both read out of derivedFrom",
      NA_character_),
    R("FHP", "released", "combine_header,strip_header,convert_serialization", "fhp-fasta", fhp,
      "not-supported-yet", "no write path", "FAIR-bioHeaders-Tools-R#3"),
    R("FHGFF3", "released", "combine_header,strip_header,convert_serialization", "fhgff3", fhg,
      "not-supported-yet", "no write path", "FAIR-bioHeaders-Tools-R#3"),
    R("FHGFF3", "released", "validate_gff3_features", "fhgff3", fhg, "not-applicable",
      "feature and biology checking belongs to gff3-validator, not to this package; a valid header says nothing about the features around it",
      NA_character_),

    # --- draft types, lane only ---
    R("FHT", "draft", "read_header", "fasta (draft)", none_yet, "draft-lane",
      "no released contract: scheduled as specification v0.7.0; readable only with the V7 lane open, against bytes pinned by commit and SHA-256, warning on every read",
      "FHT-Specification#8,FHT-Specification#9,FHT-Specification#10"),
    R("FHT", "draft", "validate_contract", "fasta (draft)", none_yet, "draft-lane",
      "as above; a draft result is not a released-contract result and takes no release form",
      "FHT-Specification#9"),
    R("FHT", "draft", "verify_checksum", "fasta (draft)", none_yet, "draft-lane",
      "the checksum rule is the shared one and runs natively; what is unresolved is selfChecksum/parentLink, which finalize at FHT release",
      "FHT-Specification#10"),
    R("FHT", "draft", "select_schema_V1_V6", "fasta (draft)", none_yet, "not-applicable",
      "V1-V6 cover released types only; V7 is the lane, and a release-shaped FHT URL stays V5 with the lane open or closed",
      NA_character_),
    R("FHT", "draft", "verify_parent_links", "fasta (draft)", none_yet, "draft-lane",
      "the C3 semantics the FHT development suite states are what bh_verify_links() implements; the evidence for it is the draft suite, not the released vectors",
      "FHT-Specification#8"),
    R("FHT", "draft", "combine_header,strip_header,convert_serialization", "fasta (draft)",
      none_yet, "not-supported-yet", "no write path at all, released or draft",
      "FAIR-bioHeaders-Tools-R#3"),
    R("FHGM", "draft", "read_model_records", "nested in fhgff3 via x-fhgm-models", none_yet,
      "not-supported-yet",
      paste0(
        "the upstream acceptance material (FHGM-Specification development/conformance, ",
        "31 vectors, K1-K6) is checker-based: per that suite's own manifest and README, ",
        "18 of its 19 invalid vectors pass the released FHGFF3 base schema and the ",
        "exact-byte checksum, so schema-vector conformance cannot express FHGM ",
        "acceptance. This package preserves an x-fhgm-models value in the parsed header ",
        "as uninterpreted data (rule R15; tested), which is transport, not reading ",
        "model records. The gate for this cell is a port of the K1-K6 model checker; ",
        "the candidate bytes are registered and digest-pinned (bh_draft_pins)"
      ),
      "FHGM-Specification#8,FHGM-Specification#9,FAIR-bioHeaders-Specification#204"),
    R("FHGM", "draft", "validate_model_records", "nested in fhgff3 via x-fhgm-models", none_yet,
      "not-supported-yet",
      paste0(
        "same gate as read_model_records: the K1-K6 model checker port. Evaluating ",
        "the 31 vectors against the pinned record contract would cover only K2 of the ",
        "six rules and none of the 18 checker-only rejections, which would inflate ",
        "the claim rather than earn it"
      ),
      "FHGM-Specification#9"),
    R("FHGM", "draft", "verify_checksum", "none", none_yet, "not-applicable",
      "FHGM is not a file type: its records are covered by the checksum of the FHGFF3 file that transports them",
      NA_character_),
    R("FHGM", "draft", "read_header", "fasta,gfa,fhgff3,jsonld,microdata", none_yet,
      "not-applicable", "FHGM has no serialization of its own", NA_character_)
  )
  do.call(rbind, out)
}
