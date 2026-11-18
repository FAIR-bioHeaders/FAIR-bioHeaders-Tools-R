/*
 * R-facing entry points for the vendored SHA-512/256 core (src/sha512.c) and the
 * line-start scanner (src/scan.c).
 *
 * There is deliberately no fallback: if this shared object is missing or miscompiled,
 * the calls error and R CMD check fails. A silent substitute - a truncated SHA-512,
 * another hash library, an external command - yields a plausible 44-character value
 * for every file and mis-verifies all of them, which is the failure mode
 * docs/DIGEST.md exists to prevent.
 *
 * bh_selftest() runs the published sample messages through the compiled core; the
 * package refuses to load when it reports nonzero, so a build that hashes wrongly
 * cannot be used at all.
 */

#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <stdlib.h>
#include <string.h>

#include "gz.h"
#include "scan.h"
#include "sha512.h"

static const char bh_b64chars[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/* Standard padded base64 (RFC 4648). Rule R4 wants canonical padded base64 of the
 * digest, default alphabet, no line breaks: 32 bytes become 44 characters ending in
 * "=". */
static void bh_b64_encode(const unsigned char *in, size_t n, char *out) {
  size_t i, o = 0;
  for (i = 0; i < n; i += 3) {
    unsigned long v = (unsigned long)in[i] << 16;
    size_t rem = n - i;
    if (rem > 1) v |= (unsigned long)in[i + 1] << 8;
    if (rem > 2) v |= (unsigned long)in[i + 2];
    out[o++] = bh_b64chars[(v >> 18) & 0x3f];
    out[o++] = bh_b64chars[(v >> 12) & 0x3f];
    out[o++] = rem > 1 ? bh_b64chars[(v >> 6) & 0x3f] : '=';
    out[o++] = rem > 2 ? bh_b64chars[v & 0x3f] : '=';
  }
  out[o] = '\0';
}

static void bh_hex_encode(const unsigned char *in, size_t n, char *out) {
  static const char digits[] = "0123456789abcdef";
  size_t i;
  for (i = 0; i < n; i++) {
    out[2 * i] = digits[(in[i] >> 4) & 0x0f];
    out[2 * i + 1] = digits[in[i] & 0x0f];
  }
  out[2 * n] = '\0';
}

static int bh_check_algo(SEXP algo) {
  int a;
  if (!isInteger(algo) || XLENGTH(algo) != 1 || INTEGER(algo)[0] == NA_INTEGER)
    error("`algo` must be a single integer: 0 for SHA-512/256, 1 for SHA-512");
  a = INTEGER(algo)[0];
  if (a != (int)BH_SHA512_256 && a != (int)BH_SHA512)
    error("`algo` must be 0 (SHA-512/256) or 1 (SHA-512), not %d", a);
  return a;
}

static const char *bh_check_as(SEXP as) {
  if (!isString(as) || XLENGTH(as) != 1 || CHAR(STRING_ELT(as, 0))[0] == '\0')
    error("`as` must be a single non-empty string: \"raw\", \"hex\" or \"b64\"");
  return CHAR(STRING_ELT(as, 0));
}

/* Renders the digest bytes as raw, hex or base64 per `as`. */
static SEXP bh_emit(const unsigned char *bytes, size_t n, const char *as) {
  if (!strcmp(as, "raw")) {
    SEXP res = PROTECT(allocVector(RAWSXP, (R_xlen_t)n));
    memcpy(RAW(res), bytes, n);
    UNPROTECT(1);
    return res;
  }
  if (!strcmp(as, "hex")) {
    char *hex = (char *)R_alloc(2 * (int)n + 1, sizeof(char));
    SEXP res;
    bh_hex_encode(bytes, n, hex);
    res = PROTECT(mkString(hex));
    UNPROTECT(1);
    return res;
  }
  if (!strcmp(as, "b64")) {
    /* four characters per three bytes, rounded up, plus the terminator */
    char *b64 = (char *)R_alloc(4 * ((int)n / 3 + 2) + 1, sizeof(char));
    SEXP res;
    bh_b64_encode(bytes, n, b64);
    res = PROTECT(mkString(b64));
    UNPROTECT(1);
    return res;
  }
  error("`as` must be \"raw\", \"hex\" or \"b64\", not \"%s\"", as);
  return R_NilValue; /* not reached */
}

/* .Call(bh_digest, bytes, algo, as) - one-shot digest of a raw vector. */
SEXP bh_digest(SEXP bytes, SEXP algo, SEXP as) {
  bh_ctx ctx;
  unsigned char out[BH_SHA512_DIGEST_BYTES];
  int a = bh_check_algo(algo);
  const char *how = bh_check_as(as);

  if (TYPEOF(bytes) != RAWSXP) error("`bytes` must be a raw vector");
  if (bh_ctx_init(&ctx, (bh_algo)a) != 0)
    error("this platform's 64-bit integer type is not exactly 64 bits; refusing to compute a digest");
  if (bh_update(&ctx, RAW(bytes), (size_t)XLENGTH(bytes)) != 0)
    error("digest context used after finalization");
  if (bh_final(&ctx, out) != 0) error("digest finalization failed");
  return bh_emit(out, bh_digest_len((bh_algo)a), how);
}

/* .Call(bh_digest_len, algo) */
SEXP bh_digest_len_r(SEXP algo) {
  int a = bh_check_algo(algo);
  return ScalarInteger((int)bh_digest_len((bh_algo)a));
}

/* --- streaming context ------------------------------------------------------
 *
 * A reference genome is larger than what should be pulled into R memory, and rule R3
 * excludes the checksum line from the hashed bytes, so the R side needs an
 * incremental hasher. It carries the R10 line scanner too: finding a `;~`/`#~` line
 * after the header block needs every line start in the file, which is the same pass
 * over the bytes the hash already makes.
 */

typedef struct {
  bh_ctx ctx;
  bh_scan scan;
  unsigned char out[BH_SHA512_DIGEST_BYTES];
  size_t outlen;
  int done;
} bh_stream;

static void bh_stream_finalize(SEXP ptr) {
  if (R_ExternalPtrAddr(ptr)) {
    free(R_ExternalPtrAddr(ptr));
    R_ClearExternalPtr(ptr);
  }
}

static bh_stream *bh_stream_get(SEXP ptr, const char *who) {
  if (TYPEOF(ptr) != EXTPTRSXP || !R_ExternalPtrAddr(ptr))
    error("%s: the digest context is not a live external pointer", who);
  return (bh_stream *)R_ExternalPtrAddr(ptr);
}

/* .Call(bh_stream_new, algo) */
SEXP bh_stream_new(SEXP algo) {
  int a = bh_check_algo(algo);
  bh_stream *s = (bh_stream *)calloc(1, sizeof(bh_stream));
  SEXP ptr;
  if (!s) error("out of memory allocating a digest context");
  if (bh_ctx_init(&s->ctx, (bh_algo)a) != 0) {
    free(s);
    error("this platform's 64-bit integer type is not exactly 64 bits; refusing to compute a digest");
  }
  bh_scan_off(&s->scan);
  ptr = PROTECT(R_MakeExternalPtr(s, R_NilValue, R_NilValue));
  R_RegisterCFinalizerEx(ptr, bh_stream_finalize, 1);
  UNPROTECT(1);
  return ptr;
}

/* .Call(bh_stream_scan, ctx, prefix, min_offset) - arms the R10 scanner: count lines
 * beginning with `prefix` at or after the 1-based file offset `min_offset`. Call it
 * before the first update. */
SEXP bh_stream_scan(SEXP ptr, SEXP prefix, SEXP min_offset) {
  bh_stream *s = bh_stream_get(ptr, "bh_stream_scan");
  double mo;
  if (TYPEOF(prefix) != RAWSXP || XLENGTH(prefix) < 1 || XLENGTH(prefix) > BH_SCAN_MAX_PREFIX)
    error("`prefix` must be a raw vector of 1 to %d bytes", BH_SCAN_MAX_PREFIX);
  if (!isReal(min_offset) && !isInteger(min_offset)) error("`min_offset` must be a single number");
  mo = asReal(min_offset);
  if (!R_FINITE(mo) || mo < 1) error("`min_offset` must be a finite number >= 1");
  if (s->done) error("bh_stream_scan: the digest context was already finalized");
  bh_scan_on(&s->scan, RAW(prefix), (int)XLENGTH(prefix), (size_t)mo);
  return ptr;
}

/* .Call(bh_stream_update, ctx, bytes, hashed) - advances the scanner over `bytes` and
 * hashes them when `hashed` is TRUE. Rule R3 excludes the checksum line from the
 * hash, but those bytes still occupy file positions that rule R10 counts, so the
 * excluded line is fed with hashed = FALSE. */
SEXP bh_stream_update(SEXP ptr, SEXP bytes, SEXP hashed) {
  bh_stream *s = bh_stream_get(ptr, "bh_stream_update");
  int keep;
  if (TYPEOF(bytes) != RAWSXP) error("`bytes` must be a raw vector");
  if (!isLogical(hashed) || XLENGTH(hashed) != 1 || LOGICAL(hashed)[0] == NA_LOGICAL)
    error("`hashed` must be TRUE or FALSE");
  keep = LOGICAL(hashed)[0];
  if (s->done) error("bh_stream_update: the digest context was already finalized");
  if (XLENGTH(bytes) > 0) {
    if (keep && bh_update(&s->ctx, RAW(bytes), (size_t)XLENGTH(bytes)) != 0)
      error("bh_stream_update: the digest context was already finalized");
    bh_scan_feed(&s->scan, RAW(bytes), (size_t)XLENGTH(bytes));
  }
  return ptr;
}

/* .Call(bh_stream_value, ctx, as) - finalizes the context and returns a list with the
 * digest in the requested encoding plus the same digest in the other two (a caller
 * that compares and then prints must not re-hash), the count of hashed bytes, and the
 * number of late header lines the scanner found (-1 when it was never armed). The
 * context cannot be updated again afterwards. */
SEXP bh_stream_value(SEXP ptr, SEXP as) {
  bh_stream *s = bh_stream_get(ptr, "bh_stream_value");
  const char *how = bh_check_as(as);
  SEXP out, names, bytes, late, dig, hex, b64;
  if (s->done) error("bh_stream_value: the digest context was already finalized");
  if (bh_final(&s->ctx, s->out) != 0) error("bh_stream_value: digest finalization failed");
  s->outlen = bh_digest_len(s->ctx.algo);
  s->done = 1;

  dig = PROTECT(bh_emit(s->out, s->outlen, how));
  hex = PROTECT(bh_emit(s->out, s->outlen, "hex"));
  b64 = PROTECT(bh_emit(s->out, s->outlen, "b64"));
  bytes = PROTECT(allocVector(REALSXP, 1));
  REAL(bytes)[0] = (double)s->ctx.count_lo; /* past 2^64 hashed bytes is out of scope */
  late = PROTECT(allocVector(REALSXP, 1));
  REAL(late)[0] = s->scan.enabled ? (double)s->scan.late : -1.0;

  out = PROTECT(allocVector(VECSXP, 5));
  names = PROTECT(allocVector(STRSXP, 5));
  SET_STRING_ELT(names, 0, mkChar("digest"));
  SET_STRING_ELT(names, 1, mkChar("hex"));
  SET_STRING_ELT(names, 2, mkChar("b64"));
  SET_STRING_ELT(names, 3, mkChar("bytes"));
  SET_STRING_ELT(names, 4, mkChar("late_header_lines"));
  SET_VECTOR_ELT(out, 0, dig);
  SET_VECTOR_ELT(out, 1, hex);
  SET_VECTOR_ELT(out, 2, b64);
  SET_VECTOR_ELT(out, 3, bytes);
  SET_VECTOR_ELT(out, 4, late);
  setAttrib(out, R_NamesSymbol, names);
  UNPROTECT(7);
  return out;
}

/* .Call(bh_selftest) - 0 when the compiled core reproduces the published values. The
 * codes name the case that failed, so a broken build says which vector it missed
 * instead of failing a dozen tests later.
 *   1          the 64-bit type is not 64 bits wide
 *   2, 3       SHA-512/256 of "abc"          (one-block message)
 *   4, 5       SHA-512/256 of the 112-char   (two-block message)
 *   6, 7       SHA-512 of "abc"              (shared compression function)
 *   8, 9, 10   SHA-512/256 of the 112-char message one byte at a time: streaming must
 *              equal the one-shot value, and 112 is the length at which the padding
 *              needs a second block
 */
SEXP bh_selftest(void) {
  static const unsigned char abc[] = {'a', 'b', 'c'};
  static const unsigned char m112[] =
      "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
      "ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu";
  static const char *want_abc =
      "53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23";
  static const char *want_112 =
      "3928e184fb8690f840da3988121d31be65cb9d3ef83ee6146feac861e19b563a";
  static const char *want_sha512_abc =
      "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
      "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f";
  unsigned char out[BH_SHA512_DIGEST_BYTES];
  char hex[2 * BH_SHA512_DIGEST_BYTES + 1];
  bh_ctx ctx;
  int i;

  if (sizeof(bh_u64) != 8) return ScalarInteger(1);

  if (bh_ctx_init(&ctx, BH_SHA512_256) || bh_update(&ctx, abc, 3) || bh_final(&ctx, out))
    return ScalarInteger(2);
  bh_hex_encode(out, bh_digest_len(BH_SHA512_256), hex);
  if (strcmp(hex, want_abc) != 0) return ScalarInteger(3);

  if (bh_ctx_init(&ctx, BH_SHA512_256) || bh_update(&ctx, m112, 112) || bh_final(&ctx, out))
    return ScalarInteger(4);
  bh_hex_encode(out, bh_digest_len(BH_SHA512_256), hex);
  if (strcmp(hex, want_112) != 0) return ScalarInteger(5);

  if (bh_ctx_init(&ctx, BH_SHA512) || bh_update(&ctx, abc, 3) || bh_final(&ctx, out))
    return ScalarInteger(6);
  bh_hex_encode(out, bh_digest_len(BH_SHA512), hex);
  if (strcmp(hex, want_sha512_abc) != 0) return ScalarInteger(7);

  if (bh_ctx_init(&ctx, BH_SHA512_256) != 0) return ScalarInteger(8);
  for (i = 0; i < 112; i++)
    if (bh_update(&ctx, m112 + i, 1) != 0) return ScalarInteger(9);
  if (bh_final(&ctx, out) != 0) return ScalarInteger(10);
  bh_hex_encode(out, bh_digest_len(BH_SHA512_256), hex);
  if (strcmp(hex, want_112) != 0) return ScalarInteger(7);

  return ScalarInteger(0);
}

/* Registered under short names; NAMESPACE binds them with the "bh_" fix, so R code
 * calls .Call(bh_digest, ...). Keeping the two spellings apart makes it obvious in a
 * backtrace which layer a failure came from. */
static const R_CallMethodDef bh_calls[] = {
    {"digest", (DL_FUNC)&bh_digest, 3},
    {"digest_len", (DL_FUNC)&bh_digest_len_r, 1},
    {"stream_new", (DL_FUNC)&bh_stream_new, 1},
    {"stream_scan", (DL_FUNC)&bh_stream_scan, 3},
    {"stream_update", (DL_FUNC)&bh_stream_update, 3},
    {"stream_value", (DL_FUNC)&bh_stream_value, 2},
    {"selftest", (DL_FUNC)&bh_selftest, 0},
    {"gz_open", (DL_FUNC)&bh_gz_open, 1},
    {"gz_read", (DL_FUNC)&bh_gz_read, 2},
    {"gz_close", (DL_FUNC)&bh_gz_close, 1},
    {NULL, NULL, 0}};

void R_init_FAIRbioHeadersTools(DllInfo *dll) {
  R_registerRoutines(dll, NULL, bh_calls, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
  R_forceSymbols(dll, TRUE);
}
