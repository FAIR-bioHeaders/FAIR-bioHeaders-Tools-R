#' The contract registry: what this package can validate, and what it cannot
#'
#' Two tables are kept apart on purpose.
#'
#' * [bh_contracts()] lists the frozen contract copies under `inst/schemas/`, one per
#'   header type per version, with the release, the commit of the source tag and the
#'   SHA-256 of the bytes. Selection rules V1 to V6 name these.
#' * [bh_types()] lists this consumer's forms: FHR, FHP and FHGFF3 as released;
#'   FHT as an explicit development snapshot; FHGM as the historical extension
#'   *model* type, not a header type. Those records ride inside FHGFF3 under
#'   `x-fhgm-models`, with no record `schema` field or separate serialization here.
#'
#' Neither table is a support claim beyond what [bh_capability()] states operation by
#' operation. The family has published FHT 1.0 and native FHGM 0.1; this build
#' does not adopt their released selection forms or add their registry rows. The
#' FHT development schema contains schemaVersion 1.0. Both consumer lanes stay
#' outside `inst/schemas/versions.json` and require rule V7 opt-in.
#'
#' @name registry
NULL

.bh_state <- new.env(parent = emptyenv())

.bh_cached <- function(key, expr) {
  hit <- get0(key, envir = .bh_state, inherits = FALSE)
  if (!is.null(hit)) return(hit)
  val <- expr
  assign(key, val, envir = .bh_state)
  val
}

.bh_inst <- function(...) {
  p <- system.file(..., package = "FAIRbioHeadersTools")
  if (!nzchar(p)) {
    bh_abort("registry", paste0(
      "the installed package has no ", paste(...), "; the contract copies and their ",
      "provenance are part of the package"
    ))
  }
  p
}

.bh_vendored <- function() {
  .bh_cached("vendored", jsonlite::fromJSON(.bh_inst("VENDORED.json"), simplifyVector = FALSE))
}

.bh_registry <- function() {
  .bh_cached("registry", jsonlite::fromJSON(.bh_inst("schemas", "versions.json"),
                                            simplifyVector = FALSE))
}

.bh_contract_row <- function(type, version) {
  cs <- bh_contracts()
  i <- which(cs$header_type == type & cs$schema_version == as.character(version))
  if (length(i) != 1L) return(NULL)
  cs[i[[1L]], , drop = FALSE]
}

#' The frozen contract copies shipped with this package
#'
#' @return A data frame with `header_type`, `schema_version`, `release`, `commit`,
#'   `source_path`, `file`, `bytes` and `sha256`, one row per vendored contract.
#' @export
bh_contracts <- function() {
  .bh_cached("contracts", {
    rows <- Filter(function(r) identical(r$kind, "released-contract"), .bh_vendored()$files)
    if (!length(rows)) bh_abort("registry", "no released-contract rows in inst/VENDORED.json")
    out <- do.call(rbind, lapply(rows, function(r) {
      data.frame(
        header_type = r$header_type, schema_version = as.character(r$schema_version),
        release = r$ref, commit = r$commit, source_path = r$source_path,
        file = basename(r$file), bytes = as.integer(r$bytes), sha256 = r$sha256,
        stringsAsFactors = FALSE
      )
    }))
    out[order(out$header_type, out$schema_version), names(out), drop = FALSE]
  })
}

#' Releases whose contract copies this package holds
#'
#' Every release in the registry that registers a contract of this type, where this
#' package holds that contract version - which is every release a `schema` URL can select.
#' Several releases can share one contract version (v0.4.0 to v0.4.2 all carry FHR 2.0).
#'
#' @param header_type `FHR`, `FHP` or `FHGFF3`.
#' @return A character vector: `main (vX.Y.Z)` first, then the release tags in version
#'   order.
#' @export
bh_releases <- function(header_type = "FHR") {
  header_type <- toupper(header_type)
  reg <- .bh_registry()
  held <- vapply(names(reg$releases), function(r) {
    v <- reg$releases[[r]][[header_type]]
    !is.null(v) && !is.null(.bh_contract_row(header_type, v))
  }, NA)
  tags <- names(reg$releases)[held]
  tags <- tags[order(numeric_version(sub("^v", "", tags)))]
  c(paste0("main (", reg$current, ")"), tags)
}

#' The header-family table
#'
#' @return A data frame with `header_type`, `status`, `is_header_type`, `contract`,
#'   `serializations`, `schema_versions` and `note`.
#' @export
bh_types <- function() {
  reg <- .bh_registry()
  cs <- bh_contracts()
  versions <- function(t) {
    v <- cs$schema_version[cs$header_type == t]
    paste(sort(unique(v)), collapse = ",")
  }
  drafts <- vapply(c("FHT", "FHGM"), function(t) {
    r <- Filter(function(x) identical(x$header_type, t), .bh_vendored()$files)
    if (!length(r)) NA_character_ else r[[1]]$citation
  }, "")
  data.frame(
    header_type = c("FHR", "FHP", "FHGFF3", "FHT", "FHGM"),
    status = c("released", "released", "released", "draft", "draft"),
    is_header_type = c(TRUE, TRUE, TRUE, TRUE, FALSE),
    contract = c(
      versions("FHR"), versions("FHP"), versions("FHGFF3"),
      paste0("draft only: ", drafts[["FHT"]]),
      paste0("draft model contract only: ", drafts[["FHGM"]])
    ),
    serializations = c(
      "fasta,gfa", "fhp-fasta", "fhgff3", "fasta (draft)",
      "none: nested records inside an FHGFF3 header"
    ),
    schema_versions = c(
      versions("FHR"), versions("FHP"), versions("FHGFF3"), NA_character_, NA_character_
    ),
    note = c(
      rep("released in the v0.6.0 baseline", 3),
      paste0(
        "this consumer has no released FHT selection form; development snapshot only ",
        "through rule V7 (family FHT 1.0 is published), ",
        "pinned by commit and SHA-256, warns on every read"
      ),
      paste0(
        "not a header type: model records transported inside an FHGFF3 header under ",
        "x-fhgm-models; draft, lane-only, no schema field of its own. The lane reads the ",
        "records (K1 transport) and validates each one against the pinned draft record ",
        "contract (K2); the checker's cross-record rules K3-K6 are not ported - see ",
        "bh_capability() and bh_draft_fhgm_vectors()"
      )
    ),
    stringsAsFactors = FALSE
  )
}
