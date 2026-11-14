# Digest decision: how this package obtains SHA-512/256

Date: **2026-11-14**. Host of measurement: macOS 14 arm64, R 4.6.1. This record
implements the instruction that the R real SHA-512/256 route be resolved
**explicitly** under the native-first direction, with no silent Python delegation,
no truncated SHA-512, and no quietly wrong schema engine.

## The constraint

The FAIR-bioHeaders file checksum is **SHA-512/256** - the 32-byte member of the
SHA-512 family defined in FIPS 180-4 section 5.3.8, written as canonical padded
base64 (docs/FORMAT.md rule R4). It is not SHA-512 truncated to 32 bytes. Truncating
a SHA-512 digest is a *different algorithm* with a different initial hash value, and
it produces a plausible 44-character base64 string for every file:

    SHA-512("abc")   = ddaf35a193617aba...   (64 bytes, FIPS 180-4 example)
    SHA-512/256("abc") = 53048e2681941ef9...  (32 bytes, NIST CVL 512/256 example)

A wrong route therefore fails *closed-looking*: every checksum silently mismatches
live files, and every fixture built the same wrong way still passes. This is the
failure mode the design below exists to make impossible.

## What the R ecosystem provides (measured, docs/CAPABILITY.md, re-verified 2026-11-14)

| candidate | SHA-512/256? | finding |
| --- | --- | --- |
| `digest` 0.6.39 (current CRAN) | **no** | not even `sha384`; `sha512` only. Truncation is not this algorithm |
| R `openssl` 2.4.2 / 2.5.0 | **no** | `digest_create()` exposes md5/sha1/sha256/sha512-family names without SHA-512/256 |
| system `openssl dgst -sha512-256` | yes | proven byte-exact three ways over all 87 valid sequence vectors in the capability study, but: a PATH dependency on a specific CLI and its flag spelling, behaviour verified on one macOS host, and a package that shells out for its central guarantee |
| Python delegation (subprocess to the reference toolkit) | yes | rejected outright by the native-first direction of issues #3/#4 and by the primary acceptance job installing no Python at all |
| `jsonvalidate`'s V8 engine (hash inside V8) | possible | rejected: couples the file checksum to the lifetime and internals of a transitive hard dependency, untestable apart from the schema layer, and V8's `crypto.subtle` support is async - it does not fit `.Call`-style sync use or streaming |
| **vendored FIPS 180-4 core in `src/`** | yes | **chosen** |

## The chosen route: vendored C core (`src/sha512.c`, `src/entry.c`, `src/scan.c`)

Reasons, against the alternatives in the same table:

1. **No new external dependency.** `Imports:` stays `digest, jsonlite, jsonvalidate,
   yaml` (digest for SHA-256 provenance pins only, never for the file checksum). A C
   compiler is already required by `SystemRequirements` and is present on CRAN and
   Bioconductor CI images. No PATH assumptions, no libcrypto symbol-name roulette.
2. **It is self-testing at load time.** `.onLoad` runs `bh_selftest()`
   (`src/entry.c`), which recomputes the published sample digests through the
   *compiled* code: SHA-512/256 of `"abc"` = `53048e2681941ef99b2e29b76b4c7dabe4c2d0c634fc6d46e0e2f13107e7af23`
   and of the FIPS 180-4 112-character two-block message =
   `3928e184fb8690f840da3988121d31be65cb9d3ef83ee6146feac861e19b563a`
   (NIST CVL worked example "Secure Hash Algorithm, Message Digest Length = 512/256",
   retrieved 2026-11-14), plus SHA-512("abc") = `ddaf35a193617aba...` through the
   same core with the 5.3.1 IV, and the 112-char message fed **one byte at a time**
   to prove the streaming path equals the one-shot path exactly at the length where
   padding needs a second block. A build that hashes differently **refuses to load**.
3. **The initial values are the published constants** (FIPS 180-4 5.3.8), carried in
   the source with their section numbers, and the SHA-512 IV is also present so the
   shared compression function can be proven correct independently of the 512/256
   truncation-by-design - the thing that distinguishes "right algorithm" from
   "reproduced one value by luck".

### Evidence the route rests on

- **Published constants:** the two NIST CVL 512/256 digests and the IV above, pinned
  in `tests/testthat/test-digest-vectors.R` and re-checked at every load.
- **Independent implementations, same bytes:** all **87** valid sequence-format
  vectors of the shared v0.6.0 suite - whose `checksum:` lines were produced by the
  reference Python toolkit and reviewed upstream - are reproduced exactly by the
  vendored core through the full R3 rule path (decompress, exclude the checksum line
  and its terminator, hash the rest) in `test-digest-fixtures.R`; and whole decompressed
  files (without the R3 exclusion) match CPython `hashlib.new("sha512_256")` **87/87**
  plus the three FIPS sample messages, measured on this host 2026-11-14 and reproducible
  with `tools/differential_hashlib.py` plus `tools/differential_hashlib.R` (a labelled,
  non-gating supplemental CI job; acceptance itself is native and the primary job
  installs no Python).
- **The trap is pinned, not just described:** `test-digest-vectors.R` records what
  truncated SHA-512 *would have written* for several fixture inputs and asserts the
  package writes the SHA-512/256 value instead.

### Accepted cost

Compiled code in a scientific R package (a C compiler at install; platform CI coverage
becomes meaningful). Mitigations: the load-time self-test, the pinned vectors, and
`R CMD check` "checking compiled code" in CI on two OSes.

## The schema-engine decision (companion constraint)

The released contracts declare JSON Schema **draft/2020-12**. `jsonvalidate` 1.5.0
validates that dialect correctly only with `engine = "ajv"`; its *default* engine
`"imjv"` was measured wrong on 8/32 dialect probes (docs/CAPABILITY.md), mis-verifying
in **both** directions. This package therefore:

- names the engine once (`.bh_engine <- "ajv"`, `R/validate.R`) and exposes no argument to change it;
- runs `bh_dialect_probe()` (version-gated `if`/`then`, `contains`+`minContains`,
  `prefixItems`, asserted `format`) before every validation and refuses to report a
  verdict if any probe stops firing;
- pins the contrast in `test-engine-pin.R` against **released vector records** whose
  expected verdicts are the shared manifest's, with the live measurement
  `ajv 17/17; imjv mis-verifies 5/17 (2 silent accepts, 3 false rejects)` printed on
  every run, so the regression test fails if the engines ever converge or drift.

`format` is asserted, as `docs/SCHEMA-VERSIONS.md` requires of a conforming validator.
