#' Reading a file: parse, verify and validate
#'
#' [bh_read()] is the entry point. It frames the header block over the file's bytes,
#' finds and checks the checksum line, hashes the covered bytes with the vendored
#' SHA-512/256 core, parses the YAML under rules R8, R12 and R13, selects the contract the
#' record cites, and validates against it. [bh_checksum()], [bh_verify()] and
#' [bh_validate()] are the same pass with the answer narrowed to one question.
#'
#' @section What "valid" means here:
#' A file is valid when every rule that applies to it passes: the checksum matches the
#' bytes it covers, the header block and its grammar are well formed, the YAML parses
#' without R8, R12 or R13 violations, the record's own `checksum` is the line that was
#' verified, the header type is one the container may carry (FHR or FHP in FASTA, FHR in
#' GFA, FHGFF3 in GFF3), and the contract the record itself selects accepts it. Two things are reported and deliberately do not change validity, because the
#' released contracts accept them and rejecting them would invalidate records that are
#' valid today: a required value that is present but empty, and a `uri` value whose scheme
#' is not `http`, `https`, `ftp`, `urn:`, `doi:` or `info:` (rule R14). Both appear in
#' `$warnings`.
#'
#' @section Errors:
#' Reader input refusals are classed conditions (`bh_error` plus a subclass), so
#' `tryCatch(expr, bh_error = handler)` catches the family. An invalid *file* is not an
#' error: the returned object says so. An unusable *input* is - a missing file, a
#' serialization the name does not identify, a header block over the reader limit, a
#' gzip file that is corrupt, truncated or followed by bytes that are not gzip, a
#' contract this build does not hold. Ordinary R argument errors and native allocation
#' failures may retain their original condition classes.
#'
#' @name read
NULL

.bh_formats <- c(fasta = "fasta", `fhp-fasta` = "fhp-fasta", `fht-fasta` = "fht-fasta",
  gfa = "gfa", fhgff3 = "fhgff3")

#' Chooses the serialization from the file name.
#'
#' The shared suite names its containers - `x.fhp.fasta`, `x.fhr.fasta`, `x.fhgff3.gff3`,
#' `x.fhr.gfa`, and `.gz` for the compressed transport - and the prefix (`;~` versus `#~`)
#' plus the block boundary (`>` record marker versus `##gff-version 3`) follow from that.
#' There is no content sniff here, and [bh_capability()] records that as a gap: a file
#' whose name says nothing must pass `format`.
#' @noRd
.bh_guess_format <- function(path) {
  base <- tolower(basename(path))
  if (endsWith(base, ".gz")) base <- sub("\\.gz$", "", base)
  if (endsWith(base, ".fhp.fasta")) return("fhp-fasta")
  if (endsWith(base, ".fht.fasta")) return("fht-fasta")
  if (endsWith(base, ".fhr.fasta") || endsWith(base, ".fasta") ||
      endsWith(base, ".fa") || endsWith(base, ".fna") || endsWith(base, ".faa")) {
    return("fasta")
  }
  if (endsWith(base, ".gfa")) return("gfa")
  if (endsWith(base, ".gff3")) return("fhgff3")
  bh_abort("input", paste0(
    "cannot tell the serialization of ", basename(path),
    " from its name; pass format = one of ", paste(names(.bh_formats), collapse = ", ")
  ))
}

# The header types each serialization may carry (docs/FORMAT.md: "A header whose type ...
# does not match the file it is in makes the file invalid, even when its checksum
# matches"). FHT joins the FASTA forms only through the draft lane.
.bh_family_allowed <- {
  # Derived from the reader's own format vocabulary: every name in .bh_formats gets
  # exactly one entry, decided by the container that name denotes — never by vector
  # position, so a future format addition fails loudly (the FASTA/GFA/FHGFF3 cases
  # must be named here) instead of silently recycling a neighbour's allow-list.
  allowed_for <- function(fmt) {
    if (fmt %in% c("fasta", "fhp-fasta", "fht-fasta")) c("FHR", "FHP")
    else if (fmt == "gfa") "FHR"
    else if (fmt == "fhgff3") "FHGFF3"
    else "" # unmapped: caught by the non-emptiness guard below, never guessed
  }
  setNames(lapply(names(.bh_formats), allowed_for), names(.bh_formats))
}

