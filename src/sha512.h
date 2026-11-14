/*
 * Vendored SHA-512 and SHA-512/256 (FIPS 180-4) for FAIR-bioHeaders.
 *
 * See docs/DIGEST.md for why the digest is vendored rather than taken from
 * `digest`, the R `openssl` package, a system command, or the Python toolkit, and
 * for the evidence behind the constants.
 *
 * The core uses no R headers on purpose: it stays buildable outside an R session,
 * so it can be exercised on its own, and the R glue in src/entry.c is the only
 * place that knows about SEXP. The package declares `SystemRequirements: C99`, so
 * <stdint.h> and the exact-width type are available.
 */

#ifndef FAIRBH_SHA512_H
#define FAIRBH_SHA512_H

#include <stddef.h>
#include <stdint.h>

typedef uint64_t bh_u64;

/* BH_SHA512_256 is the FAIR-bioHeaders checksum algorithm (docs/FORMAT.md R4).
 * BH_SHA512 exists only so the test suite can drive the same compression function
 * through the published SHA-512 vectors and show the two digests differ. */
typedef enum {
  BH_SHA512_256 = 0,
  BH_SHA512 = 1
} bh_algo;

#define BH_BLOCK_BYTES 128
#define BH_SHA512_DIGEST_BYTES 64
#define BH_SHA512_256_DIGEST_BYTES 32

typedef struct {
  bh_u64 h[8];
  bh_u64 count_lo; /* bytes fed, low 64 bits */
  bh_u64 count_hi; /* bytes fed, high 64 bits */
  unsigned char buf[BH_BLOCK_BYTES];
  size_t buflen;
  int finalized;
  bh_algo algo;
} bh_ctx;

/* Digest length in bytes for `algo`. */
size_t bh_digest_len(bh_algo algo);

/* Resets the context to the initial hash value of `algo`. Returns 0 on success,
 * -1 when the platform's 64-bit type is not exactly 64 bits. */
int bh_ctx_init(bh_ctx *ctx, bh_algo algo);

/* Feeds `len` bytes. Returns nonzero if the context was already finalized. */
int bh_update(bh_ctx *ctx, const unsigned char *data, size_t len);

/* Writes bh_digest_len(ctx->algo) bytes to `out`, which the caller owns. Returns
 * nonzero if the context was already finalized. The context must not be reused. */
int bh_final(bh_ctx *ctx, unsigned char *out);

#endif /* FAIRBH_SHA512_H */
