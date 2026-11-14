# STATUS — measured state of the R library

Date: **2026-11-14**. Everything below was measured on the commit this document
accompanies, on macOS 14 arm64 with R 4.6.1, `jsonvalidate` 1.5.0 (V8 8.2.1),
`digest` 0.6.39, `yaml` 2.3.12, `jsonlite` 2.0.0, `roxygen2` 8.1.0,
`testthat` 3.3.2. CI re-measures the same spine on ubuntu-latest and macos-latest.

## Baseline comparison, honestly framed

The stub package on `main` before this work reported `Status: OK / 39 checks /
0 notes` **because it was empty**: no compiled code, no exports beyond a
placeholder, no tests. Those 39 checks are not a quality bar; the numbers below
are the first real ones for this repository.

| measure | stub (main, `4b975bd`) | this work |
| --- | --- | --- |
| `R CMD check --as-cran --no-manual` | 39 checks, 0 notes, Status OK | 66 checks, **0 errors, 0 warnings, 1 NOTE** ("New submission", unavoidable for a first package; running with the manual adds only the host-dependent "HTML Tidy not recent enough" skip-NOTE on this macOS) |
| testthat assertions | 0 | **561, 0 failed, 0 errors, 0 skipped** (428 at the core revision; the lane revision adds 133) |
| shared v0.6.0 vectors | not run | **291 accounted: 228 pass natively, 63 not-run with reasons, 0 fail** |
| FHT development suite (draft lane only) | not run | **66/66 pass** against pinned bytes, in the separate labelled job |
| compiled digest self-test | none | runs at every package load; refuses to load on any mismatch |

## What is implemented (native, released types)

- Vendored FIPS 180-4 SHA-512/256 (`src/`), streaming with rule-R3 range exclusion
  and the rule-R10 line scanner; decision and evidence in docs/DIGEST.md.
- Byte-exact framing (rules R1-R7, R10), YAML semantics (R8, R12, R13), warning
  reporting (R11, R14, empty-required), contract validation with `engine = "ajv"`
  asserted and dialect-probed, selection rules V1-V6, parent-link verification
  (`bh_verify_links`), gzip/BGZF transport, the five-type registry
  (`bh_types`/`bh_contracts`/`bh_capability`).
- The 291-vector native runner with the seven guards in
  docs/NATIVE-ACCEPTANCE.md, the default-behavior golden, receipts. The golden is
  byte-identical between the core revision and this one: the lane changed nothing
  by default (`goldenDifferences=0` both sides).

## Draft state (rule V7; never a support claim)

- FHT: opt-in lane, pinned contract `226f923c28b680edb3c546e99a751482d06aef1a`
  (SHA-256 `59ad9641...`), suite `156bda63...` (manifest `9b071794...`), 66/66
  pass; warns on every read; release-shaped FHT URLs stay V5. FHT publishes as
  specification v0.7.0 (FHT-Specification #8/#9/#10).
- FHGM: **not a header type**; candidate bytes registered and digest-pinned
  (`ac3d37b3...`, `bf1553ca...`); `read_model_records`/`validate_model_records`
  are `not-supported-yet` because the upstream acceptance suite (31 vectors,
  K1-K6) is checker-based and 18/19 of its invalid vectors pass the base schema
  and checksum — porting the checker is the gate. Tracked in #3; FHGM publishes
  as specification v0.8.0.
- Freshness of both draft pins was verified 2026-11-14 against the owning
  repositories' live default branches (advisory CI job `draft-pin-freshness`).

## Ledger (v0.6.0 baseline; identical figures from the Java library)

    vectorsTotal=291 vectorsRun=228 vectorsPassed=228 vectorsFailed=0
    vectorsNotRun=63 vectorsDeclaredNotRunWithReason=63
    fasta=98/98 passed, 0 not run        gfa=56/56 passed, 0 not run
    fhp-fasta=36/36 passed, 0 not run    fhgff3=38/38 passed, 0 not run
    microdata=0/26 passed, 26 not run    jsonld=0/37 passed, 37 not run

## Not verified (deliberately; each is a claim someone else's measurement must make)

1. **Linux/Windows compilation and check results.** The C core was compiled and
   exercised on macOS/arm64 only locally; ubuntu coverage arrives with the CI
   runs of this PR and is not asserted here until those runs are green and
   recorded below by date.
2. **Large-file behaviour.** The streaming path is proven byte-correct on the
   suite (largest vector is small) and the head-reading path refuses oversized
   header blocks; no gigabyte-scale reference genome was hashed in this session.
3. **`selfChecksum`/`parentLink` draft semantics** beyond what the FHT suite's
   C1/C3 vectors state; they finalize at FHT release (FHT-Specification #10).
4. **Any performance claim.** No benchmarks were run.
5. **Bioconductor/CRAN acceptance.** Out of scope for these PRs by instruction;
   submission is a maintainer action.
6. **Microdata and JSON-LD readers** do not exist here (63 not-run vectors,
   reasons declared per row) — their rules (M1-M5, J1-J9, R9) are not "almost"
   covered by anything in this package.
7. **FHGM model-record checking** (K1-K6): not ported, not partial, not claimed.
8. **Windows**: the package declares no OS restriction; not tested.

## Provenance notes

- `inst/VENDORED.json`'s `commit` fields record the **annotated tag object**
  SHAs for released-contract rows (all rows consistently; for example the
  v0.6.0 tag object `ab7e3ddd53bfccee9a31d59fc10524eadf32c1da` dereferences to
  commit `0ae18b00ee4bd71ab2dc28bae706b0f9d195076b`). Byte identity was verified
  against `git show v0.6.0:<path>`, which dereferences the tag.
- Every vendored byte was re-verified 2026-11-14 three ways: local file digest
  == recorded digest == upstream bytes at the pinned ref (293 shared-suite files,
  69 FHT draft-suite files, 9 contracts, the registry, 2 draft schemas).
- The federation's R capability study is archived at docs/CAPABILITY.md
  (single-host measurement; the digest route in this repo supersedes its open
  question as a **decision**, with the alternatives and why they were rejected
  recorded in docs/DIGEST.md).
