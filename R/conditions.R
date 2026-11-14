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
#' @name conditions
NULL

#' @param class the condition subclass, without the `bh_` prefix.
#' @param message ONE format string; the continuation lines of a long message must be
#'   joined with `paste0()` inside the argument, because `sprintf` cannot tell a format
#'   fragment from a value.
#' @param ... Values substituted into `message`.
#' @rdname conditions
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
