#' The shared conformance vectors, run natively
#'
#' Acceptance for this package is the federation's language-neutral suite -
#' FAIR-bioHeaders-Specification `conformance/`, 291 vectors at the v0.6.0 baseline - not a
#' per-language test set invented here. The vector bytes and their expectations are vendored
#' byte-for-byte under `tests/conformance/`, with the digests recorded in
#' `inst/VENDORED.json`, so the run is reproducible offline and cannot quietly shrink.
#'
#' Four properties the runner enforces, because "0 of 0 passed" is how an acceptance suite
#' dies:
#'
#' 1. The suite is the pinned suite: `manifest.json` is hashed and compared with the
#'    recorded digest, and the vector count is compared with the recorded count, before any
#'    vector runs.
#' 2. Every vector is accounted for as pass, fail, error, missing-fixture or not-run, and
#'    not-run always carries a reason. jsonld and microdata are declared not-run with the
#'    unbuilt reader named, so they stay visible instead of being passed or omitted.
#' 3. The declared supported subset cannot regress or silently change size: the sequence
#'    formats must all run, and their total must equal the pinned 228.
#' 4. Each vector's rule labels are checked against [bh_rule_coverage()], so a verdict that
#'    agrees for a reason this package does not verify is reported as a gap.
#'
#' [bh_draft_vectors()] runs the FHT development suite, which is separate published material
#' from a different repository: it runs only with the rule V7 lane open, its results are
#' labelled draft evidence, and it is never counted toward the 291.
#' [bh_draft_fhgm_vectors()] runs the FHGM development suite the same way - separate,
#' labelled, never in the 291 - and reports it layer by layer, because that suite records
#' four independent outcomes per vector and this package evaluates only some of them.
#'
#' @name conformance
NULL

.bh_supported_formats <- c("fasta", "gfa", "fhp-fasta", "fhgff3")

.bh_not_run_reasons <- c(
  jsonld = "not-run: no JSON-LD reader (rules J1-J9 unbuilt)",
  microdata = "not-run: no HTML/microdata reader (rules M1-M5 and R9 unbuilt)"
)

.bh_test_path_cand <- function() {
  if (!requireNamespace("testthat", quietly = TRUE)) return(NULL)
  p <- tryCatch(testthat::test_path(), error = function(e) NULL)
  if (is.null(p)) NULL else file.path(p, "..", "conformance")
}

# The draft suites live one level up from the testthat directory: tests/draft/<sub>.
#' @noRd
.bh_draft_path_cand <- function(sub) {
  if (!requireNamespace("testthat", quietly = TRUE)) return(NULL)
  p <- tryCatch(testthat::test_path(), error = function(e) NULL)
  if (is.null(p)) NULL else file.path(p, "..", "draft", sub)
}

#' Finds the vendored shared suite.
#' @noRd
.bh_suite_dir <- function(suite = NULL) {
  named <- .bh_resolve_named(c(
    suite,
    getOption("bh.conformance_dir"),
    Sys.getenv("FAIRBH_CONFORMANCE_DIR", unset = NA_character_)
  ), "shared conformance suite")
  if (!is.null(named)) return(named)
  .bh_search(c(
    .bh_test_path_cand(),
    system.file("conformance", package = "FAIRbioHeadersTools"),
    "tests/conformance", "conformance"
  ), "shared conformance suite (vendored at tests/conformance)")
}

# A named suite location is authoritative: it either holds a manifest.json or this errors.
# Falling through to another candidate would let a typo, a mis-set option, or a
# case-insensitive filesystem quietly resolve a bad path to some other copy of the data -
# which turns "missing fixtures must fail" into a pass that proves nothing. (A sibling
# library hit exactly this: green on macOS, red on Linux, same workflow; the Java library's
# run 43640996572 is the recorded case.)
#' @noRd
.bh_resolve_named <- function(named, what) {
  named <- named[!is.na(named) & nzchar(named)]
  if (!length(named)) return(NULL)
  p <- named[[1L]]
  if (!file.exists(file.path(p, "manifest.json"))) {
    bh_abort("conformance", paste0(
      "the ", what, " was named as ", p, " but holds no manifest.json. Refusing to fall ",
      "back to another location: a fallback that rescues a bad path is how a missing suite ",
      "starts reporting passes."
    ))
  }
  normalizePath(p, mustWork = TRUE)
}

