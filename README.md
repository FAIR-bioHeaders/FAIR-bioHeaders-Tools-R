# FAIR-bioHeaders Tools — R

Native R reader, checksum verifier and contract validator for
[FAIR bioHeaders](https://github.com/FAIR-bioHeaders/FAIR-bioHeaders-Specification)
file-bound metadata (`;~`/`#~` YAML header blocks in FASTA, GFA and GFF3). Framing,
the checksum and the YAML rules are R and vendored C. JSON Schema validation uses
`jsonvalidate` with its `ajv` engine, which runs in the V8 JavaScript engine that
`jsonvalidate` embeds; no Python or other toolkit is called.

Released contracts, validated as JSON Schema draft/2020-12 with asserted `format`
(specification v0.6.0): **FHR 2.1, FHP 1.2, FHGFF3 1.2**.
FHT and FHGM are drafts under selection rule V7: opt-in, digest-pinned, warned on
every read, and **never a support claim** - see `docs/CAPABILITY-MATRIX.md`.

## Install

```sh
R CMD build . && R CMD INSTALL FAIRbioHeadersTools_*.tar.gz
```

A C compiler and `zlib` (`-lz` in `src/Makevars` / `src/Makevars.win`, declared in
`DESCRIPTION` `SystemRequirements`) are required: `src/` compiles both the vendored
FIPS 180-4 SHA-512/256 core (`src/sha512.c`; see `docs/DIGEST.md` for why it is
vendored rather than delegated) and the strict gzip transport reader (`src/gz.c`),
which uses `zlib` directly for rule-R1 member-by-member decompression, CRC-32 and
length trailer verification, and trailing-byte rejection rather than R's base
`gzfile()` connection (which silently drops trailing garbage after the last gzip
member and reports a CRC mismatch or truncated member only as a warning or unclassed
connection error).

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

bh_extract_header("genome.fhr.fasta")             # the header YAML, prefixes removed
bh_extract_header("genome.fhr.fasta", as = "json") # the parsed record as JSON

# the shared 291-vector suite; the vectors ship in the source tree (tests/conformance),
# not in the installed package, so run this from a checkout or name the directory
x <- bh_conformance("tests/conformance")
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
layer (K3-K6/B1: 43 of its 62 vectors are reported `not-run`, not passed; 19 are
compared at the model layer). FHGM's lane
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
  `Rscript tools/check_vendoring.R [--fresh --fht <checkout> --fhgm <checkout>]` and
  `Rscript tools/draft_pin_freshness.R [--self-test]`
- namespace hygiene: `Rscript tools/check_duplicate_defs.R` — fails if any top-level
  name in `R/` is defined twice. R resolves a duplicate silently (the file collated
  later owns the binding, so the earlier copy is dead code) and `R CMD check` says
  nothing about it, which is how six unreachable definitions sat on `main`; both CI
  workflows now run this as a gate
- docs: roxygen2 (`Config/roxygen2/version` in DESCRIPTION); regenerate `man/`
  and `docs/CAPABILITY-MATRIX.md` with `tools/render_capability_matrix.R`

License: **MPL-2.0** with the family's historical provenance split stated in
`LICENSE` (pre-March-2025 USDA-era material keeps its public-domain terms; see the
license header text). `DESCRIPTION` expresses it as `MPL-2.0 | file LICENSE`.
