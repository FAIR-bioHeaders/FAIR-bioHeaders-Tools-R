/*
 * Vendored SHA-512 core, configured as SHA-512/256 (FIPS 180-4).
 *
 * Why this file exists instead of a dependency: docs/DIGEST.md. In short - the
 * FAIR-bioHeaders checksum is SHA-512/256 (docs/FORMAT.md R4), neither `digest`
 * nor the R `openssl` package provides it, and a truncated SHA-512 is a different
 * algorithm that yields a plausible-looking 44-character value for every file.
 * The accepted cost here is compiled code in exchange for zero external libraries;
 * the mitigations are the load-time self-test in src/entry.c and the pinned
 * vectors in tests/testthat/test-digest-vectors.R.
 *
 * Constant provenance, all reproduced by the vectors this package runs:
 *   - FIPS 180-4 (August 2015): 4.2.3 for K, 5.3.1 for the SHA-512 initial hash
 *     value, 5.3.8 for the SHA-512/256 initial hash value, 5.1.2 for the padding
 *     and the 128-bit big-endian bit counter, 6.4 for the round function.
 *   - The NIST CVL worked example "Secure Hash Algorithm, Message Digest Length =
 *     512/256", which lists the same eight initial words and the two sample
 *     digests that bh_selftest() compares against.
 *
 * The 32-byte result is words H0..H3 of the SHA-512/256 state, so the truncation
 * happens inside the algorithm rather than by cutting a finished SHA-512 digest.
 *
 * Written for clarity over speed: one block at a time, big-endian load and store
 * by shifting so no alignment or byte-order assumptions are made, and a size check
 * on the 64-bit type instead of a list of platform #ifdefs.
 */

#include <string.h>

#include "sha512.h"

/* FIPS 180-4 4.2.3: first 64 bits of the fractional parts of the cube roots of
 * the first 80 primes. */
static const bh_u64 bh_k[80] = {
    (bh_u64)0x428a2f98d728ae22ULL, (bh_u64)0x7137449123ef65cdULL,
    (bh_u64)0xb5c0fbcfec4d3b2fULL, (bh_u64)0xe9b5dba58189dbbcULL,
    (bh_u64)0x3956c25bf348b538ULL, (bh_u64)0x59f111f1b605d019ULL,
    (bh_u64)0x923f82a4af194f9bULL, (bh_u64)0xab1c5ed5da6d8118ULL,
    (bh_u64)0xd807aa98a3030242ULL, (bh_u64)0x12835b0145706fbeULL,
    (bh_u64)0x243185be4ee4b28cULL, (bh_u64)0x550c7dc3d5ffb4e2ULL,
    (bh_u64)0x72be5d74f27b896fULL, (bh_u64)0x80deb1fe3b1696b1ULL,
    (bh_u64)0x9bdc06a725c71235ULL, (bh_u64)0xc19bf174cf692694ULL,
    (bh_u64)0xe49b69c19ef14ad2ULL, (bh_u64)0xefbe4786384f25e3ULL,
    (bh_u64)0x0fc19dc68b8cd5b5ULL, (bh_u64)0x240ca1cc77ac9c65ULL,
    (bh_u64)0x2de92c6f592b0275ULL, (bh_u64)0x4a7484aa6ea6e483ULL,
    (bh_u64)0x5cb0a9dcbd41fbd4ULL, (bh_u64)0x76f988da831153b5ULL,
    (bh_u64)0x983e5152ee66dfabULL, (bh_u64)0xa831c66d2db43210ULL,
    (bh_u64)0xb00327c898fb213fULL, (bh_u64)0xbf597fc7beef0ee4ULL,
    (bh_u64)0xc6e00bf33da88fc2ULL, (bh_u64)0xd5a79147930aa725ULL,
    (bh_u64)0x06ca6351e003826fULL, (bh_u64)0x142929670a0e6e70ULL,
    (bh_u64)0x27b70a8546d22ffcULL, (bh_u64)0x2e1b21385c26c926ULL,
    (bh_u64)0x4d2c6dfc5ac42aedULL, (bh_u64)0x53380d139d95b3dfULL,
    (bh_u64)0x650a73548baf63deULL, (bh_u64)0x766a0abb3c77b2a8ULL,
    (bh_u64)0x81c2c92e47edaee6ULL, (bh_u64)0x92722c851482353bULL,
    (bh_u64)0xa2bfe8a14cf10364ULL, (bh_u64)0xa81a664bbc423001ULL,
    (bh_u64)0xc24b8b70d0f89791ULL, (bh_u64)0xc76c51a30654be30ULL,
    (bh_u64)0xd192e819d6ef5218ULL, (bh_u64)0xd69906245565a910ULL,
    (bh_u64)0xf40e35855771202aULL, (bh_u64)0x106aa07032bbd1b8ULL,
    (bh_u64)0x19a4c116b8d2d0c8ULL, (bh_u64)0x1e376c085141ab53ULL,
    (bh_u64)0x2748774cdf8eeb99ULL, (bh_u64)0x34b0bcb5e19b48a8ULL,
    (bh_u64)0x391c0cb3c5c95a63ULL, (bh_u64)0x4ed8aa4ae3418acbULL,
    (bh_u64)0x5b9cca4f7763e373ULL, (bh_u64)0x682e6ff3d6b2b8a3ULL,
    (bh_u64)0x748f82ee5defb2fcULL, (bh_u64)0x78a5636f43172f60ULL,
    (bh_u64)0x84c87814a1f0ab72ULL, (bh_u64)0x8cc702081a6439ecULL,
    (bh_u64)0x90befffa23631e28ULL, (bh_u64)0xa4506cebde82bde9ULL,
    (bh_u64)0xbef9a3f7b2c67915ULL, (bh_u64)0xc67178f2e372532bULL,
    (bh_u64)0xca273eceea26619cULL, (bh_u64)0xd186b8c721c0c207ULL,
    (bh_u64)0xeada7dd6cde0eb1eULL, (bh_u64)0xf57d4f7fee6ed178ULL,
    (bh_u64)0x06f067aa72176fbaULL, (bh_u64)0x0a637dc5a2c898a6ULL,
    (bh_u64)0x113f9804bef90daeULL, (bh_u64)0x1b710b35131c471bULL,
    (bh_u64)0x28db77f523047d84ULL, (bh_u64)0x32caab7b40c72493ULL,
    (bh_u64)0x3c9ebe0a15c9bebcULL, (bh_u64)0x431d67c49c100d4cULL,
    (bh_u64)0x4cc5d4becb3e42b6ULL, (bh_u64)0x597f299cfc657e2aULL,
    (bh_u64)0x5fcb6fab3ad6faecULL, (bh_u64)0x6c44198c4a475817ULL};

