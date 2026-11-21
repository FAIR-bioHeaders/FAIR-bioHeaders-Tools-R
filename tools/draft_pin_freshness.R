#!/usr/bin/env Rscript
#' Draft-pin freshness: are the revisions this build pinned still what the owning
#' repository publishes on its default branch?
#'
#' Advisory by design, and it gates nothing in released-contract acceptance. The lane
#' reads the vendored bytes, whose SHA-256 is re-verified on every load, so a moved
#' upstream never changes what this library does - it changes whether this repository's
#' statement about the draft is still current.
#'
#' Usage (from the package root):
#'   Rscript tools/draft_pin_freshness.R
#'   Rscript tools/draft_pin_freshness.R --self-test
#'
#' Exit status (matching the family convention in Tools-Julia, Tools-JavaScript, Tools-Java):
#'   0  every pinned target matches live raw main (CURRENT);
#'   1  at least one target has moved (MOVED) - re-pin deliberately;
#'   2  a check was unusable (UNUSABLE) - missing/malformed provenance fields, local
#'      vendored copies do not match their own recorded digests, a 404 control probe
#'      failed, or a live request failed/redirected/returned non-200 or empty bytes.
#'
#' Four details are non-negotiable (Tools-R#23):
#'
#' 1. Parse JSON with jsonlite::fromJSON; never use line-based grep or positional sed.
#'    Values are addressed by exact object path so adding or reordering `previous` blocks
#'    can never shift or corrupt extraction.
#' 2. Verify local vendored copies against their recorded digests before probing live bytes.
#' 3. Never fall through into the mismatch branch when an extraction or probe is empty or
#'    unusable: empty/non-64-hex digests, failed 404 controls, redirects, or unreadable
#'    live reads exit 2 (UNUSABLE).
#' 4. Print one labelled row per target across all five pinned draft targets: FHT contract,
#'    FHT suite manifest, FHGM record contract, FHGM transport overlay, FHGM suite manifest.

if (!requireNamespace("digest", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE)) {
  cat("UNUSABLE: digest and jsonlite are required\n", file = stderr())
  quit(status = 2L, save = "no")
}

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a

RAW_HOST <- "https://raw.githubusercontent.com/FAIR-bioHeaders"
CONTROL_FILE <- "no-such-file-draft-pin-freshness-control.json"

is_hex64 <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && grepl("^[0-9a-f]{64}$", x)
}

is_hex40 <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && grepl("^[0-9a-f]{40}$", x)
}

sha256_file <- function(path) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !file.exists(path)) {
    return(NA_character_)
  }
  size <- file.info(path)$size
  if (is.na(size) || size < 1) return(NA_character_)
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  bytes <- readBin(con, what = "raw", n = size)
  if (length(bytes) != size) return(NA_character_)
  digest::digest(bytes, algo = "sha256", serialize = FALSE)
}

