#' SHA-512/256 digests, computed natively in this package
#'
#' The FAIR-bioHeaders file checksum is SHA-512/256 - docs/FORMAT.md rule R4, the
#' 32-byte member of the SHA-512 family defined in FIPS 180-4 section 5.3.8. Neither
#' `digest` nor the R `openssl` package provides that algorithm, so the core is vendored
#' in `src/` and called through `.Call`. `docs/DIGEST.md` in the source repository
#' records the routes that were measured and rejected, and the evidence this one rests
#' on.
#'
#' There is no fallback. If the compiled core is missing or miscompiled these calls
#' error; nothing here silently substitutes SHA-512, a truncated SHA-512, an external
#' command or the Python toolkit. Truncated SHA-512 is a different algorithm that
#' produces a plausible 44-character value for every file, and that is the failure mode
#' this design refuses.
#'
#' @name digest
NULL

# useDynLib(.registration = TRUE, .fixes = "C_") binds the routines src/entry.c
# registers as C_digest, C_stream_new and so on. R_forceSymbols() is on, so .Call takes
# those objects rather than their names.
.bh_native <- c(
  "digest", "digest_len", "stream_new", "stream_scan", "stream_update", "stream_value",
  "selftest"
)

# An external pointer cannot be unclassed, so the stream handle keeps it in a list.
.bh_stream_ptr <- function(stream) {
  if (!inherits(stream, "bh_digest_stream") || is.null(stream$ptr)) {
    stop("`stream` must come from bh_digest_stream()", call. = FALSE)
  }
  stream$ptr
}

.bh_algo_number <- function(algo) {
  switch(algo,
    "sha512-256" = 0L,
    "sha512" = 1L,
    stop(
      "`algo` must be \"sha512-256\" (the FAIR-bioHeaders checksum, docs/FORMAT.md R4) ",
      "or \"sha512\", not ", sQuote(as.character(algo)[1L]), ".",
      call. = FALSE
    )
  )
}

# Resolves C_<suffix>. A build without the compiled routines fails here naming the real
# problem; nothing in this package substitutes another hash function.
.bh_native_sym <- function(suffix) {
  nm <- paste0("C_", suffix)
  sym <- get0(nm, envir = asNamespace("FAIRbioHeadersTools"), inherits = FALSE)
  if (is.null(sym)) {
    stop(
      "The compiled digest routine ", nm, " of this package is unavailable. Reinstall ",
      "the package from source (it needs a C compiler). Do not work around this by ",
      "substituting another hash function: a different algorithm yields a plausible ",
      "checksum that is wrong for every file (docs/FORMAT.md R4).",
      call. = FALSE
    )
  }
  sym
}

.bh_call <- function(suffix, ...) .Call(.bh_native_sym(suffix), ...)

.onLoad <- function(libname, pkgname) {
  dll <- getLoadedDLLs()[[pkgname]]
  if (is.null(dll)) {
    stop(
      "the shared library of package ", pkgname, " is not loaded; reinstall the package ",
      "from source.",
      call. = FALSE
    )
  }
  for (nm in .bh_native) {
    if (is.null(get0(paste0("C_", nm), envir = asNamespace(pkgname), inherits = FALSE))) {
      stop("native routine C_", nm, " is not registered in this build", call. = FALSE)
    }
  }
  code <- .bh_call("selftest")
  if (!identical(as.integer(code), 0L)) {
    stop(
      "The vendored SHA-512/256 core failed its built-in check against the published ",
      "sample digests (code ", code,
      "). This build would compute checksums that match no real FAIR-bioHeaders file; ",
      "see docs/DIGEST.md and tests/testthat/test-digest-vectors.R.",
      call. = FALSE
    )
  }
  invisible(NULL)
}

#' Compute a SHA-512/256 (or SHA-512) digest of bytes
#'
#' @param bytes A raw vector.
#' @param encoding One of `"raw"`, `"hex"` or `"b64"`. `"b64"` is the canonical padded
#'   standard base64 that rule R4 requires of a checksum: 44 characters for a
#'   SHA-512/256 digest, the character before `=` one of `AEIMQUYcgkosw048`, ending in
#'   `=`.
#' @return A length-1 raw vector or string, per `encoding`.
#' @examples
#' bh_sha512_256_b64(charToRaw("abc"))
#' bh_sha512_256(charToRaw("abc"), encoding = "hex")
#' # truncating SHA-512 is NOT SHA-512/256, and that is the trap:
#' substr(bh_sha512(charToRaw("abc"), encoding = "hex"), 1, 64)
#' @export
bh_sha512_256 <- function(bytes, encoding = c("raw", "hex", "b64")) {
  encoding <- match.arg(encoding)
  if (!is.raw(bytes)) stop("`bytes` must be a raw vector", call. = FALSE)
  .bh_call("digest", bytes, .bh_algo_number("sha512-256"), encoding)
}