/* FIPS 180-4 5.3.1: the SHA-512 initial hash value. Carried so the shared core can
 * be run through the published SHA-512 vectors too, which is what distinguishes
 * "the compression function is right" from "it reproduces one value by luck". */
static const bh_u64 bh_iv512[8] = {
    (bh_u64)0x6a09e667f3bcc908ULL, (bh_u64)0xbb67ae8584caa73bULL,
    (bh_u64)0x3c6ef372fe94f82bULL, (bh_u64)0xa54ff53a5f1d36f1ULL,
    (bh_u64)0x510e527fade682d1ULL, (bh_u64)0x9b05688c2b3e6c1fULL,
    (bh_u64)0x1f83d9abfb41bd6bULL, (bh_u64)0x5be0cd19137e2179ULL};

/* FIPS 180-4 5.3.8: the SHA-512/256 initial hash value, listed the same way in the
 * NIST CVL 512/256 worked example. Apart from how many output words are returned,
 * this is the only difference from SHA-512 - which is exactly why cutting a
 * SHA-512 digest in half produces a different 44-character value. */
static const bh_u64 bh_iv512_256[8] = {
    (bh_u64)0x22312194fc2bf72cULL, (bh_u64)0x9f555fa3c84c64c2ULL,
    (bh_u64)0x2393b86b6f53b151ULL, (bh_u64)0x963877195940eabdULL,
    (bh_u64)0x96283ee2a88effe3ULL, (bh_u64)0xbe5e1e2553863992ULL,
    (bh_u64)0x2b0199fc2c85b8aaULL, (bh_u64)0x0eb72ddc81c52ca2ULL};

static bh_u64 bh_rotr(bh_u64 x, unsigned int n) {
  return (x >> n) | (x << (64 - n));
}

static bh_u64 bh_load64(const unsigned char *p) {
  bh_u64 v = 0;
  int i;
  for (i = 0; i < 8; i++) v = (v << 8) | (bh_u64)p[i];
  return v;
}

static void bh_store64(bh_u64 v, unsigned char *p) {
  int i;
  for (i = 0; i < 8; i++) p[i] = (unsigned char)((v >> (56 - 8 * i)) & (bh_u64)0xffu);
}

