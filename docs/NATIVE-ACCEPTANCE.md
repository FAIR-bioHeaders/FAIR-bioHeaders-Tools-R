# Native acceptance: how this package is accepted, and by what

Acceptance for FAIR-bioHeaders language libraries is the federation's shared,
language-neutral suite: **291 vectors at the specification v0.6.0 baseline**
(FAIR-bioHeaders-Specification `conformance/`, tag object `ab7e3ddd`, commit
`0ae18b0`), never a per-language test set invented here. This document states how
the R package runs them, what the guards are, and what remains genuinely unrun.

## The spine: `R CMD check`

`R CMD check --as-cran` is the CI spine. The full testthat suite (unit, integration
and the vector runs) executes inside it, in the checked tree, with no network.
Current real numbers (2026-11-14, macOS arm64 and ubuntu GitHub runners):
see docs/STATUS.md. The empty stub that preceded this work reported `Status: OK,
39 checks, 0 notes` **because it was empty**; every number now is the implementation's.

## The 291-vector ledger

`bh_conformance()` (`R/conformance.R`) runs every manifest vector through the
native reader and accounts for each as `pass`, `fail`, `error`, `missing-fixture`,
`not-run` or `excluded`, always with a reason string. The guards that make the
number mean something:

1. **The suite is the pinned suite.** `manifest.json` is SHA-256'd and compared
   against `inst/VENDORED.json` before any vector runs; the vector count is
   compared too. A moved or edited suite is an error, not a different result.
2. **Nothing disappears.** A complete run must account for all 291 rows
   (`nrow != manifest count` aborts). A `not-run` row must name its missing
   reader; `microdata` (26) and `jsonld` (37) are the declared holes and they
   stay visible with reasons.
3. **The supported subset cannot shrink silently.** The declared supported total
   is the constant 228 (fasta 98 + gfa 56 + fhp-fasta 36 + fhgff3 38); if the
   suite's format tally moves, the capability matrix (published with the draft-lane revision) and this guard must be updated
   together, deliberately, in review.
4. **Missing fixtures and zero-vector runs are errors.** `.bh_suite_dir()`
   refuses to fall through: no suite, no run.
5. **Declared warnings must be reported.** Vectors whose manifest declares a
   `warnings` expectation (two shared `R14` vectors in the released suite at this
   baseline) fail the run if the reader stays silent about them.
6. **Rule accounting.** Each vector's rule labels are matched against
   `bh_rule_coverage()`; verdicts that leave a rule unverifiable (C2, C3
   breadth, J1-J9, M1-M5, R9) are reported per vector (`rule_gaps`) instead of
   being hidden inside an agreeing verdict.
7. **Partial runs are labelled.** `limit=`/`formats=` keep the accounting but
   mark the object `limited = TRUE`; only a complete run is an acceptance run.

The baseline ledger, produced identically by the R runner and the Java runner:

    vectorsTotal=291 vectorsRun=228 vectorsPassed=228 vectorsFailed=0
    vectorsNotRun=63 vectorsDeclaredNotRunWithReason=63
    fasta=98/98 gfa=56/56 fhp-fasta=36/36 fhgff3=38/38
    microdata=0/26 (26 not run) jsonld=0/37 (37 not run)

## The default-behavior golden

`tests/testthat/reference/default-behavior-v0.6.0.json` (SHA-256
`055da14f6dcbdb8ae9e5fc3880fb5bb56d510defb2e12639bde056edc820a525`) fingerprints
the default reading over all 291 vectors - verdict, computed
checksum, hashed-byte count, selection outcome, issue/warning rule codes, and the
SHA-256 of the exact JSON the contract validator received - plus 32 V1-V6
selection probes including the V5 landing of the FHT raw-main URL, which is what an
unregistered type must get from a released-only reader.
`test-default-golden.R` compares the live computation against it and a positive
control shows the comparator bites. `tools/golden_dump.R` regenerates only by
explicit, reviewed invocation.

Honest limitation, stated rather than papered over: the Java library's golden was
generated from its pre-refactor commit (237da6c), proving that its registry
refactor changed nothing. This package had **no prior implementation** - `main`
was an empty stub - so the golden cannot prove equivalence to a past version; it
anchors the accepted-at-v0.6.0 behaviour so that later changes (draft lane, links,
refactors) must pass through it unchanged, and it makes the *next* refactor
provably additive.

## The rule V7 draft lane is a separate, later revision

The FHT development suite (66 vectors) and the pinned draft bytes are handled by the
draft-lane revision stacked on this one. At this revision nothing reads a draft:
selection has no V7 branch, `inst/` bundles no draft bytes, and an FHT citation lands
on rule V5 exactly as it would in a reader that never heard of V7. The default-behavior
golden below is what proves the lane, when it lands, changes nothing by default.

## Receipts

CI asserts *receipts*, not greens: `tools/acceptance_native.R` writes key=value property files (paths from
`BH_ACCEPTANCE_RECEIPT`, `BH_GOLDEN_RECEIPT`) whose literal
lines the workflow compares with fixed strings (counted the same way Java's
`build.yml` does). `tools/run_tests.R` fails the build on any testthat failure,
**any skip**, or a test count below the current floor. A quiet skip is a red CI.

## Primary job purity

The primary acceptance job installs **no Python and no foreign toolkit**: R, the
CRAN dependencies declared in DESCRIPTION, this repository, and the vendored
suite bytes. The differential against CPython `hashlib` (recorded in
docs/DIGEST.md and docs/STATUS.md) ran once, outside acceptance; a labelled,
non-gating supplemental job reproduces it if desired.