#' Extract the five pinned draft targets by exact JSON object path.
#'
#' Returns list(ok = logical, error = character|NULL, targets = list of target lists).
extract_draft_targets <- function(root = ".", vendored_path = file.path(root, "inst", "VENDORED.json"),
                                  fhgm_prov_path = NULL) {
  if (!file.exists(vendored_path)) {
    return(list(ok = FALSE, error = paste0("missing provenance file: ", vendored_path), targets = list()))
  }
  prov <- tryCatch(
    jsonlite::fromJSON(vendored_path, simplifyVector = FALSE),
    error = function(e) NULL
  )
  if (!is.list(prov)) {
    return(list(ok = FALSE, error = paste0("cannot parse JSON: ", vendored_path), targets = list()))
  }
  if (!is.list(prov$files)) {
    return(list(ok = FALSE, error = "inst/VENDORED.json is missing the top-level `files` array", targets = list()))
  }

  find_draft_contract <- function(type, file_path) {
    hits <- Filter(function(r) {
      is.list(r) && identical(r$kind, "draft-contract") &&
        identical(r$header_type, type) && identical(r$file, file_path)
    }, prov$files)
    if (length(hits) != 1L) return(NULL)
    hits[[1L]]
  }

  fht_c <- find_draft_contract("FHT", "inst/drafts/fht-draft.json")
  fhgm_c <- find_draft_contract("FHGM", "inst/drafts/fhgm-model-draft.schema.json")
  fht_s <- prov$draft_vectors
  fhgm_s <- prov$draft_fhgm_vectors

  if (is.null(fht_c)) {
    return(list(ok = FALSE, error = "missing or ambiguous FHT draft-contract row in files[]", targets = list()))
  }
  if (is.null(fhgm_c)) {
    return(list(ok = FALSE, error = "missing or ambiguous FHGM draft-contract row in files[]", targets = list()))
  }
  if (!is.list(fht_s) || !identical(fht_s$header_type, "FHT")) {
    return(list(ok = FALSE, error = "missing or invalid `draft_vectors` block for FHT", targets = list()))
  }
  if (!is.list(fhgm_s) || !identical(fhgm_s$header_type, "FHGM")) {
    return(list(ok = FALSE, error = "missing or invalid `draft_fhgm_vectors` block for FHGM", targets = list()))
  }

  # The FHGM transport overlay is not vendored as a separate file in inst/drafts/,
  # but its digest is pinned in the vendored FHGM suite's provenance.json
  # (`contractArtifacts` entry with local == "development/model/fhgm-draft.schema.json")
  # and in `draft_fhgm_vectors$per_file[["provenance.json"]]`. If `draft_fhgm_vectors$overlay_sha256`
  # is explicitly present in VENDORED.json, use it; otherwise read it from the digest-verified
  # vendored `tests/draft/fhgm/provenance.json`.
  fhgm_dest <- if (is.character(fhgm_s$dest) && length(fhgm_s$dest) == 1L && nzchar(fhgm_s$dest)) {
    fhgm_s$dest
  } else {
    "tests/draft/fhgm"
  }
  if (is.null(fhgm_prov_path)) {
    fhgm_prov_path <- file.path(root, fhgm_dest, "provenance.json")
  }
  overlay_sha <- fhgm_s$overlay_sha256
  overlay_local_path <- fhgm_prov_path
  overlay_local_expected <- if (is.list(fhgm_s$per_file)) fhgm_s$per_file[["provenance.json"]] else NULL

  if (is.null(overlay_sha)) {
    if (!file.exists(fhgm_prov_path)) {
      return(list(
        ok = FALSE,
        error = paste0("missing vendored FHGM provenance file for overlay pin: ", fhgm_prov_path),
        targets = list()
      ))
    }
    fprov <- tryCatch(
      jsonlite::fromJSON(fhgm_prov_path, simplifyVector = FALSE),
      error = function(e) NULL
    )
    if (!is.list(fprov) || !is.list(fprov$contractArtifacts)) {
      return(list(
        ok = FALSE,
        error = paste0("invalid vendored FHGM provenance JSON: ", fhgm_prov_path),
        targets = list()
      ))
    }
    ov_hits <- Filter(function(a) {
      is.list(a) && identical(a$local, "development/model/fhgm-draft.schema.json")
    }, fprov$contractArtifacts)
    if (length(ov_hits) != 1L) {
      return(list(
        ok = FALSE,
        error = "missing `development/model/fhgm-draft.schema.json` in FHGM provenance contractArtifacts",
        targets = list()
      ))
    }
    overlay_sha <- ov_hits[[1L]]$sha256
  }

  fht_dest <- if (is.character(fht_s$dest) && length(fht_s$dest) == 1L && nzchar(fht_s$dest)) {
    fht_s$dest
  } else {
    "tests/draft/fht"
  }
  fht_path <- if (is.character(fht_s$path) && length(fht_s$path) == 1L && nzchar(fht_s$path)) {
    fht_s$path
  } else {
    "conformance"
  }
  fhgm_path <- if (is.character(fhgm_s$path) && length(fhgm_s$path) == 1L && nzchar(fhgm_s$path)) {
    fhgm_s$path
  } else {
    "development/conformance"
  }

  targets <- list(
    list(
      name = "FHT-contract",
      repository = "FHT-Specification",
      pinned_sha256 = fht_c$sha256,
      commit = fht_c$commit,
      local_file = file.path(root, fht_c$file),
      local_expected_sha256 = fht_c$sha256,
      local_check_file = file.path(root, fht_c$file),
      url = fht_c$citation
    ),
    list(
      name = "FHT-suite-manifest",
      repository = "FHT-Specification",
      pinned_sha256 = fht_s$manifest_sha256,
      commit = fht_s$commit,
      local_file = file.path(root, fht_dest, "manifest.json"),
      local_expected_sha256 = fht_s$manifest_sha256,
      local_check_file = file.path(root, fht_dest, "manifest.json"),
      url = paste0(RAW_HOST, "/FHT-Specification/main/", fht_path, "/manifest.json")
    ),
    list(
      name = "FHGM-record-contract",
      repository = "FHGM-Specification",
      pinned_sha256 = fhgm_c$sha256,
      commit = fhgm_c$commit,
      local_file = file.path(root, fhgm_c$file),
      local_expected_sha256 = fhgm_c$sha256,
      local_check_file = file.path(root, fhgm_c$file),
      url = fhgm_c$citation
    ),
    list(
      name = "FHGM-transport-overlay",
      repository = "FHGM-Specification",
      pinned_sha256 = overlay_sha,
      commit = fhgm_c$commit,
      local_file = overlay_local_path,
      local_expected_sha256 = overlay_local_expected,
      local_check_file = overlay_local_path,
      local_is_provenance_carrier = TRUE,
      url = paste0(RAW_HOST, "/FHGM-Specification/main/development/model/fhgm-draft.schema.json")
    ),
    list(
      name = "FHGM-suite-manifest",
      repository = "FHGM-Specification",
      pinned_sha256 = fhgm_s$manifest_sha256,
      commit = fhgm_s$commit,
      local_file = file.path(root, fhgm_dest, "manifest.json"),
      local_expected_sha256 = fhgm_s$manifest_sha256,
      local_check_file = file.path(root, fhgm_dest, "manifest.json"),
      url = paste0(RAW_HOST, "/FHGM-Specification/main/", fhgm_path, "/manifest.json")
    )
  )

  for (t in targets) {
    if (!is_hex64(t$pinned_sha256)) {
      return(list(
        ok = FALSE,
        error = paste0(t$name, ": pinned sha256 is missing, empty, or not 64 lowercase hex chars"),
        targets = targets
      ))
    }
    if (!is_hex40(t$commit)) {
      return(list(
        ok = FALSE,
        error = paste0(t$name, ": pinned commit is missing, empty, or not 40 lowercase hex chars"),
        targets = targets
      ))
    }
    if (!is_hex64(t$local_expected_sha256)) {
      return(list(
        ok = FALSE,
        error = paste0(t$name, ": local expected sha256 is missing, empty, or not 64 lowercase hex chars"),
        targets = targets
      ))
    }
    if (!is.character(t$url) || length(t$url) != 1L || is.na(t$url) || !grepl("^https://", t$url)) {
      return(list(
        ok = FALSE,
        error = paste0(t$name, ": live URL is missing or invalid"),
        targets = targets
      ))
    }
  }

  list(ok = TRUE, error = NULL, targets = targets)
}

