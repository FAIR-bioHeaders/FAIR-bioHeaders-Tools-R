#' Runs the FHGM development suite and reports it layer by layer
#'
#' FHGM's published draft suite (92 vectors from FHGM-Specification
#' `development/conformance/`) is written differently from the shared one: each vector
#' records what four independent checks report, because separability is the point - `base`
#' (the released FHGFF3 contract over the parsed header), `checksum` (whether the file-bound
#' SHA-512/256 still reproduces), `gff3` (the feature layer, a separate tool, recorded
#' `accept` throughout so no outcome can be blamed on syntax) and `model` (the draft
#' checker's outcome).
#'
#' What this package can compare, per layer:
#'
#' * `base` - native, and computed with the draft lane **closed**: the file's own FHGFF3
#'   citation routes it under V1-V3 like any other FHGFF3 file, and the model records are
#'   extension fields of that header. The checksum mismatch is excluded here because it is
#'   the next layer's outcome.
#' * `checksum` - native.
#' * `model` - native only for the rules this package actually evaluates: K1 (transport: the
#'   key holds one or more records, an FHGFF3 1.0 header cannot carry it at all, and the
#'   carrier's citation must be a registered FHGFF3 release - raw main and unrecognised
#'   citation-version pairs are refused) and K2
#'   (each record against the pinned draft record contract). K3, K4, K5 and K6 are the draft
#'   checker's cross-record and feature-layer rules - modelId uniqueness within a snapshot,
#'   featureId resolving to exactly one local gene row, reference comparability against the
#'   file's genome link, predecessor-pointer resolution - and are reported `not-run` with that
#'   reason, never passed on the strength of the schema layer. A vector carrying **no rule
#'   label at all** - neither a `rules` array nor a singular `rule` - is reported `not-run`
#'   as well: an absent label is not evidence that the vector needs only the rules this
#'   package checks, and reading it that way would silently enlarge the compared set. Every
#'   vector of the pinned revision is labelled, so this is a guard on the suite's shape, not
#'   a finding about its current bytes.
#' * `gff3` - not run here: feature validation belongs to gff3-validator.
#' * `base_matrix.json` - not evaluated here at all: it is the suite's second lane, every
#'   sealed vector re-observed as an identity-rewritten twin against the released FHGFF3 1.2
#'   (v0.6.0) base by the upstream runner (maintainer dual-base decision 2026-11-15). The
#'   twin bytes are not vendored, so this package judges the sealed 1.1 lane only and says so.
#'
#' The run is separate, labelled, and never joins the 291: it is draft evidence about pinned
#' unreleased bytes, not support for FHGM.
#'
#' @param suite A directory holding the FHGM `manifest.json` and `vectors/`.
#' @param limit Run only the first N vectors.
#' @return A `bh_conformance`-shaped object with one column per layer.
#' @export
bh_draft_fhgm_vectors <- function(suite = NULL, limit = NULL) {
  pinned <- .bh_vendored()$draft_fhgm_vectors
  if (is.null(pinned)) bh_abort("conformance", "no FHGM draft vectors are vendored")
  dir <- .bh_fhgm_suite_dir(suite)
  man_bytes <- .bh_read_all(file.path(dir, "manifest.json"))
  if (!identical(.bh_sha256_hex(man_bytes), pinned$manifest_sha256)) {
    bh_abort("conformance", paste0(
      "FHGM draft suite: manifest.json has sha256 ", .bh_sha256_hex(man_bytes),
      ", pinned ", pinned$manifest_sha256
    ))
  }
  man <- jsonlite::fromJSON(rawToChar(man_bytes), simplifyVector = FALSE)
  if (length(man$vectors) != pinned$vectors) {
    bh_abort("conformance", paste0(
      "FHGM draft suite: ", length(man$vectors), " vectors, pinned ", pinned$vectors
    ))
  }
  rows <- lapply(seq_along(man$vectors), function(i) {
    v <- man$vectors[[i]]
    rules <- unlist(if (!is.null(v$rules)) v$rules else v$rule)
    unlabelled <- !length(rules)
    if (!is.null(limit) && i > limit) {
      return(.bh_fhgm_row(v, rules, "not-run", "beyond the requested limit"))
    }
    path <- normalizePath(file.path(dir, v$file), mustWork = FALSE)
    if (!file.exists(path)) {
      # several vectors cite published example files under ../examples/ rather than a copy
      # inside the suite directory; both trees are vendored, so a miss is reported, never
      # guessed at
      return(.bh_fhgm_row(v, rules, "missing-fixture", paste0(
        "the vector cites ", v$file, " which is not present under ", dir,
        "; vendor FHGM-Specification development/examples/ alongside development/conformance/ ",
        "(tools/vendor_upstream.R) or point suite= at a tree that has both"
      )))
    }
    a <- .bh_capture(.bh_analyze(path, format = "fhgff3", draft = FALSE))
    if (!is.null(a$error)) return(.bh_fhgm_row(v, rules, "error", a$error))
    got_sum <- if (is.na(a$value$checksum$computed)) {
      "unavailable"
    } else if (isTRUE(a$value$checksum$valid)) {
      "verify"
    } else {
      "stale"
    }
    base_only <- a$value$issues[!grepl("^R4:", a$value$issues)]
    got_base <- if (length(base_only)) "reject" else "accept"
    mv <- .bh_capture(bh_validate_fhgm(path))
    got_model <- if (!is.null(mv$error)) {
      "error"
    } else if (!isTRUE(mv$value$present)) {
      "absent"
    } else if (mv$value$n_records < 1L) {
      "reject" # K1: the key must hold one or more records
    } else if (isTRUE(mv$value$all_valid)) {
      "pass"
    } else {
      "reject"
    }
    model_rules <- c("K1", "K2", "R3", "R15")
    # An unlabelled vector is not a labelled-but-in-scope vector. `rules: []` would mean the
    # suite says this verdict needs nothing this package checks; no label at all means the
    # suite did not say, and the only honest reading of that is not-run. Every vector in the
    # pinned 92-vector manifest is labelled - 24 in `rules`, 68 in the singular `rule` the
    # runner has always accepted - so this guard is a shape rule for future revisions, not a
    # finding about the current bytes; it exists because a suite that dropped its labels
    # would otherwise move all singular-`rule` rejection vectors into the compared set
    # silently.
    beyond <- if (unlabelled) "K?" else setdiff(rules, model_rules)
    comparable <- !length(beyond) && !unlabelled
    status <- if (!identical(got_base, v$layers$base) ||
      !identical(got_sum, v$layers$checksum)) {
      "fail"
    } else if (!comparable) {
      "not-run"
    } else if (!identical(got_model, v$layers$model)) {
      "fail"
    } else {
      "pass"
    }
    reason <- switch(status,
      fail = paste0(
        "base ", got_base, " vs expected ", v$layers$base, "; checksum ", got_sum,
        " vs expected ", v$layers$checksum, "; model ", got_model, " vs expected ",
        v$layers$model
      ),
      `not-run` = if (!length(beyond)) {
        "base or checksum layer did not resolve"
      } else if (unlabelled) {
        paste0(
          "the manifest records no rule label for this vector - neither a `rules` array nor ",
          "a singular `rule` - so this run cannot tell whether its verdict falls inside the ",
          "scope it evaluates (K1/K2) or outside it (K3-K6/B1); reported not-run rather than ",
          "assumed comparable. The base and checksum layers this run can compare did agree, ",
          "and they are reported separately. Every vector of the pinned revision carries a ",
          "label, so an unlabelled one is a change in the suite's shape, said here rather ",
          "than smoothed over."
        )
      } else {
        paste0(
          "model layer needs rule(s) ", paste(beyond, collapse = "/"), ", which this ",
          "package does not implement: ",
          paste(vapply(unique(beyond), .bh_fhgm_rule_note, ""), collapse = "; "),
          ". The base and checksum layers this run can compare did agree, and they are ",
          "reported separately rather than folded into a model verdict (bh_capability(), ",
          "operation validate_model_records)."
        )
      },
      ""
    )
    .bh_fhgm_row(v, rules, status, reason, got_base, got_sum, got_model, beyond)
  })
  out <- do.call(rbind, rows)
  structure(
    list(
      results = out, summary = table(out$status), ok = !any(out$status %in% c("fail", "error", "missing-fixture")),
      failures = sum(out$status %in% c("fail", "error", "missing-fixture")), suite = dir, vectors = nrow(out),
      label = paste0(
        "FHGM development suite (draft evidence, rule V7 - not part of the 291); ",
        "base, checksum and the K1/K2 model rules native, checker cross-record rules ",
        "and the gff3 layer not-run"
      ),
      gap_vectors = sum(nzchar(out$rule_gaps)), reported_vectors = 0L,
      limited = !is.null(limit)
    ),
    class = "bh_conformance"
  )
}

