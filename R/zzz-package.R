#' FAIR-bioHeaders Tools
#'
#' Native R support for FAIR-bioHeaders file-bound metadata.
#'
#' @details
#' At this revision the package provides the checksum layer: a vendored FIPS 180-4
#' SHA-512/256 core with a streaming file API ([bh_sha512_256()],
#' [bh_sha512_256_file()], [bh_digest_stream()]). `docs/DIGEST.md` records why the digest is
#' vendored rather than delegated to `digest`, the R `openssl` package, a system command or
#' the Python toolkit, and the evidence the decision rests on. Header reading and contract
#' validation follow in the next revision, per
#' <https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Tools-R/issues/3> and
#' <https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Tools-R/issues/4>.
#'
#' @section Support statement:
#' Nothing in this package yet claims support for any header type. The released contracts are
#' FHR 2.1, FHP 1.2 and FHGFF3 1.2 (specification v0.6.0); FHT and FHGM are drafts with no
#' released contract, no `schemaVersion`, no registry row and no w3id URL, and take no release
#' form (rule V7).
#'
#' @keywords internal
#' @useDynLib FAIRbioHeadersTools, .registration = TRUE, .fixes = "C_"
"_PACKAGE"
