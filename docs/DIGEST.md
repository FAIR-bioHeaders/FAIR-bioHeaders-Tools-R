# The SHA-512/256 route: decision, evidence, and what was rejected

Decided **2026-11-14**. Owner: FAIR-bioHeaders-Tools-R, under
[issue #4](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Tools-R/issues/4) and
[#3](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Tools-R/issues/3), following the
native-first direction recorded in
[FAIR-bioHeaders-Specification#211](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification/issues/211)
(Round 10), which names R specifically: *"Resolve R's real SHA-512/256 route explicitly
under this native-first direction; do not silently choose Python delegation, truncated
SHA-512 or a quietly incorrect schema engine."*

## The requirement

`docs/FORMAT.md` rule R4: the checksum is **SHA-512/256** - the FIPS 180-4 algorithm of
that name - over the file's exact bytes except the root-level checksum line and its
terminator (R1-R3), encoded as canonical padded standard base64 (44 characters, the
character before `=` one of `AEIMQUYcgkosw048`), compared as exact strings.

SHA-512/256 is not SHA-512 truncated. It is the SHA-512 compression function run from a
different initial hash value (FIPS 180-4 5.3.8) with the first four state words returned.
That difference is why a wrong choice here is invisible: every candidate produces a
well-formed 44-character string.

## Decision

**Vendor FIPS 180-4 SHA-512/256 in C under `src/`, with no external library.**

* `src/sha512.c` - the SHA-512 core, configured as SHA-512/256 and as SHA-512.
* `src/scan.c` - the rule R1 line scanner that lets rule R10 be checked over a file the
  caller never loads into R memory.
* `src/entry.c` - `.Call` bindings, canonical base64, and a load-time self-test.
* `R/digest.R` - the R API: `bh_sha512_256()`, `bh_sha512_256_file()`, `bh_digest_stream()`.

Cost accepted: compiled code, so a C compiler is needed to build from source
(`SystemRequirements: C99`, `NeedsCompilation: yes`).

Capability gained: **no runtime dependency outside R and the three imported R packages**,
and no external process, so the primary acceptance job needs nothing but an R
installation.

The load-time self-test is the guard against the one failure mode this choice introduces -
a miscompiled core. `.onLoad()` runs the published sample messages through the compiled
code and **refuses to load the package** if they do not match
(`src/entry.c`, `bh_selftest()`). There is no fallback anywhere in the digest path:
`bh_sha512_256_available()` is `TRUE` exactly when the package loaded, and if the shared
object is missing, the calls error naming that fact rather than substituting something.

## Evidence

### 1. Published vectors, from a source that is not this package

The NIST CVL worked example *"Secure Hash Algorithm, Message Digest Length = 512/256"* was
retrieved on 2026-11-14 from

```
https://csrc.nist.gov/csrc/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA512_256.pdf
```

(HTTP 200, `application/pdf`, 86,756 bytes, 8 pages; positive control - the nonsense URL
`https://csrc.nist.gov/definitely-not-a-page-xyz123` returned 404, so a 200 here means
something.) It states the SHA-512/256 initial hash value and works through two sample
messages:

| input | published 512/256 digest | this package |
| --- | --- | --- |
| `"abc"` | `53048E26 81941EF9 9B2E29B7 6B4C7DAB E4C2D0C6 34FC6D46 E0E2F131 07E7AF23` | identical |
| the 112-character two-block sample | `3928E184 FB8690F8 40DA3988 121D31BE 65CB9D3E F83EE614 6FEAC861 E19B563A` | identical |

Those two values are the constants inside `bh_selftest()`, so they are checked on every
load as well as in `tests/testthat/test-digest-vectors.R`. The eight initial words in
`src/sha512.c` are the eight the same document lists under "Initial hash value".

The FIPS 180-4 message 3 sample (1,000,000 × `'a'`) is **not** in that document; its
expected value here (`9a59a052930187a97038cae692f30708aa6491923ef5194394dc68d56c74fb21`)
comes from two independent implementations on this host - `openssl dgst -sha512-256`
(OpenSSL 4.1.0) and CPython `hashlib.new("sha512_256")`, which agreed - and the test file
labels it as locally generated rather than published. The same is true of the
length-boundary corpus (0, 1, 2, 55, 56, 57, 63, 64, 65, 111, 112, 113, 119, 120, 121, 127,
128, 129, 200, 1000 bytes), which pins the padding-boundary behaviour.

The 80 round constants were derived from the definition rather than copied from memory
(first 64 bits of the fractional parts of the cube roots of the first 80 primes) and then
confirmed by the vectors; the shared SHA-512 path in the same core is checked against the
published SHA-512 of `"abc"` (`ddaf35a193617aba...`), which is what distinguishes "the
compression function is right" from "one value came out right by luck".

### 2. The reference implementation, through the shared suite

(Scope note for this revision: the digest layer and its published-vector tests land here; the
comparison against the suite's own stated checksums
(`tests/testthat/test-digest-fixtures.R`) and the supplemental client differential
(`tools/differential_digest.R`) land with the reader in the next PR of this stack. Every
number quoted below was executed locally on the combined work before the split, and each PR's
status comment reports the run it makes reproducible.)

The strongest evidence is not a hash of `"abc"`: it is that the shared suite states the
checksum of its own bytes. For **all 87 valid sequence-format vectors** at the v0.6.0
baseline, the digest this code computes over the rule R3 coverage equals the checksum line
inside the file equals the manifest's declared checksum
(`tests/testthat/test-digest-fixtures.R`, which prints the count it compared). Those 87
values were produced by the reference Python toolkit and reviewed upstream. They are
pinned data, not a live Python call: no test in this package invokes Python.

Across the whole suite the native run agrees with the manifest on **228 of 228**
sequence-format vectors, and the acceptance job reports all **291** as pass, fail or
not-run-with-reason.

### 3. The negative control, asserted rather than assumed

`tests/testthat/test-digest-vectors.R` (and `test-digest-fixtures.R`, with the reader) assert that
base64(SHA-512(bytes)[0:32]) differs from SHA-512/256 - on `"abc"` (`ddaf35a1...` against
`53048e26...`) and on a byte range taken from a real vector. If the initial hash value in
`src/sha512.c` were ever replaced by SHA-512's, those tests fail and the load self-test
fails first.

## Routes measured and rejected

| route | measured result | why rejected |
| --- | --- | --- |
| `digest` 0.6.39 (CRAN) | no SHA-512/256. Accepted `algo` values are md5, sha1, crc32, sha256, sha512, xxhash32/64, murmur32, spookyhash, blake3, crc32c, xxh3_64, xxh3_128 - not even sha384 | cannot do it; the trap is that `digest(x, "sha512")` then half-cutting looks like an answer |
| R `openssl` 2.4.2 / 2.5.0 | no SHA-512/256: exports `sha1 sha2 sha224 sha256 sha3 sha384 sha512 multihash`, and `sha2(x, size)` takes 224/256/384/512 only | cannot do it |
| truncated SHA-512 | different algorithm, plausible output | rejected by rule R4 and by the direction quoted above; now asserted against in tests |
| (b) `Rcpp` + libcrypto `EVP_get_digestbyname("SHA512/256")` | not implemented; the capability study's own wording applies: it "adds a system-library build requirement, i.e. the same class of problem as the CLI, moved to build time" | rejected: a build-time dependency on a system libcrypto whose availability and version differ across CRAN/Bioconductor images, plus an `Rcpp` LinkingTo dependency, to obtain a function that fits in one C file we already test against published vectors |
| (c) system `openssl dgst -sha512-256` CLI | **proven byte-exact**: re-run here on 106 inputs (31 pinned vectors plus the 87 valid sequence vectors' stated checksums) against OpenSSL 4.1.0, 0 disagreements | rejected as the *primary* route: one `system2()` per file, a `PATH` dependency, quoting and temp-file handling, and the class of external-process dependency that `R CMD check` portability expectations and Bioconductor deployment dislike. Kept as a **supplemental** differential (`tools/differential_digest.R`, landing with the reader in this stack), which is skipped - visibly - where no client is installed, and is not part of acceptance |
| (d) hash inside the V8 engine `jsonvalidate` already imports | not implemented; the study records it as "an option to price, not a result" | rejected: it does not remove a dependency, it relocates the problem into a JavaScript engine we pull in for schema validation, and it makes the checksum depend on how `jsonvalidate` chooses to bundle V8 in a future version. `V8` is also the least portable build in the stack (Linux source builds need `libv8`), and the checksum must not inherit that |
| Python delegation | available on this host (`hashlib`, and `fair-bioheaders` 0.11.0) | rejected by the native-first direction, and on the merits: an R library that cannot compute its own checksum cannot verify that a header still matches its bytes, which is the property the family exists for |

## Portability, stated as it stands

Verified on this revision: macOS 14 arm64 (aarch64-apple-darwin23), R 4.6.1, Apple clang 21 -
`R CMD check --no-manual` Status OK, 44 check steps, 202 testthat assertions, 0 skips,
0 warnings, 0 notes. The standalone C harness (31 vectors x 16 chunkings = 496 checks, all
passing) was run against `src/sha512.c` outside R during development and is not committed as a
package test; the same vectors are covered by `tests/testthat/test-digest-vectors.R`.

**Not verified**: Linux and Windows builds of the vendored core. The CI matrix runs
`ubuntu-latest` and `macos-latest`; `windows-latest` is not claimed, and the R-specific
constraint that `V8` (a `jsonvalidate` dependency) must build there is unresolved and
independent of this decision. `bh_ctx_init()` refuses to run if the platform's 64-bit type
is not exactly 64 bits, so an unsuitable platform errors rather than hashing wrongly, but
that path has been exercised only on this host. Before any CRAN or Bioconductor submission
the digest route needs a portability proof on Linux and Windows - see
`docs/CAPABILITY.md` item 5.

## Schema engine, decided in the same breath (implemented with the reader)

The other "quietly incorrect" risk the direction names. `jsonvalidate` 1.5.0 validates
draft/2020-12 correctly **only** with `engine = "ajv"`; its default `"imjv"` engine
mis-verifies in both directions. `engine` is therefore a package-internal constant
(`.bh_engine`), never an argument - `tests/testthat/test-engine-pin.R` asserts that no
function in the namespace takes one - and it asserts the contrast on upstream data: on the
17 contract-layer vectors chosen to exercise version-gated `if`/`then`,
`contains`/`minContains` and `$defs` references, ajv matches the manifest on 17/17 while
imjv is wrong on 5 (2 silent accepts, 3 false rejects). `bh_dialect_probe()` re-runs the
2020-12-only constructs before every validation and raises rather than reporting a verdict
from a wrong engine. A contract that does not declare `draft/2020-12` is refused outright.
