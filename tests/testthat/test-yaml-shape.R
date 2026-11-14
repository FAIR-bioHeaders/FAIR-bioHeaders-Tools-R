# The YAML shape repair: R's yaml collapses a one-item sequence to an atomic vector, which
# would make a valid single-value array fail a `type: array` property. The shape is read back
# off the text. See R/yaml-shape.R for why it is not read back off the contract.

.parse_lines <- function(txt) {
  ln <- strsplit(txt, "\n")[[1L]]
  FAIRbioHeadersTools:::.bh_parse_record(ln)
}
.json_of <- function(txt) {
  r <- .parse_lines(txt)
  FAIRbioHeadersTools:::.bh_record_json(r$record)
}

test_that("one-item sequences are recovered in block and flow style", {
  expect_equal(FAIRbioHeadersTools:::.bh_sequence_keys(c("relatedLink:", "- https://x")),
    "relatedLink")
  expect_equal(FAIRbioHeadersTools:::.bh_sequence_keys("relatedLink: [https://x]"),
    "relatedLink")
  expect_equal(
    FAIRbioHeadersTools:::.bh_sequence_keys(c("taxon:", "  name: H", "  uri: https://x")),
    character()
  )
  expect_equal(as.character(.json_of("identifier:\n- example.org:A\nversion: '1.0.0'\n")),
    '{"identifier":["example.org:A"],"version":"1.0.0"}')
  # a genuine scalar stays a scalar
  expect_equal(as.character(.json_of("documentation: one sentence\nversion: '1.0.0'\n")),
    '{"documentation":"one sentence","version":"1.0.0"}')
  expect_equal(as.character(.json_of("a:\n- p\n- q\n")), '{"a":["p","q"]}')
  # (never use y or n as a fixture value: R's yaml reads them as booleans, which is
  # precisely the R12 non-portability the reader rejects)
  # empty sequence and empty mapping stay distinguishable
  expect_equal(as.character(.json_of("a: []\nb: {}\n")), '{"a":[],"b":{}}')
})

test_that("the repair applies inside sequence items too", {
  txt <- paste(c(
    "x-fhgm-models:", "- id: M1", "  features:", "  - f1", "  genes:", "  - g1",
    "  notes:", "  - n1"
  ), collapse = "\n")
  j <- as.character(.json_of(txt))
  expect_match(j, '"features":\\["f1"\\]')
  expect_match(j, '"genes":\\["g1"\\]')
  expect_match(j, '"notes":\\["n1"\\]')
})

test_that("the repair never invents a sequence where the text has a scalar", {
  # `relatedLink:` written as a bare scalar is a shape error in the file, and the contract
  # must still see a string. Coercing by contract declaration would accept it silently,
  # which is the failure mode this design refuses.
  expect_equal(as.character(.json_of("relatedLink: https://x\n")),
    '{"relatedLink":"https://x"}')
  rejected <- .bh_verdict(.bh_contract_text("fhr", "2.1"),
    .bh_json(list(schema = "https://w3id.org/fair-bioheaders/fhr/v0.6.0",
      schemaVersion = "2.1", genome = "g", version = "1",
      metadataAuthor = list(list(name = "A")), masking = "not-masked",
      taxon = list(name = "H"), relatedLink = "https://x")),
    "ajv"
  )
  expect_false(rejected)
})

test_that("R14 fires on a single-item relatedLink with an unaccepted scheme", {
  a <- .bh_capture(.bh_analyze(.bh_vector_path("fasta-link-scheme-warning"),
    format = "fasta"
  ))
  expect_true(a$value$valid) # valid: R14 is a warning, not a rejection
  expect_match(paste(a$value$warnings, collapse = " | "), "R14")
  expect_match(paste(a$value$warnings, collapse = " | "), "javascript:void\\(0\\)")
})

test_that("the empty-required guidance warns on present-but-empty, not on absent", {
  contract <- .bh_contract("fhr", "2.1")
  w <- FAIRbioHeadersTools:::.bh_empty_required_warnings(
    list(
      genome = "", version = "1.0.0", taxon = list(name = ""),
      metadataAuthor = list(), assemblyAuthor = list(list(name = ""))
    ),
    contract
  )
  expect_true(any(grepl("genome is an empty string", w)))
  expect_true(any(grepl("taxon has neither name nor uri", w)))
  expect_true(any(grepl("metadataAuthor has no value", w)))
  expect_true(any(grepl("assemblyAuthor holds an item with an empty name", w)))
  # a required key that is simply absent is the schema's business, not a duplicate warning
  expect_false(any(grepl("is missing", w)))
})

test_that("R8, R12 and R13 are caught in the text and the parsed value", {
  why <- function(txt) paste(.parse_lines(txt)$why, collapse = " | ")
  expect_match(why("a: 1\na: 2\n"), "R8")
  expect_match(why("a: &x 1\nb: *x\n"), "R8")
  expect_match(why("a: &a\n  k: 1\nb:\n  <<: *a\n"), "R8")
  expect_match(why("a: !!str 1\n"), "R12")
  expect_match(why("a: 010\n"), "R12")
  expect_match(why("a: 1_000\n"), "R12")
  expect_match(why("a: 1:30\n"), "R12")
  expect_match(why("a: 1e3\n"), "R12")
  expect_match(why("a: yes\n"), "R12")
  expect_match(why("a: y\n"), "R12")
  expect_match(why("a: .inf\n"), "R13")
  expect_match(why("a: .nan\n"), "R13")
  # values YAML 1.1 and 1.2 read alike are left alone
  expect_equal(why("a: true\nb: '2.0'\nc: 1.5\nd: 2026-01-02\n"), "")
})
