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
#' without R8, R12 or R13 violations, and the contract the record itself selects accepts
#' it. Two things are reported and deliberately do not change validity, because the
#' released contracts accept them and rejecting them would invalidate records that are
#' valid today: a required value that is present but empty, and a `uri` value whose scheme
#' is not `http`, `https`, `ftp`, `urn:`, `doi:` or `info:` (rule R14). Both appear in
#' `$warnings`.
#'
#' @section Errors:
#' Everything this package raises is a classed condition (`bh_error` plus a subclass), so
#' `tryCatch(expr, bh_error = handler)` catches the family. An invalid *file* is not an
#' error: the returned object says so. An unusable *input* is - a missing file, a
#' serialization the name does not identify, a header block over the reader limit, a
#' contract this build does not hold.
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
#' There is no content sniff here, and docs/STATUS.md records that as a gap: a file
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

#' Full read of one file.
#' @noRd
.bh_analyze <- function(path, format = NULL, compressed = NA,
                        verify_checksum = TRUE, validate_contract = TRUE) {
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
    selection <- bh_select(record$schema, schema_version = record$schemaVersion)
    warnings_out <- c(warnings_out, selection$warnings)
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
#' @param verify_checksum,validate_contract Do the byte verification and the contract
#'   validation. Turning either off narrows the answer, and the result records that.
#' @param ... Passed to the same reader by [bh_checksum()] and [bh_validate()].
#' @return An object of class `bh_read`: a list with `record`, `format`, `header_type`,
#'   `selection`, `checksum`, `validation`, `issues`, `warnings`, `valid`, `path`.
#' @examples
#' f <- system.file("VENDORED.json", package = "FAIRbioHeadersTools")
#' file.exists(f)
#' @export
bh_read <- function(path, format = NULL, compressed = NA,
                    verify_checksum = TRUE, validate_contract = TRUE, ...) {
  a <- .bh_analyze(path,
    format = format, compressed = compressed,
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
bh_validate <- function(path, format = NULL, compressed = NA, ...) {
  a <- .bh_analyze(path,
    format = format, compressed = compressed,
    validate_contract = TRUE, ...
  )
  list(
    valid = isTRUE(a$validation$valid) && !length(a$issues),
    contract = a$selection, errors = a$validation$errors %||% character(),
    issues = a$issues, warnings = a$warnings
  )
}
