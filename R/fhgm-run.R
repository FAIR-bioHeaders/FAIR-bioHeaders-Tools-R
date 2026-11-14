#' Runs the FHGM development suite and reports it layer by layer
#'
#' FHGM's published draft suite (31 vectors from FHGM-Specification
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
#'   key holds one or more records, and an FHGFF3 1.0 header cannot carry it at all) and K2
#'   (each record against the pinned draft record contract). K3, K4, K5 and K6 are the draft
#'   checker's cross-record and feature-layer rules - modelId uniqueness within a snapshot,
#'   featureId resolving to exactly one local gene row, reference comparability against the
#'   file's genome link, predecessor-pointer resolution - and are reported `not-run` with that
#'   reason, never passed on the strength of the schema layer.
#' * `gff3` - not run here: feature validation belongs to gff3-validator.
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
    if (!is.null(limit) && i > limit) {
      return(.bh_fhgm_row(v, rules, "not-run", "beyond the requested limit"))
    }
    path <- normalizePath(file.path(dir, v$file), mustWork = FALSE)
    if (!file.exists(path)) {
      # several vectors cite published example files under development/examples/ rather than
      # a copy inside the suite; only the suite is vendored here, so the citation is
      # reported, not guessed at
      return(.bh_fhgm_row(v, rules, "not-run", paste0(
        "the vector cites ", v$file, " outside the vendored suite; vendor ",
        "FHGM-Specification development/examples/ too, or resolve the path yourself"
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
    beyond <- setdiff(rules, model_rules)
    comparable <- !length(beyond)
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
      `not-run` = if (comparable) {
        "base or checksum layer did not resolve"
      } else {
        paste0(
          "model layer needs rule(s) ", paste(beyond, collapse = "/"), ", which this ",
          "package does not implement: ",
          paste(vapply(unique(beyond), function(r) .bh_fhgm_rule_notes[[r]], ""),
            collapse = "; "),
          ". The base and checksum layers this run can compare did agree, and they are ",
          "reported separately rather than folded into a model verdict (bh_capability(), ",
          "operation validate_model_records)."
        )
      },
      ""
    )
    .bh_fhgm_row(v, rules, status, reason, got_base, got_sum, got_model)
  })
  out <- do.call(rbind, rows)
  structure(
    list(
      results = out, summary = table(out$status), ok = !any(out$status == "fail"),
      failures = sum(out$status == "fail"), suite = dir, vectors = nrow(out),
      label = paste0(
        "FHGM development suite (draft evidence, rule V7 - not part of the 291); ",
        "base, checksum and the K1/K2 model rules native, checker cross-record rules ",
        "and the gff3 layer not-run"
      ),
      gap_vectors = sum(out$status == "not-run"), reported_vectors = 0L, limited = FALSE
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
  K3 = "modelId uniqueness within one snapshot (checker rule 1)",
  K4 = "featureId resolving, percent-decoded, to exactly one local gene row in the enclosing file (checker rule 2, which needs the GFF3 feature layer)",
  K5 = "record reference comparable with, and not contradicting, the file genome link (checker rule 3)",
  K6 = "predecessor pointer resolution against explicitly supplied prior snapshots (checker rule 4)",
  B1 = "the boundary rule: a rejection reported here comes from base plus checksum rather than from a model-level gap, and this package states the two layers apart"
)

.bh_fhgm_row <- function(v, rules, status, reason, got_base = NA_character_,
                         got_checksum = NA_character_, got_model = NA_character_) {
  data.frame(
    id = v$id, format = v$format, expected = v$expected, status = status,
    expected_base = v$layers$base, got_base = got_base,
    expected_checksum = v$layers$checksum, got_checksum = got_checksum,
    expected_model = v$layers$model, got_model = got_model,
    rules = paste(rules, collapse = "+"), reason = reason,
    stringsAsFactors = FALSE
  )
}

.bh_fhgm_suite_dir <- function(suite = NULL) {
  named <- .bh_resolve_named(c(
    suite, getOption("bh.fhgm_dir"),
    Sys.getenv("FAIRBH_FHGM_DIR", unset = NA_character_)
  ), "FHGM development suite")
  if (!is.null(named)) return(named)
  tp <- NULL
  if (requireNamespace("testthat", quietly = TRUE)) {
    tp <- tryCatch(testthat::test_path(), error = function(e) NULL)
  }
  .bh_search(c(
    if (!is.null(tp)) file.path(tp, "..", "draft", "fhgm"),
    "tests/draft/fhgm"
  ), "FHGM development suite (vendored at tests/draft/fhgm from FHGM-Specification)")
}
