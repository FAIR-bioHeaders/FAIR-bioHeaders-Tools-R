#' Framing a file's leading block, its checksum line and its grammar
#'
#' Everything here is docs/FORMAT.md R2, R5, R6, R7, R10 plus G1 for GFF3, applied to
#' bytes rather than to text lines. The reason a reader cannot simply use
#' `readLines()`: R1 defines a line to end at LF, at CRLF, or at a CR that is not
#' followed by LF, with the terminator belonging to the line; `readLines()` normalizes
#' endings away, so a file whose checksum was computed over its real bytes can no longer
#' be related to them. R6 adds that header lines must be UTF-8 while bytes outside the
#' header are never decoded at all, and R7 that a FASTA or GFA file must not begin with a
#' UTF-8 byte order mark.
#'
#' The indent of a root-level header key is measured with [regexpr()]. The POSIX
#' `sub("^( *).*$", "\\\\1", x)` spelling that looks equivalent returns the wrong width in
#' R - a back-reference in a POSIX-typed substitution is not the PCRE behaviour people
#' expect - and a wrong indent silently reclassifies a nested `checksum` as the root
#' checksum line, which is how `fasta-only-nested-checksum` and
#' `fasta-nested-checksum-line` get mis-verdicted. Measured, not inferred: see
#' the `sub()` variants pinned in tests/testthat/test-framing.R.
#'
#' @name framing
NULL

# The limits docs/FORMAT.md lets a reader enforce ("Readers may refuse input beyond these
# limits"), collected so they are not scattered as literals. Exceeding one is reported as
# a refusal with the limit named, never as an invalid file.
.bh_limits <- list(
  header_block_bytes = 1024 * 1024,
  header_block_lines = 10000L,
  metadata_file_bytes = 64 * 1024 * 1024
)

# `%||%` and `.bh_c` were also defined here, duplicating R/internals.R. The copies in
# R/internals.R are the ones the namespace binds (this file is collated first), so #12 removed
# these duplicates; both were byte-identical to the retained definitions.

.bh_is_gzip_file <- function(path) {
  con <- file(path, "rb")
  on.exit(close(con), add = TRUE)
  b <- readBin(con, what = "raw", n = 2L)
  length(b) == 2L && identical(b, as.raw(c(0x1f, 0x8b)))
}

#' Opens a file's bytes for reading, decompressing a gzip transport strictly.
#'
#' Returns `list(read = function(n), close = function())`. A compressed file is read by
#' the zlib reader in src/gz.c rather than by `gzfile()`, which drops bytes after the last
#' member without a word and reports a bad CRC or a truncated member only as a connection
#' warning. Here each of those is a classed `bh_input` error naming the problem.
#' @noRd
.bh_open_input <- function(path, compressed) {
  if (!isTRUE(compressed)) {
    con <- file(path, open = "rb")
    return(list(read = function(n) readBin(con, what = "raw", n = n),
                close = function() close(con)))
  }
  ptr <- .Call(C_gz_open, path)
  list(
    read = function(n) {
      r <- .Call(C_gz_read, ptr, as.integer(n))
      if (is.character(r)) {
        bh_abort("input", "%s", paste0("cannot read ", basename(path), " as gzip: ", r))
      }
      r
    },
    close = function() invisible(.Call(C_gz_close, ptr))
  )
}

#' Independent detection of the R1 framing condition on one file's own bytes.
#'
#' TRUE when the bytes AT `path` carry the gzip magic AND the strict reader cannot
#' reach the end of a member - the stream is truncated. Nothing from any manifest
#' is consulted: this is the runner re-reading the file, the same external evidence
#' the released reader's own errors are built on. A CRC-corrupt stream or trailing
#' non-gzip bytes are refused by the reader but are not truncations, so they do not
#' match here. Used by the conformance runner's R1 scoring (R/conformance.R).
#' @noRd
.bh_gz_stream_truncated <- function(path) {
  con <- file(path, open = "rb")
  magic <- readBin(con, what = "raw", n = 2L)
  close(con)
  if (length(magic) != 2L || !identical(magic, as.raw(c(0x1f, 0x8b)))) return(FALSE)
  r <- .bh_capture({
    inp <- .bh_open_input(path, compressed = TRUE)
    repeat {
      b <- inp$read(1048576L)
      if (!length(b)) break
    }
    inp$close()
    TRUE
  })
  !is.null(r$error) &&
    grepl("truncated: the file ends inside a member", r$error, fixed = TRUE)
}

.bh_nl <- as.raw(10)
.bh_cr <- as.raw(13)

# Substr's upper bound: longer than any line the limits allow.
.bhc_max <- 10000000L

