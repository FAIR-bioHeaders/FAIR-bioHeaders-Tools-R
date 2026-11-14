# The published capability matrix, and the parent-link operation.

test_that("every matrix cell declares its support and its reason", {
  m <- bh_capability()
  expect_gt(nrow(m), 30L)
  expect_false(any(is.na(m$support)))
  expect_setequal(unique(m$support),
    c("native", "draft-lane", "not-supported-yet", "not-applicable"))
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
  # nothing released is described as released when it is not
  rel <- m[m$type_status == "released", ]
  expect_setequal(unique(rel$header_type), c("FHR", "FHP", "FHGFF3"))
  # the draft types appear only with draft-lane, not-supported-yet or not-applicable
  drafts <- m[m$header_type %in% c("FHT", "FHGM"), ]
  expect_setequal(unique(drafts$support), c("draft-lane", "not-supported-yet", "not-applicable"))
  # FHGM is not a header type and has no serialization of its own
  expect_false(t$is_header_type[t$header_type == "FHGM"])
  fhgm <- t[t$header_type == "FHGM", ]
  expect_match(fhgm$serializations, "nested")
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
    expect_true(ver %in% listed, info = paste(t, ver, "not in", paste(listed, collapse = "/")))
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

test_that("bh_verify_links recomputes a cited parent checksum", {
  suite <- .bh_draft_suite_dir()
  child <- file.path(suite, "invalid/fht-fasta-parent-mismatched.fht.fasta")
  parent <- file.path(suite, "parents/parent-genome.fhr.fasta")
  skip_if_not(all(file.exists(child, parent)))
  links <- suppressWarnings(bh_parent_links(child, format = "fht-fasta", draft = "FHT"))
  expect_equal(nrow(links), 1L)
  expect_equal(links$relationship, "transcribedFrom")
  expect_false(is.na(links$stated_checksum))

  v <- suppressWarnings(bh_verify_links(child, parent = parent, format = "fht-fasta",
    draft = "FHT"
  ))
  expect_equal(v$links$verdict, "mismatch")
  expect_equal(v$mismatched, 1L)
  expect_false(v$all_matched)

  # the passing sibling: same parent, the checksum the parent really has
  okid <- file.path(suite, "valid/fht-fasta-parent-transcribed-from.fht.fasta")
  v2 <- suppressWarnings(bh_verify_links(okid, parent = parent, format = "fht-fasta",
    draft = "FHT"
  ))
  expect_equal(v2$links$verdict, "match")
  expect_true(v2$all_matched)

  # no path supplied: unchecked, and unchecked is not a pass
  v3 <- suppressWarnings(bh_verify_links(okid, format = "fht-fasta", draft = "FHT"))
  expect_equal(v3$links$verdict, "unchecked")
  expect_equal(v3$unchecked, 1L)
  expect_true(v3$all_matched) # nothing failed...
  expect_gt(v3$unchecked, 0L) # ...but the caller can see nothing was checked either

  # by header type rather than by position
  v4 <- suppressWarnings(bh_verify_links(okid, parent = c(FHR = parent),
    format = "fht-fasta", draft = "FHT"
  ))
  expect_equal(v4$links$verdict, "match")
})

test_that("a file's own checksum verdict and its parent-link verdict are separate facts", {
  suite <- .bh_draft_suite_dir()
  child <- file.path(suite, "invalid/fht-fasta-parent-mismatched.fht.fasta")
  skip_if_not(file.exists(child))
  # the child's own bytes are fine: the mismatch is about the parent it cites
  expect_true(suppressWarnings(bh_verify(child, format = "fht-fasta", draft = "FHT")))
  v <- suppressWarnings(bh_verify_links(child,
    parent = file.path(suite, "parents/parent-genome.fhr.fasta"),
    format = "fht-fasta", draft = "FHT"
  ))
  expect_equal(v$mismatched, 1L)
})

test_that("the mixed-verdict vector reports both links independently", {
  suite <- .bh_draft_suite_dir()
  child <- file.path(suite, "invalid/fht-fasta-parent-mixed-verdicts.fht.fasta")
  parents <- c(
    file.path(suite, "parents/parent-genome.fhr.fasta"),
    file.path(suite, "valid/fht-fasta-minimal.fht.fasta")
  )
  skip_if_not(all(file.exists(c(child, parents))))
  v <- suppressWarnings(bh_verify_links(child, parent = parents, format = "fht-fasta",
    draft = "FHT"
  ))
  expect_equal(nrow(v$links), 2L)
  expect_equal(v$links$verdict, c("match", "mismatch"))
  expect_equal(v$mismatched, 1L)
  expect_false(v$all_matched)
})
