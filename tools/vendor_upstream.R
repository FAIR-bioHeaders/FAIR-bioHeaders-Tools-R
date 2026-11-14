#!/usr/bin/env Rscript
#' Re-vendor the upstream data this package ships, and rewrite its provenance.
#'
#' What lands in this repository, and why:
#'
#'   inst/schemas/     one frozen copy per contract version the selection rules can
#'                     name (docs/SCHEMA-VERSIONS.md V1-V6), plus the release registry.
#'                     Readers validate against these bytes; nothing is fetched at run
#'                     time, and a released copy is never edited here.
#'   tests/conformance/ a byte-for-byte copy of the shared conformance suite at the
#'                     pinned release. The vector bytes are normative upstream material
#'                     - FAIR-bioHeaders-Specification scripts/make_conformance.py
#'                     generates them - and an implementation adapts to them, never the
#'                     other way round. They are vendored rather than downloaded so the
#'                     acceptance run cannot quietly shrink to zero vectors on a machine
#'                     without a network or a second checkout, and they live under
#'                     tests/ rather than inst/ because they are test data: R CMD check
#'                     runs them, the installed package does not carry them.
#'   inst/drafts/      the rule V7 draft bytes, opt-in only, pinned by commit and
#'                     SHA-256. A draft is not a released contract and is never selected
#'                     unless the caller asks for the lane.
#'
#' Usage, from the package root with the sibling checkouts present:
#'
#'   Rscript tools/vendor_upstream.R --source ../FAIR-bioHeaders-Specification \
#'       --fht ../FHT-Specification --fhgm ../FHGM
#'
#' Bytes come from `git show <rev>:<path>`, so a tag or commit is vendored rather than
#' whatever a working tree happens to hold. Verification of what is on disk is
#' tools/check_vendoring.R; this script writes, that one audits.

`%||%` <- function(a, b) if (is.null(a)) b else a

.options <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default = NULL) {
  i <- match(name, .options)
  if (is.na(i)) default else .options[i + 1L]
}

spec <- normalizePath(arg("--source", stopifnot(FALSE) || "."), mustWork = FALSE)
fht_repo <- arg("--fht")
fhgm_repo <- arg("--fhgm")
if (is.null(fht_repo) || is.null(fhgm_repo)) {
  stop(paste0(
    "usage: Rscript tools/vendor_upstream.R --source <FAIR-bioHeaders-Specification> ",
    "--fht <FHT-Specification> --fhgm <FHGM-Specification>"
  ))
}
fht_repo <- normalizePath(fht_repo)
fhgm_repo <- normalizePath(fhgm_repo)
here <- normalizePath(".")

if (!requireNamespace("digest", quietly = TRUE)) {
  stop("the digest package is required to record SHA-256 provenance")
}
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("the jsonlite package is required to write the provenance file")
}

sha256_bytes <- function(bytes) digest::digest(bytes, algo = "sha256", serialize = FALSE)

# Byte-exact extraction of one file at one revision. A binary pipe is used rather than
# system2(stdout = <file>) because R replaces an unusable stdout target with TRUE and
# the result is a 0-byte file that would then be vendored as "the contract".
git_show <- function(repo, ref, path) {
  cmd <- paste("git", shQuote("-C"), shQuote(repo), "show",
               shQuote(paste0(ref, ":", path)))
  con <- pipe(cmd, open = "rb")
  on.exit(close(con), add = TRUE)
  out <- raw()
  repeat {
    b <- readBin(con, what = "raw", n = 1048576L)
    if (!length(b)) break
    out <- c(out, b)
  }
  if (length(out) == 0L) {
    stop("git show ", ref, ":", path, " in ", repo, " produced no bytes")
  }
  out
}

git_out <- function(repo, args) {
  out <- system2("git", c("-C", shQuote(repo), args), stdout = TRUE)
  if (length(out) != 1L || !nzchar(out[[1]])) {
    stop("git ", paste(args, collapse = " "), " in ", repo, " returned: ", paste(out, collapse = " "))
  }
  out[[1]]
}

write_bytes <- function(path, bytes) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- file(path, "wb")
  on.exit(close(con), add = TRUE)
  writeBin(bytes, con)
  invisible(bytes)
}

