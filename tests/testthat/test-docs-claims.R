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