#' @rdname bh_sha512_256
#' @export
bh_sha512 <- function(bytes, encoding = c("raw", "hex", "b64")) {
  encoding <- match.arg(encoding)
  if (!is.raw(bytes)) stop("`bytes` must be a raw vector", call. = FALSE)
  .bh_call("digest", bytes, .bh_algo_number("sha512"), encoding)
}

#' @rdname bh_sha512_256
#' @export
bh_sha512_256_b64 <- function(bytes) bh_sha512_256(bytes, encoding = "b64")

#' Digest length in bytes
#'
#' @param algo `"sha512-256"` or `"sha512"`.
#' @return An integer: 32 or 64.
#' @export
bh_digest_bytes <- function(algo = c("sha512-256", "sha512")) {
  algo <- match.arg(algo)
  as.integer(.bh_call("digest_len", .bh_algo_number(algo)))
}

#' An incremental SHA-512/256 hasher
#'
#' A reference genome is larger than what should be pulled into R memory, and rule R3
#' excludes the checksum line from the hashed bytes, so a file's checksum is produced by
#' feeding the covered ranges. [bh_stream_update()] advances the stream;
#' [bh_stream_value()] finalizes it and returns the digest.
#'
#' A stream can also count header lines beginning after a byte offset, which is rule
#' R10 (`;~`/`#~` lines must form the leading block, including in a concatenated file).
#' That check needs every line start in the file, so it rides along in the pass the hash
#' already makes; see [bh_stream_scan()].
#'
#' @param algo `"sha512-256"` (default) or `"sha512"`.
#' @param stream A stream from [bh_digest_stream()].
#' @param bytes A raw vector.
#' @param hashed Whether these bytes count toward the digest. Rule R3 excludes the
#'   checksum line from the hash, but those bytes still occupy file positions that rule
#'   R10 counts, so the excluded line is fed with `hashed = FALSE`.
#' @param prefix,after Rule R10 scan arguments: the header prefix as a raw vector, and
#'   the 1-byte-based offset from which late header lines are counted.
#' @param encoding `"b64"`, `"raw"` or `"hex"`.
#' @return [bh_digest_stream()] returns a stream handle; [bh_stream_update()] and
#'   [bh_stream_scan()] return it invisibly; [bh_stream_value()] returns a list with
#'   `digest` (the requested encoding), `hex`, `b64`, `bytes` (how many bytes were
#'   hashed) and `late_header_lines` (the rule R10 count, or `NA` when no scan was
#'   armed).
#' @examples
#' s <- bh_digest_stream()
#' bh_stream_update(s, charToRaw("ab"))
#' bh_stream_update(s, charToRaw("c"))
#' bh_stream_value(s, "hex")$digest
#' @export
bh_digest_stream <- function(algo = c("sha512-256", "sha512")) {
  algo <- match.arg(algo)
  structure(list(ptr = .bh_call("stream_new", .bh_algo_number(algo))),
    class = "bh_digest_stream"
  )
}

#' @rdname bh_digest_stream
#' @export
bh_stream_scan <- function(stream, prefix, after) {
  if (!inherits(stream, "bh_digest_stream")) {
    stop("`stream` must come from bh_digest_stream()", call. = FALSE)
  }
  if (!is.raw(prefix) || length(prefix) < 1L || length(prefix) > 8L) {
    stop("`prefix` must be a raw vector of 1 to 8 bytes", call. = FALSE)
  }
  if (!is.numeric(after) || length(after) != 1L || !is.finite(after) || after < 1) {
    stop("`after` must be a single finite number >= 1", call. = FALSE)
  }
  invisible(.bh_call("stream_scan", .bh_stream_ptr(stream), prefix, as.double(after)))
}

#' @rdname bh_digest_stream
#' @export
bh_stream_update <- function(stream, bytes, hashed = TRUE) {
  if (!inherits(stream, "bh_digest_stream")) {
    stop("`stream` must come from bh_digest_stream()", call. = FALSE)
  }
  if (!is.raw(bytes)) stop("`bytes` must be a raw vector", call. = FALSE)
  if (!is.logical(hashed) || length(hashed) != 1L || is.na(hashed)) {
    stop("`hashed` must be TRUE or FALSE", call. = FALSE)
  }
  invisible(.bh_call("stream_update", .bh_stream_ptr(stream), bytes, hashed))
}

#' @rdname bh_digest_stream
#' @export
bh_stream_value <- function(stream, encoding = c("b64", "raw", "hex")) {
  encoding <- match.arg(encoding)
  if (!inherits(stream, "bh_digest_stream")) {
    stop("`stream` must come from bh_digest_stream()", call. = FALSE)
  }
  res <- .bh_call("stream_value", .bh_stream_ptr(stream), encoding)
  late <- res$late_header_lines
  list(
    digest = res$digest, hex = res$hex, b64 = res$b64,
    bytes = as.double(res$bytes),
    late_header_lines = if (is.na(late) || late < 0) NA_integer_ else as.integer(late)
  )
}

