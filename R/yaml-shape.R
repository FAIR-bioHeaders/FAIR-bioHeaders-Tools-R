#' YAML shape repair: reading the sequence structure back off the text
#'
#' R's `yaml` package returns an atomic vector for a one-item sequence, in either style:
#'
#' ```
#' yaml::yaml.load("a:\n- x")$a  # "x"          - a length-1 character vector
#' yaml::yaml.load("a: [x]")$a   # "x"          - the same
#' yaml::yaml.load("a:\n- x\n- y")$a # c("x","y")
#' ```
#'
#' so a header whose `relatedLink`, `identifier` or `instrument` holds exactly one value
#' reaches the contract as a string, and a `type: array` property rejects a file that is
#' valid. The released v0.6.0 vectors never hit this; the FHT development vectors do
#' (`fht-fasta-rich` and `fht-fasta-link-scheme-warning`), which is how it was found. It is
#' a shape problem, so it is repaired where the shape is recorded - in the text - rather
#' than in the schema.
#'
#' Two alternatives were rejected. Coercing whatever the *contract* declares to be an array
#' would turn a genuine scalar (`relatedLink: https://x`) into a one-item array and accept
#' an invalid file - the dangerous direction, and the same class of mistake as a quietly
#' wrong engine. Writing a YAML parser is out of scope.
#'
#' @section Known limit:
#' Keys are matched by name at any depth, not by full path, because a contract gives one
#' key name one shape. A key that appears both as a scalar and as a sequence in the same
#' contract would be over-wrapped, and the result would be a rejection of a valid file - a
#' visible failure that the vector suite would catch, never a silent pass.
#'
#' The scan is line-oriented, so it sees a key whose value is a sequence on its own line or
#' in flow brackets at the top level of a line; it does not look *inside* a flow value. That
#' was harmless while every array-typed property in the released contracts was a top-level
#' key (measured over fhr-2.1, fhp-1.2 and fhgff3-1.2: it is still true there). The FHGM
#' draft record contract is the first in the family with an array nested inside an object -
#' `publication.deposit` and `methods.limitations`, both arrays of scalars - so a record
#' written as one JSON flow value on one line loses exactly that shape here. The FHGM lane
#' repairs it from the same text, in its own module
#' (`FAIRbioHeadersTools:::.bh_fhgm_flow_scalar_keys()`), and nothing about the released
#' path changes.
#'
#' @name yaml-shape
NULL

#' The key names whose value is written as a sequence.
#'
#' @param lines Header lines with the `;~`/`#~` prefix removed, in file order.
#' @return A character vector of key names.
#' @noRd
.bh_sequence_keys <- function(lines) {
  # The per-line regular expressions run once over all lines, vectorized; the loop below
  # only carries the pending key from line to line. (Run line by line, they made a
  # 9,000-line header take seconds.)
  tl <- trimws(lines)
  skip <- !nzchar(tl) | startsWith(tl, "#")
  ind <- attr(regexpr("^ *", lines), "match.length") # regexpr: see test-framing.R on sub()
  body <- sub("^ *", "", lines)
  item <- grepl("^-([ \t]|$)", body)
  inner <- sub("^-([ \t]|$)", "", body)
  head <- ifelse(item, inner, body)
  is_key <- grepl("^[^:#]+:([ \t]|$)", head)
  k <- trimws(sub("([ \t]*):.*$", "", head))
  v <- trimws(sub("^[^:]*:[ \t]*", "", head))
  has_v <- grepl(":", head) & nzchar(v)
  ind2 <- ind + attr(regexpr("^[^:#]+:", inner), "match.length")

  keys <- character()
  pending_name <- NULL # a key whose value is not on its own line: the next line decides
  pending_ind <- NA_integer_
  for (i in which(!skip)) {
    if (item[[i]]) {
      # a block sequence item; it belongs to the pending key when one is open, including
      # the FASTA-header style where the item sits at the key's own indentation
      if (!is.null(pending_name) && ind[[i]] >= pending_ind) keys <- c(keys, pending_name)
      pending_name <- NULL
      if (is_key[[i]] && !has_v[[i]]) {
        pending_name <- k[[i]]
        pending_ind <- ind2[[i]]
      }
      next
    }
    pending_name <- NULL
    if (!is_key[[i]]) next
    if (!has_v[[i]]) {
      pending_name <- k[[i]]
      pending_ind <- ind[[i]]
      next
    }
    if (startsWith(v[[i]], "[")) keys <- c(keys, k[[i]]) # a flow sequence
  }
  unique(keys)
}

#' The inline value of `key: value`, or NULL when the key carries none.
#' @noRd
.bh_inline_value <- function(body) {
  if (!grepl(":", body)) return(NULL)
  v <- trimws(sub("^[^:]*:[ \t]*", "", body))
  if (!nzchar(v)) NULL else v
}

#' Forces the sequence-valued keys to list shape.
#'
#' @param x The parsed record.
#' @param keys The result of [.bh_sequence_keys()].
#' @return The record with those values as lists.
#' @noRd
.bh_repair_shape <- function(x, keys) {
  if (!is.list(x) || !length(keys)) return(x)
  walk <- function(node) {
    if (!is.list(node)) return(node)
    nms <- names(node)
    out <- lapply(node, walk)
    if (is.null(nms)) return(out)
    hit <- which(nms %in% keys)
    for (i in hit) {
      v <- out[[i]]
      if (is.atomic(v) && length(v) >= 1L) out[[i]] <- as.list(v)
    }
    # a key whose value is null is left out, as it always was here
    out[!vapply(out, is.null, logical(1L))]
  }
  walk(x)
}

#' Turns a repaired record into the JSON the validator consumes.
#'
#' Scalars are marked with [jsonlite::unbox()] rather than relying on `auto_unbox`, which
#' unboxes any length-1 atomic whatever its parent is and so re-flattens the sequences just
#' repaired above. R's yaml keeps `{}` and `[]` distinguishable (a named empty list against
#' an unnamed one), and jsonlite reads that back as an object against an array.
#'
#' @param record A parsed record.
#' @return A length-1 JSON string.
#' @noRd
.bh_record_json <- function(record) {
  jsonlite::toJSON(.bh_mark_scalars(record), auto_unbox = FALSE, null = "null",
    digits = NA, na = "string"
  )
}

.bh_mark_scalars <- function(x) {
  if (is.list(x)) {
    out <- lapply(x, .bh_mark_scalars)
    names(out) <- names(x)
    out
  } else if (is.atomic(x) && length(x) == 1L && !is.na(x)) {
    jsonlite::unbox(x)
  } else {
    x
  }
}
