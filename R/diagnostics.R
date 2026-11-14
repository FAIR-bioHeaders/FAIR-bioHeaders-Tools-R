#' Rule R14: link schemes a validator must report
#'
#' R14 is explicit that a `uri` value with an unaccepted scheme stays *schema-valid* - the
#' released contracts never restricted the scheme, and restricting it would invalidate files
#' that are valid today - but that a validator warns about it, and that a tool rendering the
#' metadata should linkify only an accepted scheme. So this is reported, never rejected.
#'
#' Which values are links is read off the contract rather than hard-coded: every property
#' that declares `"format": "uri"`, directly or through `items` or a `$ref`, contributes its
#' key name, and the record's values under those names are checked as written. That recovers
#' the set docs/FORMAT.md names - `relatedLink`, `assemblyProtocol`, `accessionID.url`, a
#' software `uri`, the taxon and author `uri`, and the FHP and FHGFF3 counterparts - and it
#' keeps working if a contract adds another link field in a minor version.
#'
#' @name diagnostics
NULL

.bh_is_uri_node <- function(node, root, depth = 0L) {
  if (!is.list(node) || depth > 12L) return(FALSE)
  if (identical(node$format, "uri")) return(TRUE)
  if (is.character(node[["$ref"]]) && nzchar(node[["$ref"]])) {
    tgt <- .bh_resolve_ref(root, node[["$ref"]])
    if (!is.null(tgt) && .bh_is_uri_node(tgt, root, depth + 1L)) return(TRUE)
  }
  if (.bh_is_uri_node(node$items, root, depth + 1L)) return(TRUE)
  if (.bh_is_uri_node(node$contains, root, depth + 1L)) return(TRUE)
  FALSE
}

.bh_resolve_ref <- function(root, ref) {
  if (!grepl("^#/", ref)) return(NULL)
  parts <- strsplit(sub("^#/", "", ref), "/")[[1L]]
  node <- root
  for (p in parts) {
    p <- gsub("~1", "/", gsub("~0", "~", p), fixed = TRUE)
    if (is.null(node[[p]])) return(NULL)
    node <- node[[p]]
  }
  node
}

#' The property names one contract declares as `format: uri`, at any depth.
#' @noRd
.bh_uri_keys <- function(contract, root = contract) {
  out <- character()
  visit <- function(node, depth = 0L) {
    if (!is.list(node) || depth > 16L) return(invisible())
    for (nm in names(node$properties)) {
      if (.bh_is_uri_node(node$properties[[nm]], root)) out <<- c(out, nm)
      visit(node$properties[[nm]], depth + 1L)
    }
    for (nm in names(node$patternProperties)) {
      if (.bh_is_uri_node(node$patternProperties[[nm]], root)) out <<- c(out, nm)
      visit(node$patternProperties[[nm]], depth + 1L)
    }
    for (nm in names(node[["$defs"]])) visit(node[["$defs"]][[nm]], depth + 1L)
    for (nm in names(node[["definitions"]])) visit(node[["definitions"]][[nm]], depth + 1L)
    for (k in c("items", "contains", "if", "then", "else", "additionalProperties", "not")) {
      visit(node[[k]], depth + 1L)
    }
    for (k in c("allOf", "anyOf", "oneOf")) {
      if (is.list(node[[k]])) for (e in node[[k]]) visit(e, depth + 1L)
    }
    invisible()
  }
  visit(contract)
  unique(out)
}

.bh_link_warnings <- function(record, contract) {
  if (is.null(record) || is.null(contract)) return(character())
  keys <- .bh_uri_keys(contract)
  if (!length(keys)) return(character())
  hits <- .bh_link_scan(record, keys)
  if (!length(hits)) return(character())
  vapply(hits, function(h) paste0(
    "R14: ", h$key, " is ", h$value,
    ", whose scheme is not http, https, ftp, urn:, doi: or info:; the record stays ",
    "schema-valid, a validator warns, and a linked-data writer must not render it as a link"
  ), "", USE.NAMES = FALSE)
}

.bh_link_scan <- function(x, keys, out = list()) {
  if (is.list(x) && !is.null(names(x))) {
    for (nm in names(x)) {
      v <- x[[nm]]
      if (nm %in% keys) {
        # the value can arrive as a character vector (a plain YAML sequence) or as a
        # list of them (.bh_repair_shape wraps sequence keys into lists), so collect
        # the character leaves rather than assuming one shape
        for (s in .bh_char_leaves(v)) {
          if (nzchar(s) && !.bh_scheme_accepted(s)) {
            out[[length(out) + 1L]] <- list(value = s, key = nm)
          }
        }
      }
      out <- .bh_link_scan(v, keys, out)
    }
    return(out)
  }
  if (is.list(x)) for (v in x) out <- .bh_link_scan(v, keys, out)
  out
}

# Character leaves of a parsed YAML value, at any depth: "" is skipped by the caller's
# nzchar test; logical, numeric and NULL leaves are not URIs and are dropped.
.bh_char_leaves <- function(x) {
  if (is.character(x)) return(unname(x))
  if (is.list(x)) return(unlist(lapply(x, .bh_char_leaves), use.names = FALSE))
  character()
}

# Checked as written, per R14: the scheme must start the value and is compared without
# regard to case, and whitespace, a control character or a bidirectional formatting
# character anywhere means there is no accepted scheme. http, https and ftp also need
# "//" and a host.
.bh_scheme_accepted <- function(s) {
  if (grepl("[\r\n\t\f\v]", s) || grepl("[\u200e\u200f\u202a-\u202e\u2060]", s)) return(FALSE)
  if (grepl("^\\s|\\s$", s)) return(FALSE)
  m <- regmatches(s, regexec("^([A-Za-z][A-Za-z0-9+.-]*):(.*)$", s))[[1L]]
  if (!length(m)) return(FALSE)
  scheme <- tolower(m[[2L]])
  rest <- m[[3L]]
  if (scheme %in% c("urn", "doi", "info")) return(nzchar(rest))
  if (scheme %in% c("http", "https", "ftp")) return(grepl("^//[^/]", rest))
  FALSE
}

#' Rule R11: a plain FASTA header value holding a record marker, which strict readers treat
#' as the start of a sequence. Reported, never rejected.
#' @noRd
.bh_marker_warnings <- function(lines, format) {
  if (!format %in% c("fasta", "fhp-fasta", "fht-fasta")) return(character())
  out <- character()
  for (l in lines) {
    body <- trimws(l)
    if (!nzchar(body) || startsWith(body, "#")) next
    item <- grepl("^-([ \t]|$)", body)
    if (item) body <- trimws(sub("^-([ \t]|$)", "", body))
    v <- .bh_inline_value(body)
    if (is.null(v) || !.bh_plain_value(v)) next
    if (grepl("[>@]", v)) {
      out <- c(out, paste0(
        "R11: ", body, " puts ", if (grepl(">", v)) "`>`" else "`@`",
        " in a plain header value; strict FASTA readers start a record there. Quote the ",
        "value and write \\x3E or \\x40"
      ))
    }
  }
  unique(out)
}

# Is this scalar written plain - no quotes, no block or anchor indicator?
.bh_plain_value <- function(val) {
  nzchar(val) && !grepl("^['\"]", val) && !grepl("^[|>&*!]", val)
}