#' The container rule: an FHGFF3 header in FASTA, an FHP header in GFA and the like.
#'
#' An unsupported citation is left to rule V4, which already says why the file cannot be
#' checked, as the Python reference does.
#' @noRd
.bh_family_issue <- function(selection, format) {
  if (!is.character(format) || length(format) != 1L || is.na(format) ||
      !format %in% names(.bh_formats)) {
    bh_abort("input", paste0("unknown serialization ", sQuote(as.character(format)[1L])))
  }
  if (is.null(selection) || identical(selection$status, "unsupported")) return(character())
  type <- selection$header_type
  allowed <- .bh_family_allowed[[format]]
  if (!length(allowed) || any(!nzchar(allowed))) {
    bh_abort("input", paste0("no allowed header types registered for serialization ", sQuote(format)))
  }
  if (format %in% c("fasta", "fhp-fasta", "fht-fasta") && identical(selection$status, "draft")) {
    allowed <- c(allowed, "FHT")
  }
  if (is.na(.bh_c(type, NA_character_)) || type %in% allowed) return(character())
  paste0(
    "container: the record's schema selects ", type, ", which a ", format,
    " file cannot carry; expected ", paste(allowed, collapse = " or "), " metadata"
  )
}

#' The checksum line the bytes were verified against must be the record's own checksum.
#'
#' Rules R2 and R5 find the one root-level line that starts with `checksum:` and hold it to
#' the bare value, but a line can look like that and still be part of something else - the
#' middle of a multi-line quoted scalar or of a flow mapping - while the record's real
#' `checksum` key sits elsewhere. The line read alone must give `{checksum: value}` (R5
#' guarantees that shape), and the parsed record's top-level checksum must be that value.
#' @noRd
.bh_checksum_binding_issue <- function(record, cs) {
  if (!isTRUE(cs$ok) || is.null(record)) return(character())
  own <- record[["checksum"]]
  if (is.character(own) && length(own) == 1L && identical(own, cs$value)) return(character())
  paste0(
    "R5: the checksum line is not the record's checksum: the line holds ", cs$value,
    " but the parsed record's checksum is ",
    if (is.character(own) && length(own) == 1L) own else "something else"
  )
}

#' Full read of one file.
#' @noRd
.bh_analyze <- function(path, format = NULL, compressed = NA,
                        draft = getOption("bh.draft_lane", FALSE), verify_checksum = TRUE,
                        validate_contract = TRUE) {
  .bh_input_path(path)
  format <- format %||% .bh_guess_format(path)
  if (!format %in% names(.bh_formats)) {
    bh_abort("input", paste0("unknown serialization ", sQuote(format)))
  }
  head <- .bh_head(path, compressed = compressed)
  frame <- .bh_frame(head$bytes, format, complete = head$complete)
  issues <- frame$why
  warnings_out <- character()
  selection <- NULL
  record <- NULL
  chk <- list(
    recorded = NA_character_, computed = NA_character_, valid = NA, bytes = NA_real_,
    late_header_lines = NA_integer_, exclusion = NULL
  )

  cs <- .bh_find_checksum(frame)
  issues <- c(issues, cs$why)
  if (cs$ok) {
    chk$recorded <- cs$value
    chk$exclusion <- .bh_excluded_range(frame, cs$index)
  }

  lines <- .bh_header_lines(frame)
  if (length(lines)) {
    parsed <- .bh_parse_record(lines)
    issues <- c(issues, parsed$why)
    record <- parsed$record
  }
  if (!is.null(record)) {
    warnings_out <- c(warnings_out, .bh_marker_warnings(lines, format))
    selection <- bh_select(record$schema, schema_version = record$schemaVersion, draft = draft)
    warnings_out <- c(warnings_out, selection$warnings)
    # Rule V7 requires the draft notice on *every* record read through the lane, so it is
    # signalled here and not merely collected: a caller who never looks at $warnings still
    # hears about it. Everything else is collected and surfaced by bh_read(strict = TRUE),
    # because those diagnostics describe the file rather than the reader's mode.
    if (identical(selection$status, "draft")) {
      for (w in selection$warnings) bh_warn("draft", "%s", w)
    }
    issues <- c(issues, .bh_family_issue(selection, format))
    issues <- c(issues, .bh_checksum_binding_issue(record, cs))
  }

  if (verify_checksum && cs$ok) {
    res <- bh_sha512_256_file(
      path, skip = chk$exclusion, compressed = head$compressed,
      scan = list(prefix = charToRaw(frame$prefix), after = frame$scan_after)
    )
    chk$computed <- res$digest
    chk$bytes <- res$bytes
    chk$late_header_lines <- res$late_header_lines
    chk$valid <- identical(res$digest, cs$value)
    if (!isTRUE(chk$valid)) {
      issues <- c(issues, paste0(
        "R4: the recorded checksum ", cs$value, " does not match the computed ",
        res$digest
      ))
    }
    if (isTRUE(res$late_header_lines > 0L)) {
      issues <- c(issues, "R10: a header line appears after the leading block")
    }
  }

  validation <- NULL
  if (validate_contract && !is.null(selection)) {
    validation <- .bh_validate_record(record, selection)
    if (!isTRUE(validation$valid)) {
      issues <- c(issues, paste0(
        "rule ", selection$rule, " selected ", selection$header_type, " ",
        selection$schema_version, " and the record failed it: ",
        paste(validation$errors, collapse = "; ")
      ))
    }
    if (!is.null(validation$contract)) {
      warnings_out <- c(warnings_out,
        .bh_empty_required_warnings(record, validation$contract),
        .bh_link_warnings(record, validation$contract)
      )
    }
  }

  list(
    path = path, format = format, compressed = head$compressed, record = record,
    selection = selection, checksum = chk, validation = validation,
    issues = unique(issues), warnings = unique(warnings_out), valid = !length(unique(issues))
  )
}

