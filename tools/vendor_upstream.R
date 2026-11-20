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

source("tools/vendor_tree.R")

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

# The record being replaced, read before anything is written. A re-pin that overwrote the
# previous pin's numbers in place would leave a reader unable to say what moved without
# the git history; the replaced values are carried into the new record under `previous`,
# the pattern the Java library's suitePinAnnotation established. Rotation happens ONLY on
# a genuine change - decided by comparing the resolved digests, never the date the run
# happens on: an unchanged rerun must carry the existing `previous` forward untouched, or
# the audit trail would restate itself into fiction (the superseded pin would read as the
# current one, and a later real move would lose its predecessor). This is the same defect
# class as a pin-currency note that restates rather than records.
prev_file <- file.path(here, "inst", "VENDORED.json")
prev <- if (file.exists(prev_file)) {
  jsonlite::fromJSON(prev_file, simplifyVector = FALSE)
} else {
  list()
}
prev_contract <- function(type) {
  hit <- Filter(function(r) {
    identical(r$header_type, type) && identical(r$kind, "draft-contract")
  }, prev$files %||% list())
  if (!length(hit)) return(NULL)
  hit[[1L]]
}
rotate_contract <- function(type, sha, commit, bytes, head) {
  old <- prev_contract(type)
  if (is.null(old)) return(NULL) # nothing recorded yet; there is no predecessor to name
  if (identical(old$sha256, sha)) {
    return(old$previous) # unchanged bytes: keep the real predecessor, do not restate it
  }
  list(ref = old$ref, commit = old$commit, sha256 = old$sha256, bytes = old$bytes,
    head_at_retrieval = old$head_at_retrieval,
    vendored_on = prev$vendored %||% old$vendored_on
  )
}
rotate_suite <- function(key, manifest_sha, combined_sha, files, vectors, commit) {
  p <- prev[[key]]
  if (is.null(p)) return(NULL)
  if (identical(p$manifest_sha256, manifest_sha) &&
      identical(p$combined_sha256, combined_sha)) {
    return(p$previous)
  }
  list(commit = p$commit, head_at_retrieval = p$head_at_retrieval,
    manifest_sha256 = p$manifest_sha256, combined_sha256 = p$combined_sha256,
    files = p$files, vectors = p$vectors,
    vendored_on = prev$vendored %||% p$vendored_on
  )
}

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
    status = "draft; no released contract, no schemaVersion, no registry row, no w3id URL",
    retrieved_by = paste0("Rscript tools/vendor_upstream.R; bytes from `git show ",
      substr(fht_commit, 1, 8), ":fht.json` in the FHT-Specification checkout")
  )
)
# `previous` is resolved AFTER the row exists, from the row's own fresh digest, so an
# unchanged rerun carries the real predecessor forward instead of restating the current
# pin as its own parent.
rows[[length(rows)]]$previous <- rotate_contract(
  "FHT", rows[[length(rows)]]$sha256, rows[[length(rows)]]$commit,
  rows[[length(rows)]]$bytes, rows[[length(rows)]]$head_at_retrieval
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
    ),
    retrieved_by = paste0("Rscript tools/vendor_upstream.R; bytes from `git show ",
      substr(fhgm_commit, 1, 8), ":", fhgm_path, "` in the FHGM-Specification checkout")
  )
)
rows[[length(rows)]]$previous <- rotate_contract(
  "FHGM", rows[[length(rows)]]$sha256, rows[[length(rows)]]$commit,
  rows[[length(rows)]]$bytes, rows[[length(rows)]]$head_at_retrieval
)

cat("draft vectors (FHT-Specification, development suite, labelled as such upstream)\n")
# These are NOT part of the 291. The FHT manifest's own status field says the expectations
# are "derived from the rule text, never from an implementation under test", so the results
# they produce are draft evidence and are reported separately by bh_draft_vectors().
dcmd <- paste("git", shQuote("-C"), shQuote(fht_repo),
              "archive --format=tar origin/main conformance >", shQuote(tar <- tempfile()))
dst <- system2("/bin/sh", c("-c", shQuote(dcmd)), stdout = TRUE, stderr = TRUE)
if (!is.null(attr(dst, "status")) && attr(dst, "status") != 0) {
  stop("git archive of the FHT draft vectors failed: ", paste(dst, collapse = " "))
}
tmp <- tempfile("fhtraw")
dir.create(tmp)
if (system2("tar", c("-xf", shQuote(tar), "-C", shQuote(tmp))) != 0L) stop("FHT archive extraction failed")
unlink(tar)
# the archive's own directory is conformance/; the destination names the type that owns
# these bytes, so the draft set cannot be mistaken for the shared suite
dest <- file.path(here, "tests", "draft")
if (!dir.exists(file.path(tmp, "conformance"))) {
  stop("unexpected FHT archive layout: no conformance/ directory")
}
dir.create(dest, showWarnings = FALSE, recursive = TRUE)
dfh <- file.path(dest, "fht")
replace_vendor_tree(file.path(tmp, "conformance"), dfh)
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
dper <- dper[sort(names(dper))] # the record's key order: locale sort
dman <- jsonlite::fromJSON(file.path(dfh, "manifest.json"), simplifyVector = FALSE)
fcommit <- git_out(fht_repo, c("log", "-1", "--format=%H", "origin/main", "--",
                               "conformance/manifest.json"))
