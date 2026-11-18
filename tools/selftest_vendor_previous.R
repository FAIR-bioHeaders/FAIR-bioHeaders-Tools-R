#!/usr/bin/env Rscript
#' Selftest: tools/vendor_upstream.R must rotate `previous` only on a real change.
#'
#' The record's `previous` field names the SUPERSEDED pin. Re-running the vendor step
#' with unchanged inputs must therefore leave `previous` byte-identical to what it was;
#' a generator that overwrites it with the current values silently restates the audit
#' trail (the last real pin transition disappears). This script builds three throwaway
#' git repositories shaped like the owning checkouts, runs the generator twice with no
#' upstream change, asserts the history field is unchanged, then changes one contract's
#' bytes and asserts the rotation fires exactly once and carries the true predecessor.
#'
#' Usage (from the package root): Rscript tools/selftest_vendor_previous.R [script.R]
#' The optional argument names an alternate vendor_upstream.R to exercise - the
#' red-first proof runs it against the pre-fix copy. It exits nonzero on any failure.
#' tools/ is excluded from the package tarball (.Rbuildignore), so this lives beside the
#' generator as a build step rather than in testthat, where R CMD check could not reach
#' it without a skip - and skips are a build failure here (docs/NATIVE-ACCEPTANCE.md).

`%||%` <- function(a, b) if (is.null(a)) b else a
.fail <- 0L
.ok <- function(cond, label) {
  cat(if (isTRUE(cond)) "  ok   " else "  FAIL ", label, "\n", sep = "")
  if (!isTRUE(cond)) .fail <<- .fail + 1L
}

script <- if (length(commandArgs(trailingOnly = TRUE))) {
  normalizePath(commandArgs(trailingOnly = TRUE)[[1L]])
} else {
  normalizePath("tools/vendor_upstream.R")
}
if (!file.exists(script)) stop("no such vendor script: ", script)
Rscript_bin <- file.path(R.home("bin"), "Rscript")

root <- tempfile("vendorselftest")
invisible(dir.create(root))
on.exit(unlink(root, recursive = TRUE), add = TRUE)
g <- function(repo, ...) {
  out <- system2("git", c("-C", shQuote(repo), "-c", "user.name=selftest",
    "-c", "user.email=selftest@example.invalid", ...),
    stdout = TRUE, stderr = TRUE
  )
  st <- attr(out, "status")
  if (!is.null(st) && st != 0) {
    stop("git ", paste(...), " in ", basename(repo), " failed: ",
      paste(out, collapse = " ")
    )
  }
  invisible(out)
}
# a bare origin plus a working clone: the generator reads `origin/main` refs and
# git archives, and a mutation is only a mutation once it has been pushed
mkrepo <- function(name, files) {
  bare <- file.path(root, paste0(name, ".git"))
  invisible(dir.create(bare))
  g(bare, "init", "-q", "--bare")
  work <- file.path(root, name)
  out <- system2("git", c("clone", "-q", shQuote(bare), shQuote(work)),
    stdout = TRUE, stderr = TRUE
  )
  if (!is.null(attr(out, "status")) && attr(out, "status") != 0) {
    stop("clone of ", name, " failed: ", paste(out, collapse = " "))
  }
  for (p in names(files)) {
    invisible(dir.create(file.path(work, dirname(p)), recursive = TRUE,
      showWarnings = FALSE
    ))
    writeLines(files[[p]], file.path(work, p))
  }
  g(work, "add", "-A")
  g(work, "commit", "-q", "-m", "seed")
  g(work, "push", "-q", "origin", "HEAD:refs/heads/main")
  invisible(work)
}
tagrepo <- function(work, name) {
  g(work, "tag", "-a", "-m", name, name)
  g(work, "push", "-q", "origin", name)
}

# --- three fake owning repositories, matching the shapes vendor_upstream.R reads -----
spec_w <- mkrepo("spec", list(
  "fhr.json" = '{"marker":"fhr"}', "fhp.json" = '{"marker":"fhp"}',
  "fhgff3.json" = '{"marker":"fhgff3"}',
  "schemas/versions.json" = '{"current":"v0.6.0"}',
  "conformance/manifest.json" = '{"vectors":[]}',
  "conformance/README.md" = "fake shared suite\n"
))
for (t in c("v0.3.1", "v0.4.0", "v0.5.0", "v0.6.0")) tagrepo(spec_w, t)
fht_w <- mkrepo("fht", list(
  "fht.json" = '{"marker":"fht-v1"}',
  "conformance/manifest.json" = '{"vectors":[],"status":"fake draft suite"}',
  "conformance/README.md" = "fake fht suite\n"
))
fhgm_w <- mkrepo("fhgm", list(
  "development/model/fhgm-model.schema.json" = '{"marker":"fhgm-v1"}',
  "development/conformance/manifest.json" = '{"vectors":[],"status":"fake fhgm suite"}',
  "development/conformance/README.md" = "fake fhgm suite\n",
  "development/examples/README.md" = "fake examples\n"
))

