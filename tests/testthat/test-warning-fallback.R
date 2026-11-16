# The issue #12 ruling retains every call part when sprintf() cannot format it.
test_that("warning formatting failure keeps the joined parts and warning classes", {
  expect_error(sprintf("%s %d", "a"))
  raised <- NULL
  result <- withCallingHandlers(
    withVisible(FAIRbioHeadersTools:::bh_warn("draft", "%s %d", "a")),
    warning = function(w) {
      raised <<- w
      invokeRestart("muffleWarning")
    }
  )
  expect_identical(conditionMessage(raised), "%s %da")
  expect_identical(class(raised), c("bh_draft", "bh_warning", "warning", "condition"))
  expect_null(result$value)
  expect_false(result$visible)
})