#' Reads a file's header, checksum and contract verdict
#'
#' @param path A FASTA, GFA or GFF3 file carrying a FAIR-bioHeaders header.
#' @param format The serialization. Inferred from the file name by default; pass it when
#'   the name does not say.
#' @param compressed `TRUE`, `FALSE` or `NA` to detect a gzip member.
#' @param draft Draft lane: `FALSE` (default), `TRUE`, or draft type names such as
#'   `"FHT"`. With the lane closed, a draft citation is selected under V5 exactly as
#'   before the lane existed.
#' @param verify_checksum,validate_contract Do the byte verification and the contract
#'   validation. Turning either off narrows the answer, and the result records that.
#' @param ... Passed to the same reader by [bh_checksum()] and [bh_validate()].
#' @return An object of class `bh_read`: a list with `record`, `format`, `header_type`,
#'   `selection`, `checksum`, `validation`, `issues`, `warnings`, `valid`, `path`.
#' @examples
#' # A file whose header citation selects the released FHR 2.1 contract:
#' f <- tempfile(fileext = ".fasta")
#' writeLines(c(";~schema: https://w3id.org/fair-bioheaders/fhr/v0.6.0",
#'              ';~schemaVersion: "2.1"', ">seq1", "ACGT"), f)
#' x <- bh_read(f)
#' x$selection          # which selection rule chose which contract
#' x$valid              # FALSE here: the header carries no checksum line - a
#' x$issues             # reader reports that loudly; never hand-edit a checksum,
#' x$checksum$computed  # recombine with `bioheaders combine` instead.
#' # bh_validate shares the result shape for the contract layer alone.
#' @export
bh_read <- function(path, format = NULL, compressed = NA,
                    draft = getOption("bh.draft_lane", FALSE), verify_checksum = TRUE,
                    validate_contract = TRUE, ...) {
  if (...length()) bh_abort("input", "unused arguments in bh_read(...)")
  a <- .bh_analyze(path,
    format = format, compressed = compressed, draft = draft,
    verify_checksum = verify_checksum, validate_contract = validate_contract
  )
  structure(
    list(
      record = a$record, format = a$format, header_type = a$selection$header_type,
      selection = a$selection, checksum = a$checksum, validation = a$validation,
      issues = a$issues, warnings = a$warnings, valid = a$valid, path = a$path,
      compressed = a$compressed, checksum_verified = verify_checksum,
      contract_checked = validate_contract
    ),
    class = "bh_read"
  )
}

#' @export
print.bh_read <- function(x, ...) {
  cat("<bh_read> ", basename(x$path), " [", x$format, "]\n", sep = "")
  if (!is.null(x$selection)) {
    cat(
      "  contract: ", x$selection$header_type %||% "?", " ",
      x$selection$schema_version %||% "?", " (rule ", x$selection$rule, ", ",
      x$selection$status,
      if (!is.na(.bh_c(x$selection$release, NA_character_))) paste0(", ", x$selection$release) else "",
      ")\n",
      sep = ""
    )
  }
  if (!is.na(x$checksum$recorded)) {
    cat(
      "  checksum: ",
      if (is.na(x$checksum$valid)) "not checked" else if (x$checksum$valid) "matches" else "DOES NOT MATCH",
      " (", format(x$checksum$bytes, scientific = FALSE), " bytes hashed)\n", sep = ""
    )
  }
  cat("  valid: ", x$valid, "\n", sep = "")
  if (length(x$issues)) {
    cat("  issues:\n")
    for (i in x$issues) cat("    - ", i, "\n", sep = "")
  }
  if (length(x$warnings)) {
    cat("  warnings:\n")
    for (w in x$warnings) cat("    - ", w, "\n", sep = "")
  }
  invisible(x)
}

