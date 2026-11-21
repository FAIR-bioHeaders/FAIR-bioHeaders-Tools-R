# FHGM is transport, not a header type, and the code must behave like that claim.
#
# A file carrying model records under x-fhgm-models is an FHGFF3 file: it keeps the
# released FHGFF3 citation, its checksum covers its own bytes, and the extension key
# is rule R15 data the base schema cannot see inside. Nothing in the released lane may
# interpret it, and nothing may give FHGM a schemaVersion, a registry row or a w3id URL
# (rule V7). This tests the transport half; the model layer is tested in
# test-fhgm-lane.R, against the suite FHGM publishes for it.

test_that("an FHGFF3 1.1 header carries x-fhgm-models through as uninterpreted data", {
  # a released minimal FHGFF3 record, extended in memory only: no fixture is invented
  # and nothing is written to the pinned suite
  rec <- .bh_base_record("fhgff3-extension-fields")
  payload <- list(list(
    modelId = "model:synthetic-1", modelVersion = "1.0.0",
    featureId = "rna-1", reference = "file:./models.jsonl#1"
  ))
  rec[["x-fhgm-models"]] <- payload
  txt <- FAIRbioHeadersTools:::.bh_record_json(rec)
  expect_true(grepl("x-fhgm-models", txt, fixed = TRUE))
  # the FHGFF3 1.2 contract still accepts the key (R15 extension space), so the
  # transport is visible to the reader and invisible to the base schema's meaning
  v <- jsonvalidate::json_validator(.bh_contract_text("fhgff3", "1.2"), engine = "ajv")
  expect_true(isTRUE(suppressWarnings(v(txt))))
  # and it round-trips unchanged: the reader does not reorder, rename or drop it
  back <- jsonlite::fromJSON(txt, simplifyVector = FALSE)
  expect_identical(back[["x-fhgm-models"]], payload)
})

test_that("the model layer is claimed only for K1/K2, and the rest is still a gap", {
  m <- bh_capability()
  done <- m[m$header_type == "FHGM" &
    m$operation %in% c("read_model_records", "validate_model_records"), ]
  expect_equal(nrow(done), 2L)
  expect_true(all(done$support == "draft-lane"))
  # a draft-lane cell is not a native one, and its blocker states the boundary it stops at
  expect_false(any(m$support == "native" & m$header_type == "FHGM"))
  val <- done$blocker[done$operation == "validate_model_records"]
  expect_match(val, "K1")
  expect_match(val, "K2")
  expect_match(val, "not-run")
  expect_match(val, "55", fixed = TRUE)
  # the rules the run cannot evaluate are named operations with their own reason, not
  # folded into the cells above
  gaps <- m[m$header_type == "FHGM" & m$support == "not-supported-yet", ]
  expect_setequal(gaps$operation, c(
    "check_model_id_uniqueness", "resolve_feature_target",
    "check_reference_agreement", "resolve_revision_pointer"
  ))
  expect_true(all(nzchar(gaps$blocker)))
  expect_true(all(nzchar(gaps$tracker)))
  expect_true(all(grepl("K[3-6]", gaps$blocker)))
})

test_that("FHGM keeps no released form anywhere a reader could mistake for one", {
  reg <- FAIRbioHeadersTools:::.bh_registry()
  expect_setequal(names(reg$files), c("FHR", "FHP", "FHGFF3"))
  expect_setequal(names(reg$w3id), c("FHR", "FHP", "FHGFF3"))
  for (rel in names(reg$releases)) expect_null(reg$releases[[rel]]$FHGM)
  # no FHGM copy in the released schemas directory; the draft bytes live apart
  expect_false(any(grepl("fhgm", list.files(.bh_inst("schemas")))))
  expect_true(file.exists(.bh_inst("drafts", "fhgm-model-draft.schema.json")))
  t <- bh_types()
  expect_false(t$is_header_type[t$header_type == "FHGM"])
  expect_true(is.na(t$schema_versions[t$header_type == "FHGM"]))
})