# The un-named case: search the known spots, and say which were searched when none matches.
#' @noRd
.bh_search <- function(cands, what) {
  cands <- cands[!is.na(cands) & nzchar(cands)]
  for (c in cands) {
    if (file.exists(file.path(c, "manifest.json"))) return(normalizePath(c, mustWork = TRUE))
  }
  bh_abort("conformance", paste0(
    "the ", what, " was not found. Looked in: ",
    paste(sQuote(unique(cands)), collapse = ", "),
    ". The vectors are part of the package's source tree, not of the installed package: ",
    "run from a source checkout, or pass the directory as `suite` (for the shared suite, ",
    "\"<checkout>/tests/conformance\"; option bh.conformance_dir and the ",
    "FAIRBH_CONFORMANCE_DIR environment variable also name it). A copy missing from a ",
    "checkout is re-created with tools/vendor_upstream.R."
  ))
}

#' @noRd
.bh_draft_suite_dir <- function(suite = NULL) {
  named <- .bh_resolve_named(c(
    suite,
    getOption("bh.draft_dir"),
    Sys.getenv("FAIRBH_DRAFT_DIR", unset = NA_character_)
  ), "FHT development suite")
  if (!is.null(named)) return(named)
  .bh_search(c(
    .bh_draft_path_cand("fht"),
    "tests/draft/fht", file.path("tests", "draft", "fht")
  ), "FHT development suite (vendored at tests/draft/fht from FHT-Specification)")
}

