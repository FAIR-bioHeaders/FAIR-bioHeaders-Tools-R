# FAIR-bioHeaders Tools — R

Native R reader, checksum verifier and contract validator for
[FAIR bioHeaders](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification)
file-bound metadata (`;~`/`#~` YAML header blocks in FASTA, GFA and GFF3), with no
foreign-language runtime anywhere in the acceptance path.

Released contracts, validated as JSON Schema draft/2020-12 with asserted `format`
(specification v0.6.0): **FHR 2.1, FHP 1.2, FHGFF3 1.2**.
FHT and FHGM are drafts under selection rule V7: opt-in, digest-pinned, warned on
every read, and **never a support claim** - see `docs/CAPABILITY-MATRIX.md`.

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

# Rule V7 draft lane - explicit, per read or process-wide, always warns:
bh_read("transcripts.fht.fasta", draft = "FHT")
bh_draft_vectors()                        # the FHT development suite, labelled draft evidence
bh_fhgm_models("ann.fhgff3.gff3", draft = "FHGM")   # FHGM records transported in an FHGFF3 header
bh_validate_fhgm("ann.fhgff3.gff3")                  # each record against the pinned draft contract
bh_draft_fhgm_vectors()                              # the FHGM suite, layer by layer
```

## What this package promises, and where the holes are

`bh_capability()` answers per type x operation x serialization x contract version,
and `docs/CAPABILITY-MATRIX.md` is that table published. Unfilled cells carry a
reason and a tracker - in particular the JSON-LD (37 vectors) and microdata
(26 vectors) readers are **not implemented**, nor is the FHGM checker's cross-record
layer (K3-K6: 24 of its 31 vectors are reported `not-run`, not passed). FHGM's lane
cells cover reading the transported records and validating each one against the
pinned draft record contract (K1/K2).
Acceptance is the federation's shared 291-vector suite; how it is run, guarded,
receipted and golden-pinned is `docs/NATIVE-ACCEPTANCE.md`. The measured state and
the explicit not-verified list are `docs/STATUS.md`.

## Development

- tests: `Rscript tools/run_tests.R` (fails on any skip or a low count), then
  `R CMD check --as-cran`
- shared-vector acceptance: `Rscript tools/acceptance_native.R`
- draft-lane acceptance: `Rscript tools/acceptance_draft.R` (FHT) and
  `Rscript tools/acceptance_fhgm.R` (FHGM, layer by layer; receipts to
  `BH_DRAFT_RECEIPT` / `BH_FHGM_RECEIPT`)
- vendored-bytes audit (offline) / draft-pin freshness (online, advisory):
  `Rscript tools/check_vendoring.R [--fresh --fht <checkout> --fhgm <checkout>]`
- docs: roxygen2 (`Config/roxygen2/version` in DESCRIPTION); regenerate `man/`
  and `docs/CAPABILITY-MATRIX.md` with `tools/render_capability_matrix.R`

License: **MPL-2.0** with the family's historical provenance split stated in
`LICENSE` (pre-March-2025 USDA-era material keeps its public-domain terms; see the
license header text). `DESCRIPTION` expresses it as `MPL-2.0 | file LICENSE`.