rows <- list()
vendored_file <- function(dest, repo, ref, path, kind, extra = list()) {
  bytes <- git_show(repo, ref, path)
  row <- c(
    list(
      file = dest, repository = git_out(repo, c("remote", "get-url", "origin")),
      ref = ref, commit = git_out(repo, c("rev-parse", ref)),
      source_path = path, sha256 = sha256_bytes(bytes), bytes = length(bytes), kind = kind
    ),
    extra
  )
  write_bytes(file.path(here, dest), unlist(bytes, use.names = FALSE))
  rows[[length(rows) + 1L]] <<- row
  cat(sprintf("  %-42s %s %7d\n", dest, substr(row$sha256, 1, 16), row$bytes))
  invisible(row)
}

cat("released contracts and the version registry\n")
contracts <- list(
  c(tag = "v0.3.1", type = "fhr", name = "fhr-1.json"),
  c(tag = "v0.4.0", type = "fhr", name = "fhr-2.0.json"),
  c(tag = "v0.5.0", type = "fhr", name = "fhr-2.1.json"),
  c(tag = "v0.4.0", type = "fhp", name = "fhp-1.0.json"),
  c(tag = "v0.5.0", type = "fhp", name = "fhp-1.1.json"),
  c(tag = "v0.6.0", type = "fhp", name = "fhp-1.2.json"),
  c(tag = "v0.4.0", type = "fhgff3", name = "fhgff3-1.0.json"),
  c(tag = "v0.5.0", type = "fhgff3", name = "fhgff3-1.1.json"),
  c(tag = "v0.6.0", type = "fhgff3", name = "fhgff3-1.2.json")
)
for (r in contracts) {
  vendored_file(
    file.path("inst/schemas", r[["name"]]), spec, r[["tag"]],
    paste0(r[["type"]], ".json"), "released-contract",
    list(header_type = toupper(r[["type"]]), schema_version = sub("^[a-z0-9]+-([0-9.]+)\\.json$", "\\1", r[["name"]]))
  )
}
vendored_file("inst/schemas/versions.json", spec, "v0.6.0", "schemas/versions.json",
  "version-registry", list(release = "v0.6.0")
)

cat("draft contracts (rule V7, opt-in only)\n")
# The pinned commit is the commit that last touched the file, because that is whose
# bytes these are; the default-branch head at retrieval is recorded with it so the
# freshness check in tools/check_vendoring.R can tell "unchanged" from "moved".
fhgm_path <- "development/model/fhgm-model.schema.json"
fht_commit <- git_out(fht_repo, c("log", "-1", "--format=%H", "origin/main", "--", "fht.json"))
vendored_file("inst/drafts/fht-draft.json", fht_repo, fht_commit, "fht.json", "draft-contract",
  list(
    header_type = "FHT", citation = "https://raw.githubusercontent.com/FAIR-bioHeaders/FHT-Specification/main/fht.json",
    head_at_retrieval = git_out(fht_repo, c("rev-parse", "origin/main")),
    status = "draft; no released contract, no schemaVersion, no registry row, no w3id URL"
  )
)
fhgm_commit <- git_out(fhgm_repo, c("log", "-1", "--format=%H", "origin/main", "--", fhgm_path))
vendored_file("inst/drafts/fhgm-model-draft.schema.json", fhgm_repo, fhgm_commit, fhgm_path,
  "draft-contract",
  list(
    header_type = "FHGM",
    citation = paste0(
      "https://raw.githubusercontent.com/FAIR-bioHeaders/FHGM-Specification/main/", fhgm_path
    ),
    head_at_retrieval = git_out(fhgm_repo, c("rev-parse", "origin/main")),
    status = paste0(
      "draft; FHGM is not a header type - these records are model records transported ",
      "inside an FHGFF3 header under x-fhgm-models, and they carry no schema of their own"
    )
  )
)

cat("draft vectors (FHT-Specification, development suite, labelled as such upstream)\n")
# These are NOT part of the 291. The FHT manifest's own status field says the expectations
# are "derived from the rule text, never from an implementation under test", so the results
# they produce are draft evidence and are reported separately by bh_draft_vectors().
unlink(file.path(here, "tests", "draft", "fht"), recursive = TRUE)
dcmd <- paste("git", shQuote("-C"), shQuote(fht_repo),
              "archive --format=tar origin/main conformance >", shQuote(tar <- tempfile()))
