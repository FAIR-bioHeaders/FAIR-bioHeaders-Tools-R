# Selection rules V1 to V6 of docs/SCHEMA-VERSIONS.md, against the vendored registry.

test_that("V1: raw-main selects this build's current contract of that type", {
  for (f in c("fhr", "fhp", "fhgff3")) {
    for (repo in c("FAIR-bioHeaders-Specification", "FHR-Specification")) {
      s <- bh_select(sprintf(
        "https://raw.githubusercontent.com/FAIR-bioHeaders/%s/main/%s.json", repo, f
      ))
      expect_equal(s$rule, "V1")
      expect_equal(s$header_type, toupper(f))
      expect_equal(s$release, "v0.6.0")
      expect_equal(s$status, "released")
    }
  }
})

test_that("V2 and V3: a release tag, and its w3id alias, select that release", {
  s2 <- bh_select(
    "https://raw.githubusercontent.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/v0.5.0/fhp.json"
  )
  expect_equal(c(s2$rule, s2$schema_version), c("V2", "1.1"))
  s3 <- bh_select("https://w3id.org/fair-bioheaders/fhgff3/v0.4.0")
  expect_equal(c(s3$rule, s3$schema_version), c("V3", "1.0"))
  s3s <- bh_select("https://w3id.org/fair-bioheaders/fhgff3/v0.4.0/") # trailing slash
  expect_equal(c(s3s$rule, s3s$schema_version), c("V3", "1.0"))
})

test_that("V4: an unknown ref or unregistered release is unsupported-version, not a guess", {
  cases <- c(
    "https://w3id.org/fair-bioheaders/fhr/v9.9.9",
    "https://w3id.org/fair-bioheaders/fhp/v0.3.1", # no FHP contract in that release
    "https://raw.githubusercontent.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/branch-name/fhr.json",
    "https://raw.githubusercontent.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/v9.9.9/fhr.json"
  )
  for (u in cases) {
    s <- bh_select(u)
    expect_equal(s$status, "unsupported", info = u)
    expect_match(s$message, "unsupported schema version|no contract", info = u)
    # the message must name the value and the releases this tool has, per V4
    expect_match(s$message, "this tool has", info = u)
  }
})

test_that("V5: anything else is FHR against the current FHR schema", {
  for (u in c(
    "https://example.org/profile/fhr.json", "not a url",
    "https://w3id.org/fair-bioheaders/fhr/v0.4.0/fhr.json", # the path form is not V3
    "https://raw.githubusercontent.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/main/core.yaml"
  )) {
    s <- bh_select(u)
    expect_equal(c(s$rule, s$header_type), c("V5", "FHR"), info = u)
  }
  expect_equal(bh_select(NULL)$rule, "V5")
  expect_equal(bh_select(NA_character_)$rule, "V5")
})

test_that("V6: raw-main plus the number 1 is FHR 1 (v0.3.1), deprecated not invalid", {
  raw <- "https://raw.githubusercontent.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/main/fhr.json"
  for (v in c(1, 1.0)) {
    s <- bh_select(raw, schema_version = v)
    expect_equal(s$rule, "V6")
    expect_equal(s$release, "v0.3.1")
    expect_equal(s$schema_version, "1")
    expect_match(paste(s$warnings, collapse = " "), "FHR 1 \\(v0.3.1\\)")
  }
  # the string "1", TRUE and other numbers are not the number 1
  for (v in list("1", TRUE, 2, 0, c(1, 1))) {
    s <- bh_select(raw, schema_version = v)
    expect_equal(s$rule, "V1", info = paste(class(v), v))
  }
  # V6 is FHR only: an FHP record cannot have an earlier raw-main contract
  s <- bh_select(
    "https://raw.githubusercontent.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/main/fhp.json",
    schema_version = 1
  )
  expect_equal(s$rule, "V1")
})

test_that("the registry rows and the vendored files agree with versions.json", {
  reg <- FAIRbioHeadersTools:::.bh_registry()
  cs <- bh_contracts()
  expect_null(reg$preRelease) # v0.6.0 is published
  for (rel in names(reg$releases)) {
    for (type in names(reg$releases[[rel]])) {
      v <- as.character(reg$releases[[rel]][[type]])
      row <- cs[cs$header_type == type & cs$schema_version == v, , drop = FALSE]
      expect_equal(nrow(row), 1L, info = paste(rel, type, v))
      expect_true(file.exists(.bh_inst("schemas", row$file[[1L]])), info = row$file[[1L]])
    }
  }
  # every vendored file is reachable from the registry, and its digest matches
  for (i in seq_len(nrow(cs))) {
    bytes <- .bh_read_all(.bh_inst("schemas", cs$file[[i]]))
    expect_identical(.bh_sha256_hex(bytes), cs$sha256[[i]], info = cs$file[[i]])
  }
})