# Runs one suite. `lane` is the draft argument passed through, `pinned` is the provenance
# block the digests are checked against, `label` prefixes the accounting so a draft run
# can never be mistaken for the shared one, and `run_formats` are the formats this runner
# claims to read; anything else is not-run with a reason rather than a verdict.
.bh_run_suite <- function(dir, pinned, lane, formats, limit, label, run_formats) {
  man_path <- file.path(dir, "manifest.json")
  man_bytes <- .bh_read_all(man_path)
  got_sha <- .bh_sha256_hex(man_bytes)
  if (!is.null(pinned$manifest_sha256) && !identical(got_sha, pinned$manifest_sha256)) {
    bh_abort("conformance", paste0(
      label, ": ", man_path, " has sha256 ", got_sha,
      " but inst/VENDORED.json records ", pinned$manifest_sha256,
      " - the suite on disk is not the suite this package was pinned to"
    ))
  }
  man <- jsonlite::fromJSON(rawToChar(man_bytes), simplifyVector = FALSE)
  if (!is.null(pinned$vectors) && length(man$vectors) != pinned$vectors) {
    bh_abort("conformance", paste0(
      label, ": the manifest holds ", length(man$vectors), " vectors, pinned ",
      pinned$vectors
    ))
  }

  rows <- list()
  for (v in man$vectors) {
    fmt <- v$format
    rules <- unlist(if (!is.null(v$rules)) v$rules else v$rule)
    if (!is.null(formats) && !fmt %in% formats) {
      rows[[length(rows) + 1L]] <- .bh_conf_row(v, rules, "excluded",
        "not requested in this run")
      next
    }
    if (!fmt %in% run_formats) {
      rows[[length(rows) + 1L]] <- .bh_conf_row(v, rules, "not-run",
        .bh_not_run_reasons[[fmt]] %||%
          paste0("not-run: no native reader for the ", fmt, " serialization"))
      next
    }
    path <- file.path(dir, v$file)
    if (!file.exists(path)) {
      rows[[length(rows) + 1L]] <- .bh_conf_row(v, rules, "missing-fixture",
        paste0("no such file: ", v$file))
      next
    }
    if (!is.null(limit) && .bh_count_fmt(rows, fmt) >= limit) {
      rows[[length(rows) + 1L]] <- .bh_conf_row(v, rules, "not-run",
        paste0("not-run: beyond the limit of ", limit, " vectors per format"))
      next
    }
    res <- .bh_capture(.bh_analyze(path, format = fmt, draft = lane))
    if (!is.null(res$error)) {
      # A vector may declare its own failure class. `selfChecksum: "unreachable"` says
      # the bytes cannot be framed at all - the suite's reason for the truncated gzip
      # vector reads "there are no decompressed bytes for R1 to hash and the file is
      # rejected before any checksum comparison" - which is the same scoring the
      # toolkit's FHT lane applies ("unreachable rejects before any checksum question
      # arises"). When such a vector expects `invalid` and this reader answers with its
      # classed gzip-refusal (R/framing.R: a truncated member, a bad CRC or trailing
      # garbage is an unusable input, never a verdict built on missing bytes), the
      # reader has produced exactly the rejection the vector declares. Scoring that
      # `error` would call a faithful refusal a defect; scoring `pass` here says on the
      # record which refusal it accepted and why. Any other error stays an error.
      if (identical(v$expected, "invalid") && identical(v$selfChecksum, "unreachable") &&
          grepl(" as gzip: ", res$error, fixed = TRUE)) {
        rows[[length(rows) + 1L]] <- .bh_conf_row(v, rules, "pass",
          reason = "", observed = "invalid",
          diagnostics = paste0(
            "rejected before any checksum question: the reader refused the compressed ",
            "framing (", res$error, "); the vector declares selfChecksum=unreachable"
          )
        )
        next
      }
      rows[[length(rows) + 1L]] <- .bh_conf_row(v, rules, "error",
        paste0("native reader errored: ", res$error))
      next
    }
    a <- res$value
    observed <- if (isTRUE(a$valid)) "valid" else "invalid"
    # Rule C3: a cited parent checksum that does not recompute makes the child invalid even
    # though its own bytes and metadata are fine. The suite states which parent file each
    # link points at; without that, the link is unchecked and the verdict is not the
    # suite's business. See R/links.R.
    if (!is.null(v$parentLink) && length(v$parentLink)) {
      files <- vapply(v$parentLink, function(pl) {
        f <- pl$file
        if (is.null(f) || is.na(f)) NA_character_ else file.path(dir, f)
      }, "")
      lv <- .bh_capture(bh_verify_links(path, parent = files[!is.na(files)],
        format = fmt, draft = lane
      ))
      if (!is.null(lv$error)) {
        rows[[length(rows) + 1L]] <- .bh_conf_row(v, rules, "error",
          paste0("link verification errored: ", lv$error))
        next
      }
      if (lv$value$mismatched > 0L || any(lv$value$links$verdict == "missing-parent-file")) {
        observed <- "invalid"
      }
    }
    agree <- identical(observed, v$expected)
    # a vector that declares expected warnings must get them: the manifest's `warnings`
    # field is upstream's claim, and silently not reporting them is a real gap
    declared <- unlist(v$warnings %||% character())
    missing_w <- if (length(declared)) {
      Filter(function(w) !any(grepl(w, a$warnings, fixed = TRUE)), declared)
    } else {
      character()
    }
    agree <- agree && !length(missing_w)
    rows[[length(rows) + 1L]] <- .bh_conf_row(v, rules,
      status = if (agree) "pass" else "fail",
      reason = if (agree) "" else paste0(
        "reader said ", observed, ", manifest expects ", v$expected,
        if (length(missing_w)) {
          paste0("; declared warnings not reported: ", paste(missing_w, collapse = ","))
        } else {
          ""
        },
        ": ", paste(a$issues, collapse = " | ")
      ),
      observed = observed, diagnostics = paste(a$issues, collapse = " | "),
      warnings = paste(a$warnings, collapse = " | ")
    )
  }
  out <- do.call(rbind, rows)
  rule_labels <- strsplit(out$rules, "+", fixed = TRUE)
  gap_of <- function(rs) {
    g <- .bh_rule_gaps(rs)
    if (length(g)) paste(vapply(strsplit(g, ": ", fixed = TRUE), function(x) x[[1L]], ""),
      collapse = "+"
    ) else ""
  }
  # a not-run vector's rules are unverified for the reason already in its own column; the
  # gap column is for vectors that produced a verdict while leaving a rule unchecked
  out$rule_gaps <- ifelse(out$status %in% c("pass", "fail"), vapply(rule_labels, gap_of, ""), "")
  out$rule_reported <- vapply(rule_labels, function(rs) {
    paste(intersect(rs, names(.bh_rules_warning_only)), collapse = "+")
  }, "")

  supported_total <- sum(out$format %in% run_formats)
  supported_ran <- sum(out$format %in% run_formats &
      out$status %in% c("pass", "fail", "error", "missing-fixture"))
  unexpected <- sum(out$status %in% c("fail", "error", "missing-fixture"))
  # the guards run only for a complete pass: a limited run is a developer convenience and
  # is labelled partial rather than being held to the full counts
  if (is.null(formats) && is.null(limit)) {
    if (nrow(out) != length(man$vectors)) {
      bh_abort("conformance", paste0(
        label, ": only ", nrow(out), " of ", length(man$vectors),
        " vectors were accounted for"
      ))
    }
    if (!is.null(pinned$expected_supported) && supported_total != pinned$expected_supported) {
      bh_abort("conformance", paste0(
        label, ": the declared supported subset is ", pinned$expected_supported,
        " vectors but the suite has ", supported_total,
        " - the capability matrix, this guard and the pin move together, deliberately"
      ))
    }
    if (supported_ran != supported_total) {
      bh_abort("conformance", paste0(
        label, ": ", supported_total - supported_ran, " of ", supported_total,
        " supported vectors did not run"
      ))
    }
  }
  structure(
    list(
      results = out, summary = table(out$format, out$status), ok = unexpected == 0L,
      failures = unexpected, suite = dir, vectors = nrow(out), label = label,
      gap_vectors = sum(nzchar(out$rule_gaps)),
  reported_vectors = sum(nzchar(out$rule_reported)),
      limited = !is.null(formats) || !is.null(limit)
    ),
    class = "bh_conformance"
  )
}