# The rules this package cannot evaluate, and what each one needs. K3-K6 are the draft
# checker's cross-record and feature-layer rules; B1 is the boundary statement that a model
# verdict only exists once the base schema and the exact-byte checksum already pass, which is
# the reason this package reports the layers separately instead of collapsing them into one
# "invalid" like the checker does.
.bh_fhgm_rule_notes <- list(
  `K?` = paste0(
    "the suite recorded no rule label for this vector, so the run cannot establish whether ",
    "its verdict is inside this package's model scope; the checker rules K1-K6 and B1 are ",
    "all named in the manifest's own rules block"
  ),
  K3 = "modelId uniqueness within one snapshot (checker rule 1)",
  K4 = "featureId as written matching the decoded ID of exactly one local gene row in the enclosing file (checker rule 2, which needs the GFF3 feature layer)",
  K5 = "record reference comparable with, and not contradicting, the file genome link (checker rule 3)",
  K6 = "predecessor pointer resolution against explicitly supplied prior snapshots (checker rule 4)",
  B1 = "the boundary rule: a rejection reported here comes from base plus checksum rather than from a model-level gap, and this package states the two layers apart"
)

# A rule label the suite uses that this build has no note for is still a gap, and says so;
# it must not abort the run and it must not read as covered.
.bh_fhgm_rule_note <- function(rule) {
  note <- .bh_fhgm_rule_notes[[rule]]
  if (is.null(note)) {
    return(paste0(
      rule, ": no note recorded in this build (compare the ruleVocabulary of ",
      "tests/draft/fhgm/manifest.json); not evaluated here"
    ))
  }
  note
}

