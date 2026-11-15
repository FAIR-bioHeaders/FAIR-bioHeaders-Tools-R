#' FHGM model records: the draft lane for a type that is not a header type
#'
#' FHGM is described by its owning repository (FAIR-bioHeaders/FHGM-Specification) and by
#' the bytes vendored here at `tests/draft/fhgm/README.md`: its records are **not** a header
#' type. They are model records transported inside an FHGFF3 header under an `x-`-prefixed
#' key (`x-fhgm-models` in the reviewed drafts), so a file carrying them stays a schema-valid
#' FHGFF3 header, keeps its FHGFF3 `schema` URL and `schemaVersion`, and its checksum covers
#' the model bytes like any other header byte (R3). Consequences this module implements:
#'
#' * the record carries no `schema` field, so nothing selects a contract for it - rule V7
#'   chooses only *what validates the records*, never what they are;
#' * the file is routed by its own FHGFF3 citation under V1-V3, with or without the lane;
#' * the enclosing header must actually allow extension fields, i.e. FHGFF3 1.1 or later
#'   (R15): a 1.0 header cannot transport FHGM records;
#' * the model verdict is reported separately from the base header verdict, and a model
#'   failure does not rewrite the FHGFF3 result - the upstream suite records its four
#'   layers apart for exactly that reason (see the `layers` block of each vector);
#' * the contract is a pinned draft: warning on every use, no release form, no
#'   `schemaVersion`, no registry row, no w3id URL. [bh_draft_pins()] prints the pin.
#'
#' What this module evaluates is the transport rule (K1) and the record contract (K2).
#' The upstream checker's cross-record rules - K3 modelId uniqueness within a snapshot,
#' K4 feature-target resolution, K5 reference comparability, K6 predecessor-pointer
#' resolution - are **not** implemented here; [bh_draft_fhgm_vectors()] reports the vectors
#' that turn on them as `not-run`, and [bh_capability()] names them as gaps.
#'
#' @name fhgm
NULL

.bh_fhgm_key <- "x-fhgm-models"

# Extracts the transported model records from a parsed header. The single-item case is the
# one to watch: R's yaml hands back the flow sequence as a list, and a one-record file must
# still read as one record rather than as its fields.
.bh_fhgm_records <- function(record) {
  raw <- record[[.bh_fhgm_key]]
  if (is.null(raw)) return(list())
  if (!is.list(raw)) return(list(raw))
  # R's yaml returns an unnamed list of items; a single item may have collapsed to a map
  if (!is.null(names(raw))) return(list(raw))
  raw
}

#' Reads the FHGM model records out of an FHGFF3 file
#'
#' @param path An FHGFF3 file.
#' @param format,compressed,draft Passed to the reader; the lane must be open for the
#'   records to be validated, and `draft = "FHGM"` is what opens it.
#' @return A list with `records` (the transported records, as parsed), `count`, and
#'   `present` (whether the header carries the key at all).
#' @export
bh_fhgm_models <- function(path, format = "fhgff3", compressed = NA,
                           draft = getOption("bh.draft_lane", FALSE)) {
  a <- .bh_capture(.bh_analyze(path, format = format, compressed = compressed,
    draft = draft, validate_contract = FALSE
  ))
  if (!is.null(a$error)) bh_abort("input", "the file could not be read: %s", a$error)
  recs <- .bh_fhgm_records(a$value$record)
  list(
    present = !is.null(a$value$record[[.bh_fhgm_key]]), records = recs,
    count = length(recs), header = a$value$record, header_issues = a$value$issues
  )
}

#' Validates the FHGM model records of an FHGFF3 file against the pinned draft contract
#'
#' The base file is validated separately by [bh_validate()]; this reports the model layer
#' only, per record, so a result can never be read as "the file is a valid FHGM file" -
#' FHGM has no released contract and no such verdict exists.
#'
#' @param path An FHGFF3 file whose header transports model records.
#' @param format,compressed Passed to the reader.
#' @return A list with `records` (one row per record: `index`, `valid`, `errors`,
#'   `modelId`), `all_valid`, `n_records`, `warnings` (which include the rule V7 draft
#'   notice) and `contract` (the pinned commit and digest the records were read against).
#' @export
bh_validate_fhgm <- function(path, format = "fhgff3", compressed = NA) {
  models <- bh_fhgm_models(path, format = format, compressed = compressed,
    draft = "FHGM"
  )
  sel <- .bh_draft_selection("FHGM", .bh_draft_citation("FHGM"))
  warn <- sel$warnings
  for (w in warn) bh_warn("draft", "%s", w)
  if (!models$present) {
    return(list(
      records = data.frame(index = integer(), valid = logical(), errors = character(),
        modelId = character(), stringsAsFactors = FALSE),
      all_valid = TRUE, n_records = 0L, warnings = warn,
      contract = sel$pin[c("commit", "sha256")], present = FALSE
    ))
  }
  # R15 precondition: an FHGFF3 1.0 header has no extension fields at all, so it cannot
  # transport model records; that is a base-layer fact and is reported as one.
  transport_ok <- TRUE
  transport_note <- character()
  sv <- as.character(.bh_c(models$header$schemaVersion, ""))
  if (identical(sv, "1.0")) {
    transport_ok <- FALSE
    transport_note <- paste0(
      "R15: the enclosing header states FHGFF3 1.0, which has no extension fields, so ",
      "an x-fhgm-models key there is an unknown key rather than a transported record"
    )
  }
  validator <- .bh_validator(sel$file)
  if (!length(models$records)) {
    # K1: the transport key must hold one or more records. An empty array is a violation of
    # the transport rule, not a vacuous pass over zero records.
    return(list(
      records = .bh_empty_model_rows(), all_valid = FALSE, n_records = 0L,
      warnings = c(warn, paste0(
        "K1: the header carries ", .bh_fhgm_key, " with no records; transport requires one ",
        "or more"
      )),
      contract = sel$pin[c("commit", "sha256")], present = TRUE, transport_ok = transport_ok
    ))
  }
  rows <- lapply(seq_along(models$records), function(i) {
    json <- .bh_record_json(models$records[[i]])
    res <- tryCatch(suppressWarnings(validator(json)), error = function(e) {
      bh_abort("schema", "the FHGM draft validator could not run on record %d: %s",
        i, conditionMessage(e)
      )
    })
    errs <- character()
    if (!isTRUE(res)) {
      e <- attr(res, "errors")
      errs <- if (is.data.frame(e) && nrow(e)) {
        paste0(.bh_c(e$instancePath, ""), " ", .bh_c(e$keyword, ""), ": ",
          .bh_c(e$message, ""), collapse = "; "
        )
      } else {
        "the pinned draft contract rejected the record"
      }
    }
    if (!transport_ok) {
      errs <- paste(c(transport_note, errs), collapse = " | ")
      res <- FALSE
    }
    data.frame(
      index = i, valid = isTRUE(res), errors = paste(errs, collapse = "; "),
      modelId = .bh_c(models$records[[i]]$modelId, NA_character_),
      stringsAsFactors = FALSE
    )
  })
  tab <- do.call(rbind, rows)
  list(
    records = tab, all_valid = all(tab$valid), n_records = nrow(tab),
    warnings = warn, contract = sel$pin[c("commit", "sha256")], present = TRUE,
    transport_ok = transport_ok
  )
}

# Zero rows of the model verdict table, with the column types the non-empty case produces, so
# an empty transport array and a missing key stay distinguishable in the result.
.bh_empty_model_rows <- function() {
  data.frame(
    index = integer(), valid = logical(), errors = character(),
    modelId = character(), stringsAsFactors = FALSE
  )
}