pkg <- file.path(root, "pkg")
invisible(dir.create(file.path(pkg, "tools"), recursive = TRUE))
invisible(file.copy(script, file.path(pkg, "tools", "vendor_upstream.R"),
  overwrite = TRUE
))

run_vendor <- function() {
  owd <- setwd(pkg)
  on.exit(setwd(owd), add = TRUE)
  log <- tempfile("vendorrun")
  st <- system2(Rscript_bin, c(shQuote(file.path("tools", "vendor_upstream.R")),
    "--source", shQuote(spec_w), "--fht", shQuote(fht_w), "--fhgm", shQuote(fhgm_w)),
    stdout = log, stderr = log
  )
  out <- if (file.exists(log)) readLines(log, warn = FALSE) else character()
  unlink(log)
  if (!is.null(st) && st != 0) {
    stop("vendor run failed (status ", st, "):\n", paste(out, collapse = "\n"))
  }
  prov <- jsonlite::fromJSON(file.path(pkg, "inst", "VENDORED.json"),
    simplifyVector = FALSE
  )
  row <- function(type) {
    hit <- Filter(function(r) identical(r$header_type, type), prov$files)[[1]]
    hit
  }
  list(
    fht_sha = row("FHT")$sha256, fhgm_sha = row("FHGM")$sha256,
    fht_prev = row("FHT")$previous, fhgm_prev = row("FHGM")$previous,
    suite_prev = prov$draft_vectors$previous,
    fhgm_suite_prev = prov$draft_fhgm_vectors$previous,
    suite_man = prov$draft_vectors$manifest_sha256
  )
}

cat("vendor_upstream selftest: exercising ", script, "\n", sep = "")

r1 <- run_vendor()
.ok(is.null(r1$fht_prev), "run 1 (no prior record): no predecessor invented")
r2 <- run_vendor()
.ok(identical(r2$fht_prev, r1$fht_prev),
  "run 2 (inputs unchanged): FHT contract previous byte-identical"
)
.ok(identical(r2$fhgm_prev, r1$fhgm_prev),
  "run 2 (inputs unchanged): FHGM contract previous byte-identical"
)
.ok(identical(r2$suite_prev, r1$suite_prev),
  "run 2 (inputs unchanged): FHT suite previous byte-identical"
)
.ok(identical(r2$fhgm_suite_prev, r1$fhgm_suite_prev),
  "run 2 (inputs unchanged): FHGM suite previous byte-identical"
)
.ok(identical(r2$suite_man, r1$suite_man), "run 2: suite manifest unchanged as expected")

# a genuine change: mutate ONLY the FHT contract; rotate it, leave the suites alone
writeLines('{"marker":"fht-v2"}', file.path(fht_w, "fht.json"))
g(fht_w, "add", "-A")
g(fht_w, "commit", "-q", "-m", "move-fht-json")
g(fht_w, "push", "-q", "origin", "HEAD:main")
r3 <- run_vendor()
.ok(!identical(r3$fht_sha, r2$fht_sha), "run 3: FHT contract digest moved")
.ok(identical(r3$fht_prev$sha256, r2$fht_sha),
  "run 3: previous names the superseded pin (the real predecessor)"
)
.ok(is.null(r3$fhgm_prev) || !identical(r3$fhgm_prev$sha256, r3$fhgm_sha),
  "run 3: unchanged FHGM contract did not self-parent"
)
.ok(identical(r3$suite_prev, r2$suite_prev),
  "run 3: FHT suite previous untouched by the other lane's move"
)

# and a second real move rotates again: previous becomes the FIRST successor, not run 1
writeLines('{"marker":"fht-v3"}', file.path(fht_w, "fht.json"))
g(fht_w, "add", "-A")
g(fht_w, "commit", "-q", "-m", "move-fht-json-again")
g(fht_w, "push", "-q", "origin", "HEAD:main")
r4 <- run_vendor()
.ok(identical(r4$fht_prev$sha256, r3$fht_sha),
  "run 4: a second genuine move rotates previous to the immediately prior pin"
)

if (.fail > 0L) {
  cat("vendor_upstream selftest: ", .fail, " FAILURE(S)\n", sep = "")
  quit(status = 1L, save = "no")
}
cat("vendor_upstream selftest: all checks passed\n")