.bh_fhgm_row <- function(v, rules, status, reason, got_base = NA_character_,
                         got_checksum = NA_character_, got_model = NA_character_,
                         beyond = character()) {
  data.frame(
    id = v$id, format = v$format, expected = v$expected, status = status,
    expected_base = v$layers$base, got_base = got_base,
    expected_checksum = v$layers$checksum, got_checksum = got_checksum,
    expected_model = v$layers$model, got_model = got_model,
    rules = paste(rules, collapse = "+"),
    rule_gaps = if (identical(status, "not-run") && length(beyond)) {
      paste(beyond, collapse = "+")
    } else {
      ""
    },
    rule_reported = "",
    reason = reason,
    stringsAsFactors = FALSE
  )
}

.bh_fhgm_suite_dir <- function(suite = NULL) {
  named <- .bh_resolve_named(c(
    suite, getOption("bh.fhgm_dir"),
    Sys.getenv("FAIRBH_FHGM_DIR", unset = NA_character_)
  ), "FHGM development suite")
  if (!is.null(named)) return(named)
  .bh_search(
    c(.bh_draft_path_cand("fhgm"), "tests/draft/fhgm"),
    paste0(
      "FHGM development suite (vendored at tests/draft/fhgm from FHGM-Specification, ",
      "with the example files it cites under tests/draft/examples)"
    )
  )
}