.bh_count_fmt <- function(rows, fmt) {
  sum(vapply(rows, function(r) identical(r$format, fmt) &&
      r$status %in% c("pass", "fail"), logical(1L)))
}

.bh_conf_row <- function(v, rules, status, reason, observed = NA_character_,
                         diagnostics = "", warnings = "") {
  data.frame(
    id = v$id, format = v$format, expected = v$expected, observed = observed,
    status = status, rules = paste(rules, collapse = "+"), reason = reason,
    diagnostics = diagnostics, warnings = warnings,
    stringsAsFactors = FALSE
  )
}

#' Runs the shared conformance vectors through the native reader
#'
#' @param suite A directory holding `manifest.json` and the vector files. The vectors are
#'   vendored in the package's source tree under `tests/conformance/`, which `R CMD
#'   INSTALL` does not install, so from an installed package name the directory - a source
#'   checkout's `tests/conformance`, or the specification's `conformance/` at the pinned
#'   commit - here, with `options(bh.conformance_dir = )` or with the
#'   `FAIRBH_CONFORMANCE_DIR` environment variable. Inside the package's own tests it is
#'   found without help.
#' @param formats Restrict the run to these formats. The accounting still covers all 291,
#'   and the count guards are skipped, because a partial run is not an acceptance run.
#' @param draft Passed to the reader; `FALSE` (the default) runs the released vectors exactly
#'   as they were before the draft lane existed.
#' @param limit Run only the first N vectors per format, for a quick local pass.
#' @return A `bh_conformance` object: `results`, `summary`, `ok`, `vectors`, `failures` and
#'   `gap_vectors`.
#' @examples
#' \dontrun{
#' x <- bh_conformance()
#' x$ok
#' bh_conformance_report(x, "conformance.json")
#' }
#' @export
bh_conformance <- function(suite = NULL, formats = NULL, draft = FALSE, limit = NULL) {
  pinned <- .bh_vendored()$conformance
  pinned$expected_supported <- .bh_expected_supported # fasta 98 + gfa 56 + fhp-fasta 36 + fhgff3 38
  .bh_run_suite(.bh_suite_dir(suite), pinned, lane = draft, formats = formats,
    limit = limit, label = "shared v0.6.0 suite (291 vectors)",
    run_formats = .bh_supported_formats
  )
}

