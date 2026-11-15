#!/usr/bin/env Rscript
#' Fail when a name is defined twice at the top level of R/.
#'
#' Why this script exists (issue #12): R resolves duplicate top-level definitions inside a
#' package namespace silently - the file loaded later simply overwrites the earlier binding -
#' so `R CMD check` reports nothing about it. Measured on main at 4611c2c:
#' `R CMD check --as-cran --no-manual` exits 0 with `Status: 1 NOTE` while six names are
#' defined twice, and its log never uses the word "duplicate" about them. Six dead copies sat
#' in R/conditions.R (bh_abort, bh_warn, .bh_capture, .bh_read_all) and R/framing.R (.bh_c,
#' %||%) until this issue; one of them, `bh_warn`, had a body that differs semantically from
#' the copy that actually runs. The hazard is a maintainer editing the file they are looking
#' at and changing nothing. (#12's table lists five names and 126 definitions; a parse of the
#' same tree finds 128 top-level function definitions and one more duplicated name, `%||%`,
#' which is reported here because it is the same defect and the same seam.)
#'
#' What it checks: every top-level assignment in the package's R/ directory - the `<-`,
#' `<<-`, `->`, `->>` and `=` forms, and `assign()` with a literal character name. A name
#' bound more than once, across files or within one file, is a violation. Identical bodies
#' are violations too: an exact duplicate is still dead code that can drift.
#'
#' What it does not do: it does not load the package, and it does not need the compiled
#' core or any dependency, so it runs before `R CMD build`. It compares the deparsed source
#' of each right-hand side, which is why byte-for-byte identical bodies with different
#' indentation count as identical, and any real difference in parameters or body counts as
#' divergent.
#'
#' Scope: R/ only. `tools/*.R` are standalone CI harness scripts, sourced one at a time, and
#' never collated into a namespace, so a repeated name there cannot shadow anything.
#'
#' Exit status: 0 when every top-level name is unique; 1 when a duplicate is found; 2 when
#' the script cannot see the package sources at all. A run that finds nothing because it
#' could not read R/ is a failure, never a pass.
#'
#' Usage: Rscript tools/check_duplicate_defs.R [package-root]   # default: the working
#' directory, which must be the package root.

verbose <- "--verbose" %in% commandArgs(trailingOnly = TRUE)

# Deliberately no parent-directory fallback: an unnamed invocation must resolve exactly the
# tree it is standing in, so that "run this somewhere without R/" fails rather than finding
# data through a path the caller never named.
root <- local({
  a <- commandArgs(trailingOnly = TRUE)
  pos <- a[!startsWith(a, "-")]
  if (length(pos)) pos[[1L]] else "."
})
cand <- normalizePath(root, mustWork = FALSE)
rdir <- file.path(cand, "R")
if (!dir.exists(rdir)) {
  cat("VIOLATION: no R/ directory under ", cand, " - run this from the package root\n",
    sep = "")
  quit(status = 2L)
}
if (!file.exists(file.path(cand, "DESCRIPTION"))) {
  cat("VIOLATION: no DESCRIPTION next to ", rdir, " - that is not a package root\n", sep = "")
  quit(status = 2L)
}

files <- sort(list.files(rdir, pattern = "[.]R$", full.names = TRUE))
if (!length(files)) {
  cat("VIOLATION: ", rdir, " holds no .R files - nothing was checked\n", sep = "")
  quit(status = 2L)
}

# The order R CMD INSTALL will collate them in: an explicit Collate: field when the
# package declares one, alphabetical order otherwise. Used only to say which definition
# wins; the duplicate itself is the violation either way.
collate_files <- function(desc) {
  i <- grep("^Collate:", desc)
  if (!length(i)) return(character())
  j <- i[[1L]]
  # continuation lines of a Collate: field, until the next unindented field
  block <- desc[seq.int(j, length(desc))]
  if (length(block) > 1L) {
    nxt <- grep("^[^ \t]", block)[-1L]
    if (length(nxt)) block <- block[seq_len(nxt[[1L]] - 1L)]
  }
  unlist(regmatches(paste(block, collapse = " "), gregexpr('"[^"]+[.]R"', paste(block, collapse = " "))))
}
desc <- readLines(file.path(cand, "DESCRIPTION"), warn = FALSE)
collated <- gsub('"', "", collate_files(desc), fixed = TRUE)
load_order <- if (length(collated)) file.path(rdir, collated) else files
rank_of <- setNames(seq_along(load_order), basename(load_order))
rank <- function(f) {
  r <- rank_of[[f]]
  if (is.null(r)) length(load_order) + 1L else as.integer(r)
}

