# FAIR-bioHeaders-Tools-R

An R package that reads, checksum-verifies and contract-validates
[FAIR-bioHeaders](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification)
file-bound metadata - natively in R, with no Python or other foreign-language runtime
behind it.

Baseline: specification **v0.6.0** (FHR 2.1, FHP 1.2, FHGFF3 1.2). See
[`docs/CAPABILITY-MATRIX.md`](docs/CAPABILITY-MATRIX.md) for what is implemented and what is
deliberately not, and [`docs/DIGEST.md`](docs/DIGEST.md) for the SHA-512/256 decision.

## Install

```sh
R CMD build .
R CMD INSTALL FAIRbioHeadersTools_0.1.0.tar.gz
```

Building needs a C99 compiler: the SHA-512/256 core is vendored C under `src/`, with no
external library. R package dependencies: `jsonvalidate` (which brings `V8`), `yaml`,
`jsonlite`, `digest`.

## Use

```r
library(FAIRbioHeadersTools)

r <- bh_read("genome.fhr.fasta")   # parse + checksum-verify + contract-validate
r$valid
r$header_type                      # "FHR", chosen by the file's own schema URL
r$checksum                         # recorded, computed, valid, bytes hashed
r$warnings                         # R11/R14 advice, empty-required values, V6, V7

bh_verify("genome.fhr.fasta")      # just the checksum verdict
bh_validate("proteins.fhp.fasta")  # just the contract verdict, naming the contract used

bh_verify_links("annotation.fhgff3.gff3", parent = "genome.fhr.fasta")

bh_types()                         # the family: three released, two drafts
bh_contracts()                     # the frozen contract copies this build holds
bh_capability()                    # type x operation x serialization x version matrix
```

Draft contracts (FHT, FHGM) are **not supported types**: they have no released contract, no
`schemaVersion`, no registry row and no w3id URL. They are reachable only through an
explicit rule V7 lane, pinned by commit and SHA-256, warning on every record read:

```r
bh_draft_pins()                                   # what is pinned, and its digest
bh_read("rna.fht.fasta", draft = "FHT")           # warns; V7, not a released result
bh_validate_fhgm("annotation.fhgff3.gff3")        # model records inside an FHGFF3 header
bh_draft_lane(FALSE)                              # closed again; the default is closed
```

With the lane closed, a draft citation is selected under V5 exactly as before V7 existed.

## What "verified" means here

Acceptance is the federation's shared, language-neutral suite - **291 vectors** at v0.6.0 -
not a per-language test set:

```sh
Rscript tools/check_vendoring.R          # the vendored bytes still match their provenance
R CMD check --no-manual FAIRbioHeadersTools_0.1.0.tar.gz
Rscript tools/run_conformance.R          # the shared vectors: 228 native pass, 63 not-run
Rscript tools/run_conformance.R --draft  # FHT development suite (draft evidence)
Rscript tools/run_conformance.R --fhgm   # FHGM development suite (layer by layer)
```

Current results on macOS/arm64 with R 4.6.1: `R CMD check` Status OK (0 errors, 0 warnings,
0 notes; 646 testthat assertions, 0 skips); shared suite 228/228 on the sequence formats
with 63 not-run and reasons; FHT 66/66 under the lane; FHGM base 31/31 and checksum 31/31,
model layer compared where its rules are record-shape only.

The suite is vendored under `tests/` with per-file SHA-256 in `inst/VENDORED.json`, so the
run is offline and cannot quietly shrink: a missing suite, a missing fixture, an unexpected
skip, or a zero-vector run is an error, not a pass.

## Not implemented

Writers (combine, strip, convert), the JSON-LD and microdata readers, and the FHGM draft
checker's cross-record rules. Each is a named cell with a reason in
[`docs/CAPABILITY-MATRIX.md`](docs/CAPABILITY-MATRIX.md), and the vector counts they leave
unrun are printed rather than hidden.

## License

MPL-2.0 (`LICENSE`), carrying the family's provenance split: material produced under USDA
employment through February 2025 stays public domain within the United States, and
contributions from March 2025 onward are MPL-2.0; previously distributed versions keep the
terms they were distributed under.