#' Default curl probe (no `-L`, so redirects are never silently followed).
#' Returns list(status = integer, redirect = character, sha256 = character, bytes = integer, error = character|NULL)
curl_probe <- function(url) {
  dest <- tempfile("freshprobe")
  on.exit(unlink(dest), add = TRUE)
  out <- tryCatch(
    system2(
      "curl",
      c("-sS", "--connect-timeout", "10", "--max-time", "60", "-o", shQuote(dest), "-w", shQuote("%{http_code} %{redirect_url}"), shQuote(url)),
      stdout = TRUE, stderr = TRUE
    ),
    error = function(e) structure(conditionMessage(e), status = 1L)
  )
  st <- attr(out, "status")
  if (!is.null(st) && st != 0L) {
    return(list(
      status = NA_integer_, redirect = "", sha256 = NA_character_,
      bytes = 0L, error = paste(out, collapse = " ")
    ))
  }
  line <- if (length(out)) tail(out, 1L) else ""
  parts <- strsplit(line, " ", fixed = TRUE)[[1L]]
  code <- suppressWarnings(as.integer(parts[[1L]] %||% NA_character_))
  redir <- if (length(parts) >= 2L) paste(parts[-1L], collapse = " ") else ""
  sz <- if (file.exists(dest)) file.info(dest)$size else 0L
  if (is.na(sz)) sz <- 0L
  sha <- if (sz > 0L) sha256_file(dest) else NA_character_
  list(status = code, redirect = redir, sha256 = sha, bytes = as.integer(sz), error = NULL)
}

