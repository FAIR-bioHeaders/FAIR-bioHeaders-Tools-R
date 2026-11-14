#' Parent-link verification (the rule the FHT development suite calls C3)
#'
#' A header may cite a parent file: FHGFF3 through `derivedFrom[].genome.checksum` (and the
#' `annotates` form), FHT and FHP through their own `derivedFrom` entries. The cited value is
#' the SHA-512/256 of the parent's bytes, so verifying a link means recomputing it over the
#' parent the caller names. Nothing about that is inferable from the child alone: two
#' assemblies can share an accession, and a file name is not provenance. So the parent paths
#' are an argument here, and an entry with no path supplied is reported `unchecked`, never
#' silently passed - the shared suite's own instruction is that "a verifier must report an
#' invalid link, not treat it as unchecked and not pass it silently".
#'
#' This is a distinct operation from [bh_verify()], which checks a file against the checksum
#' line inside itself. A file's own checksum can match while its cited parent checksum does
#' not; both verdicts are reported, separately.
#'
#' @name links
NULL

#' The parent links a header cites
#'
#' @param path A file carrying a header with `derivedFrom` entries.
#' @param format,compressed,draft Passed to the reader.
#' @return A data frame with one row per cited link: `index`, `header_type`,
#'   `relationship`, `accession`, `stated_checksum`.
#' @export
bh_parent_links <- function(path, format = NULL, compressed = NA, draft = getOption("bh.draft_lane", FALSE)) {
  a <- .bh_analyze(path, format = format, compressed = compressed, draft = draft,
    verify_checksum = FALSE, validate_contract = FALSE
  )
  if (is.null(a$record)) return(.bh_empty_links())
  df <- a$record$derivedFrom
  if (is.null(df)) return(.bh_empty_links())
  if (!is.list(df)) df <- list(df)
  entries <- lapply(seq_along(df), function(i) {
    e <- df[[i]]
    g <- e$genome
    if (is.null(g)) g <- e$parent
    data.frame(
      index = i,
      header_type = .bh_c(e$headerType, .bh_c(g$headerType, NA_character_)),
      relationship = .bh_c(e$relationship, NA_character_),
      accession = .bh_c(g$accession, .bh_c(e$accession, NA_character_)),
      stated_checksum = .bh_c(g$checksum, .bh_c(e$checksum, NA_character_)),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, entries)
}

.bh_empty_links <- function() {
  data.frame(index = integer(), header_type = character(), relationship = character(),
    accession = character(), stated_checksum = character(), stringsAsFactors = FALSE)
}

#' Verifies the parent links of one file against the parent files the caller supplies
#'
#' @param path The child file.
#' @param parent Parent file paths, matched to the cited links in order. A named vector
#'   (`c(FHR = "genome.fhr.fasta")`) matches by the cited `headerType` instead; entries no
#'   name covers stay `unchecked`.
#' @param format,compressed,draft Passed to the reader.
#' @return A list with `links` (the cited links plus `parent`, `computed`, `verdict` -
#'   `match`, `mismatch` or `unchecked`), `all_matched`, `mismatched` and `unchecked`
#'   counts.
#' @export
bh_verify_links <- function(path, parent = NULL, format = NULL, compressed = NA,
                            draft = getOption("bh.draft_lane", FALSE)) {
  links <- bh_parent_links(path, format = format, compressed = compressed, draft = draft)
  if (!nrow(links)) {
    return(list(links = links, all_matched = TRUE, mismatched = 0L, unchecked = 0L))
  }
  if (!is.null(names(parent))) {
    # matched by cited header type; an entry whose type is absent stays unchecked
    picks <- ifelse(is.na(links$header_type), NA_character_, links$header_type)
    files <- vapply(picks, function(k) {
      hit <- parent[names(parent) == k]
      if (length(hit)) hit[[1L]] else NA_character_
    }, "")
  } else {
    files <- if (length(parent)) parent[seq_len(nrow(links))] else rep(NA_character_, nrow(links))
    length(files) <- nrow(links)
  }
  links$parent <- unname(files)
  links$computed <- NA_character_
  links$verdict <- "unchecked"
  for (i in seq_len(nrow(links))) {
    f <- links$parent[[i]]
    if (is.na(f) || !nzchar(f)) next
    if (!file.exists(f)) {
      links$verdict[[i]] <- "missing-parent-file"
      next
    }
    if (is.na(links$stated_checksum[[i]])) next
    got <- bh_checksum(f, format = NULL)
    links$computed[[i]] <- got$computed
    links$verdict[[i]] <- if (identical(got$computed, links$stated_checksum[[i]])) {
      "match"
    } else {
      "mismatch"
    }
  }
  list(
    links = links,
    all_matched = !any(links$verdict %in% c("mismatch", "missing-parent-file")),
    mismatched = sum(links$verdict == "mismatch"),
    unchecked = sum(links$verdict == "unchecked")
  )
}