dst <- system2("/bin/sh", c("-c", shQuote(dcmd)), stdout = TRUE, stderr = TRUE)
if (!is.null(attr(dst, "status")) && attr(dst, "status") != 0) {
  stop("git archive of the FHT draft vectors failed: ", paste(dst, collapse = " "))
}
tmp <- tempfile("fhtraw")
dir.create(tmp)
system2("tar", c("-xf", shQuote(tar), "-C", shQuote(tmp)))
unlink(tar)
# the archive's own directory is conformance/; the destination names the type that owns
# these bytes, so the draft set cannot be mistaken for the shared suite
dest <- file.path(here, "tests", "draft")
unlink(dest, recursive = TRUE) # a stale layout from an interrupted run must not survive
if (!dir.exists(file.path(tmp, "conformance"))) {
  stop("unexpected FHT archive layout: no conformance/ directory")
}
invisible(dir.create(dest, showWarnings = FALSE, recursive = TRUE))
dfh <- file.path(dest, "fht")
unlink(dfh, recursive = TRUE)
file.rename(file.path(tmp, "conformance"), dfh)
unlink(tmp, recursive = TRUE)
if (!file.exists(file.path(dfh, "manifest.json"))) {
  stop("the FHT draft vectors did not land at ", dfh)
}
dfiles <- list.files(dfh, recursive = TRUE, all.files = TRUE, no.. = TRUE)
dsizes <- file.info(file.path(dfh, dfiles))$size
dper <- vapply(seq_along(dfiles), function(i) {
  sha256_bytes(readBin(file.path(dfh, dfiles[[i]]), what = "raw", n = dsizes[[i]]))
}, "")
names(dper) <- dfiles
dper <- dper[order(names(dper))]
dman <- jsonlite::fromJSON(file.path(dfh, "manifest.json"), simplifyVector = FALSE)
cat(sprintf("  %d files, manifest %s, %d vectors (status: %s)\n", length(dper),
            substr(unname(dper[["manifest.json"]]), 1, 16), length(dman$vectors),
            substr(unlist(dman$status), 1, 40)))

cat("FHGM draft vectors (FHGM-Specification development suite, layered expectations)\n")
# Published by the FHGM development repository, not by the shared specification: 31 vectors
# whose manifest records what four independent checks report (base schema, checksum, gff3
# feature layer, model layer). They are draft evidence and are never counted toward the 291.
fhgm_conformance_path <- "development/conformance"
unlink(file.path(here, "tests", "draft", "fhgm"), recursive = TRUE)
tmpg <- tempfile("fhgmraw")
dir.create(tmpg)
gcmd <- paste("git", shQuote("-C"), shQuote(fhgm_repo), "archive --format=tar origin/main",
              fhgm_conformance_path, ">", shQuote(tar <- tempfile()))
gst <- system2("/bin/sh", c("-c", shQuote(gcmd)), stdout = TRUE, stderr = TRUE)
if (!is.null(attr(gst, "status")) && attr(gst, "status") != 0) {
  stop("git archive of the FHGM draft vectors failed: ", paste(gst, collapse = " "))
}
system2("tar", c("-xf", shQuote(tar), "-C", shQuote(tmpg)))
unlink(tar)
if (!dir.exists(file.path(tmpg, fhgm_conformance_path))) {
  stop("unexpected FHGM archive layout")
}
invisible(dir.create(file.path(here, "tests", "draft"), showWarnings = FALSE, recursive = TRUE))
gdest <- file.path(here, "tests", "draft", "fhgm")
file.rename(file.path(tmpg, fhgm_conformance_path), gdest)
unlink(tmpg, recursive = TRUE)
# Several vectors cite example files one level up (../examples/model/snapshot-v1.fhgff3.gff3
# and friends), so those bytes are vendored alongside, at the path the citations resolve to.
unlink(file.path(here, "tests", "draft", "examples"), recursive = TRUE)
tmpg2 <- tempfile("fhgmex")
dir.create(tmpg2)
ecmd <- paste("git", shQuote("-C"), shQuote(fhgm_repo),
              "archive --format=tar origin/main development/examples >", shQuote(tar2 <- tempfile()))
