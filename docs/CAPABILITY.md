# Provenance of this document

This is a verbatim copy of a capability study measured on **2026-11-14** on **one
macOS/arm64 host** (macOS 14, arm64) with **R 4.6.1** and **jsonvalidate 1.5.0**
(dependency V8 8.2.1), against the released v0.6.0 contract bytes. It is **not** a claim
about a released FAIR-bioHeaders R library: none existed when the study was written and
none exists now. The raw probe data it summarises (the `.tsv` result tables and the
throwaway `conform.R` and `digest_equality.R` scripts) was kept with the study in the
federation's working materials and is not reproduced in this repository. Every figure
below is a single-host measurement, and the dependency question it frames - how a real
package should obtain SHA-512/256 - is an open maintainer decision, not a recommendation
implemented here. The study text follows unchanged.

---

# Capability study — R for FAIR-bioHeaders (E0) and shared-vector results (E2)

Studied on **2026-11-14** on one host (macOS 14, arm64; R 4.6.1 "Happy Hop" at
`/usr/local/bin/R`). All statements below are measurements taken on that host and in that
R session; nothing here is a claim about a released FAIR-bioHeaders R library, because
none exists.

Inputs are the **released v0.6.0 contract bytes** (spec tag `v0.6.0` → main commit
`0ae18b0`), verified by SHA-256 before use:

| file | sha256 (first 16) |
| --- | --- |
| `fhr.json` | `694ab5afaf8c3743` |
| `fhp.json` | `92a0b3cbcfe69939` |
| `fhgff3.json` | `1942be4cefc8b3a2` |

Registry (`schemas/versions.json` at `v0.6.0`, `preRelease: null`): **FHR 2.1, FHP 1.2,
FHGFF3 1.2**. FHT and FHGM are drafts and take no part in this study (rule V7).

## Verdict

R is **feasible**, not blocked, but neither hard technical constraint is satisfied by the
obvious package:

1. **Schema layer — clear, with a mandatory configuration requirement.** `jsonvalidate`
   1.5.0 with `engine = "ajv"` validates the contracts' actual dialect correctly: 32/32
   probes matched the reference Python verdict. `jsonvalidate`'s *default* engine
   (`"imjv"`) is wrong on 8 of 32 probes and fails **silently in both directions**.
2. **Checksum layer — no pure-R route.** Neither `digest` (0.6.39, current CRAN) nor
   `openssl` (2.4.2 installed / 2.5.0 current CRAN) exposes SHA-512/256. The system
   `openssl dgst -sha512-256` reproduces the released toolkit exactly (87/87 valid
   vectors, byte-identical digests). Choosing between a system-CLI dependency, a
   vendored C implementation and delegation to the Python CLI is a **maintainer
   dependency-policy decision for a scientific package**, not an implementation detail.

So the reconnaissance the task began from is **half superseded**: `jsonvalidate` is not
draft-07-capped at 1.5.0 (it was, in the 1.3-era docs, and its own DESCRIPTION still says
"Drafts 04, 06 and 07"), while the SHA-512/256 gap in `digest` is real and unfilled.

## E0(a) — does the contracts' dialect validate in R?

Dialect confirmed from the released tag, not from documentation: all three contracts
declare `"$schema": "https://json-schema.org/draft/2020-12/schema"`.

Environment: `jsonvalidate` **1.5.0** (CRAN binary), dependency `V8` **8.2.1**
(CRAN binary; `Imports: R6, V8`; `V8.so` links only `libR.dylib`, `libc++.1`,
`libSystem.B` — the libv8 it needs is static inside the package). `jsonvalidate` vendors
ajv; `strictTypes` is present in the bundle, which is an ajv-8 option, and the bundle
contains the draft-07 **and** the 2019-09 and 2020-12 meta-schema/vocabulary modules. The
exact ajv version is not readable from the minified bundle; `jsonvalidate`'s NEWS records
the 1.3.0 upgrade to **ajv 8.5.0**.

Ground truth: `jsonschema` **4.26.0**, `Draft202012Validator(schema,
format_checker=FormatChecker())` — the same construction FAIR-bioHeaders-Tools uses —
with `rfc3987` installed, so `format` **is asserted** by the reference implementation.
My 32 probe expectations were checked against it first: all 32 agreed, so the probe set
is anchored to the reference semantics, not to my guesses.

Probes exercise only constructs the released contracts actually use, plus one
2020-12-only set to test dialect dispatch.

