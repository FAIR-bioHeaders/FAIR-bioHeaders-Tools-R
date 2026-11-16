#' Conditions and diagnostics
#'
#' Failures are classed conditions. Every error this package raises carries `bh_error`
#' plus a specific subclass, so a caller can catch the family or one kind of failure with
#' [tryCatch()] instead of matching on message text. Warnings carry `bh_warning` plus a
#' subclass. A rule that reports rather than rejects - R11 and R14 (writer and link-scheme
#' advice), the empty-required-value guidance in docs/SCHEMA-VERSIONS.md, the rule V6
#' deprecation, and the rule V7 draft notice - is a warning by design and never changes
#' validity.
#'
#' The helpers that raise these conditions, `bh_abort()` and `bh_warn()`, are documented on
#' one page only: see [internals()].
#'
#' @name conditions
#' @seealso [internals()]
NULL

# `bh_abort()`, `bh_warn()`, `.bh_capture()` and `.bh_read_all()` were each defined twice on
# `main`: once in this file and once in `R/internals.R`. `DESCRIPTION` declares no `Collate:`
# field, so this file is collated first and its bindings were overwritten at load time - the
# copies here were dead code, not a second implementation. #12 removed them, so
# `R/internals.R` is now the only definition of each name. Which copy ran was established from
# the installed namespace's bindings, not by reasoning about load order.
#
# The deleted `bh_warn()` copy handled a failing `sprintf()` with `error = function(e)
# message`, reporting the format string alone. The live `R/internals.R` copy instead uses
# `paste(c(message, ...), collapse = "")`, reporting every part of the call. The maintainer
# ruling on 2026-11-16 in FAIR-bioHeaders-Tools-R#12 retains this joined-parts behaviour;
# tests/testthat/test-warning-fallback.R exercises a deliberately mismatched format string
# and asserts its exact message and warning classes. The same ruling declines `Collate:`:
# the duplicate-definition guard catches the underlying hazard instead.
#
# `tools/check_duplicate_defs.R` fails the build if any top-level name is defined twice again.

# SHA-256 for provenance and draft pins. This is the family's pinning digest, a
# different job from the file checksum, which is SHA-512/256 and computed by the
# vendored core in src/.
.bh_sha256_hex <- function(bytes) digest::digest(bytes, algo = "sha256", serialize = FALSE)
