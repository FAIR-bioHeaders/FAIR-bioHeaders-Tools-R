# Claims the documentation makes about the package, held to the code.

test_that("bh_extract_header backs the extract_header_* capability rows", {
  p <- .bh_write_header_file("x-a: [1, 2]\n")
  y <- bh_extract_header(p)
  expect_match(y, "^schema: https://w3id.org/fair-bioheaders/fhr/v0.6.0\n")
  expect_match(y, "\nx-a: \\[1, 2\\]\nchecksum: [A-Za-z0-9+/]{43}=\n$")
  expect_false(grepl(";~", y, fixed = TRUE))
  j <- jsonlite::fromJSON(bh_extract_header(p, as = "json"), simplifyVector = FALSE)
  expect_identical(j$genome, "Synthetic genome")
  expect_identical(j[["x-a"]], list(1L, 2L))
  g <- .bh_write_header_file(ext = ".gfa")
  expect_match(bh_extract_header(g), "^schema: ")
  e <- tryCatch(bh_extract_header(.bh_write_header_file("x-a: &a 1\n"), as = "json"),
    bh_error = function(e) e)
  expect_s3_class(e, "bh_input")
  expect_match(conditionMessage(e), "R8: an anchor")
  # a record that parses but bh_read() rejects (R12 a YAML 1.1 boolean, R13 a non-finite
  # float) is refused too, never exported as the JSON the file did not mean
  for (case in list(c("x-a: yes\n", "R12"), c("x-a: .nan\n", "R13"))) {
    p <- .bh_write_header_file(case[[1L]])
    r <- suppressWarnings(bh_read(p))
    expect_false(r$valid)
    expect_true(any(startsWith(r$issues, case[[2L]])), info = case[[1L]])
    e <- tryCatch(bh_extract_header(p, as = "json"), bh_error = function(e) e)
    expect_s3_class(e, "bh_input")
    expect_match(conditionMessage(e), paste0(case[[2L]], ":"), info = case[[1L]])
    expect_match(bh_extract_header(p), sub("\n$", "", case[[1L]]), fixed = TRUE)
  }
  rows <- bh_capability(operation = c("extract_header_yaml", "extract_header_json"))
  expect_true(all(rows$support == "native"))
  expect_true(all(grepl("bh_extract_header", rows$blocker)))
  expect_true("bh_extract_header" %in% getNamespaceExports("FAIRbioHeadersTools"))
})

test_that("bh_conformance says how to find the vectors when they are not installed", {
  withr::local_dir(tempdir())
  e <- tryCatch(.bh_search(c(file.path(tempdir(), "nowhere")), "shared conformance suite"),
    bh_error = function(e) e)
  expect_s3_class(e, "bh_conformance")
  expect_match(conditionMessage(e), "not of the installed package")
  expect_match(conditionMessage(e), "FAIRBH_CONFORMANCE_DIR")
})

test_that("the package text does not claim to run without a foreign-language runtime", {
  desc <- utils::packageDescription("FAIRbioHeadersTools")$Description
  expect_false(grepl("no foreign-language runtime", desc, fixed = TRUE))
  expect_match(desc, "V8")
  expect_true("V8" %in% c(tools::package_dependencies("jsonvalidate",
    db = utils::installed.packages())[[1L]]))
})

# Locates the repository or unpacked package root without skipping under R CMD check.
.bh_find_repo_file <- function(rel) {
  cands <- c(
    rel,
    file.path("..", rel),
    file.path("..", "..", rel),
    file.path(dirname(dirname(.bh_suite_dir())), rel),
    file.path("..", "..", "00_pkg_src", "FAIRbioHeadersTools", rel)
  )
  for (c in unique(cands)) {
    if (file.exists(c)) return(normalizePath(c, mustWork = TRUE))
  }
  NULL
}

test_that("prose counts in capability matrix, README, and Rd files match the pinned manifests (#21)", {
  prov <- FAIRbioHeadersTools:::.bh_vendored()
  expect_equal(prov$conformance$vectors, 291L)
  expect_equal(prov$draft_vectors$vectors, 93L)
  expect_equal(prov$draft_fhgm_vectors$vectors, 92L)

  fhgm_run <- suppressWarnings(bh_draft_fhgm_vectors())
  n_fhgm_total <- fhgm_run$vectors
  n_fhgm_model <- sum(fhgm_run$results$status == "pass")
  n_fhgm_notrun <- sum(fhgm_run$results$status == "not-run")
  expect_equal(n_fhgm_total, 92L)
  expect_equal(n_fhgm_model, 37L)
  expect_equal(n_fhgm_notrun, 55L)

  # Capability matrix row for FHGM validate_model_records states the exact measured split
  cap_fhgm <- bh_capability(header_type = "FHGM", operation = "validate_model_records")
  expect_equal(nrow(cap_fhgm), 1L)
  expect_match(
    cap_fhgm$blocker,
    paste0("Of the ", n_fhgm_total, " pinned development vectors, ", n_fhgm_model,
           " are compared within K1/K2; ", n_fhgm_notrun,
           " require unimplemented K3-K6 or B1 and are reported not-run"),
    fixed = TRUE
  )

  # README.md (present in source checkout and in the package tarball) states the current
  # FHGM and shared counts and documents zlib (#21 item 2 & dependency statement)
  readme <- .bh_find_repo_file("README.md")
  expect_false(is.null(readme))
  readme_txt <- paste(readLines(readme, warn = FALSE), collapse = "\n")
  expect_match(
    readme_txt,
    paste0(n_fhgm_notrun, " of its ", n_fhgm_total, " vectors are reported `not-run`, not passed; ",
           n_fhgm_model, " are\ncompared at the model layer"),
    fixed = TRUE
  )
  expect_false(grepl("24 of its 31", readme_txt, fixed = TRUE))
  expect_match(readme_txt, "JSON-LD (37 vectors)", fixed = TRUE)
  expect_match(readme_txt, "microdata\n(26 vectors)", fixed = TRUE)
  expect_match(readme_txt, "shared 291-vector suite", fixed = TRUE)
  expect_match(readme_txt, "zlib", fixed = TRUE)
  expect_match(readme_txt, "src/gz.c", fixed = TRUE)

  # Rd files in man/ (present in source checkout and in 00_pkg_src during R CMD check)
  rd_fhgm <- .bh_find_repo_file(file.path("man", "bh_draft_fhgm_vectors.Rd"))
  expect_false(is.null(rd_fhgm))
  rd_fhgm_txt <- paste(readLines(rd_fhgm, warn = FALSE), collapse = "\n")
  expect_match(rd_fhgm_txt, paste0("(", prov$draft_fhgm_vectors$vectors, " vectors from FHGM-Specification"), fixed = TRUE)
  expect_false(grepl("31 vectors", rd_fhgm_txt, fixed = TRUE))

  rd_fht <- .bh_find_repo_file(file.path("man", "bh_draft_vectors.Rd"))
  expect_false(is.null(rd_fht))
  rd_fht_txt <- paste(readLines(rd_fht, warn = FALSE), collapse = "\n")
  expect_match(rd_fht_txt, paste0("These ", prov$draft_vectors$vectors, " vectors are published by FHT-Specification"), fixed = TRUE)
  expect_false(grepl("66 vectors|72 vectors", rd_fht_txt))
})