#' Runs the FHT development suite through the draft lane
#'
#' These 82 vectors are published by FHT-Specification, not by the shared specification, and
#' their manifest says its expectations are "derived from the rule text, never from an
#' implementation under test". They are therefore reported separately, under the rule V7 lane
#' with the pinned draft bytes, and they never join the 291. A result here is draft evidence:
#' it says what this build does with an unreleased contract, not that FHT is supported.
#'
#' @param suite A directory holding the FHT suite's `manifest.json`. It is vendored in the
#'   source tree under `tests/draft/fht/`, which is not installed; from an installed package
#'   name it here, with `options(bh.draft_dir = )` or with `FAIRBH_DRAFT_DIR`.
#' @param formats Restrict the run; the default runs the whole draft suite.
#' @inheritParams bh_conformance
#' @return A `bh_conformance` object, labelled as draft evidence.
#' @export
bh_draft_vectors <- function(suite = NULL, formats = NULL, limit = NULL) {
  pinned <- .bh_vendored()$draft_vectors
  if (is.null(pinned)) {
    bh_abort("conformance", "no draft vectors are vendored in this build")
  }
  .bh_run_suite(.bh_draft_suite_dir(suite), pinned, lane = "FHT",
    formats = if (identical(formats, "fht-fasta")) NULL else formats, limit = limit,
    label = "FHT development suite (draft evidence, rule V7 - not part of the 291)",
    run_formats = "fht-fasta"
  )
}

.bh_expected_supported <- 228L

#' @export
print.bh_conformance <- function(x, ...) {
  cat(x$label, "\n", sep = "")
  cat("  suite: ", x$suite, "\n", sep = "")
  cat("  vectors accounted for: ", x$vectors,
      if (isTRUE(x$limited)) " (partial run)" else "", "\n", sep = "")
  print(x$summary)
  cat("  unexpected results: ", x$failures, "\n", sep = "")
  cat("  vectors whose verdict leaves a rule unverified: ", x$gap_vectors, "\n", sep = "")
  cat("  vectors that also had to report a warning-only rule: ", x$reported_vectors,
      "\n", sep = "")
  bad <- x$results[x$results$status %in% c("fail", "error", "missing-fixture"), , drop = FALSE]
  if (nrow(bad)) {
    for (i in seq_len(nrow(bad))) {
      cat("    ", bad$status[[i]], " ", bad$id[[i]], ": ",
          substr(bad$reason[[i]], 1, 220), "\n", sep = "")
    }
  }
  gaps <- x$results[nzchar(x$results$rule_gaps), , drop = FALSE]
  if (nrow(gaps)) {
    cat("  unverified rules by vector:\n")
    for (i in seq_len(nrow(gaps))) {
      cat("    ", gaps$id[[i]], ": ", gaps$rule_gaps[[i]], "\n", sep = "")
    }
  }
  invisible(x)
}

#' Writes a run as a JSON report
#'
#' @param x A `bh_conformance` object.
#' @param path Where to write it; `NULL` returns the text.
#' @return The report path, invisibly, or the JSON text.
#' @export
bh_conformance_report <- function(x, path = NULL) {
  txt <- jsonlite::toJSON(list(
    label = x$label, suite = x$suite, vectors = x$vectors, ok = x$ok,
    failures = x$failures, gap_vectors = x$gap_vectors,
    by_format = lapply(split(x$results, x$results$format), function(d) list(
      total = nrow(d), pass = sum(d$status == "pass"), fail = sum(d$status == "fail"),
      error = sum(d$status == "error"), not_run = sum(d$status == "not-run"),
      missing_fixture = sum(d$status == "missing-fixture"),
      excluded = sum(d$status == "excluded"),
      not_run_reasons = unique(d$reason[d$status == "not-run"])
    )),
    results = x$results
  ), auto_unbox = TRUE, pretty = 2, null = "null")
  if (is.null(path)) return(txt)
  writeLines(txt, path)
  invisible(path)
}