#' Splits bytes into lines under rule R1.
#'
#' @param b A raw vector.
#' @return A list with `start`, `end` (1-based, inclusive of the terminator) and `n`.
#'   A trailing fragment with no terminator counts as a line.
#' @noRd
.bh_split_lines <- function(b) {
  n <- length(b)
  if (n == 0L) return(list(start = integer(), end = integer(), n = 0L))
  is_lf <- b == .bh_nl
  is_cr <- b == .bh_cr
  cr_ends <- which(is_cr)
  cr_pair <- cr_ends[cr_ends < n & is_lf[cr_ends + 1L]]
  ends <- sort(unique(c(which(is_lf), setdiff(cr_ends, cr_pair))))
  if (!length(ends)) ends <- n
  if (ends[length(ends)] != n) ends <- c(ends, n)
  list(start = as.integer(c(1L, ends[-length(ends)] + 1L)), end = as.integer(ends),
       n = length(ends))
}

.bh_line_bytes <- function(b, lines, i) b[seq.int(lines$start[[i]], lines$end[[i]])]

#' Decodes a line, or returns NA when it is not valid UTF-8 (rule R6).
#' @noRd
.bh_decode <- function(bytes) {
  if (!length(bytes)) return("")
  s <- tryCatch(rawToChar(bytes), error = function(e) NA_character_)
  if (is.na(s)) return(NA_character_)
  out <- suppressWarnings(iconv(s, "UTF-8", "UTF-8"))
  if (length(out) != 1L || is.na(out)) NA_character_ else out
}

#' Drops the terminator(s) at the end of a decoded line.
#' @noRd
.bh_strip_term <- function(s) sub("[\r\n]+$", "", s)

.bh_prefix <- function(format) {
  switch(format,
    fasta = ";~",
    `fhp-fasta` = ";~",
    `fht-fasta` = ";~",
    gfa = "#~",
    fhgff3 = "#~",
    bh_abort("input", paste0(
      "unknown serialization ", shQuote(as.character(format)[1L])
    ))
  )
}

.bh_has_prefix <- function(bytes, prefix) {
  p <- charToRaw(prefix)
  length(bytes) >= length(p) && identical(bytes[seq_along(p)], p)
}

#' Rule R7: a FASTA or GFA file must not begin with a UTF-8 BOM.
#' @noRd
.bh_bom_issue <- function(bytes, format) {
  if (!format %in% c("fasta", "gfa", "fhp-fasta", "fht-fasta")) return(character())
  if (length(bytes) >= 3L && identical(bytes[seq_len(3L)], as.raw(c(0xef, 0xbb, 0xbf)))) {
    return("R7: the file begins with a UTF-8 byte order mark")
  }
  character()
}

#' Frames the leading block.
#'
#' @param b The leading bytes (at least the whole block; see `.bh_head()`).
#' @param format The serialization.
#' @param complete TRUE when `b` is the entire decompressed file.
#' @return A list with `lines`, `text`, `header` (indices of header lines), `extent`
#'   (logical, per line), `block_end` (index of the first line after the block, or NA),
#'   `scan_after` (the byte offset from which a header line is late), `why`.
#' @noRd
.bh_frame <- function(b, format, complete = TRUE) {
  lines <- .bh_split_lines(b)
  text <- vapply(seq_len(lines$n), function(i) .bh_decode(.bh_line_bytes(b, lines, i)), "")
  prefix <- .bh_prefix(format)
  n <- lines$n
  header <- integer()
  extent <- logical(n)
  why <- .bh_bom_issue(b, format)
  block_end <- NA_integer_

  for (i in seq_len(n)) {
    raw_line <- .bh_line_bytes(b, lines, i)
    shown <- .bh_c(text[[i]], "\001invalid\001")
    blank <- grepl("^[ \t\r\n]*$", shown)
    fc <- if (length(raw_line)) rawToChar(raw_line[[1L]]) else ""
    pref <- .bh_has_prefix(raw_line, prefix)

    if (format == "fhgff3" && i == 1L) {
      s <- .bh_strip_term(shown)
      if (!grepl("^##gff-version 3(\\.[0-9]+\\.[0-9]+)?[ \t]*$", s)) {
        why <- c(why, "G1: line 1 is not '##gff-version 3' or '##gff-version 3.x.y'")
      }
      if (pref) why <- c(why, "G1: a #~ line may not be line 1")
      extent[[i]] <- TRUE
      next
    }

    if (is.na(block_end)) {
      stop_line <- switch(format,
        fasta = fc == ">",
        `fhp-fasta` = fc == ">",
        `fht-fasta` = fc == ">",
        gfa = !blank && fc != "#",
        fhgff3 = (!blank && fc != "#") || startsWith(.bh_strip_term(shown), "##FASTA"),
        FALSE
      )
      if (stop_line) block_end <- i else extent[[i]] <- TRUE
    }

    if (!is.na(block_end) && i >= block_end && pref) {
      why <- c(why, "R10: a header line appears after the leading block")
    }

    if (extent[[i]] && pref) {
      if (is.na(text[[i]])) {
        why <- c(why, "R6: a header line is not valid UTF-8")
      } else {
        header <- c(header, i)
      }
    }
  }

  if (!length(header)) why <- c(why, "R2: the file carries no header block")
  if (is.na(block_end) && !complete) {
    bh_abort("limit", paste0(
      "the leading header block is larger than the ", length(b),
      " bytes this reader loaded; the block exceeds the limit docs/FORMAT.md allows a ",
      "reader to enforce"
    ))
  }
  if (length(header) > .bh_limits$header_block_lines) {
    bh_abort("limit", paste0(
      "the header block holds ", length(header), " lines, over the limit of ",
      .bh_limits$header_block_lines
    ))
  }

  list(
    bytes = b, lines = lines, text = text, header = header, extent = extent,
    block_end = block_end, prefix = prefix, format = format,
    scan_after = if (!is.na(block_end)) lines$start[[block_end]] else length(b) + 1L,
    why = unique(why)
  )
}

