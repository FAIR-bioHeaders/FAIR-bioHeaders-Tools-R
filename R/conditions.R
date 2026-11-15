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

# `bh_abort()` and `bh_warn()` are each defined twice on `main`: here, and again in
# `R/internals.R`, together with duplicate copies of `.bh_read_all()` and `.bh_capture()`.
# They are documented in `R/internals.R` only, on purpose: that file is collated after this
# one, so its assignments overwrite the bindings below and its copies are the ones the package
# actually runs, and documenting the same topic twice is what produced the
# `Rd files with duplicated alias 'bh_abort'` WARNING that #10 is about. The duplicates are
# the seam left by the two PR chains merged into `main` on 2026-11-14. Deleting them is a
# code decision, not a documentation one: `bh_abort()` and `.bh_read_all()` are identical in
# both files, but the two `bh_warn()` copies differ - here a failed `sprintf()` yields
# `message`, in `R/internals.R` it yields the arguments pasted together - and only the
# latter is in effect. Recorded with #10; nothing here changes behaviour.
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

bh_warn <- function(class, message, ...) {
  text <- tryCatch(sprintf(message, ...), error = function(e) message)
  cond <- structure(
    class = c(paste0("bh_", class), "bh_warning", "warning", "condition"),
    list(message = text, call = sys.call(-1L))
  )
  warning(cond)
  invisible(NULL)
}

# Runs `expr` collecting the diagnostics it emits rather than stopping at the first one,
# so one pass over a file can report every problem found in it.
#
# @return A list with `value` (NULL when `expr` raised a bh_error), `error` (the message
#   or NULL), and `warnings` (character).
.bh_capture <- function(expr) {
  warns <- character()
  err <- NULL
  val <- NULL
  val <- withCallingHandlers(
    tryCatch(
      expr,
      bh_error = function(e) {
        err <<- conditionMessage(e)
        NULL
      }
    ),
    bh_warning = function(w) {
      warns <<- c(warns, conditionMessage(w))
      invokeRestart("muffleWarning")
    }
  )
  list(value = val, error = err, warnings = warns)
}

# Reads a whole file as bytes; used for contracts, pins and suites alike.
.bh_read_all <- function(path) {
  size <- file.info(path)$size
  if (is.na(size)) bh_abort("input", paste0("no such file: ", path))
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  readBin(con, what = "raw", n = size)
}

# SHA-256 for provenance and draft pins. This is the family's pinning digest, a
# different job from the file checksum, which is SHA-512/256 and computed by the
# vendored core in src/.
.bh_sha256_hex <- function(bytes) digest::digest(bytes, algo = "sha256", serialize = FALSE)
