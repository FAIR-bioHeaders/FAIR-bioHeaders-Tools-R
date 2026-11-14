# Agent instructions — FAIR-bioHeaders-Tools-R

Repo-specific rules for agents working in this checkout. Workspace-wide rules and
operational lessons live in `/Users/molik/Code/FHR/AGENTS.md`; the federation-wide
guidance is `AGENTS.md` in FAIR-bioHeaders-Specification, ported to the six specification
repositories. This file is not one of those six shared copies and does not travel with
them.

## What this repository is

An R library for FAIR-bioHeaders: read, checksum-verify and contract-validate file-bound
metadata in FASTA, GFA and GFF3. It is a client of the published contracts, not a place to
change them — a field, a requiredness change or a new constraint is a schema addition and
belongs in FAIR-bioHeaders-Specification with its own cycle.

`docs/CAPABILITY.md` is an archived capability study (measured 2026-11-14), not a description
of shipped behaviour. Read `docs/CAPABILITY-MATRIX.md` for what the package does.

## Two constraints that are not negotiable here

1. **The checksum is SHA-512/256**, computed by the vendored core in `src/`. `digest` and the
   R `openssl` package do not provide the algorithm, and truncated SHA-512 is a different
   algorithm that produces a plausible 44-character value for every file. Do not add a
   fallback, a feature-detected substitute or a "use whatever is installed" branch. The core
   self-tests against published vectors at load time and refuses to load when it disagrees;
   keep it that way. `docs/DIGEST.md` records the decision and the evidence.
2. **The schema engine is `engine = "ajv"`, pinned.** `jsonvalidate`'s default `imjv` engine
   mis-verifies draft/2020-12 constructs in both directions on the released contracts. The
   engine is a package-internal constant; no function takes it as an argument. Do not expose
   it, and do not remove the `bh_dialect_probe()` guard or the imjv-contrast test that
   explains why the pin exists.

## Native-first acceptance

The acceptance job uses R only: no Python, no `fair-bioheaders`, no foreign runner, no
oracle call. `.github/workflows/native-acceptance.yaml` asserts this by refusing a
foreign-language dependency in `DESCRIPTION` and any external-process call under `R/`.
Reference differentials against Python or the released toolkit are separate and supplemental
(`reference-differential.yaml`, `tools/differential_digest.R`); they may be skipped, visibly,
and nothing may depend on them.

Acceptance numbers are the federation's shared vectors, never a new suite: 291 vectors at the
v0.6.0 baseline, of which this package runs 228 and reports the other 63 as not-run with the
missing reader named. Vendored upstream bytes are audited by `tools/check_vendoring.R`
against `inst/VENDORED.json`; re-vendoring is `tools/vendor_upstream.R`, which vendors from a
tag or commit rather than a working tree.

## Rule V7, drafts, and what may not be claimed

FHT and FHGM have **no released contract**: scheduled as specification v0.7.0 and v0.8.0 by
maintainer decision. In this repository that means no `schemaVersion`, no row in
`inst/schemas/versions.json`, no w3id URL, and no "five types supported" claim anywhere. The
draft lane is opt-in per call or per option, is digest-pinned by commit and SHA-256, warns on
every record read through it, and leaves the default path identical to the pre-V7 outcome.
A release-shaped URL for an unregistered type (`…/fht/v0.7.0`, a raw tag URL) stays V5 with
the lane open or closed. FHGM is **not a header type**: its records are transported inside an
FHGFF3 header under `x-fhgm-models` and carry no `schema` field, so the lane selects only the
contract applied to the records.

Pre-release evidence (the FHT and FHGM development suites) is vendored and run separately and
labelled as draft evidence; it never joins the 291 and never supports a release claim.

## Working rules

- Fetch before asserting anything about this or a sibling repository's state; checkouts lag
  in both directions.
- Verify by digest, not by description: contract copies, draft pins, vector bytes and
  checksum values are all re-checked with `tools/check_vendoring.R`.
- Report a negative result as measured. A documented "cannot do this natively, here is why"
  is an acceptable outcome; a false pass is not. Never invent a digest, version, DOI,
  test count or vector count, and never print a count that a run did not produce.
- In this shared workspace, stage explicit paths — never `git add -A` — because sibling
  task checkouts and other agents' in-flight work sit alongside this one.
- Publishing is not agent work: no merging, no tagging, no CRAN or Bioconductor submission,
  no board edits, no contact with other maintainers from here. Opens and updates pull
  requests; a maintainer releases.
- Plain technical prose in code, docs, comments and commit messages.

## Checks

```sh
Rscript tools/check_vendoring.R
R CMD build . && R CMD check --no-manual FAIRbioHeadersTools_0.1.0.tar.gz
Rscript tools/run_conformance.R
Rscript tools/run_conformance.R --draft
Rscript tools/run_conformance.R --fhgm
Rscript tools/render_capability_matrix.R     # keeps docs/CAPABILITY-MATRIX.md honest
```

`docs/` and `tools/` are excluded from the installed package (`.Rbuildignore`); the vendored
contracts, drafts and provenance under `inst/` and the vectors under `tests/` are inside it,
so a check run needs neither a network nor a second checkout.
