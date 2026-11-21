#' FAIR-bioHeaders Tools
#'
#' Reads, verifies and validates FAIR-bioHeaders file-bound metadata in R.
#'
#' @details
#' The checksum is a vendored FIPS 180-4 SHA-512/256 implementation
#' ([bh_sha512_256()], [bh_sha512_256_file()]); `docs/DIGEST.md` in the source
#' repository records why it is not delegated to `digest`, the R `openssl` package,
#' a system command or the Python toolkit. Reading and validation are [bh_read()],
#' [bh_verify()] and [bh_validate()]. The type and operation coverage, including
#' what this package does not implement, is [bh_capability()].
#'
#' @section Support statement:
#' Released contracts: FHR 2.1, FHP 1.2 and FHGFF3 1.2 (specification v0.6.0).
#' The family has published FHT 1.0 and native FHGM 0.1, but this consumer does
#' not select those released forms. Its FHT development snapshot carries
#' `schemaVersion: 1.0`; FHGM here is the historical embedded-record extension.
#' Both are reachable only through the explicit, pinned rule V7 lane
#' ([bh_draft_lane()]), without released-support claims for either.
#'
#' @keywords internal
#' @useDynLib FAIRbioHeadersTools, .registration = TRUE, .fixes = "C_"
"_PACKAGE"
