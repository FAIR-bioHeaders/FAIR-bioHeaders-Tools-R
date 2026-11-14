#' FAIR-bioHeaders Tools
#'
#' Reads, verifies and validates FAIR-bioHeaders file-bound metadata in R.
#'
#' @details
#' The checksum is a vendored FIPS 180-4 SHA-512/256 implementation
#' ([bh_sha512_256()], [bh_sha512_256_file()]); `docs/DIGEST.md` in the source
#' repository records why it is not delegated to `digest`, the R `openssl` package,
#' a system command or the Python toolkit. Reading and validation are [bh_read()],
#' [bh_verify()] and [bh_validate()]. What this package does not implement is
#' declared in docs/STATUS.md and by the not-run reasons of the shared-vector run.
#'
#' @section Support statement:
#' Released contracts: FHR 2.1, FHP 1.2 and FHGFF3 1.2 (specification v0.6.0).
#' FHT and FHGM have no released contract - no `schemaVersion`, no registry row, no
#' w3id URL - and this revision of the package does not read them at all: the rule V7
#' opt-in draft lane is a separate, later addition. An FHT citation is therefore
#' selected under rule V5 exactly as the released rules specify.
#'
#' @keywords internal
#' @useDynLib FAIRbioHeadersTools, .registration = TRUE, .fixes = "C_"
"_PACKAGE"
