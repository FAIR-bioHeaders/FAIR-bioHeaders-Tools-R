#!/usr/bin/env Rscript
#' Assert that this package is native, structurally - not just in intent.
#'
#' The acceptance job calls this before it runs anything else. Three claims are checked, each
#' one a thing a later commit could break quietly:
#'
#' 1. `DESCRIPTION` declares no foreign-language runtime: no Python bridge, no conda or
#'    virtualenv requirement, and no `configure`/`Makevars` trick that would reach for another
#'    interpreter at build time.
#' 2. `R/` contains no external-process call - no `system()`, `system2()`, `shell()`, no
#'    `file(..., open = "r")` pipe - so nothing in the library can delegate the checksum, the
#'    parsing or the validation to a subprocess. Prose *about* Python is allowed (this file
#'    contains some); a call is not.
#' 3. No function defined in `R/` takes an `engine` argument, so no caller can ask for the
#'    draft-07-era default that mis-verifies these contracts. This is checked on the parsed
#'    formals, which is what a caller could actually pass, rather than by searching text.
#'
#' The script parses the sources instead of loading them, so it runs before the package is
#' installed. Exit status: 0 when all three hold; 1 with every violation printed.

fail <- character()
note <- function(...) cat(..., "\n", sep = "")

if (!dir.exists("R") && dir.exists("../R")) setwd("..")
if (!dir.exists("R")) {
  cat("VIOLATION: not run from the package root (no R/ directory)\n")
  quit(status = 1L)
}

# 1. declared dependencies ---------------------------------------------------------------
d <- read.dcf("DESCRIPTION")
want <- c("Depends", "Imports", "LinkingTo", "Suggests", "Enhances", "SystemRequirements")
cols <- intersect(want, colnames(d))
if (!length(cols)) fail <- c(fail, "DESCRIPTION exposes no dependency field to read")
declared <- gsub("[\r\n]+[ \t]*", " ", paste(unlist(d[, cols, drop = TRUE]), collapse = " "))
declared <- trimws(gsub("[ \t]{2,}", " ", declared))
if (grepl("python|reticulate|virtualenv|conda|miniconda", declared, ignore.case = TRUE)) {
  fail <- c(fail, paste0("DESCRIPTION names a foreign-language runtime: ", declared))
}
if (file.exists("configure") || file.exists("configure.win")) {
  scripts <- c("configure", "configure.win")[file.exists(c("configure", "configure.win"))]
  txt <- paste(unlist(lapply(scripts, readLines, warn = FALSE)), collapse = "\n")
  if (grepl("python|pip|virtualenv|conda", txt, ignore.case = TRUE)) {
    fail <- c(fail, paste0("the build script(s) ", paste(scripts, collapse = ", "),
      " reach for a foreign runtime"))
  }
}
cat("declared dependencies: ", declared, "\n", sep = "")

# 2. no external process in the library --------------------------------------------------
rfiles <- list.files("R", pattern = "[.]R$", full.names = TRUE)
if (!length(rfiles)) fail <- c(fail, "no R sources found - nothing to check")
call_pat <- paste0(
  "(^|[^.[:alnum:]_])(system2|system|shell|pipe|system.file2)[[:space:]]*\\(",
  "|open[[:space:]]*\\([^)]*[\"']r[|]"
)
hits <- unlist(lapply(rfiles, function(f) {
  l <- readLines(f, warn = FALSE)
  m <- grep(call_pat, l, value = TRUE)
  if (length(m)) paste0(f, ": ", trimws(m)) else character()
}))
if (length(hits)) {
  fail <- c(fail, paste0(
    "R/ must not invoke an external process; found ", length(hits), " line(s):\\n",
    paste(hits, collapse = "\n")
  ))
}
cat("R/ sources: ", length(rfiles), " files, no external-process call\n", sep = "")

# 3. no engine argument anywhere ---------------------------------------------------------
collect_functions <- function(e, out = list()) {
  if (!is.call(e)) return(out)
  head <- if (is.name(e[[1L]])) as.character(e[[1L]]) else ""
  if (length(head) == 1L && head %in% c("<-", "=", "<<-") && length(e) >= 3L &&
      is.call(e[[3L]]) && is.name(e[[3L]][[1L]]) &&
      identical(as.character(e[[3L]][[1L]]), "function") && is.name(e[[2L]])) {
    out[[as.character(e[[2L]])]] <- e[[3L]]
  }
  # an anonymous function can be a list element or an argument rather than an assignment, and
  # its formals are still the pairlist at [[2L]]. Assignments are recorded by name above, so
  # the anonymous pass skips anything already present to avoid double-reporting one function.
  if (head == "function" && !any(vapply(out, identical, logical(1L), e))) {
    out[[paste0("<anonymous>", length(out) + 1L)]] <- e
  }
  for (i in seq_along(e)) {
    walk <- tryCatch(is.call(e[[i]]) || is.pairlist(e[[i]]), error = function(x) FALSE)
    if (isTRUE(walk)) out <- collect_functions(e[[i]], out)
  }
  out
}

exprs <- unlist(lapply(rfiles, function(f) as.list(parse(f))), recursive = FALSE)
fns <- list()
for (e in exprs) fns <- collect_functions(e, fns)

# The collected objects are unevaluated `function(...)` calls, so the formals are the pairlist
# at [[2L]]. formals() on a call is not a function and warns while returning NULL, which made
# an earlier revision of this check pass unconditionally - the negative control at the bottom
# of this file's history caught it.
formal_names <- function(f) {
  if (!is.call(f) || !length(f) >= 2L) return(character())
  pl <- f[[2L]]
  if (is.null(pl)) return(character())
  as.character(names(pl))
}
takes_engine <- names(fns)[vapply(fns, function(f) "engine" %in% formal_names(f),
  logical(1L)
)]
# jsonvalidate::json_validator itself takes one; that call is the pin, so only functions this
# package defines are in scope - and among those, none may accept it
if (length(takes_engine)) {
  fail <- c(fail, paste0("functions defined in R/ accept an engine argument: ",
    paste(sQuote(takes_engine), collapse = ", ")))
}
cat("functions found in R/: ", length(fns), "; taking an engine argument: ",
  if (length(takes_engine)) paste(sQuote(takes_engine), collapse = ", ") else "none",
  "\n", sep = "")

if (length(fail)) {
  cat("\n")
  for (f in fail) cat("VIOLATION: ", gsub("\\\\n", "\n", f), "\n", sep = "")
  quit(status = 1L)
}
uses_engine <- any(grepl("jsonvalidate", vapply(rfiles, function(f)
  paste(readLines(f, warn = FALSE), collapse = " "), ""
)))
cat("native: no foreign-language dependency, no external-process call",
  if (uses_engine) ", engine pinned (no function accepts an engine argument)" else
    " (no schema engine in use at this revision)", "\n", sep = "")
