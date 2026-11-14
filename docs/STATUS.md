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
| testthat assertions | 0 | **543, 0 failed, 0 errors, 0 skipped** |
| shared v0.6.0 vectors | not run | **291 accounted: 228 pass natively, 63 not-run with reasons, 0 fail** |
| FHT development suite (draft lane) | not run | not read at this revision: the lane is the next stacked change |
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
  docs/NATIVE-ACCEPTANCE.md, the default-behavior golden, receipts.

## Draft state (rule V7) at this revision

None. This revision registers and reads the three released types only: no draft
bytes are bundled, there is no V7 selection branch, and `bh_select()` sends every
FHT citation to rule V5 - the documented behaviour for unregistered values. The
pinned rule V7 lane for FHT (and the FHGM candidate bytes) lands in the stacked
draft-lane revision; until it does, no FHT or FHGM claim of any kind is made here.

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
3. **Any draft-type behaviour.** FHT and FHGM are not read at this revision; nothing
   is claimed about them beyond the V5 landing rule, which is tested.
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