est <- system2("/bin/sh", c("-c", shQuote(ecmd)), stdout = TRUE, stderr = TRUE)
if (!is.null(attr(est, "status")) && attr(est, "status") != 0) {
  stop("git archive of the FHGM examples failed: ", paste(est, collapse = " "))
}
system2("tar", c("-xf", shQuote(tar2), "-C", shQuote(tmpg2)))
unlink(tar2)
invisible(file.rename(file.path(tmpg2, "development", "examples"),
                      file.path(here, "tests", "draft", "examples")))
unlink(tmpg2, recursive = TRUE)
exfiles <- list.files(file.path(here, "tests", "draft", "examples"), recursive = TRUE,
                      all.files = TRUE, no.. = TRUE)
exkeep <- exfiles[!grepl("[.]py$", exfiles)]
exdrop <- c(exfiles[grepl("[.]py$", exfiles)],
            paste0("conformance/", list.files(gdest, pattern = "[.]py$", recursive = TRUE)))
exper <- vapply(exkeep, function(f) {
  sha256_bytes(readBin(file.path(here, "tests", "draft", "examples", f), what = "raw",
                       n = file.info(file.path(here, "tests", "draft", "examples", f))$size))
}, "")
cat(sprintf("  %d example files vendored, %d generator scripts left upstream\n",
            length(exper), length(exdrop)))
# drop the owning repository's tooling from the vendored copy: this package reads data,
# and leaving their scripts here would invite someone to run or edit them
unlink(list.files(gdest, pattern = "[.]py$", recursive = TRUE, full.names = TRUE))
unlink(list.files(file.path(here, "tests", "draft", "examples"), pattern = "[.]py$",
  recursive = TRUE, full.names = TRUE
))
gfiles <- list.files(gdest, recursive = TRUE, all.files = TRUE, no.. = TRUE)
# the upstream wrapper files are the owning repo's tooling, not data this package reads
keep <- !grepl("[.]py$", gfiles)
dropped <- c(gfiles[!keep], paste0("examples/", exdrop))
gfiles <- gfiles[keep]
gsizes <- file.info(file.path(gdest, gfiles))$size
gper <- vapply(seq_along(gfiles), function(i) {
  sha256_bytes(readBin(file.path(gdest, gfiles[[i]]), what = "raw", n = gsizes[[i]]))
}, "")
names(gper) <- gfiles
gper <- gper[order(names(gper))]
gman <- jsonlite::fromJSON(file.path(gdest, "manifest.json"), simplifyVector = FALSE)
cat(sprintf("  %d files (%d generator/checker scripts not vendored), manifest %s, %d vectors\n",
            length(gper), length(dropped), substr(unname(gper[["manifest.json"]]), 1, 16),
            length(gman$vectors)))

cat("shared conformance suite\n")
unlink(file.path(here, "tests/conformance"), recursive = TRUE)
# The archive goes through a shell redirect: R replaces an unusable system2 stdout
# target with TRUE, which would have streamed the tar to the console and left an empty
# file to be "extracted".
tar <- tempfile(fileext = ".tar")
cmd <- paste("git", shQuote("-C"), shQuote(spec),
             "archive --format=tar v0.6.0 conformance >", shQuote(tar))
st <- system2("/bin/sh", c("-c", shQuote(cmd)), stdout = TRUE, stderr = TRUE)
if (!is.null(attr(st, "status")) && attr(st, "status") != 0) {
  stop("git archive failed: ", paste(st, collapse = " "))
}
if (is.na(file.info(tar)$size) || file.info(tar)$size < 1) {
  stop("git archive produced an empty tar")
}
system2("tar", c("-xf", shQuote(tar), "-C", shQuote(file.path(here, "tests"))))
unlink(tar)
suite <- file.path(here, "tests/conformance")
files <- list.files(suite, recursive = TRUE, all.files = TRUE, no.. = TRUE)
sizes <- file.info(file.path(suite, files))$size
per_file <- vapply(seq_along(files), function(i) {
  sha256_bytes(readBin(file.path(suite, files[[i]]), what = "raw", n = sizes[[i]]))
}, "")
names(per_file) <- files
per_file <- per_file[order(names(per_file))]
manifest <- jsonlite::fromJSON(file.path(suite, "manifest.json"), simplifyVector = FALSE)
combined <- sha256_bytes(charToRaw(paste(sprintf("%s %s", names(per_file), unname(per_file)),
                                           collapse = "\n")))