#' Verifies a file's checksum, and nothing else
#'
#' @param path A file carrying a FAIR-bioHeaders header.
#' @param ... Passed to [bh_read()]'s reader.
#' @return `bh_checksum()` returns a list with `recorded`, `computed`, `valid`, `bytes`
#'   (hashed), `late_header_lines` and `why`; `bh_verify()` returns the single logical.
#' @examples
#' f <- tempfile(fileext = ".fasta")
#' writeLines(c(";~schema: https://w3id.org/fair-bioheaders/fhr/v0.6.0", ">seq1", "ACGT"), f)
#' cs <- bh_checksum(f)         # the byte layer: what the file must state vs what it is
#' names(cs)                    # recorded, computed, valid, bytes, late_header_lines, why
#' bh_verify(f)                 # one logical: does the stated checksum match?
#' @export
bh_checksum <- function(path, ...) {
  a <- .bh_analyze(path, validate_contract = FALSE, ...)
  chk <- a$checksum
  list(
    recorded = chk$recorded, computed = chk$computed,
    valid = if (is.na(chk$computed)) NA else isTRUE(chk$valid),
    bytes = chk$bytes, late_header_lines = chk$late_header_lines, why = a$issues
  )
}

#' @rdname bh_checksum
#' @export
bh_verify <- function(path, ...) isTRUE(bh_checksum(path, ...)$valid)

#' Validates a file against the contract its own `schema` value selects
#'
#' @rdname bh_read
#' @export
bh_validate <- function(path, format = NULL, compressed = NA,
                        draft = getOption("bh.draft_lane", FALSE), ...) {
  a <- .bh_analyze(path,
    format = format, compressed = compressed, draft = draft,
    validate_contract = TRUE, ...
  )
  list(
    valid = isTRUE(a$validation$valid) && !length(a$issues),
    contract = a$selection, errors = a$validation$errors %||% character(),
    issues = a$issues, warnings = a$warnings
  )
}

#' Extracts a file's header, as YAML text or as the parsed record in JSON
#'
#' `as = "yaml"` returns the header block's YAML exactly as written, with the `;~` or `#~`
#' prefix removed from every line. `as = "json"` returns the parsed record as the JSON the
#' contract validator sees; it needs a header that parses, so a header the YAML rules
#' reject (R8, R12, R13, a parse error) raises a `bh_input` error naming why. Neither form
#' verifies the checksum or validates the contract: use [bh_read()] for that.
#'
#' @param path A FASTA, GFA or GFF3 file carrying a FAIR-bioHeaders header.
#' @param as `"yaml"` (default) or `"json"`.
#' @param format,compressed As for [bh_read()].
#' @return A length-1 character string.
#' @examples
#' f <- tempfile(fileext = ".fasta")
#' writeLines(c(";~schema: https://w3id.org/fair-bioheaders/fhr/v0.6.0",
#'              ';~taxon: "Example organism"', ">seq1", "ACGT"), f)
#' bh_extract_header(f)              # prefixes removed, YAML text
#' bh_extract_header(f, as = "json") # the parsed record as a JSON string
#' @export
bh_extract_header <- function(path, as = c("yaml", "json"), format = NULL, compressed = NA) {
  as <- match.arg(as)
  format <- format %||% .bh_guess_format(path)
  if (!format %in% names(.bh_formats)) {
    bh_abort("input", paste0("unknown serialization ", sQuote(format)))
  }
  head <- .bh_head(path, compressed = compressed)
  frame <- .bh_frame(head$bytes, format, complete = head$complete)
  lines <- .bh_header_lines(frame)
  if (!length(lines)) bh_abort("input", "%s", paste0(basename(path), " carries no header block"))
  if (as == "yaml") return(paste0(paste(lines, collapse = "\n"), "\n"))
  parsed <- .bh_parse_record(lines)
  # `record` can be present while `ok` is FALSE: R12 and R13 are found after parsing, and
  # a record bh_read() rejects is never exported as if the file had said it.
  if (!isTRUE(parsed$ok)) {
    bh_abort("input", "%s", paste0(
      "the header of ", basename(path), " does not parse to a record: ",
      paste(parsed$why, collapse = "; ")
    ))
  }
  as.character(.bh_record_json(parsed$record))
}