| construct | where it occurs | `engine="ajv"` | `engine="imjv"` (default) |
| --- | --- | --- | --- |
| `$defs` + `$ref` | fhp 25 refs, fhgff3 29 refs | correct | correct |
| legacy `definitions` + `#/definitions/...` | fhr (`orcidUri`, `sha2`) | correct | correct |
| `patternProperties` `^x-[A-Za-z0-9][A-Za-z0-9_.-]*$` | all three | correct | correct |
| `propertyNames: {not: {pattern: …}}` | all three | correct | correct |
| `additionalProperties: false` | all three | correct | correct |
| version-gated `if`/`then` (reject `x-` keys at FHR 2.0, FHP/FHGFF3 1.0) | fhr 1, fhp 6, fhgff3 8 | **correct: rejects** | **wrong: accepts** (6 records that must be invalid read as valid) |
| version-gated `if`/`then` on dotted BUSCO `lineageDataset` (1.0/1.1 reject, 1.2 accepts) | fhp, fhgff3 | correct | **wrong: accepts** |
| `contains` + `minContains: 2` (FHGFF3 "not two `annotates` parents") | fhgff3 | correct | **wrong in both directions** (2 valid records rejected) |
| `if` whose condition is a `$ref` (`items: {if: {$ref: AnnotatesAny}, then: {headerType const FHR}}`) | fhgff3 | correct | wrong |
| `format: uri` | all three | asserted (matches reference) | asserted |
| `prefixItems` / `unevaluatedProperties` / `dependentRequired` / `$dynamicRef` (dialect probe, not used by the contracts) | — | honoured as 2020-12; a schema declaring draft-07 gets draft-07 semantics instead | n/a |

**Totals: ajv 32/32; imjv 24/32.** The dispatch is `$schema`-driven: `jsonvalidate` reads
the meta-schema URI (`read_meta_schema_version` accepts
`draft/2020-12`) rather than assuming draft-07, which is why the 2020-12-only constructs
behave correctly here.

Two caveats that belong in any R README:

- `jsonvalidate` 1.5.0's own DESCRIPTION advertises only "Drafts 04, 06 and 07", so the
  2020-12 behaviour, while reproducible, is **not documented upstream**. An R package that
  relies on it is relying on an implementation detail of a vendored bundle and must pin
  and test it, not trust it.
- A schema with **no `$schema` key at all** compiles and then fails at validation time with
  `ReferenceError: dialect is not defined` (upstream fragility, not triggered by our
  contracts, which always declare the dialect).

Consequence for the library: `engine = "ajv"` must be **non-negotiable and covered by
tests** — a regression to the default engine would not error, it would accept FHR 2.0
records carrying extension fields and reject valid FHGFF3 records, i.e. mis-verify
metadata.

## E0(b) — SHA-512/256

The checksum is `base64(SHA-512/256)` over the file's exact bytes except the single
root-level checksum line (docs/FORMAT.md R1–R5; 44 canonical base64 characters).

Routes tested on this host:

| route | result |
| --- | --- |
| `digest` 0.6.39 (current CRAN) | **no SHA-512/256.** Accepted `algo` values are md5, sha1, crc32, sha256, sha512, xxhash32/64, murmur32, spookyhash, blake3, crc32c, xxh3_64, xxh3_128. Not even sha384. |
| `openssl` R package 2.4.2 / current 2.5.0 | **no SHA-512/256.** Exports `sha1 sha2 sha224 sha256 sha3 sha384 sha512 multihash`; `sha2(x, size)` takes 224/256/384/512 only. |
| naive truncation of SHA-512 | **wrong algorithm**, and this is the trap to name explicitly: `sha512("abc")` starts `ddaf35a1…`, `SHA-512/256("abc")` is `53048e26…`. A port that hashes SHA-512 and cuts it in half mis-verifies every file while producing a plausible 44-character value. |
| system `openssl dgst -sha512-256` (OpenSSL 4.1.0, Homebrew) | **works.** On four real released vectors the hex digest was byte-equal to Python `hashlib.new("sha512_256")`: `example.fhr.fasta bece8f95…`, `fasta-lf.fhr.fasta 3ed0cba1…`, `rich.fhp.fasta f3c471fc…`, `v.fhgff3.gff3 7812a363…`. At scale: for all **87** valid sequence-format vectors, R-computed digest == the checksum line inside the file == the manifest's declared checksum. R's own `gzfile()` decompression handled the gzip and multi-member/BGZF vectors. |

Base64 came from `openssl::base64_encode` (pure package call); only the hash needed the CLI.

The CLI route costs a `system2()` call per file, needs `openssl` on `PATH`, and is the kind
of external-process dependency that R CMD check portability expectations and bioconductor
deployment dislike; it was verified only on macOS with Homebrew OpenSSL 4.1.0. Options for
a real package, in the order I would put them to a maintainer:

1. **Vendor a FIPS 180-4 SHA-512/256 in `src/`** (C, no external library), with the RFC's
   test vectors plus the 87 vector digests above as regression tests. Cleanest
   dependency story; costs compiled code and a portability matrix.
2. **Link libcrypto through Rcpp and call `EVP_get_digestbyname("SHA512/256")`** — small,
   but adds a system-library build requirement, i.e. the same class of problem as the CLI,
   moved to build time.
3. **System `openssl` CLI** — zero compiled code, proven correct here; a runtime
   dependency that must be declared, feature-detected, and fail loudly when absent.
4. **Delegate the checksum to the Python toolkit** and ship R as a schema/metadata-only
   library. Honest but partial: an R user could then read and validate a header but not
   verify that it still matches its bytes, which is the property the family exists for.