#' SHA-512/256 of a file, streamed, with an optional excluded byte range
#'
#' This is the shape rules R1 to R4 need: the file's exact bytes - decompressed when the
#' file is a gzip member, because compression is transport - hashed in full except one
#' excluded range, which is how the checksum line and its terminator stay out of their
#' own value (R3). Offsets are 1-based positions in the decompressed stream.
#'
#' @param path A file path.
#' @param skip A length-2 numeric vector `c(offset, length)` naming the byte range to
#'   leave out of the hash, or `NULL` to hash the whole file.
#' @param compressed `TRUE`, `FALSE`, or `NA` to detect a gzip member from the first two
#'   bytes.
#' @param scan `NULL`, or `list(prefix = <raw>, after = <number>)` to count lines that
#'   begin with `prefix` at or after the given 1-based offset (rule R10).
#' @param buffer Bytes read per step.
#' @return A list with `digest` (canonical base64), `hex`, `bytes` (hashed) and
#'   `late_header_lines`.
#' @export
bh_sha512_256_file <- function(path, skip = NULL, compressed = NA, scan = NULL,
                               buffer = 1048576L) {
  if (!is.character(path) || length(path) != 1L || !nzchar(path)) {
    stop("`path` must be a single file path", call. = FALSE)
  }
  if (!file.exists(path)) stop("no such file: ", path, call. = FALSE)
  if (!is.null(skip)) {
    if (!is.numeric(skip) || length(skip) != 2L || any(!is.finite(skip)) ||
        any(skip < 0) || skip[1L] < 1) {
      stop("`skip` must be NULL or c(offset, length) with offset >= 1", call. = FALSE)
    }
  }
  if (!is.na(compressed) && !isTRUE(compressed) && !isFALSE(compressed)) {
    stop("`compressed` must be TRUE, FALSE or NA", call. = FALSE)
  }
  buffer <- suppressWarnings(as.integer(buffer))
  if (is.na(buffer) || buffer < 1024L) buffer <- 1024L

  if (is.na(compressed)) compressed <- .bh_is_gzip_file(path)
  con <- if (compressed) gzfile(path, open = "rb") else file(path, open = "rb")
  on.exit(close(con), add = TRUE)

  st <- bh_digest_stream("sha512-256")
  if (!is.null(scan)) {
    if (!is.raw(scan$prefix) || !is.numeric(scan$after)) {
      stop("`scan` must be list(prefix = <raw>, after = <number>)", call. = FALSE)
    }
    bh_stream_scan(st, scan$prefix, scan$after)
  }

  from <- if (is.null(skip)) NA_real_ else as.double(skip[1L])
  to <- if (is.null(skip)) NA_real_ else from + as.double(skip[2L]) - 1
  fed <- 0
  repeat {
    chunk <- readBin(con, what = "raw", n = buffer)
    if (length(chunk) == 0L) break
    start <- fed + 1
    fed <- fed + length(chunk)
    if (is.na(from) || fed < from || start > to) {
      bh_stream_update(st, chunk, hashed = TRUE)
    } else if (start >= from && fed <= to) {
      bh_stream_update(st, chunk, hashed = FALSE)
    } else {
      # the excluded range overlaps this chunk: up to three pieces, fed in file order so
      # the scanner's offsets stay right
      i1 <- max(1L, as.integer(from - start + 1))
      i2 <- min(length(chunk), as.integer(to - start + 1))
      if (i1 > 1L) bh_stream_update(st, chunk[seq_len(i1 - 1L)], hashed = TRUE)
      if (i2 >= i1) bh_stream_update(st, chunk[i1:i2], hashed = FALSE)
      if (i2 < length(chunk)) {
        bh_stream_update(st, chunk[seq.int(i2 + 1L, length(chunk))], hashed = TRUE)
      }
    }
  }
  res <- bh_stream_value(st, "b64")
  list(
    digest = res$digest, hex = res$hex, bytes = res$bytes,
    late_header_lines = res$late_header_lines
  )
}

.bh_is_gzip_file <- function(path) {
  con <- file(path, open = "rb")
  on.exit(close(con), add = TRUE)
  b <- readBin(con, what = "raw", n = 2L)
  length(b) == 2L && identical(b, as.raw(c(0x1f, 0x8b)))
}

#' Whether a correct SHA-512/256 is available in this build
#'
#' Always `TRUE` when the package loads: `.onLoad` runs the compiled core against the
#' published sample digests and refuses to load the package when they do not match. This
#' function exists for callers, diagnostics and CI reports that want to state the fact
#' rather than assume it. The digest functions do not consult it, because the only
#' alternative to a correct SHA-512/256 here would be a wrong one.
#'
#' @return `TRUE`.
#' @export
bh_sha512_256_available <- function() TRUE
