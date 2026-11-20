test_that("reader refuses missing files, directories and unused arguments as input errors", {
  expect_error(bh_read(tempfile(fileext = ".fhr.fasta")), class = "bh_input")
  expect_error(bh_read(tempdir(), format = "fasta"), class = "bh_input")
  expect_error(bh_read(.bh_vector_path("fasta-space-before-colon"), mistyped = TRUE),
    "unused arguments", class = "bh_input")
})

test_that("per-format limits include a missing first fixture", {
  suite <- tempfile("limited-suite")
  dir.create(suite)
  on.exit(unlink(suite, recursive = TRUE), add = TRUE)
  v <- .bh_vector("fasta-space-before-colon")
  v$file <- "missing.fhr.fasta"
  second <- v
  second$id <- "second-case"
  second$file <- "second.fhr.fasta"
  file.copy(.bh_vector_path(v$id), file.path(suite, second$file))
  jsonlite::write_json(list(vectors = list(v, second)), file.path(suite, "manifest.json"),
    auto_unbox = TRUE)
  out <- FAIRbioHeadersTools:::.bh_run_suite(suite, list(vectors = 2L),
    formats = NULL, limit = 1L, label = "bounded control", run_formats = "fasta")
  expect_equal(out$results$status, c("missing-fixture", "not-run"))
  expect_false(out$ok)
})

test_that("missing FHGM fixtures and reader errors never yield ok", {
  src <- FAIRbioHeadersTools:::.bh_fhgm_suite_dir()
  root <- tempfile("fhgm-unavailable")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  file.copy(src, root, recursive = TRUE)
  file.copy(file.path(dirname(src), "examples"), root, recursive = TRUE)
  suite <- file.path(root, basename(src))
  man <- jsonlite::fromJSON(file.path(suite, "manifest.json"), simplifyVector = FALSE)
  target <- file.path(suite, man$vectors[[1L]]$file)
  expect_true(unlink(target) == 0L)
  out <- suppressWarnings(bh_draft_fhgm_vectors(suite = suite, limit = 1L))
  expect_equal(out$results$status[[1L]], "missing-fixture")
  expect_false(out$ok)
  expect_equal(out$failures, 1L)
  local_mocked_bindings(.bh_analyze = function(...) FAIRbioHeadersTools:::bh_abort("input", "controlled input error"),
    .package = "FAIRbioHeadersTools")
  out <- suppressWarnings(bh_draft_fhgm_vectors(limit = 1L))
  expect_equal(out$results$status[[1L]], "error")
  expect_false(out$ok)
  expect_equal(out$failures, 1L)
})

test_that("vendoring stages bytes and preserves prior tree on rename failure", {
  helper <- testthat::test_path("..", "..", "tools", "vendor_tree.R")
  env <- new.env(parent = baseenv())
  sys.source(helper, envir = env)
  root <- tempfile("vendor-stage-control")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  source <- file.path(root, "incoming")
  target <- file.path(root, "current")
  dir.create(source)
  dir.create(target)
  writeLines("new bytes", file.path(source, "data"))
  writeLines("old bytes", file.path(target, "data"))
  calls <- 0L
  failing_rename <- function(from, to) {
    calls <<- calls + 1L
    if (calls == 2L) return(FALSE)
    file.rename(from, to)
  }
  expect_error(env$replace_vendor_tree(source, target, rename = failing_rename), "restored")
  expect_equal(readLines(file.path(target, "data")), "old bytes")
  expect_equal(readLines(file.path(source, "data")), "new bytes")
  env$replace_vendor_tree(source, target)
  expect_equal(readLines(file.path(target, "data")), "new bytes")
})
