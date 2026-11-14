#' The contract registry: what this package can validate, and what it cannot
#'
#' Two tables are kept apart on purpose.
#'
#' * [bh_contracts()] lists the frozen contract copies under `inst/schemas/`, one per
#'   header type per version, with the release, the commit of the source tag and the
#'   SHA-256 of the bytes. Selection rules V1 to V6 name these.
#' * [bh_types()] lists the header types this revision reads: FHR, FHP and FHGFF3,
#'   all released. The family has five type names; FHT and FHGM have no released
#'   contract - no `schemaVersion`, no registry row and no w3id URL - and drafts take
#'   no release form (docs/SCHEMA-VERSIONS.md V7). Neither is registered, bundled or
#'   read at this revision; rule V7 recognition arrives with the draft lane, and until
#'   then an FHT citation is selected under V5 exactly as the released rules specify.
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
#' @param header_type `FHR`, `FHP` or `FHGFF3`.
#' @return A character vector of release tags, `main` first as `main (vX.Y.Z)`.
#' @export
bh_releases <- function(header_type = "FHR") {
  header_type <- toupper(header_type)
  reg <- .bh_registry()
  cs <- bh_contracts()
  have <- unique(cs$release[cs$header_type == header_type])
  c(paste0("main (", reg$current, ")"), sort(setdiff(have, reg$current)))
}

#' The header-family table
#'
#' @return A data frame with `header_type`, `status`, `is_header_type`, `contract`,
#'   `serializations`, `schema_versions` and `note`.
#' @export
bh_types <- function() {
  cs <- bh_contracts()
  versions <- function(t) {
    v <- cs$schema_version[cs$header_type == t]
    paste(sort(unique(v)), collapse = ",")
  }
  data.frame(
    header_type = c("FHR", "FHP", "FHGFF3"),
    status = c("released", "released", "released"),
    is_header_type = c(TRUE, TRUE, TRUE),
    contract = c(versions("FHR"), versions("FHP"), versions("FHGFF3")),
    serializations = c("fasta,gfa", "fhp-fasta", "fhgff3"),
    schema_versions = c(versions("FHR"), versions("FHP"), versions("FHGFF3")),
    note = rep("released in the v0.6.0 baseline", 3L),

    stringsAsFactors = FALSE
  )
}