test_that("docs/NATIVE-ACCEPTANCE.md cites the live golden digest and current counts (#21 items 1-2)", {
  golden_path <- FAIRbioHeadersTools:::.bh_golden_path()
  actual_golden_sha <- .bh_sha256_hex(.bh_read_all(golden_path))
  expect_match(actual_golden_sha, "^[0-9a-f]{64}$")

  nat_doc <- .bh_find_repo_file(file.path("docs", "NATIVE-ACCEPTANCE.md"))
  if (!is.null(nat_doc)) {
    txt <- paste(readLines(nat_doc, warn = FALSE), collapse = "\n")
    # Extract the SHA-256 cited immediately after default-behavior-v0.6.0.json
    m <- regmatches(
      txt,
      regexec("default-behavior-v0\\.6\\.0\\.json`\\s*\\(SHA-256\\s+`([0-9a-f]{64})`\\)", txt)
    )[[1L]]
    expect_equal(length(m), 2L)
    expect_identical(m[[2L]], actual_golden_sha)
    expect_false(grepl("055da14f", txt, fixed = TRUE))

    # Prose counts in docs/NATIVE-ACCEPTANCE.md match the pinned manifests
    prov <- FAIRbioHeadersTools:::.bh_vendored()
    expect_match(txt, paste0("**", prov$draft_vectors$vectors, " FHT development vectors**"), fixed = TRUE)
    expect_match(txt, paste0("**", prov$draft_fhgm_vectors$vectors, " FHGM development vectors**"), fixed = TRUE)
    expect_match(txt, "base and checksum are compared on\nall 92, the model layer only on the 37", fixed = TRUE)
    expect_match(txt, "The other 55\nturn on K3-K6 or B1 and are `not-run`", fixed = TRUE)
  }

  # Also check docs/STATUS.md, docs/DIGEST.md and docs/CAPABILITY-MATRIX.md when in checkout
  status_doc <- .bh_find_repo_file(file.path("docs", "STATUS.md"))
  if (!is.null(status_doc)) {
    st_txt <- paste(readLines(status_doc, warn = FALSE), collapse = "\n")
    expect_match(st_txt, "Current development evidence: FHT **93/93**; FHGM **37 compared / 55 not-run of 92**", fixed = TRUE)
    expect_match(st_txt, "src/Makevars.win", fixed = TRUE)
    expect_match(st_txt, "zlib", fixed = TRUE)
  }
  cap_doc <- .bh_find_repo_file(file.path("docs", "CAPABILITY-MATRIX.md"))
  if (!is.null(cap_doc)) {
    cap_txt <- paste(readLines(cap_doc, warn = FALSE), collapse = "\n")
    expect_match(cap_txt, "src/Makevars.win", fixed = TRUE)
    expect_match(cap_txt, "zlib", fixed = TRUE)
    expect_match(cap_txt, "The other 55\nare explicitly not-run at the model layer with named gaps", fixed = TRUE)
  }
})

test_that("draft_pin_freshness.R parses VENDORED.json by path and enforces exit-1/exit-2 controls (#23)", {
  script <- .bh_find_repo_file(file.path("tools", "draft_pin_freshness.R"))
  if (!is.null(script)) {
    repo_root <- dirname(dirname(script))
    env <- new.env(parent = globalenv())
    sys.source(script, envir = env)
    expect_identical(env$run_self_test(repo_root), 0L)
  } else {
    # Inside R CMD check (where tools/ is .Rbuildignore'd), still verify VENDORED.json's
    # parsed structure has the exact paths and 64-hex digests that draft_pin_freshness.R reads
    prov <- FAIRbioHeadersTools:::.bh_vendored()
    expect_match(prov$draft_vectors$manifest_sha256, "^[0-9a-f]{64}$")
    expect_match(prov$draft_fhgm_vectors$manifest_sha256, "^[0-9a-f]{64}$")
  }
})
