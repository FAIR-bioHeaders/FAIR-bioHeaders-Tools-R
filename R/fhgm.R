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
#' * K1 additionally binds the transport to a **registered** FHGFF3 release: a citation no
#'   registered release answers to (raw main, superseded or unregistered tags, an
#'   unrecognised citation-version pair) is refused at the model layer, while v0.5.0 with
#'   1.1 and v0.6.0 with 1.1 or 1.2 - w3id URL or raw tag URL, under either repository
#'   name - are accepted (maintainer dual-base decision 2026-11-15);
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

# K1's carrier-identity clause: a file that transports FHGM records "keeps a released
# FHGFF3 identity", and the checker "refuses a citation no registered release answers to
# (raw main, superseded releases)". A registered citation is the w3id release URL or the
# raw TAG URL for fhgff3.json, under either repository name (the current
# FAIR-bioHeaders-Specification or its historical FHR-Specification alias), and the
# citation-version pairs the manifest's K1 text recognises are v0.5.0 with schemaVersion
# 1.1, and v0.6.0 with 1.1 or 1.2 (maintainer dual-base decision 2026-11-15). The pinned
# suite first exercises this clause at vector `carrier-cites-raw-main`; the evaluation
# stays inside the draft lane - it reads the carrier's own header and decides only the
# model-layer question of whether that header may transport records at all.
.bh_fhgm_carrier_issue <- function(header) {
  url <- .bh_c(header$schema, NA_character_)
  sv <- as.character(.bh_c(header$schemaVersion, ""))
  if (is.na(url) || !nzchar(url)) {
    return(paste0(
      "K1: the carrier header names no schema citation, so no registered FHGFF3 ",
      "release answers to it"
    ))
  }
  w3id <- paste0("^https://w3id\\.org/fair-bioheaders/fhgff3/",
    "(v[0-9]+\\.[0-9]+\\.[0-9]+)$")
  tagpat <- paste0(
    "^https://raw\\.githubusercontent\\.com/FAIR-bioHeaders/",
    "(FAIR-bioHeaders-Specification|FHR-Specification)/",
    "(v[0-9]+\\.[0-9]+\\.[0-9]+)/fhgff3\\.json$"
  )
  tag <- sub(w3id, "\\1", url)
  tag <- sub(tagpat, "\\2", tag)
  if (identical(tag, url)) {
    return(paste0(
      "K1: the carrier cites ", url, ", which no registered FHGFF3 release answers ",
      "to (raw main, superseded releases and unregistered tags are refused; a ",
      "registered citation is the w3id release URL or the raw tag URL for ",
      "fhgff3.json, under either repository name)"
    ))
  }
  pair_ok <- (identical(tag, "v0.5.0") && identical(sv, "1.1")) ||
    (identical(tag, "v0.6.0") && sv %in% c("1.1", "1.2"))
  if (!pair_ok) {
    return(paste0(
      "K1: the carrier pairs ", tag, " with schemaVersion ", sv, ", and no ",
      "registered release answers that citation-version pair (recognised: v0.5.0 ",
      "with 1.1; v0.6.0 with 1.1 or 1.2 - maintainer dual-base decision 2026-11-15; ",
      "a file stating FHGFF3 1.0 cannot carry the extension at all)"
    ))
  }
  character()
}

