#!/usr/bin/env Rscript
#' Render docs/CAPABILITY-MATRIX.md from bh_capability() itself.
#' Run after changing R/capability.R; CI re-renders and fails on drift.

suppressMessages(library(FAIRbioHeadersTools))
m <- bh_capability()
esc <- function(x) gsub("|", "\\|", gsub("\n", " ", x, fixed = TRUE), fixed = TRUE)
rows <- split(m, list(m$header_type, m$type_status), drop = TRUE)
lines <- c()
for (g in rows) {
  t <- g$header_type[[1L]]
  st <- g$type_status[[1L]]
  lines <- c(lines, sprintf("### %s (%s)", t, st), "")
  lines <- c(lines,
    "| operation | serialization | contract versions | support | blocker | tracker |",
    "| --- | --- | --- | --- | --- | --- |"
  )
  for (i in seq_len(nrow(g))) {
    lines <- c(lines, sprintf("| %s | %s | %s | **%s** | %s | %s |",
      esc(g$operation[i]), esc(g$serialization[i]), esc(g$contract_versions[i]),
      esc(g$support[i]), esc(g$blocker[i]), esc(g$tracker[i])
    ))
  }
  lines <- c(lines, "")
}
hdr <- readLines("docs/CAPABILITY-MATRIX.header.md")
while (length(lines) && !nzchar(lines[[length(lines)]])) lines <- lines[-length(lines)]
writeLines(c(hdr, lines), "docs/CAPABILITY-MATRIX.md")
cat("rendered docs/CAPABILITY-MATRIX.md with", nrow(m), "cells\n")