ops <- c("<-", "<<-", "->", "->=", "=")
name_of <- function(e) {
  if (!is.call(e)) return(NULL)
  op <- as.character(e[[1L]])
  if (op %in% ops) {
    lhs <- if (op %in% c("->", "->>")) e[[3L]] else e[[2L]]
    if (is.name(lhs)) return(as.character(lhs))
    if (is.character(lhs)) return(lhs[[1L]])
    return(NULL)
  }
  if (op == "assign" && length(e) >= 2L) {
    nm <- if (!is.null(e$name)) e$name else e[[2L]]
    if (is.character(nm)) return(nm[[1L]])
  }
  NULL
}

# Deparse the RHS so that formatting differences cancel out and semantic ones cannot.
rhs_text <- function(e) {
  op <- as.character(e[[1L]])
  rhs <- if (op %in% c("->", "->>")) {
    e[[2L]]
  } else if (op == "assign") {
    if (!is.null(e$value)) e$value else if (length(e) >= 3L) e[[3L]] else NULL
  } else {
    e[[3L]]
  }
  if (is.null(rhs)) return("<unknown rhs>")
  paste(deparse(rhs, width.cutoff = 500L), collapse = "\n")
}

defs <- list()
for (f in files) {
  ex <- tryCatch(parse(f, keep.source = TRUE), error = function(e) {
    cat("VIOLATION: ", basename(f), " does not parse: ", conditionMessage(e), "\n", sep = "")
    quit(status = 2L)
  })
  refs <- attr(ex, "srcref")
  for (i in seq_along(ex)) {
    nm <- name_of(ex[[i]])
    if (is.null(nm)) next
    defs[[length(defs) + 1L]] <- list(
      name = nm, file = basename(f),
      line = if (is.null(refs)) NA_integer_ else as.integer(refs[[i]][1L]),
      text = rhs_text(ex[[i]])
    )
  }
}

by_name <- split(defs, vapply(defs, `[[`, "", "name"))
dups <- Filter(function(d) length(d) > 1L, by_name)

cat(sprintf("check_duplicate_defs: %d .R files, %d top-level assignments, %d distinct names\n",
  length(files), length(defs), length(by_name)))
if (!length(dups)) {
  cat("check_duplicate_defs: OK - every top-level name in R/ is defined once\n")
  quit(status = 0L)
}

for (nm in names(dups)[order(names(dups))]) {
  d <- dups[[nm]]
  d <- d[order(vapply(d, function(x) rank(x$file), 0L))]
  live <- d[[length(d)]]
  same <- length(unique(vapply(d, `[[`, "", "text"))) == 1L
  cat(sprintf("VIOLATION: `%s` is defined %d times; the definition that runs is %s:%d (%s)\n",
    nm, length(d), live$file, live$line, if (same) "all copies identical" else "copies DIFFER"))
  for (c in d) {
    cat(sprintf("    %s:%-4d %s\n", c$file, c$line,
      if (identical(c$file, live$file) && identical(c$line, live$line)) "live" else "dead"))
  }
  if (verbose) {
    cat("  --- bodies, in load order (last is the one that runs) ---\n")
    for (c in d) {
      body <- paste0("      ", strsplit(c$text, "\n", fixed = TRUE)[[1L]], collapse = "\n")
      cat(sprintf("    ## %s:%d\n%s\n", c$file, c$line, body))
    }
  }
}
cat(sprintf("check_duplicate_defs: %d duplicated name(s) - see FAIR-bioHeaders-Tools-R#12\n",
  length(dups)))
quit(status = 1L)