# A flow array holding exactly one scalar - `"deposit":["doi:10.22002/x"]` - is the shape
# R's yaml hands back as an atomic vector, after which it is indistinguishable from a
# scalar. `.bh_record_json` then writes a scalar and the pinned record contract rejects a
# record whose bytes say array (measured on the suite's own s6k fixture). The released
# header path repairs this shape from the text, where it is still recorded
# (R/yaml-shape.R), and the FHGM records get the same treatment here, with two
# differences: the scan is confined to the x-fhgm-models value, and it reads the
# JSON-in-YAML flow style the draft records are written in, which the line scanner for
# top-level YAML keys does not look inside. Nothing is coerced from the contract: a key
# is re-wrapped only because the bytes of this file wrote it as an array.
.bh_fhgm_flow_scalar_keys <- function(txt) {
  # \K resets where the match starts, so the match IS the key name; the lookahead keeps
  # the shape test (a flow array with one comma-free, bracket-free item) out of the result
  pats <- c(
    '"\\K[^"]+(?="\\s*:\\s*\\[[^\\]\\[{,}]*\\])', # "deposit":["doi:..."]
    '(^|[{,[:space:]])\\K[A-Za-z0-9_-]+(?=\\s*:\\s*\\[[^\\]\\[{,}]*\\])' # deposit: [doi:...]
  )
  hits <- unlist(lapply(pats, function(p) regmatches(txt, gregexpr(p, txt, perl = TRUE))))
  hits <- unlist(hits)
  if (!length(hits)) return(character())
  unique(hits[nzchar(hits)])
}

# The lines that carry the x-fhgm-models value: its own line plus every following line
# indented deeper than the key, which is how a block-style extension value continues.
.bh_fhgm_value_lines <- function(lines) {
  if (!length(lines)) return(character())
  at <- grep(paste0("^", .bh_fhgm_key, "[ \t]*:"), lines)
  if (!length(at)) return(character())
  i <- at[[1L]]
  ind <- nchar(sub("[^ ].*$", "", lines[[i]]))
  out <- lines[[i]]
  if (i < length(lines)) {
    for (j in (i + 1L):length(lines)) {
      l <- lines[[j]]
      if (!nzchar(trimws(l))) next
      if (nchar(sub("[^ ].*$", "", l)) <= ind) break
      out <- c(out, l)
    }
  }
  out
}

# The key names to re-wrap, taken from the transport value's own text. The transport key
# itself is excluded: `.bh_fhgm_records()` already resolves whether the value holds one
# record or several.
.bh_fhgm_shape_keys <- function(lines) {
  vlines <- .bh_fhgm_value_lines(lines)
  if (!length(vlines)) return(character())
  setdiff(unique(c(
    .bh_fhgm_flow_scalar_keys(paste(vlines, collapse = "\n")),
    .bh_sequence_keys(vlines)
  )), .bh_fhgm_key)
}

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
  # the header text again, to recover the sequence shapes the YAML parse flattened; the
  # framing rules are the released path's own, so no second implementation is introduced,
  # and the repair is applied to the transported records only - never to the header the
  # released verdict was computed on
  lines <- character()
  h <- .bh_capture(.bh_head(path, compressed = compressed))
  if (is.null(h$error)) {
    fr <- .bh_capture(.bh_frame(h$value$bytes, format, complete = h$value$complete))
    if (is.null(fr$error)) lines <- .bh_header_lines(fr$value)
  }
  recs <- .bh_fhgm_records(a$value$record)
  keys <- .bh_fhgm_shape_keys(lines)
  if (length(keys)) {
    recs <- lapply(recs, function(r) .bh_repair_shape(r, keys))
  }
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
  # K1 carrier identity, beside the 1.0 clause: the header must cite a registered FHGFF3
  # release the transport can bind to. First exercised by the re-pinned suite vector
  # `carrier-cites-raw-main`; recorded as a model-layer rejection, never rewritten into
  # the base FHGFF3 verdict (the base layer judges this citation under V1 on its own).
  carrier <- .bh_fhgm_carrier_issue(models$header)
  if (length(carrier)) {
    transport_ok <- FALSE
    transport_note <- c(transport_note, carrier)
  }
  validator <- .bh_validator(sel$file)
  if (!length(models$records)) {
    # K1: the transport key must hold one or more records. An empty array is a violation of
    # the transport rule, not a vacuous pass over zero records.
    return(list(
      records = .bh_empty_model_rows(), all_valid = FALSE, n_records = 0L,
      warnings = c(warn, transport_note, paste0(
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
