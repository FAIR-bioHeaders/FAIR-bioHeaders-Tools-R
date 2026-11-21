#' The rule V7 draft lane, and what a draft is not
#'
#' A draft contract is an unreleased schema held in the development repository that owns
#' the type. docs/SCHEMA-VERSIONS.md V7 lets a reader recognise one, under four
#' constraints this module implements literally:
#'
#' 1. Never the default. The lane opens only where the caller asks for it, per type
#'    ([bh_draft_lane()], or the `draft` argument of [bh_read()] and [bh_validate()]).
#'    With the lane closed, a draft citation is "any other value" under V5 and the
#'    outcome is byte-for-byte what it was before V7 existed - [bh_draft_default_off()]
#'    asserts exactly that.
#' 2. Only the raw-main URL of the owning development repository is in the lane. A
#'    release-shaped URL for an unregistered type - `https://w3id.org/fair-bioheaders/fht/
#'    v0.7.0`, or a raw tag URL - is not a draft citation and is not read as one, with
#'    the lane open or closed: no release number is invented for a draft, and this
#'    consumer has no row for it in `inst/schemas/versions.json`.
#' 3. Pinned by commit and SHA-256. Selection runs against the bytes this package was
#'    built with, recorded in `inst/VENDORED.json`; if the file on disk no longer matches
#'    its recorded digest the lane says so instead of quietly reading something newer.
#' 4. A warning on every record read through it, naming the draft, the commit and the
#'    digest, and saying the result is not a released-contract result.
#'
#' Reading this lane does not adopt a released form. The family has published FHT 1.0
#' and native FHGM 0.1; this consumer retains explicit development-snapshot selection
#' and does not silently repin or adopt publication merely because it exists.
#'
#' Complete FHT BUSCO count sums are verified only within this reader's exact
#' integer range (0 through 2^53 - 1). Larger counts raise `bh_limit`, a consumer
#' precision limitation rather than an upstream schema maximum.
#'
#' @name drafts
NULL

.bh_draft_rows <- function() {
  Filter(function(r) identical(r$kind, "draft-contract"), .bh_vendored()$files)
}

.bh_draft_row <- function(type) {
  r <- Filter(function(x) identical(x$header_type, type), .bh_draft_rows())
  if (!length(r)) return(NULL)
  r[[1L]]
}

.bh_draft_citation <- function(type) {
  r <- .bh_draft_row(type)
  if (is.null(r)) NA_character_ else r$citation
}

.bh_lane_types <- function(draft) {
  lane <- list(FHT = FALSE, FHGM = FALSE)
  if (isTRUE(draft)) {
    for (r in .bh_draft_rows()) lane[[r$header_type]] <- TRUE
    return(lane)
  }
  if (is.character(draft)) {
    want <- toupper(draft)
    unknown <- setdiff(want, names(lane))
    if (length(unknown)) {
      bh_abort("draft", paste0(
        "no draft contract is bundled for ", paste(sQuote(unknown), collapse = ", "),
        "; the lane covers ", paste(names(lane), collapse = " and ")
      ))
    }
    for (t in want) lane[[t]] <- TRUE
    return(lane)
  }
  if (isFALSE(draft)) return(lane)
  bh_abort("draft", "`draft` must be FALSE, TRUE or a character vector of draft types")
}

#' Opens or reports the draft lane
#'
#' @param types `NULL` to report the current lane; `FALSE` to close it; `TRUE` to open
#'   every bundled draft; or a character vector such as `c("FHT", "FHGM")`.
#' @return A named logical list of the drafts the lane covers after the call. The lane is
#'   process state, so a caller that opens it should close it again -
#'   `withr::defer(bh_draft_lane(FALSE))` in tests, or pass `draft =` per call instead.
#' @export
bh_draft_lane <- function(types = NULL) {
  if (is.null(types)) return(.bh_lane_types(getOption("bh.draft_lane", FALSE)))
  opts <- .bh_lane_types(types)
  active <- Filter(isTRUE, opts)
  if (!length(active)) {
    options(bh.draft_lane = FALSE)
  } else {
    options(bh.draft_lane = names(active))
  }
  invisible(opts)
}

#' The pinned draft bytes: citation, commit and digest
#'
#' @return A data frame with `header_type`, `citation`, `commit`, `head_at_retrieval`,
#'   `sha256`, `bytes` and `digest_ok`.
#' @export
bh_draft_pins <- function() {
  rows <- .bh_draft_rows()
  if (!length(rows)) return(invisible(NULL))
  do.call(rbind, lapply(rows, function(r) {
    p <- .bh_inst(sub("^inst/", "", r$file))
    bytes <- .bh_read_all(p)
    data.frame(
      header_type = r$header_type, citation = r$citation, commit = r$commit,
      head_at_retrieval = .bh_c(r$head_at_retrieval, NA_character_),
      sha256 = r$sha256, bytes = as.integer(r$bytes),
      digest_ok = identical(.bh_sha256_hex(bytes), r$sha256),
      stringsAsFactors = FALSE
    )
  }))
}

.bh_draft_selection <- function(type, value) {
  r <- .bh_draft_row(type)
  p <- .bh_inst(sub("^inst/", "", r$file))
  bytes <- .bh_read_all(p)
  got <- .bh_sha256_hex(bytes)
  if (!identical(got, r$sha256)) {
    bh_abort("draft", paste0(
      type, ": the bundled draft bytes no longer match their recorded digest (found ",
      got, ", pinned ", r$sha256, " of commit ", r$commit,
      "); refusing to read a draft this package cannot name"
    ))
  }
  if (length(bytes) != r$bytes) {
    bh_abort("draft", paste0(
      type, ": the bundled draft is ", length(bytes), " bytes, recorded ", r$bytes
    ))
  }
  warn <- paste0(
    type, ": warning: schema ", value, " is an unreleased draft (commit ", r$commit,
    ", sha256 ", r$sha256, " of those bytes); read against that pinned draft, not a ",
    "released schema. Drafts take no release form (docs/SCHEMA-VERSIONS.md V7)."
  )
  structure(list(
    rule = "V7", header_type = type, release = NA_character_, file = p,
    schema_version = NA_character_, status = "draft", message = NA_character_,
    warnings = warn, pin = r
  ), class = "bh_selection")
}

#' With the lane closed, a draft citation is selected exactly as V5 always selected it
#'
#' This is the byte-identity check for the default path: the `schema` values of an
#' unregistered type - the draft's raw-main URL and every release-shaped URL near it -
#' all land on the current FHR schema with the same outcome, warning and rule as before
#' the lane existed.
#'
#' @param value A `schema` URL to classify.
#' @return The selection made with the lane closed.
#' @export
bh_draft_default_off <- function(value = "https://raw.githubusercontent.com/FAIR-bioHeaders/FHT-Specification/main/fht.json") {
  bh_select(value, draft = FALSE)
}
