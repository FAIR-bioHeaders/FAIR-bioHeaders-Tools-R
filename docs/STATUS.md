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

| measure | stub (main, `4b975bd`) | v0.6.0 core + lane (main, `8957f4f`) | this work (FHGM model lane) |
| --- | --- | --- | --- |
| `R CMD check --as-cran --no-manual` | 39 checks, 0 notes, Status OK | recorded by that revision as "66 checks, 0 errors, 0 warnings, 1 NOTE"; **not reproducible in this session** — the same commit `8957f4f`, checked here with the toolchain above, reports 1 WARNING and 1 NOTE | **0 errors, 1 WARNING, 1 NOTE** (66 check lines, 53 `checking` steps; `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 755 ]` inside the check). The NOTE is the unavoidable "New submission"; the WARNING is `Rd files with duplicated alias 'bh_abort'` (`man/conditions.Rd` and `man/internals.Rd`), present at `8957f4f` as well, so nothing here introduces it. Removing the duplicate roxygen block is a separate cleanup. |
| testthat assertions | 0 | **561, 0 failed, 0 errors, 0 skipped** (re-measured locally at `8957f4f`) | **755, 0 failed, 0 errors, 0 skipped** |
| shared v0.6.0 vectors | not run | **291 accounted: 228 pass natively, 63 not-run with reasons, 0 fail** | unchanged: the receipt is byte-identical to the one produced at `8957f4f` |
| default-behavior golden | none | `goldenDifferences=0` | `goldenDifferences=0`; the golden file is still SHA-256 `055da14f6dcbdb8ae9e5fc3880fb5bb56d510defb2e12639bde056edc820a525` |
| FHT development suite (draft lane only) | not run | **66/66 pass** against pinned bytes, in the separate labelled job | unchanged, same job |
| FHGM development suite (draft lane only) | not run | not run (the checker was not on `main`; see below) | **31 evaluated: base 31/31, checksum 31/31; model layer compared on the 7 K1/K2 vectors, all agreeing; 24 `not-run` naming K3-K6/B1** |
| compiled digest self-test | none | runs at every package load; refuses to load on any mismatch | unchanged |

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
- FHGM: **not a header type**. Its records are transported inside an FHGFF3 header under
  `x-fhgm-models` and carry no `schema` field, so the lane selects only the contract applied
  to the records. Contract bytes registered and digest-pinned (`ac3d37b3...`, SHA-256
  `bf1553cac04dc88d...`, 9,564 bytes - re-verified 2026-11-14 against the owning
  repository's live `main`, whose head is `52b07b7a...`, with a nonsense-path 404 control);
  the suite bytes are vendored under `tests/draft/fhgm` plus the `tests/draft/examples`
  files its vectors cite (17 + 23 files, manifest `31f14f02...`, 31 vectors).
  `bh_fhgm_models()` / `bh_validate_fhgm()` / `bh_draft_fhgm_vectors()` are the lane: they
  evaluate K1 (transport: one or more records, and no extension at all in an FHGFF3 1.0
  header) and K2 (each record against the pinned draft contract) and report the model verdict
  apart from the base FHGFF3 verdict. K3-K6 are **not** ported and stay named gaps with their
  own matrix rows; 24 of the 31 vectors are `not-run` for exactly that reason. Opt-in only,
  warns on every record read, and `schemaVersion`, registry row and w3id URL are all absent,
  as rule V7 requires. Tracked in #3; FHGM publishes as specification v0.8.0.
- Freshness of both draft pins was verified 2026-11-14 against the owning
  repositories' live default branches (advisory CI job `draft-pin-freshness`, which now
  covers both contracts and both suite manifests).

## The FHGM re-land (2026-11-14): what this section replaces

`docs/STATUS.md` at `8957f4f` said FHGM's checker was "not ported, not partial, not
claimed", and `bh_capability()` held `read_model_records` / `validate_model_records` at
`not-supported-yet`. Both were accurate for that commit, and both were the residue of a
merge accident rather than a decision to drop the work: on 2026-11-14 two parallel R PR
chains were merged minutes apart (#5 → #7 from `feat/native-sha512-256`, #6 → #8 from
`pr1/native-core`/`pr2/v7-draft-lane`) and `main` resolved to the #6/#7 content, so the
checker that the other chain carried - `R/fhgm.R`, `R/fhgm-run.R`, the vendored FHGM suite
and its tests - landed on `feat/native-sha512-256` (merge `3418cb8`) and never reached
`main`. Nothing on `main` was broken by that: `build` and `Native acceptance` were green at
`8957f4f`, and no document claimed the missing code.