# the combined digest is computed once and used for both the record and the rotation
# decision, so the two can never be compared against different values
dcombined <- sha256_bytes(charToRaw(paste(sprintf("%s %s", names(dper), unname(dper)),
                                          collapse = "\n")))
# how many vectors are still promotion=candidate-unreviewed at this pin - counted from
# the manifest bytes, never carried forward from the last pin's prose
fht_unreviewed <- sum(vapply(dman$vectors, function(v) {
  identical(v$promotion, "candidate-unreviewed")
}, logical(1L)))
cat(sprintf("  %d files, manifest %s, %d vectors (%d promotion=candidate-unreviewed, status: %s)\n",
            length(dper), substr(unname(dper[["manifest.json"]]), 1, 16), length(dman$vectors),
            fht_unreviewed, substr(unlist(dman$status), 1, 40)))

cat("FHGM draft vectors (FHGM-Specification development suite, layered expectations)\n")
# Published by the FHGM development repository, not by the shared specification: a suite
# whose manifest records what four independent checks report (base schema, checksum, gff3
# feature layer, model layer), at whatever count the pinned revision carries. It is draft
# evidence and is never counted toward the 291.
# The bytes come from `git archive origin/main` of the owning repository, so a revision is
# vendored rather than whatever a working tree happens to hold.
fhgm_conformance_path <- "development/conformance"
fhgm_examples_path <- "development/examples"
gdest <- file.path(here, "tests", "draft", "fhgm")
edest <- file.path(here, "tests", "draft", "examples")

archive_subtree <- function(sub, target) {
  t <- tempfile(fileext = ".tar")
  c1 <- paste("git", shQuote("-C"), shQuote(fhgm_repo),
              "archive --format=tar origin/main", sub, ">", shQuote(t))
  s1 <- system2("/bin/sh", c("-c", shQuote(c1)), stdout = TRUE, stderr = TRUE)
  if (!is.null(attr(s1, "status")) && attr(s1, "status") != 0) {
    stop("git archive of FHGM ", sub, " failed: ", paste(s1, collapse = " "))
  }
  u <- tempfile("fhgmr")
  dir.create(u)
  if (system2("tar", c("-xf", shQuote(t), "-C", shQuote(u))) != 0L) stop("FHGM archive extraction failed")
  unlink(t)
  if (!dir.exists(file.path(u, sub))) stop("unexpected FHGM archive layout for ", sub)
  dir.create(dirname(target), showWarnings = FALSE, recursive = TRUE)
  replace_vendor_tree(file.path(u, sub), target)
  unlink(u, recursive = TRUE)
  invisible(target)
}
archive_subtree(fhgm_conformance_path, gdest)
# Several vectors cite example files one level up (../examples/model/snapshot-v1.fhgff3.gff3
# and friends), so those bytes are vendored alongside, at the path the citations resolve to.
archive_subtree(fhgm_examples_path, edest)
if (!file.exists(file.path(gdest, "manifest.json"))) stop("the FHGM suite did not land at ", gdest)

# The owning repository's generator and checker scripts are not data this package reads;
# they stay upstream rather than being carried here to be run or edited.
drop_scripts <- function(dir) {
  py <- list.files(dir, pattern = "[.]py$", recursive = TRUE)
  unlink(file.path(dir, py))
  py
}
dropped_g <- paste0("conformance/", drop_scripts(gdest))
dropped_e <- paste0("examples/", drop_scripts(edest))

sha_tree <- function(dir) {
  fs <- list.files(dir, recursive = TRUE, all.files = TRUE, no.. = TRUE)
  szs <- file.info(file.path(dir, fs))$size
  out <- vapply(seq_along(fs), function(i) {
    sha256_bytes(readBin(file.path(dir, fs[[i]]), what = "raw", n = szs[[i]]))
  }, "")
  names(out) <- fs
  out[order(names(out))]
}
gper <- sha_tree(gdest)
esper <- sha_tree(edest)
gman <- jsonlite::fromJSON(file.path(gdest, "manifest.json"), simplifyVector = FALSE)
# the revision of the data that was vendored, which is not necessarily the tip of main
gcommit <- git_out(fhgm_repo, c("log", "-1", "--format=%H", "origin/main", "--",
                                paste0(fhgm_conformance_path, "/manifest.json")))
gcombined <- sha256_bytes(charToRaw(paste(sprintf("%s %s", names(gper), unname(gper)),
                                          collapse = "\n")))
cat(sprintf("  %d suite files + %d example files, %d upstream scripts left behind, manifest %s, %d vectors\n",
            length(gper), length(esper), length(dropped_g) + length(dropped_e),
            substr(unname(gper[["manifest.json"]]), 1, 16), length(gman$vectors)))

