# The header YAML scan (R/yaml-scan.R) and the parse that follows it (R/record.R).
# Expected verdicts are the Python reference's (fair-bioheaders 0.12.0) on the same text.

read_extra <- function(extra, ...) suppressWarnings(bh_read(.bh_write_header_file(extra, ...)))
issues_of <- function(extra) read_extra(extra)$issues
scan_of <- function(txt) .bh_yaml_scan(strsplit(txt, "\n", fixed = TRUE)[[1L]])

test_that("integers past 2^31 read as numbers, not NA (C1)", {
  r <- read_extra("vitalStats:\n  totalBasePairs: 3100000000\n  numberContigs: 5\n")
  expect_true(r$valid, info = paste(r$issues, collapse = "; "))
  expect_identical(r$record$vitalStats$totalBasePairs, 3100000000)

  r <- read_extra("x-a: 2147483648\nx-b: 9007199254740992\nx-c: 12345678901234567890123\n")
  expect_true(r$valid, info = paste(r$issues, collapse = "; "))
  expect_identical(r$record[["x-a"]], 2^31)
  expect_identical(r$record[["x-b"]], 2^53)
  expect_identical(r$record[["x-c"]], 12345678901234567890123)
  expect_false(any(vapply(r$record, function(v) identical(v, "NA"), NA)))
  # still an integer where it fits
  expect_identical(read_extra("x-a: 2147483647\n")$record[["x-a"]], 2147483647L)
  expect_identical(read_extra("x-a: 0x1F\n")$record[["x-a"]], 31L)
  expect_identical(read_extra("x-a: 0x100000000\n")$record[["x-a"]], 2^32)
})

test_that("anchors, aliases and merge keys are rejected anywhere, and never parsed (H1)", {
  cases <- c(
    "x-a: [&a 1, *a]\n", "x-a: {k: &a 1}\n", "x-a: {k: *a}\n", "&a x-a: 1\n",
    "x-a: {&a k: 1}\n", "x-a: {<<: {b: 1}}\n", "x-a:\n  <<: {b: 1}\n",
    "x-a:\n- &a 1\n- *a\n", "x-a: [[*a]]\n", "x-a: <<\n"
  )
  for (x in cases) {
    r <- read_extra(x)
    expect_false(r$valid, info = x)
    expect_true(any(grepl("^R8: ", r$issues)), info = x)
    expect_null(r$record)
  }
  # the same characters inside quotes, block scalars and comments are text
  for (x in c("x-a: '&a *b <<'\n", "x-a: \"[*a, &b]\"\n", "x-a: |\n  &a *a\n  <<: x\n",
              "x-a: b # &c *d\n", "x-a: a&b*c\n", "x-a: '<<'\n")) {
    r <- read_extra(x)
    expect_true(r$valid, info = paste(x, paste(r$issues, collapse = "; ")))
  }
})

test_that("the billion-laughs shape is refused before R's yaml can expand it (H1)", {
  laughs <- paste0("x-a: &a [\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\"]\n",
    paste0(sprintf("x-%s: &%s [*%s,*%s,*%s,*%s,*%s,*%s,*%s,*%s,*%s]\n",
      letters[2:10], letters[2:10], letters[1:9], letters[1:9], letters[1:9], letters[1:9],
      letters[1:9], letters[1:9], letters[1:9], letters[1:9], letters[1:9]), collapse = ""))
  t <- system.time(r <- read_extra(laughs))[["elapsed"]]
  expect_false(r$valid)
  expect_null(r$record)
  expect_lt(t, 10)
})

test_that("nesting past 64 levels and more than 20,000 nodes are refused as reader limits", {
  # boundaries measured against the Python reference: 63 nested block mappings below the
  # root pass, 64 do not; a flow sequence of 19,997 items passes, 19,998 do not
  nest <- function(d) {
    paste0(paste0(strrep(" ", 0:(d - 2)), "k", 0:(d - 2), ":", collapse = "\n"), "\n",
      strrep(" ", d - 1L), "k: v")
  }
  expect_null(scan_of(nest(63))$limit)
  expect_match(scan_of(nest(64))$limit, "nested more than 64 levels")
  flow <- function(d) paste0("a: ", strrep("[", d), "1", strrep("]", d))
  expect_null(scan_of(flow(62))$limit)
  expect_match(scan_of(flow(63))$limit, "nested more than 64 levels")
  items <- function(n) paste0("a: [", paste(rep("1", n), collapse = ", "), "]")
  expect_null(scan_of(items(19997))$limit)
  expect_match(scan_of(items(19998))$limit, "more than 20000 nodes")

  # 10,000 levels used to overflow the C stack inside the parser
  deep <- paste0(paste0("x-k", 1:10000, ": {", collapse = ""), "a: 1", strrep("}", 10000), "\n")
  e <- tryCatch(read_extra(deep), bh_error = function(e) e)
  expect_s3_class(e, "bh_limit")
  e <- tryCatch(read_extra(paste0("x-a:\n", paste0(strrep(" ", 1:200), "k:", collapse = "\n"),
    " 1\n")), bh_error = function(e) e)
  expect_s3_class(e, "bh_limit")
})

test_that("a 9,000-line header reads in seconds, not tens of seconds (M3)", {
  extra <- paste0(sprintf("x-k%d: value %d\n", 1:9000, 1:9000), collapse = "")
  path <- .bh_write_header_file(extra)
  bh_dialect_probe() # once per session; not what is being timed
  t <- system.time(r <- suppressWarnings(bh_read(path)))[["elapsed"]]
  expect_true(r$valid)
  expect_lt(t, 15)
})

