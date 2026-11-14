# FAIR-bioHeaders Tools — R

Native R reader, checksum verifier and contract validator for
[FAIR bioHeaders](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification)
file-bound metadata (`;~`/`#~` YAML header blocks in FASTA, GFA and GFF3), with no
foreign-language runtime anywhere in the acceptance path.

Released contracts, validated as JSON Schema draft/2020-12 with asserted `format`
(specification v0.6.0): **FHR 2.1, FHP 1.2, FHGFF3 1.2**.
FHT and FHGM are drafts under selection rule V7; this revision does not read them
(no draft bytes, no V7 branch) - the opt-in draft lane is the next stacked change.

## Install

```sh
R CMD build . && R CMD INSTALL FAIRbioHeadersTools_*.tar.gz
```

A C compiler is required (the vendored SHA-512/256 core in `src/`; see
`docs/DIGEST.md` for why it is vendored rather than delegated).

## Use

```r
library(FAIRbioHeadersTools)

x <- bh_read("genome.fhr.fasta")          # parse + verify + validate
x$valid                                   # one logical, everything considered
x$checksum$computed == x$checksum$recorded
x$selection$rule                          # which selection rule chose the contract

bh_verify("genome.fhr.fasta")             # checksum only
bh_validate("ann.fhgff3.gff3")            # contract verdict against the cited schema
bh_sha512_256_file("genome.fhr.fasta")    # the file checksum, streamed

x <- bh_conformance()                     # the shared 291-vector suite, natively
x$ok
```

## Where the holes are

The JSON-LD (37 shared vectors) and microdata (26) readers are **not implemented**;
the 291-vector run declares those 63 vectors not-run with reasons instead of hiding
them. The five-type capability table is published with the draft-lane revision
(`docs/CAPABILITY-MATRIX.md` lands there). Acceptance is the federation's shared
291-vector suite; how it is run, guarded, receipted and golden-pinned is
`docs/NATIVE-ACCEPTANCE.md`. The measured state and the explicit not-verified list
are `docs/STATUS.md`.

## Development

- tests: `Rscript tools/run_tests.R` (fails on any skip or a low count), then
  `R CMD check --as-cran`
- shared-vector acceptance: `Rscript tools/acceptance_native.R`
- vendored-bytes audit (offline): `Rscript tools/check_vendoring.R`
- docs: roxygen2 (`Config/roxygen2/version` in DESCRIPTION); regenerate `man/`

License: **MPL-2.0** with the family's historical provenance split stated in
`LICENSE` (pre-March-2025 USDA-era material keeps its public-domain terms; see the
license header text). `DESCRIPTION` expresses it as `MPL-2.0 | file LICENSE`.