cat(sprintf("  %d files, manifest %s, combined %s, %d vectors\n",
            length(per_file), substr(unname(per_file[["manifest.json"]]), 1, 16),
            substr(combined, 1, 16), length(manifest$vectors)))

prov <- list(
  description = paste(
    "Byte-for-byte copies of upstream FAIR-bioHeaders data, vendored from tagged",
    "releases and pinned commits of the owning repositories. Never edited here: a new",
    "release or a moved draft means a new vendored file plus a provenance row,",
    "produced by tools/vendor_upstream.R and audited by tools/check_vendoring.R.",
    "The draft rows exist for the rule V7 opt-in lane only."
  ),
  digests = "SHA-256 of the exact bytes stored at `file`. The FAIR-bioHeaders file checksum is SHA-512/256 and is computed by this package's vendored core; SHA-256 here is the family's pinning digest for copied files, a different job.",
  vendored = format(Sys.time(), "%Y-%m-%d"),
  released_baseline = "v0.6.0",
  files = rows,
  draft_vectors = list(
    header_type = "FHT", repository = git_out(fht_repo, c("remote", "get-url", "origin")),
    ref = "origin/main", commit = git_out(fht_repo, c("rev-parse", "origin/main")),
    path = "conformance", dest = "tests/draft/fht", files = length(dper),
    manifest_sha256 = unname(dper[["manifest.json"]]),
    combined_sha256 = sha256_bytes(charToRaw(paste(sprintf("%s %s", names(dper), unname(dper)),
                                                   collapse = "\n"))),
    vectors = length(dman$vectors), status = dman$status,
    note = "development vectors, not part of the 291; expectations derived from rule text upstream",
    per_file = setNames(as.list(unname(dper)), names(dper))
  ),
  draft_fhgm_vectors = list(
    header_type = "FHGM", transport_type = "FHGFF3",
    repository = git_out(fhgm_repo, c("remote", "get-url", "origin")),
    ref = "origin/main",
    commit = git_out(fhgm_repo, c("log", "-1", "--format=%H", "origin/main", "--",
                                  "development/conformance/manifest.json")),
    head_at_retrieval = git_out(fhgm_repo, c("rev-parse", "origin/main")),
    path = fhgm_conformance_path, dest = "tests/draft/fhgm", files = length(gper),
    not_vendored = dropped,
    manifest_sha256 = unname(gper[["manifest.json"]]),
    combined_sha256 = sha256_bytes(charToRaw(paste(sprintf("%s %s", names(gper), unname(gper)),
                                                   collapse = "\n"))),
    vectors = length(gman$vectors), status = gman$status,
    examples_dir = "tests/draft/examples", examples = length(exper),
    examples_sha256 = setNames(as.list(unname(exper[order(names(exper))])), names(exper[order(names(exper))])),
    note = paste0(
      "draft evidence, not part of the 291. Layers are recorded per vector: base (the ",
      "released fhgff3.json contract over the parsed header), checksum, gff3 (a separate ",
      "tool; every vector is recorded as accept) and model (the draft checker). This ",
      "package can report base, checksum and model-schema; the model checker's own ",
      "cross-record rules and the gff3 layer are not implemented here."
    ),
    per_file = setNames(as.list(unname(gper)), names(gper))
  ),
  conformance = list(
    repository = git_out(spec, c("remote", "get-url", "origin")),
    ref = "v0.6.0", commit = git_out(spec, c("rev-parse", "v0.6.0")),
    path = "conformance", files = length(per_file),
    manifest_sha256 = unname(per_file[["manifest.json"]]),
    combined_sha256 = combined,
    vectors = length(manifest$vectors),
    by_format = as.list(sort(table(unlist(lapply(manifest$vectors, function(v) v$format))))),
    per_file = setNames(as.list(unname(per_file)), names(per_file))
  )
)
writeLines(
  jsonlite::toJSON(prov, auto_unbox = TRUE, pretty = 2, null = "null"),
  file.path(here, "inst/VENDORED.json")
)
cat("wrote inst/VENDORED.json\n")
