/*
 * A strict gzip reader for the compressed transport.
 *
 * R's gzfile() connection is lenient in the two ways a checksum verifier cannot be: bytes
 * after the last gzip member are dropped silently, so a file with trailing garbage
 * verified as valid, and a CRC mismatch or a truncated member surfaces only as a
 * connection warning or an unclassed "error reading from the connection". This reader
 * walks the members itself with zlib and reports each of those as an error the R side
 * turns into a classed condition.
 *
 * It accepts what the Python reference's gzip module accepts: one or more members back to
 * back (BGZF is such a file), with zero bytes allowed as padding between or after them.
 * Anything else after a member, a member that does not end before the file does, and a
 * member whose CRC-32 or length trailer does not match are errors.
 */

#include <R.h>
#include <Rinternals.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#include "gz.h"

#define BH_GZ_IN 65536

typedef struct {
  FILE *fp;
  z_stream strm;
  int strm_ready;   /* inflateInit2 succeeded */
  int in_member;    /* inside a member: its end has not been seen */
  int members;      /* members started */
  int done;         /* clean end of input */
  unsigned char in[BH_GZ_IN];
} bh_gz;

static void bh_gz_free(bh_gz *g) {
  if (!g) return;
  if (g->strm_ready) inflateEnd(&g->strm);
  if (g->fp) fclose(g->fp);
  free(g);
}

static void bh_gz_finalize(SEXP ptr) {
  bh_gz *g = (bh_gz *)R_ExternalPtrAddr(ptr);
  if (g) {
    bh_gz_free(g);
    R_ClearExternalPtr(ptr);
  }
}

static bh_gz *bh_gz_get(SEXP ptr) {
  if (TYPEOF(ptr) != EXTPTRSXP || !R_ExternalPtrAddr(ptr))
    error("the gzip reader is closed");
  return (bh_gz *)R_ExternalPtrAddr(ptr);
}

SEXP bh_gz_open(SEXP path) {
  bh_gz *g;
  SEXP ptr;
  if (!isString(path) || XLENGTH(path) != 1 || STRING_ELT(path, 0) == NA_STRING)
    error("`path` must be a single file path");
  g = (bh_gz *)calloc(1, sizeof(bh_gz));
  if (!g) error("out of memory opening a gzip reader");
  g->fp = fopen(R_ExpandFileName(translateChar(STRING_ELT(path, 0))), "rb");
  if (!g->fp) {
    free(g);
    error("cannot open %s", translateChar(STRING_ELT(path, 0)));
  }
  /* 16 + MAX_WBITS: a gzip wrapper, CRC-32 and length trailer checked by zlib */
  if (inflateInit2(&g->strm, 16 + MAX_WBITS) != Z_OK) {
    bh_gz_free(g);
    error("cannot initialise zlib");
  }
  g->strm_ready = 1;
  g->strm.next_in = g->in;
  g->strm.avail_in = 0;
  ptr = PROTECT(R_MakeExternalPtr(g, R_NilValue, R_NilValue));
  R_RegisterCFinalizerEx(ptr, bh_gz_finalize, 1);
  UNPROTECT(1);
  return ptr;
}

/* Refills the input buffer; returns the bytes now available. */
static unsigned int bh_gz_fill(bh_gz *g) {
  size_t got;
  if (g->strm.avail_in) return g->strm.avail_in;
  got = fread(g->in, 1, BH_GZ_IN, g->fp);
  g->strm.next_in = g->in;
  g->strm.avail_in = (uInt)got;
  return (unsigned int)got;
}

static SEXP bh_gz_fail(const char *msg) { return mkString(msg); }

/* Reads up to `n` decompressed bytes. Returns a raw vector (empty at the clean end of the
 * input) or a character string naming what is wrong with the file. */
SEXP bh_gz_read(SEXP ptr, SEXP n_) {
  bh_gz *g = bh_gz_get(ptr);
  int n;
  size_t have = 0;
  unsigned char *out;
  SEXP res, buf;
  char msg[256];
  if (!isInteger(n_) || XLENGTH(n_) != 1 || INTEGER(n_)[0] == NA_INTEGER || INTEGER(n_)[0] < 1)
    error("`n` must be a positive integer");
  n = INTEGER(n_)[0];
  buf = PROTECT(allocVector(RAWSXP, n));
  out = RAW(buf);

  while (have < (size_t)n && !g->done) {
    if (!g->in_member) {
      /* between members: zero padding is allowed, then a member or the end */
      for (;;) {
        if (!bh_gz_fill(g)) break;
        while (g->strm.avail_in && *g->strm.next_in == 0) {
          g->strm.next_in++;
          g->strm.avail_in--;
        }
        if (g->strm.avail_in) break;
      }
      if (!g->strm.avail_in) {
        if (ferror(g->fp)) {
          UNPROTECT(1);
          return bh_gz_fail("the file could not be read");
        }
        if (!g->members) {
          UNPROTECT(1);
          return bh_gz_fail("the file is empty, not a gzip member");
        }
        g->done = 1;
        break;
      }
      if (*g->strm.next_in != 0x1f) {
        UNPROTECT(1);
        return bh_gz_fail(g->members
          ? "bytes that are not a gzip member follow the last gzip member"
          : "the file does not start with a gzip member");
      }
      if (inflateReset(&g->strm) != Z_OK) {
        UNPROTECT(1);
        return bh_gz_fail("cannot reset zlib between gzip members");
      }
      g->in_member = 1;
      g->members++;
    }
    if (!bh_gz_fill(g)) {
      UNPROTECT(1);
      return bh_gz_fail(ferror(g->fp) ? "the file could not be read"
        : "the gzip data is truncated: the file ends inside a member");
    }
    g->strm.next_out = out + have;
    g->strm.avail_out = (uInt)((size_t)n - have);
    {
      int ret = inflate(&g->strm, Z_NO_FLUSH);
      have = (size_t)n - g->strm.avail_out;
      if (ret == Z_STREAM_END) {
        g->in_member = 0;
      } else if (ret == Z_BUF_ERROR) {
        /* no progress possible without more input: the next fill decides */
        if (g->strm.avail_in) {
          UNPROTECT(1);
          return bh_gz_fail("the gzip data could not be decompressed");
        }
      } else if (ret != Z_OK) {
        snprintf(msg, sizeof msg, "the gzip data is corrupt (%s)",
          g->strm.msg ? g->strm.msg : "zlib error");
        UNPROTECT(1);
        return bh_gz_fail(msg);
      }
    }
  }
  res = PROTECT(allocVector(RAWSXP, (R_xlen_t)have));
  if (have) memcpy(RAW(res), out, have);
  UNPROTECT(2);
  return res;
}

SEXP bh_gz_close(SEXP ptr) {
  if (TYPEOF(ptr) == EXTPTRSXP) bh_gz_finalize(ptr);
  return R_NilValue;
}