#' Run the full freshness check with an injectable probe function.
#'
#' Returns list(exit_code = 0L|1L|2L, rows = data.frame, controls = list, error = character|NULL).
evaluate_freshness <- function(root = ".", vendored_path = file.path(root, "inst", "VENDORED.json"),
                               fhgm_prov_path = NULL, probe_fn = curl_probe, quiet = FALSE) {
  say <- function(...) if (!quiet) cat(..., "\n", sep = "")

  ext <- extract_draft_targets(root = root, vendored_path = vendored_path, fhgm_prov_path = fhgm_prov_path)
  if (!isTRUE(ext$ok)) {
    say(sprintf("%-24s | %-16s | %-16s | %-16s | %s",
      "TARGET", "PINNED", "SHIPPED", "LIVE", "VERDICT"
    ))
    say(sprintf("%-24s | %-16s | %-16s | %-16s | %s",
      "provenance", "unusable", "unusable", "not-probed", paste0("UNUSABLE (", ext$error, ")")
    ))
    return(list(exit_code = 2L, rows = data.frame(), controls = list(), error = ext$error))
  }

  targets <- ext$targets

  # Step 1: Verify local vendored copies before probing live bytes.
  local_digests <- character(length(targets))
  local_bad <- character()
  for (i in seq_along(targets)) {
    t <- targets[[i]]
    got_local <- sha256_file(t$local_check_file)
    if (!is_hex64(got_local) || !identical(got_local, t$local_expected_sha256)) {
      local_digests[[i]] <- got_local %||% "missing"
      local_bad <- c(local_bad, paste0(
        t$name, ": local file ", t$local_check_file, " has sha256 ",
        got_local %||% "missing", " != expected ", t$local_expected_sha256
      ))
    } else {
      # For FHGM-transport-overlay, local_check_file is tests/draft/fhgm/provenance.json
      # (which carries the overlay digest in contractArtifacts); report the verified pin.
      local_digests[[i]] <- if (isTRUE(t$local_is_provenance_carrier)) {
        paste0(substr(t$pinned_sha256, 1, 16), " (via provenance.json)")
      } else {
        t$pinned_sha256
      }
    }
  }

  if (length(local_bad) > 0L) {
    say(sprintf("%-24s | %-16s | %-16s | %-16s | %s",
      "TARGET", "PINNED", "SHIPPED", "LIVE", "VERDICT"
    ))
    for (i in seq_along(targets)) {
      t <- targets[[i]]
      ok_loc <- is_hex64(sha256_file(t$local_check_file)) &&
        identical(sha256_file(t$local_check_file), t$local_expected_sha256)
      say(sprintf("%-24s | %-16s | %-16s | %-16s | %s",
        t$name,
        substr(t$pinned_sha256, 1, 16),
        substr(local_digests[[i]], 1, 16),
        "not-probed",
        if (ok_loc) "UNUSABLE (aborted on local mismatch)" else "UNUSABLE (local copy mismatch)"
      ))
    }
    return(list(
      exit_code = 2L, rows = data.frame(), controls = list(),
      error = paste(local_bad, collapse = "; ")
    ))
  }

  # Step 2: 404 control probe per owning repository.
  repos <- unique(vapply(targets, function(t) t$repository, ""))
  controls <- list()
  for (repo in repos) {
    ctrl_url <- paste0(RAW_HOST, "/", repo, "/main/", CONTROL_FILE)
    pr <- probe_fn(ctrl_url)
    ok_ctrl <- is.null(pr$error) && identical(pr$status, 404L) && !nzchar(pr$redirect)
    controls[[repo]] <- list(url = ctrl_url, status = pr$status, redirect = pr$redirect, ok = ok_ctrl)
    if (!ok_ctrl) {
      err_msg <- paste0(
        "404 control failed for ", repo, " (status=", pr$status %||% "NA",
        if (nzchar(pr$redirect)) paste0(", redirect=", pr$redirect) else "",
        if (!is.null(pr$error)) paste0(", error=", pr$error) else "", ")"
      )
      say("control  ", repo, ": FAIL - ", err_msg)
      say(sprintf("%-24s | %-16s | %-16s | %-16s | %s",
        "TARGET", "PINNED", "SHIPPED", "LIVE", "VERDICT"
      ))
      for (i in seq_along(targets)) {
        t <- targets[[i]]
        say(sprintf("%-24s | %-16s | %-16s | %-16s | %s",
          t$name, substr(t$pinned_sha256, 1, 16), substr(t$pinned_sha256, 1, 16),
          "not-probed", paste0("UNUSABLE (", err_msg, ")")
        ))
      }
      return(list(exit_code = 2L, rows = data.frame(), controls = controls, error = err_msg))
    }
    say("control  ", repo, ": 404 as expected (", ctrl_url, ")")
  }

  # Step 3: Probe every target and print one labelled row per target.
  say(sprintf("%-24s | %-16s | %-16s | %-16s | %s",
    "TARGET", "PINNED", "SHIPPED", "LIVE", "VERDICT"
  ))
  row_list <- list()
  any_unusable <- FALSE
  any_moved <- FALSE

  for (i in seq_along(targets)) {
    t <- targets[[i]]
    pr <- probe_fn(t$url)
    shipped_short <- substr(t$pinned_sha256, 1, 16)
    pinned_short <- substr(t$pinned_sha256, 1, 16)

    if (!is.null(pr$error) || !identical(pr$status, 200L) || nzchar(pr$redirect) || !is_hex64(pr$sha256)) {
      verdict <- "UNUSABLE"
      live_short <- "unusable"
      any_unusable <- TRUE
      detail <- paste0(
        "HTTP ", pr$status %||% "ERR",
        if (nzchar(pr$redirect)) paste0(" redirect->", pr$redirect) else "",
        if (!is.null(pr$error)) paste0(" ", pr$error) else "",
        if (!is_hex64(pr$sha256)) " (no valid 64-hex digest)" else ""
      )
    } else if (identical(pr$sha256, t$pinned_sha256)) {
      verdict <- "CURRENT"
      live_short <- substr(pr$sha256, 1, 16)
      detail <- paste0("commit ", substr(t$commit, 1, 10), " (", pr$bytes, " B)")
    } else {
      verdict <- "MOVED"
      live_short <- substr(pr$sha256, 1, 16)
      any_moved <- TRUE
      detail <- paste0("pinned ", t$pinned_sha256, " vs live ", pr$sha256, " (", t$url, ")")
    }

    say(sprintf("%-24s | %-16s | %-16s | %-16s | %s (%s)",
      t$name, pinned_short, shipped_short, live_short, verdict, detail
    ))
    if (identical(verdict, "MOVED") && !quiet) {
      say("::warning::", t$name, ": PIN MOVED - pinned ", t$pinned_sha256,
          ", live main ", pr$sha256, " (", t$url, ")")
    }

    row_list[[i]] <- data.frame(
      target = t$name,
      pinned = t$pinned_sha256,
      shipped = t$pinned_sha256,
      live = if (is_hex64(pr$sha256)) pr$sha256 else NA_character_,
      verdict = verdict,
      stringsAsFactors = FALSE
    )
  }

  rows_df <- do.call(rbind, row_list)
  exit_code <- if (any_unusable) 2L else if (any_moved) 1L else 0L
  if (exit_code == 2L) {
    say("draft-pin-freshness: UNUSABLE (one or more probes or inputs could not be verified)")
  } else if (exit_code == 1L) {
    say("draft-pin-freshness: MOVED (re-vendor deliberately with tools/vendor_upstream.R, never as a drive-by)")
  } else {
    say("draft-pin-freshness: CURRENT (all 5 pinned draft targets match live raw main)")
  }

  list(exit_code = exit_code, rows = rows_df, controls = controls, error = NULL)
}