#' Reads the leading bytes of a file: enough to cover the whole header block.
#'
#' The block is bounded by docs/FORMAT.md's reader limits, so the head is read in
#' doubling steps up to `header_block_bytes` plus one, and `complete` says whether the
#' file ended inside that window.
#'
#' @return A list with `bytes`, `compressed` and `complete`.
#' @noRd
.bh_head <- function(path, compressed = NA, limit = .bh_limits$header_block_bytes) {
  if (is.na(compressed)) compressed <- .bh_is_gzip_file(path)
  con <- .bh_open_input(path, compressed)
  on.exit(con$close(), add = TRUE)
  step <- min(65536L, limit + 1L)
  got <- raw()
  repeat {
    b <- con$read(step)
    got <- c(got, b)
    if (length(b) < step) {
      return(list(bytes = got, compressed = compressed, complete = TRUE))
    }
    if (length(got) > limit) {
      return(list(bytes = got, compressed = compressed, complete = FALSE))
    }
    step <- min(step * 4L, limit + 1L - length(got))
  }
}

#' Rules R2 and R5: the one root-level checksum line and what it may contain.
#'
#' @param frame The result of `.bh_frame()`.
#' @return A list with `ok`, `index`, `value`, `root_indent`, `why`.
#' @noRd
.bh_find_checksum <- function(frame) {
  prefix <- frame$prefix
  idx <- frame$header
  if (!length(idx)) {
    return(list(ok = FALSE, index = NA_integer_, value = NA_character_,
                root_indent = NA_integer_, why = "R2: no header line to scan"))
  }
  first <- .bh_strip_term(.bh_c(frame$text[[idx[[1L]]]], ""))
  m <- regexpr(paste0("^", prefix, " *"), first)
  if (m[[1L]] < 0) {
    return(list(ok = FALSE, index = NA_integer_, value = NA_character_,
                root_indent = NA_integer_, why = "R2: the first header line is malformed"))
  }
  root_indent <- nchar(regmatches(first, m)) - nchar(prefix)

  # one vectorized pass: a per-line loop here cost seconds on a 10,000-line header
  txt <- .bh_strip_term(vapply(frame$text[idx], .bh_c, "", default = ""))
  g <- regmatches(txt, regexec(paste0("^", prefix, "( *)checksum( *):"), txt))
  hit <- vapply(g, function(m) length(m) > 0L && nchar(m[[2L]]) == root_indent, NA)
  cand <- idx[hit]
  if (length(cand) != 1L) {
    return(list(ok = FALSE, index = NA_integer_, value = NA_character_,
                root_indent = root_indent,
                why = paste0("R2: ", length(cand), " root-level checksum line(s)")))
  }

  i <- cand[[1L]]
  l <- .bh_strip_term(.bh_c(frame$text[[i]], ""))
  rest <- sub(paste0("^", prefix, " *checksum *:"), "", l)
  if (grepl(paste0("^ +", .bh_b64_canonical, " *$"), rest)) {
    value <- trimws(rest)
  } else if (grepl(paste0("^ +[\"']", .bh_b64_canonical, "[\"'] *$"), rest)) {
    value <- gsub("^['\"]|['\"]$", "", trimws(rest))
  } else {
    return(list(
      ok = FALSE, index = i, value = NA_character_, root_indent = root_indent,
      why = paste0("R5: the checksum line holds more than the value: ", rest)
    ))
  }
  list(ok = TRUE, index = i, value = value, root_indent = root_indent, why = character())
}

# The 44-character canonical base64 of rules R4 and R5: 42 alphabet characters, one of
# the 16 characters whose two unused low bits are zero, then the padding.
.bh_b64_canonical <- "[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]="

#' The byte range rule R3 excludes from the hash: the checksum line and its terminator.
#' @noRd
.bh_excluded_range <- function(frame, index) {
  c(frame$lines$start[[index]], frame$lines$end[[index]] - frame$lines$start[[index]] + 1L)
}

#' The header line texts with the prefix removed: one YAML document.
#' @noRd
.bh_header_lines <- function(frame) {
  k <- nchar(frame$prefix, type = "bytes")
  vapply(frame$header, function(i) {
    substr(.bh_strip_term(.bh_c(frame$text[[i]], "")), k + 1L, .bhc_max)
  }, "")
}