This revision re-lands the checker onto `main` by port, not by re-merge, because the
surrounding modules on `main` are the other chain's: `.bh_resolve_named()`/`.bh_search()`
and the locator tests came over, `tools/run_conformance.R` did not (its role here is
`tools/acceptance_fhgm.R`, in the shape of the existing `tools/acceptance_draft.R`), and the
capability cells were rewritten for main's matrix rather than copied. `src/sha512.c` is the
same blob on both chains (`131f49cd58b9...`) and was not touched.

What is *newly* claimed, and what is not: the two FHGM cells move from `not-supported-yet`
to `draft-lane` for K1/K2 only, four named gap rows (K3-K6) are added, the shared ledger is
untouched at 291/228/63, and the default path is unchanged (golden identical).

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
7. **FHGM cross-record model rules** K3 (modelId uniqueness in a snapshot), K4
   (feature-target resolution against the GFF3 feature layer), K5 (record/file
   reference comparability) and K6 (predecessor-pointer resolution): not ported,
   named as their own matrix rows, and their 24 vectors are reported `not-run`
   rather than passed. The upstream checker (`validate_fhgm.py`) stays the
   reference for them and is deliberately not vendored here.
8. **FHGM revision/curator semantics.** A resolved pointer would only identify a
   predecessor, never accept a revision; that is a curator decision (shared #204)
   and nothing here claims it.
9. **Windows**: the package declares no OS restriction; not tested.

## Provenance notes

- `inst/VENDORED.json`'s `commit` fields record the **annotated tag object**
  SHAs for released-contract rows (all rows consistently; for example the
  v0.6.0 tag object `ab7e3ddd53bfccee9a31d59fc10524eadf32c1da` dereferences to
  commit `0ae18b00ee4bd71ab2dc28bae706b0f9d195076b`). Byte identity was verified
  against `git show v0.6.0:<path>`, which dereferences the tag.
- Every vendored byte was re-verified 2026-11-14 three ways: local file digest
  == recorded digest == upstream bytes at the pinned ref (293 shared-suite files,
  69 FHT draft-suite files, 9 contracts, the registry, 2 draft schemas). The FHGM
  set was vendored again for this revision, from a fresh clone of FHGM-Specification
  at `origin/main` = `52b07b7a`: 17 suite files and 23 example files, each written
  with `git show origin/main:<path>` and hashed here, and every digest-bearing
  field of the resulting `draft_fhgm_vectors` block (per-file SHA-256, manifest
  `31f14f02...`, combined `3ab6118f...`, contract `bf1553ca...` of 9,564 bytes at
  commit `ac3d37b3`) independently reproduced the values the lost branch had
  recorded. The 7 upstream generator/checker `.py` files are recorded as
  `not_vendored` and stay upstream. The ported `tools/vendor_upstream.R` step was then
  run end-to-end in a scratch clone against that same fresh FHGM clone: it wrote 17 + 23
  files byte-identical to what is committed (`diff -r`, empty) and a block identical in
  every digest-bearing field. Two residual differences are prose, not digests, and both
  are pre-existing in kind: `repository` is taken from the given checkout's own `origin`
  (the tool writes the HTTPS `FHGM-Specification` URL where the committed rows, including
  `main`'s FHGM contract row, name the SSH redirect `git@github.com:FAIR-bioHeaders/FHGM.git`),
  and the tool's `commit_field` sentence is older than the refined text in the committed
  file, so a full re-vendor would revert it. Neither is settled here; the shared and FHT
  blocks reproduce exactly.
- What the FHGM lane does **not** vendor: the transport overlay contract
  (`development/model/fhgm-draft.schema.json`, the FHGFF3-with-`x-fhgm-models`
  shape) and the reference checker (`development/model/validate_fhgm.py`). This
  package validates records against the pinned record contract and reads the
  transport from the parsed header; the overlay is not asserted here, and K3-K6
  remain upstream's checker.
- The federation's R capability study is archived at docs/CAPABILITY.md
  (single-host measurement; the digest route in this repo supersedes its open
  question as a **decision**, with the alternatives and why they were rejected
  recorded in docs/DIGEST.md).