A fifth possibility the schema study opens up: **compute the digest inside the V8 engine
that `jsonvalidate` already pulls in** (a JS SHA-512/256, or an existing JS implementation
bundled as `inst/`), reusing a dependency the package needs anyway instead of adding a
second one. I did not implement or benchmark that; it is recorded as an option to price,
not as a result.

## E2 — shared conformance vectors (291, no new suite)

`conformance/manifest.json` at `v0.6.0`: **291 vectors** (fasta 98, gfa 56, fhgff3 38,
fhp-fasta 36, jsonld 37, microdata 26; 11 compressed), plus 1 retired id.

A throwaway R prototype (`conform.R`, not a package, no Python in its loop) implemented
R1–R8, R10, R12, R13, G1, V1–V6 selection and schema validation, with the digest from the
system `openssl` CLI.

| format | vectors | R prototype == manifest expectation |
| --- | --- | --- |
| fasta | 98 | **98/98** |
| gfa | 56 | **56/56** |
| fhp-fasta | 36 | **36/36** |
| fhgff3 | 38 | **38/38** |
| jsonld | 37 | **not run** — no JSON-LD reader |
| microdata | 26 | **not run** — no HTML/microdata reader |

- Sequence formats: **228/228**, including all 141 expected-invalid vectors. The same 228
  run through released `fair-bioheaders` **0.11.0** on this host: 228/228, and the R
  prototype agreed with the released toolkit on **228/228**.
- Rejection reasons for the 141 invalid vectors, by how they surfaced: 74 named the
  declared rule directly; 46 were schema-layer rules (P1/P2, G2/G3, R15, V1/V2/V3/V5/V6)
  reported as "the selected schema rejected the record"; 15 were byte-tamper rules
  (R1/R3) reported as a digest mismatch (R4) — a single-pass verifier cannot tell those
  apart by construction; 3 duplicate-key vectors (R8) were caught by the `yaml` 2.3.12
  package itself ("Duplicate map key"); 2 non-canonical-base64 vectors (R4) were caught one
  step earlier by the R5 line grammar; 1 G1 vector surfaced as R10. **Zero vectors were
  accepted for an unexplained reason.**
- Not run, and why: all 37 jsonld and all 26 microdata vectors (rules J1–J9, M1–M5, R9,
  plus R11/R14 which are writer/warning rules). R has no JSON-LD expansion implementation
  in the tested stack, and the microdata layer needs an HTML reader with implied-end-tag
  semantics; both are unbuilt work, not measured failures.

Provenance note that matters for a real port: the per-release schema files this run
validated against came from the released Python wheel
(`bioheaders/schemas/{fhr,fhp,fhgff3}-<version>.json`), and I verified each is byte-equal
to the spec tag it stands for — `fhr-1`↔`v0.3.1` `e3d3843e…`, `fhr-2.0`↔`v0.4.0` `168a6046…`,
`fhp-1.0`/`fhgff3-1.0`↔`v0.4.0` `e3f8f452…`/`f89635f2…`,
`fhp-1.1`/`fhgff3-1.1`↔`v0.5.0` `2409739d…`/`20ce320f…`,
`fhr-2.1`/`fhp-1.2`/`fhgff3-1.2`↔`v0.6.0` `694ab5af…`/`92a0b3cb…`/`1942be4c…`. An R package
must ship its own pinned copies from those tags rather than borrow the Python wheel's.

## What a real FAIR-bioHeaders-Tools-R still needs

1. A SHA-512/256 decision (above), enforced by a test that fails when the digest source is
   missing — never a silent skip.
2. `engine = "ajv"` pinned in code, with the 32-probe suite as regression tests, plus a
   guard that the dialect is actually 2020-12 (the probes are cheap and they are the only
   thing that distinguishes a correct engine from a quietly wrong one).
3. Pinned contract copies per release + `versions.json`, with a draft-pin freshness check
   (recorded sha256 against the owning repo's live raw-main bytes).
4. The microdata and JSON-LD readers, or an explicit documented non-goal.
5. Portability proof for the digest route on Linux and Windows before any CRAN/Bioconductor
   submission (Bioconductor would also need `V8` to build there; CRAN provides binaries for
   macOS and Windows, source builds need `libv8-dev`/`v8-devel` on Linux).

## What this document does not claim

- No R library exists, is released, or is installable; the prototype is a single-host
  throwaway script, not a package, not tested under `R CMD check`, not run on Linux or
  Windows.
- No FHT or FHGM support of any kind: no `schemaVersion`, no w3id URL, no registry row, no
  conformance coverage (rule V7 — drafts take no release form).
- jsonvalidate 1.5.0's 2020-12 behaviour is measured, not licensed by upstream
  documentation, and not verified for constructs beyond those listed.
- The 228/228 figure covers the rules the prototype implements; it is not a claim that R
  conforms to FORMAT.md as a whole (63 vectors unrun, and rule labels were matched by
  category as documented above).
