#!/usr/bin/env Rscript
#' Audit the vendored upstream data against the recorded provenance.
#'
#' Two questions, in two modes.
#'
#' 1. Off-line (the default, and what CI runs): does every file this package depends
#'    on still have the SHA-256 recorded in inst/VENDORED.json? This catches an
#'    accidental edit of a frozen contract or a vector, which would otherwise look
#'    like a normal validation difference.
#' 2. On-line (--fresh): do the rule V7 draft pins still match the live default branch
#'    of the repository that owns each draft? A moved draft must be noticed and said,
#'    not quietly read as current - docs/SCHEMA-VERSIONS.md V7. Mode 2 fetches with
#'    `git fetch` in the owning checkout given by --fht/--fhgm; it changes nothing.
#'
#' Exit status is nonzero on any drift, with one line per finding. Advisory for the
#' shared-guidance text comparisons of the federation; normative for these bytes.

.options <- commandArgs(trailingOnly = TRUE)
flag <- function(name) name %in% .options
arg <- function(name, default = NULL) {
  i <- match(name, .options)
  if (is.na(i) || i == length(.options)) default else .options[i + 1L]
}

if (!requireNamespace("digest", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE)) {
  stop("digest and jsonlite are required to audit the vendored copies")
}
here <- normalizePath(".")
prov <- jsonlite::fromJSON(file.path(here, "inst/VENDORED.json"), simplifyVector = FALSE)
sha256_file <- function(path) {
  size <- file.info(path)$size
  if (is.na(size)) return(NA_character_)
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  digest::digest(readBin(con, what = "raw", n = size), algo = "sha256", serialize = FALSE)
}

problems <- 0L
report <- function(ok, line) {
  if (!ok) problems <<- problems + 1L
  cat(if (ok) "  ok   " else "  DRIFT", line, "\n", sep = "")
}

cat("vendored rows\n")
for (row in prov$files) {
  path <- file.path(here, row$file)
  got <- sha256_file(path)
  report(identical(got, row$sha256), sprintf(
    "%s%s", row$file,
    if (identical(got, row$sha256)) "" else paste0(" recorded ", substr(row$sha256, 1, 16),
                                                   " found ", substr(got %||% "missing", 1, 16))
  ))
}

audit_suite <- function(title, dir, want) {
  cat(title, "\n")
  listed <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  listed <- setdiff(listed, "pax_global_header")
  missing <- setdiff(names(want$per_file), listed)
  extra <- setdiff(listed, names(want$per_file))
  report(length(missing) == 0L, paste0("files present (", length(listed), " of ",
                                       want$files, ")",
    if (length(missing)) paste0(" missing: ", paste(head(missing, 5), collapse = ", ")) else ""
  ))
  report(length(extra) == 0L, paste0("no unrecorded files",
    if (length(extra)) paste0(" extra: ", paste(head(extra, 5), collapse = ", ")) else ""
  ))
  drifted <- character()
  for (nm in names(want$per_file)) {
    got <- sha256_file(file.path(dir, nm))
    if (!identical(got, want$per_file[[nm]])) drifted <- c(drifted, nm)
  }
  report(length(drifted) == 0L, paste0("per-file digests",
    if (length(drifted)) paste0(" drifted: ", paste(head(drifted, 5), collapse = ", ")) else ""
  ))
  man_sha <- sha256_file(file.path(dir, "manifest.json"))
  report(identical(man_sha, want$manifest_sha256), paste0(
    "manifest.json ", substr(man_sha %||% "missing", 1, 16), " recorded ",
    substr(want$manifest_sha256, 1, 16)
  ))
  manifest <- jsonlite::fromJSON(file.path(dir, "manifest.json"), simplifyVector = FALSE)
  report(length(manifest$vectors) == want$vectors, paste0(
    "vector count ", length(manifest$vectors), " recorded ", want$vectors
  ))
  if (!is.null(want$by_format)) {
    fmts <- as.list(sort(table(unlist(lapply(manifest$vectors, function(v) v$format)))))
    want_fmts <- as.list(sort(unlist(want$by_format)))
    report(identical(fmts, want_fmts), paste0("vectors per format: ",
      paste(sprintf("%s=%s", names(fmts), unlist(fmts)), collapse = " ")))
  }
}

audit_suite("shared conformance suite", file.path(here, "tests/conformance"),
  prov$conformance
)
if (!is.null(prov$draft_vectors)) {
  audit_suite("FHT development suite (draft evidence)",
    file.path(here, sub("^tests/", "tests/", prov$draft_vectors$dest)),
    prov$draft_vectors
  )
}

if (flag("--fresh")) {
  cat("draft-pin freshness (live default branch)\n")
  repos <- list(
    FHT = arg("--fht"), FHGM = arg("--fhgm")
  )
  for (nm in names(repos)) {
    repo <- repos[[nm]]
    if (is.null(repo)) {
      report(FALSE, paste0(nm, ": no --", tolower(nm), " checkout given"))
      next
    }
    row <- Filter(function(r) identical(r$header_type, nm), prov$files)
    if (!length(row)) {
      report(FALSE, paste0(nm, ": no draft row is registered in inst/VENDORED.json"))
      next
    }
    row <- row[[1]]
    st <- system2("git", c("-C", shQuote(repo), "fetch", "--quiet", "origin"),
      stdout = TRUE, stderr = TRUE
    )
    if (!is.null(attr(st, "status")) && attr(st, "status") != 0) {
      report(FALSE, paste0(nm, ": git fetch failed: ", paste(st, collapse = " ")))
      next
    }
    head <- system2("git", c("-C", shQuote(repo), "rev-parse", "origin/main"), stdout = TRUE)
    tmp <- tempfile()
    st2 <- system2("/bin/sh", c("-c", shQuote(paste(
      "git", shQuote("-C"), shQuote(repo), "show",
      shQuote(paste0("origin/main:", row$source_path)), ">", shQuote(tmp)
    ))), stdout = TRUE, stderr = TRUE)
    got <- sha256_file(tmp)
    unlink(tmp)
    same <- identical(got, row$sha256)
    report(same, paste0(
      nm, " pinned ", substr(row$commit, 1, 10), " head ", substr(head, 1, 10),
      if (same) " unchanged" else paste0(" MOVED: live sha256 ", substr(got %||% "?", 1, 16),
                                         " != pinned ", substr(row$sha256, 1, 16))
    ))
    if (!is.null(attr(st2, "status")) && attr(st2, "status") != 0) {
      report(FALSE, paste0(nm, ": could not read origin/main:", row$source_path))
    }
  }
}

if (problems > 0L) {
  cat("\n", problems, "problem(s); re-vendor with tools/vendor_upstream.R only after\n",
      "reading what moved - a provenance mismatch is a finding, not a step to erase.\n",
      sep = "")
  quit(status = 1L)
}
cat("\nvendored data matches its provenance\n")