run_self_test <- function(root = ".") {
  cat("draft_pin_freshness selftest\n")
  fails <- 0L
  assert_ok <- function(cond, msg) {
    cat(if (isTRUE(cond)) "  ok   " else "  FAIL ", msg, "\n", sep = "")
    if (!isTRUE(cond)) fails <<- fails + 1L
  }

  ext <- extract_draft_targets(root = root)
  assert_ok(isTRUE(ext$ok) && length(ext$targets) == 5L,
    "extracts all 5 draft targets from real inst/VENDORED.json"
  )

  # Build a mock probe that returns 404 for control URLs and the pinned sha256 for live URLs.
  url_map <- setNames(
    lapply(ext$targets, function(t) t$pinned_sha256),
    vapply(ext$targets, function(t) t$url, "")
  )
  mock_probe_current <- function(url) {
    if (grepl(CONTROL_FILE, url, fixed = TRUE)) {
      return(list(status = 404L, redirect = "", sha256 = NA_character_, bytes = 0L, error = NULL))
    }
    sha <- url_map[[url]]
    if (is.null(sha)) {
      return(list(status = 404L, redirect = "", sha256 = NA_character_, bytes = 0L, error = NULL))
    }
    list(status = 200L, redirect = "", sha256 = sha, bytes = 1000L, error = NULL)
  }

  # Baseline: real VENDORED.json with matching mock probe -> CURRENT (exit 0)
  res0 <- evaluate_freshness(root = root, probe_fn = mock_probe_current, quiet = TRUE)
  assert_ok(identical(res0$exit_code, 0L) && nrow(res0$rows) == 5L &&
    all(res0$rows$verdict == "CURRENT"),
    "baseline: all 5 targets report CURRENT (exit 0)"
  )

  # Case (a): wrong pinned digest -> MOVED (exit 1)
  # Note: local copy verification checks local files against VENDORED.json first, so to
  # test live drift (MOVED) we also copy the local file or have the mock live probe
  # return a moved digest while VENDORED.json matches the local copy, AND we also test
  # a synthetic VENDORED.json with a moved pin + matching local scratch file.
  tmp_dir <- tempfile("fresh_selftest")
  dir.create(tmp_dir, recursive = TRUE)
  on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)
  for (sub in c("inst/drafts", "tests/draft/fht", "tests/draft/fhgm")) {
    dir.create(file.path(tmp_dir, sub), recursive = TRUE, showWarnings = FALSE)
  }
  file.copy(file.path(root, "inst/VENDORED.json"), file.path(tmp_dir, "inst/VENDORED.json"))
  file.copy(file.path(root, "inst/drafts/fht-draft.json"), file.path(tmp_dir, "inst/drafts/fht-draft.json"))
  file.copy(file.path(root, "inst/drafts/fhgm-model-draft.schema.json"),
    file.path(tmp_dir, "inst/drafts/fhgm-model-draft.schema.json"))
  file.copy(file.path(root, "tests/draft/fht/manifest.json"),
    file.path(tmp_dir, "tests/draft/fht/manifest.json"))
  file.copy(file.path(root, "tests/draft/fhgm/manifest.json"),
    file.path(tmp_dir, "tests/draft/fhgm/manifest.json"))
  file.copy(file.path(root, "tests/draft/fhgm/provenance.json"),
    file.path(tmp_dir, "tests/draft/fhgm/provenance.json"))

  # Mutate FHT contract on disk + its pinned sha256 in synthetic VENDORED.json so local matches
  # VENDORED.json, while live probe still returns the upstream sha256 -> MOVED (exit 1)
  writeLines('{"synthetic":"moved"}', file.path(tmp_dir, "inst/drafts/fht-draft.json"))
  moved_sha <- sha256_file(file.path(tmp_dir, "inst/drafts/fht-draft.json"))
  prov_a <- jsonlite::fromJSON(file.path(tmp_dir, "inst/VENDORED.json"), simplifyVector = FALSE)
  for (i in seq_along(prov_a$files)) {
    if (identical(prov_a$files[[i]]$file, "inst/drafts/fht-draft.json")) {
      prov_a$files[[i]]$sha256 <- moved_sha
    }
  }
  writeLines(jsonlite::toJSON(prov_a, auto_unbox = TRUE, pretty = 2, null = "null"),
    file.path(tmp_dir, "inst/VENDORED.json"))
  res_a <- evaluate_freshness(root = tmp_dir, probe_fn = mock_probe_current, quiet = TRUE)
  assert_ok(identical(res_a$exit_code, 1L) &&
    identical(res_a$rows$verdict[res_a$rows$target == "FHT-contract"], "MOVED") &&
    sum(res_a$rows$verdict == "CURRENT") == 4L,
    "case (a): synthetic VENDORED.json with wrong pinned digest -> MOVED (exit 1)"
  )

  # Restore FHT contract in tmp_dir
  file.copy(file.path(root, "inst/drafts/fht-draft.json"),
    file.path(tmp_dir, "inst/drafts/fht-draft.json"), overwrite = TRUE)
  file.copy(file.path(root, "inst/VENDORED.json"),
    file.path(tmp_dir, "inst/VENDORED.json"), overwrite = TRUE)

  # Case (b1): missing key / empty sha256 in VENDORED.json -> UNUSABLE (exit 2)
  prov_b1 <- jsonlite::fromJSON(file.path(tmp_dir, "inst/VENDORED.json"), simplifyVector = FALSE)
  prov_b1$draft_fhgm_vectors$manifest_sha256 <- ""
  v_b1 <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(prov_b1, auto_unbox = TRUE, pretty = 2, null = "null"), v_b1)
  res_b1 <- evaluate_freshness(root = tmp_dir, vendored_path = v_b1,
    probe_fn = mock_probe_current, quiet = TRUE)
  unlink(v_b1)
  assert_ok(identical(res_b1$exit_code, 2L),
    "case (b1): empty sha256 in VENDORED.json -> UNUSABLE (exit 2), never MOVED"
  )

  # Case (b2): non-64-hex sha256 / missing draft_vectors block -> UNUSABLE (exit 2)
  prov_b2 <- jsonlite::fromJSON(file.path(tmp_dir, "inst/VENDORED.json"), simplifyVector = FALSE)
  prov_b2$draft_vectors$manifest_sha256 <- "not-a-64-char-hex"
  v_b2 <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(prov_b2, auto_unbox = TRUE, pretty = 2, null = "null"), v_b2)
  res_b2 <- evaluate_freshness(root = tmp_dir, vendored_path = v_b2,
    probe_fn = mock_probe_current, quiet = TRUE)
  unlink(v_b2)
  assert_ok(identical(res_b2$exit_code, 2L),
    "case (b2): non-64-hex sha256 in VENDORED.json -> UNUSABLE (exit 2)"
  )

  # Case (b3): local vendored copy does not match VENDORED.json -> UNUSABLE (exit 2)
  prov_b3 <- jsonlite::fromJSON(file.path(tmp_dir, "inst/VENDORED.json"), simplifyVector = FALSE)
  prov_b3$draft_vectors$manifest_sha256 <- strrep("a", 64)
  v_b3 <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(prov_b3, auto_unbox = TRUE, pretty = 2, null = "null"), v_b3)
  res_b3 <- evaluate_freshness(root = tmp_dir, vendored_path = v_b3,
    probe_fn = mock_probe_current, quiet = TRUE)
  unlink(v_b3)
  assert_ok(identical(res_b3$exit_code, 2L),
    "case (b3): local file mismatch against VENDORED.json -> UNUSABLE (exit 2)"
  )

  # Case (b4): 404 control probe returns 200 -> UNUSABLE (exit 2)
  bad_ctrl_probe <- function(url) {
    list(status = 200L, redirect = "", sha256 = strrep("c", 64), bytes = 50L, error = NULL)
  }
  res_b4 <- evaluate_freshness(root = tmp_dir, probe_fn = bad_ctrl_probe, quiet = TRUE)
  assert_ok(identical(res_b4$exit_code, 2L),
    "case (b4): failed 404 control probe -> UNUSABLE (exit 2)"
  )

  # Case (b5): live probe returns empty/unreadable or redirect -> UNUSABLE (exit 2)
  bad_live_probe <- function(url) {
    if (grepl(CONTROL_FILE, url, fixed = TRUE)) {
      return(list(status = 404L, redirect = "", sha256 = NA_character_, bytes = 0L, error = NULL))
    }
    list(status = 200L, redirect = "", sha256 = NA_character_, bytes = 0L, error = NULL)
  }
  res_b5 <- evaluate_freshness(root = tmp_dir, probe_fn = bad_live_probe, quiet = TRUE)
  assert_ok(identical(res_b5$exit_code, 2L) && all(res_b5$rows$verdict == "UNUSABLE"),
    "case (b5): empty live response -> UNUSABLE (exit 2)"
  )

  # Case (c): `previous` block inserted FIRST in every object -> still extracts live paths
  # and reports CURRENT (exit 0)
  prov_c <- jsonlite::fromJSON(file.path(tmp_dir, "inst/VENDORED.json"), simplifyVector = FALSE)
  prepend_previous <- function(obj, bogus_sha) {
    prev_block <- list(
      previous = list(
        ref = strrep("1", 40),
        commit = strrep("1", 40),
        sha256 = bogus_sha,
        manifest_sha256 = bogus_sha,
        combined_sha256 = bogus_sha,
        bytes = 123L,
        vectors = 1L
      )
    )
    c(prev_block, obj[setdiff(names(obj), "previous")])
  }
  for (i in seq_along(prov_c$files)) {
    if (identical(prov_c$files[[i]]$kind, "draft-contract")) {
      prov_c$files[[i]] <- prepend_previous(prov_c$files[[i]], strrep("9", 64))
    }
  }
  prov_c$draft_vectors <- prepend_previous(prov_c$draft_vectors, strrep("8", 64))
  prov_c$draft_fhgm_vectors <- prepend_previous(prov_c$draft_fhgm_vectors, strrep("7", 64))
  v_c <- tempfile(fileext = ".json")
  writeLines(jsonlite::toJSON(prov_c, auto_unbox = TRUE, pretty = 2, null = "null"), v_c)
  res_c <- evaluate_freshness(root = tmp_dir, vendored_path = v_c,
    probe_fn = mock_probe_current, quiet = TRUE)
  unlink(v_c)
  assert_ok(identical(res_c$exit_code, 0L) && nrow(res_c$rows) == 5L &&
    all(res_c$rows$verdict == "CURRENT") &&
    identical(res_c$rows$pinned, res0$rows$pinned),
    "case (c): `previous` block inserted first in every record -> extracts live paths and reports CURRENT (exit 0)"
  )

  if (fails > 0L) {
    cat("draft_pin_freshness selftest: ", fails, " FAILURE(S)\n", sep = "")
    return(1L)
  }
  cat("draft_pin_freshness selftest: all checks passed\n")
  0L
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if ("--self-test" %in% args) {
    st <- run_self_test(".")
    quit(status = st, save = "no")
  }
  res <- evaluate_freshness(".")
  quit(status = res$exit_code, save = "no")
}