static void bh_compress(bh_u64 h[8], const unsigned char *block) {
  bh_u64 w[80];
  bh_u64 a, b, c, d, e, f, g, hh, t1, t2;
  int t;

  for (t = 0; t < 16; t++) w[t] = bh_load64(block + 8 * t);
  for (t = 16; t < 80; t++) {
    bh_u64 s0 = bh_rotr(w[t - 15], 1) ^ bh_rotr(w[t - 15], 8) ^ (w[t - 15] >> 7);
    bh_u64 s1 = bh_rotr(w[t - 2], 19) ^ bh_rotr(w[t - 2], 61) ^ (w[t - 2] >> 6);
    w[t] = w[t - 16] + s0 + w[t - 7] + s1;
  }

  a = h[0]; b = h[1]; c = h[2]; d = h[3];
  e = h[4]; f = h[5]; g = h[6]; hh = h[7];

  for (t = 0; t < 80; t++) {
    bh_u64 S1 = bh_rotr(e, 14) ^ bh_rotr(e, 18) ^ bh_rotr(e, 41);
    bh_u64 ch = (e & f) ^ ((~e) & g);
    bh_u64 S0 = bh_rotr(a, 28) ^ bh_rotr(a, 34) ^ bh_rotr(a, 39);
    bh_u64 maj = (a & b) ^ (a & c) ^ (b & c);
    t1 = hh + S1 + ch + bh_k[t] + w[t];
    t2 = S0 + maj;
    hh = g; g = f; f = e; e = d + t1;
    d = c; c = b; b = a; a = t1 + t2;
  }

  h[0] += a; h[1] += b; h[2] += c; h[3] += d;
  h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
}

size_t bh_digest_len(bh_algo algo) {
  return algo == BH_SHA512_256 ? BH_SHA512_256_DIGEST_BYTES : BH_SHA512_DIGEST_BYTES;
}

int bh_ctx_init(bh_ctx *ctx, bh_algo algo) {
  const bh_u64 *iv;
  int i;
  if (sizeof(bh_u64) != 8) return -1; /* refuse to compute a wrong digest */
  iv = algo == BH_SHA512_256 ? bh_iv512_256 : bh_iv512;
  for (i = 0; i < 8; i++) ctx->h[i] = iv[i];
  ctx->count_lo = 0;
  ctx->count_hi = 0;
  ctx->buflen = 0;
  ctx->finalized = 0;
  ctx->algo = algo;
  return 0;
}

/* Adds `len` to the 128-bit byte counter; the conversion to bits happens in the
 * padding block (FIPS 180-4 5.1.2). */
static void bh_add_count(bh_ctx *ctx, size_t len) {
  bh_u64 l = (bh_u64)len;
  bh_u64 old = ctx->count_lo;
  ctx->count_lo += l;
  if (ctx->count_lo < old) ctx->count_hi += 1;
}

int bh_update(bh_ctx *ctx, const unsigned char *data, size_t len) {
  size_t need;

  if (ctx->finalized) return 1;
  if (!len) return 0;
  bh_add_count(ctx, len);

  if (ctx->buflen) {
    need = BH_BLOCK_BYTES - ctx->buflen;
    if (len < need) {
      memcpy(ctx->buf + ctx->buflen, data, len);
      ctx->buflen += len;
      return 0;
    }
    memcpy(ctx->buf + ctx->buflen, data, need);
    bh_compress(ctx->h, ctx->buf);
    data += need;
    len -= need;
    ctx->buflen = 0;
  }
  while (len >= BH_BLOCK_BYTES) {
    bh_compress(ctx->h, data);
    data += BH_BLOCK_BYTES;
    len -= BH_BLOCK_BYTES;
  }
  if (len) {
    memcpy(ctx->buf, data, len);
    ctx->buflen = len;
  }
  return 0;
}

int bh_final(bh_ctx *ctx, unsigned char *out) {
  /* 0x80, then zeros so the tail is 112 mod 128, then the 128-bit big-endian bit
   * length. A tail of 112..127 bytes needs a second padding block, so the scratch
   * buffer holds two blocks; bh_update() guarantees buflen < 128 here. */
  unsigned char tail[BH_BLOCK_BYTES * 2];
  bh_u64 bits_lo, bits_hi;
  size_t n, padlen, total, off, words, i;

  if (ctx->finalized) return 2;
  ctx->finalized = 1;

  n = ctx->buflen;
  padlen = (n <= 111) ? (111 - n) : (239 - n);
  total = n + 1 + padlen + 16; /* a multiple of 128 */

  memcpy(tail, ctx->buf, n);
  tail[n] = 0x80;
  memset(tail + n + 1, 0, padlen);
  bits_lo = ctx->count_lo << 3;
  bits_hi = (ctx->count_hi << 3) | (ctx->count_lo >> 61);
  bh_store64(bits_hi, tail + total - 16);
  bh_store64(bits_lo, tail + total - 8);

  for (off = 0; off < total; off += BH_BLOCK_BYTES) bh_compress(ctx->h, tail + off);
  ctx->buflen = 0;

  words = bh_digest_len(ctx->algo) / 8;
  for (i = 0; i < words; i++) bh_store64(ctx->h[i], out + 8 * i);
  return 0;
}
