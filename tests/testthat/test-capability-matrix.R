# The published capability matrix, and the invariants that keep it honest.
#
# CI regenerates docs/CAPABILITY-MATRIX.md from bh_capability() and fails on drift, which
# pins the table to the code. These tests pin the code to the truth: a gap names a reason,
# a filled cell does not smuggle a gap into its reason text, and nothing reads as released
# that the registry says is not.

test_that("every matrix cell declares its support and its reason", {
  m <- bh_capability()
  expect_gt(nrow(m), 30L)
  expect_false(any(is.na(m$support)))
  expect_setequal(unique(m$support),
    c("native", "draft-lane", "not-supported-yet", "not-applicable")
  )
  # a gap is never blank: it names a blocker, and where one exists, a tracker
  gaps <- m[m$support %in% c("not-supported-yet", "not-applicable"), ]
  expect_true(all(nzchar(gaps$blocker)))
  nsy <- m[m$support == "not-supported-yet", ]
  expect_true(all(nzchar(nsy$tracker)))
  # a filled cell may carry a condition note, but never one that says the operation is
  # missing: that would be a gap written as a capability
  filled <- m[m$support %in% c("native", "draft-lane"), ]
  notes <- tolower(filled$blocker[!is.na(filled$blocker)])
  expect_false(any(grepl("not implemented|unbuilt|not supported", notes)))
})

test_that("the matrix refuses to claim the five types are supported", {
  m <- bh_capability()
  t <- bh_types()
  expect_setequal(t$header_type, c("FHR", "FHP", "FHGFF3", "FHT", "FHGM"))
  expect_equal(t$status[t$header_type %in% c("FHT", "FHGM")], c("draft", "draft"))
  rel <- m[m$type_status == "released", ]
  expect_setequal(unique(rel$header_type), c("FHR", "FHP", "FHGFF3"))
  # the draft types appear only with draft-lane, not-supported-yet or not-applicable
  drafts <- m[m$header_type %in% c("FHT", "FHGM"), ]
  expect_setequal(unique(drafts$support),
    c("draft-lane", "not-supported-yet", "not-applicable")
  )
  # FHGM is not a header type and has no serialization of its own
  expect_false(t$is_header_type[t$header_type == "FHGM"])
  fhgm <- t[t$header_type == "FHGM", ]
  expect_match(fhgm$serializations, "nested")
  # and no FHGM row of any kind is a released-type row
  expect_false(any(m$header_type == "FHGM" & m$type_status == "released"))
})

test_that("the native rows cover exactly the contract versions that are vendored", {
  cs <- bh_contracts()
  m <- bh_capability()
  for (i in seq_len(nrow(cs))) {
    t <- cs$header_type[[i]]
    ver <- cs$schema_version[[i]]
    hit <- m[m$header_type == t & m$operation == "validate_contract" &
      m$support == "native", , drop = FALSE]
    expect_true(nrow(hit) >= 1L, info = paste(t, "has no native validate_contract row"))
    listed <- unlist(strsplit(paste(hit$contract_versions, collapse = ","), ", "))
    listed <- gsub(paste0("^", t, " "), "", trimws(listed))
    expect_true(ver %in% listed,
      info = paste(t, ver, "not in", paste(listed, collapse = "/"))
    )
  }
  # and no native row names a version this build does not hold
  nat <- m[m$support == "native", ]
  for (i in seq_len(nrow(nat))) {
    listed <- unlist(strsplit(nat$contract_versions[[i]], ", "))
    listed <- gsub("^[A-Za-z0-9]+ ", "", trimws(listed))
    for (ver in listed) {
      if (!grepl("^v?[0-9]", ver)) next
      expect_true(any(cs$schema_version == ver), info = paste(nat$header_type[[i]], ver))
    }
  }
})

test_that("the draft-lane cells say which rules they stop at", {
  m <- bh_capability()
  fhgm <- m[m$header_type == "FHGM", ]
  # every K rule in the FHGM vocabulary appears somewhere: K1/K2 as claimed scope,
  # K3-K6 as named gaps, and no K rule is left unmentioned
  claimed <- paste(fhgm$operation, fhgm$blocker, collapse = " ")
  for (k in c("K1", "K2", "K3", "K4", "K5", "K6")) {
    expect_true(grepl(k, claimed, fixed = TRUE), info = paste(k, "is nowhere in the matrix"))
  }
  # and the rule accounting agrees with the matrix: exactly K3-K6 are unverified
  cov <- bh_rule_coverage()
  expect_setequal(grep("^K", names(cov$unverified), value = TRUE),
    c("K3", "K4", "K5", "K6"))
  expect_true(all(c("K1", "K2") %in% cov$checked))
})