cat("shared conformance suite\n")
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
shared_stage <- tempfile("shared-suite-")
dir.create(shared_stage)
if (system2("tar", c("-xf", shQuote(tar), "-C", shQuote(shared_stage))) != 0L) {
  stop("shared conformance archive extraction failed")
}
if (!file.exists(file.path(shared_stage, "conformance", "manifest.json"))) {
  stop("unexpected shared conformance archive layout")
}
replace_vendor_tree(file.path(shared_stage, "conformance"), file.path(here, "tests/conformance"))
unlink(shared_stage, recursive = TRUE)
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
  commit_field = paste(
    "For released-contract rows this records the annotated tag OBJECT SHA of the ref",
    "(e.g. v0.6.0's tag object ab7e3ddd53bfccee9a31d59fc10524eadf32c1da, which",
    "dereferences to commit 0ae18b00ee4bd71ab2dc28bae706b0f9d195076b); byte identity",
    "was verified against the dereferenced tag. Draft rows record ordinary commit SHAs."
  ),
  vendored = format(Sys.time(), "%Y-%m-%d"),
  released_baseline = "v0.6.0",
  files = rows,
  draft_vectors = list(
    header_type = "FHT", repository = git_out(fht_repo, c("remote", "get-url", "origin")),
    ref = "origin/main",
    # The suite pin is the revision of the SUITE, taken from the commit that last touched
    # its manifest, and it is deliberately not the contract pin: the contract row above is
    # the commit that last touched fht.json, and the two move independently. Pointing the
    # suite at the branch head instead would let a commit that touches neither the manifest
    # nor a vector read as a suite change.
    commit = fcommit,
    head_at_retrieval = git_out(fht_repo, c("rev-parse", "origin/main")),
    path = "conformance", dest = "tests/draft/fht", files = length(dper),
    manifest_sha256 = unname(dper[["manifest.json"]]),
    combined_sha256 = dcombined,
    vectors = length(dman$vectors), status = dman$status,
    candidates_unreviewed = fht_unreviewed,
    note = paste0(
      "development vectors, not part of the 291; expectations derived from rule text ",
      "upstream; ", fht_unreviewed, " vectors are marked promotion=candidate-unreviewed ",
      "at this pin and are presented as unreviewed, never as reviewed"
    ),
    previous = rotate_suite("draft_vectors",
      unname(dper[["manifest.json"]]), dcombined,
      length(dper), length(dman$vectors), fcommit),
    per_file = setNames(as.list(unname(dper)), names(dper))
  ),
  draft_fhgm_vectors = list(
    header_type = "FHGM", transport_type = "FHGFF3",
    repository = git_out(fhgm_repo, c("remote", "get-url", "origin")),
    ref = "origin/main",
    commit = gcommit,
    head_at_retrieval = git_out(fhgm_repo, c("rev-parse", "origin/main")),
    path = fhgm_conformance_path, dest = "tests/draft/fhgm", files = length(gper),
    not_vendored = c(dropped_g, dropped_e),
    not_vendored_note = paste0(
      "paths relative to development/ in the owning repository: the upstream generator and ",
      "checker scripts stay there, this package vendors data only"
    ),
    manifest_sha256 = unname(gper[["manifest.json"]]),
    combined_sha256 = gcombined,
    vectors = length(gman$vectors), status = gman$status,
    examples_dir = "tests/draft/examples", examples = length(esper),
    examples_sha256 = setNames(as.list(unname(esper)), names(esper)),
    note = paste0(
      "draft evidence, not part of the 291. Layers are recorded per vector: base (the ",
      "released fhgff3.json contract over the parsed header), checksum, gff3 (a separate ",
      "tool; every vector is recorded as accept) and model (the draft checker). This ",
      "package reports base, checksum and the K1/K2 model layer natively; the checker's ",
      "cross-record rules K3-K6 and the gff3 layer are not implemented here and their ",
      "vectors are reported not-run with the rule named. LIMITATION, stated not implied: ",
      "the pinned record-contract bytes encode a widened layers.model semantics - a pass ",
      "additionally implies trimmed, invisible-character-free text, RFC 3986 schemes with ",
      "a real host, non-blank deposits, NFC-unique identifiers and a root-level gene ",
      "target - which upstream records in development/conformance/LAYER-SEMANTICS-PROPOSAL.",
      "md as proposed, not adopted (FHGM-Specification#22, #27 and #28 remain open ",
      "decisions). That proposal file is vendored only because this suite mirrors the ",
      "whole upstream non-script conformance subtree; its presence here is not adoption ",
      "by this package. K4 abstention is unresolved upstream, and K4 stays not-supported-",
      "yet here by design: this package does not implement the GFF3 feature layer and ",
      "reports every K4 vector not-run rather than inheriting a contested verdict."
    ),
    previous = rotate_suite("draft_fhgm_vectors",
      unname(gper[["manifest.json"]]), gcombined,
      length(gper), length(gman$vectors), gcommit),
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
