#' Small shared internals
#'
#' The handful of primitives the rest of the package is built from: one format string
#' helper, one condition pair, and the byte-level file probes. They live together because
#' each is three lines and each is used from several modules.
#'
#' @name internals
NULL

# This module is the sole owner of every helper defined below. Until #12 the same names also
# appeared in R/conditions.R (`bh_abort`, `bh_warn`, `.bh_capture`, `.bh_read_all`) and
# R/framing.R (`%||%`, `.bh_c`), where they were dead code: with no `Collate:` field this file is
# collated after both of those, so its bindings were always the ones the namespace held. The
# deleted `R/conditions.R` copy of `bh_warn()` had a different `sprintf()`-failure fallback; that
# alternative is recorded in R/conditions.R. The maintainer ruling on 2026-11-16 in #12
# retains the joined-parts fallback, covered directly by tests/testthat/test-warning-fallback.R,
# and `tools/check_duplicate_defs.R` fails the build if any top-level name is defined twice again.

# Base R has had %||% since 4.4; this package keeps its own so the null-coalescing
# behaviour is identical on every R version it claims to support.
`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a

.bh_c <- function(x, default) if (length(x) != 1L || is.na(x)) default else x

# Reads a whole file as bytes. Used for pinned contract and draft bytes, which are small and
# are always consumed in full; the checksum path streams instead (see bh_sha512_256_file()).
.bh_read_all <- function(path) {
  size <- file.info(path)$size
  if (is.na(size)) bh_abort("input", paste0("no such file: ", path))
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  readBin(con, what = "raw", n = size)
}

#' Conditions and diagnostics
#'
#' Failures are classed conditions. Every error this package raises carries `bh_error` plus
#' a specific subclass, so a caller can catch the family or one kind of failure with
#' [tryCatch()] instead of matching on message text. Warnings carry `bh_warning` plus a
#' subclass. A rule that reports rather than rejects - R11 and R14, the empty-required-value
#' guidance in docs/SCHEMA-VERSIONS.md, the rule V6 deprecation - is a warning by design and
#' never changes validity.
#'
#' @param class the condition subclass, without the `bh_` prefix.
#' @param message one format string; continuation lines of a long message must be joined
#'   with `paste0()` inside this argument, because `sprintf` cannot tell a format fragment
#'   from a value.
#' @param ... values substituted into `message`.
#' @rdname internals
#' @keywords internal
bh_abort <- function(class, message, ...) {
  text <- tryCatch(sprintf(message, ...), error = function(e) {
    paste(c(message, ...), collapse = "")
  })
  cond <- structure(
    class = c(paste0("bh_", class), "bh_error", "error", "condition"),
    list(message = text, call = sys.call(-1L))
  )
  stop(cond)
}

#' @rdname internals
#' @keywords internal
bh_warn <- function(class, message, ...) {
  text <- tryCatch(sprintf(message, ...), error = function(e) {
    paste(c(message, ...), collapse = "")
  })
  cond <- structure(
    class = c(paste0("bh_", class), "bh_warning", "warning", "condition"),
    list(message = text, call = sys.call(-1L))
  )
  warning(cond)
  invisible(NULL)
}

# Runs `expr` collecting the diagnostics it emits rather than stopping at the first one, so
# one pass over a file can report every problem found in it.
#
# @return A list with `value` (NULL when `expr` raised a bh_error), `error` (the message or
#   NULL), and `warnings` (character).
#' @noRd
.bh_capture <- function(expr) {
  warns <- character()
  err <- NULL
  val <- withCallingHandlers(
    tryCatch(expr, bh_error = function(e) {
      err <<- conditionMessage(e)
      NULL
    }),
    bh_warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(value = val, error = err, warnings = warns)
}