test_that("every tag form is rejected (H3)", {
  for (x in c("x-a: !foo 1\n", "x-a: !<tag:yaml.org,2002:str> 1\n", "x-a: [!!str 1]\n",
              "x-a: !expr 1\n", "x-a: ! 5\n", "x-a: {k: !!int 1}\n", "!!str x-a: 1\n",
              "x-a:\n- !!str 1\n")) {
    r <- read_extra(x)
    expect_false(r$valid, info = x)
    expect_true(any(grepl("^R12: an explicit YAML tag", r$issues)), info = x)
    expect_null(r$record)
  }
  expect_true(read_extra("x-a: 'a !b'\nx-b: c!d\n")$valid)
})

test_that("R12 applies to flow items, sequence items and keys, as in the reference (H4)", {
  bad <- c("x-a: [yes]\n", "x-a:\n- yes\n", "x-a: {k: on}\n", "x-a: [010]\n",
           "x-a: 0o17\n", "x-a: 1.0e3\n", "x-a: [1e3]\n", "x-a: 1_000\n", "x-a: 1:30\n",
           "x-a: 0b11\n", "x-a: =\n", "x-a: {y: 1}\n", "x-a:\n  Off: 1\n", "x-a: -0x1F\n")
  for (x in bad) {
    r <- read_extra(x)
    expect_false(r$valid, info = x)
    expect_true(any(grepl("^R12: ", r$issues)), info = paste(x, paste(r$issues, collapse = "; ")))
  }
  good <- c("x-a: 0x1F\n", "x-a: 1.5e+3\n", "x-a: [true, false, ~, null, 1.5, .5]\n",
            "x-a: 2026-10-08\n", "x-a: 'yes'\n", "x-a: yEs\n", "x-a: [\"on\", 'off']\n",
            "x-a: |\n  yes\n  010\n")
  for (x in good) {
    r <- read_extra(x)
    expect_true(r$valid, info = paste(x, paste(r$issues, collapse = "; ")))
  }
  # 1.0e+400 is portable, and too large for a double: R13 rejects it
  r <- read_extra("x-a: 1.0e+400\n")
  expect_false(r$valid)
  expect_true(any(grepl("^R13: /x-a ", r$issues)))
})

test_that("mapping keys must be strings", {
  for (x in c("x-a: {1: b}\n", "x-a: {~: b}\n", "x-a: {[a]: b}\n", "x-a: {true: b}\n")) {
    r <- read_extra(x)
    expect_false(r$valid, info = x)
    expect_true(any(grepl("^R8: .*not a string", r$issues)), info = x)
  }
})

test_that("R13 finds non-finite numbers in sequences and at the top level (M1)", {
  for (x in c("x-a: [1, .nan]\n", "x-a:\n- .inf\n- 2\n", "x-a: .NaN\n", "x-a: -.inf\n",
              "x-a: {b: [.inf]}\n")) {
    r <- read_extra(x)
    expect_false(r$valid, info = x)
    expect_true(any(grepl("^R13: ", r$issues)), info = x)
  }
})

test_that("text that merely mentions NaN, .inf, hex or YAML is not rejected (M2)", {
  for (x in c("x-a: NaN\n", "x-a: Infinity\n", "x-a: the NaN word\n",
              "x-a: see .inf files\n", "x-a: '.inf'\n", "x-a: \"Infinity\"\n",
              "x-a: |\n  yes: no\n  key: &anchor\n  dup: 1\n  dup: 2\n",
              "x-a: >\n  0x1F and 010\n", "x-a: 0x1F\n")) {
    r <- read_extra(x)
    expect_true(r$valid, info = paste(x, paste(r$issues, collapse = "; ")))
  }
  expect_identical(read_extra("x-a: NaN\n")$record[["x-a"]], "NaN")
})

test_that("duplicate keys are found per mapping, block or flow, and not inside text", {
  expect_true(any(grepl("R8: a duplicate", issues_of("x-a: 1\nx-a: 2\n"))))
  expect_true(any(grepl("R8: a duplicate", issues_of("x-a: {k: 1, k: 2}\n"))))
  expect_true(any(grepl("R8: a duplicate", issues_of("x-a: {\"k\":1,\"k\":2}\n"))))
  expect_true(read_extra("x-a:\n  k: 1\nx-b:\n  k: 1\n")$valid)
})

test_that(".na and its variants are strings, not R's NA", {
  r <- read_extra("x-a: .na\nx-b: .na.character\nx-c: [.na.real, .na.integer]\n")
  expect_true(r$valid, info = paste(r$issues, collapse = "; "))
  expect_identical(r$record[["x-a"]], ".na")
  expect_identical(r$record[["x-b"]], ".na.character")
  expect_identical(unlist(r$record[["x-c"]]), c(".na.real", ".na.integer"))
  r <- read_extra("", base = sub("Synthetic genome", ".na.character", .bh_fhr_base))
  expect_true(r$valid)
  expect_identical(r$record$genome, ".na.character")
})

test_that("JSON-style flow values, multi-line quoted values and block scalars still read", {
  r <- read_extra(paste0(
    "x-a: {\"k\":[1,2],\"j\":{\"m\":\"n\"}}\n",
    "x-b: \"first\n  second\"\n",
    "x-c: 'one\n  two'\n",
    "x-d: [a,\n  b]\n",
    "x-e: |\n  text\n"
  ))
  expect_true(r$valid, info = paste(r$issues, collapse = "; "))
  expect_identical(r$record[["x-b"]], "first second")
})
