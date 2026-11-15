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
   suite's format tally moves, this guard and `bh_capability()` must be updated
   together, deliberately, in review.
4. **Missing fixtures and zero-vector runs are errors.** A suite location that is
   *named* - by argument, `bh.conformance_dir`, `bh.draft_dir`, `bh.fhgm_dir` or the
   matching environment variable - is authoritative: `.bh_resolve_named()` errors
   unless that directory holds a `manifest.json`, rather than falling through to
   the vendored copy. Only an unnamed lookup searches (`.bh_search()`), and it
   names what it searched. A fallback that rescues a bad path is how "missing
   fixtures must fail" becomes a pass that proves nothing, and a case-insensitive
   filesystem makes the rescue silent: `test-fhgm-lane.R` measures the
   filesystem and asserts the guard bites on the case-sensitive (Linux) leg,
   while the macOS leg says plainly that it cannot prove it.
5. **Declared warnings must be reported.** Vectors whose manifest declares a
   `warnings` expectation (three at this baseline: two shared `R14`, one FHT
   draft `R14`) fail the run if the reader stays silent about them.
6. **Rule accounting.** Each vector's rule labels are matched against
   `bh_rule_coverage()`; verdicts that leave a rule unverifiable (C2, C3
   breadth, J1-J9, M1-M5, R9, and FHGM's K3-K6) are reported per vector
   (`rule_gaps`) instead of being hidden inside an agreeing verdict.
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
the default reading (`draft = FALSE`) over all 291 vectors - verdict, computed
checksum, hashed-byte count, selection outcome, issue/warning rule codes, and the
SHA-256 of the exact JSON the contract validator received - plus 32 V1-V6
selection probes including the lane-closed V5 landing of the FHT raw-main URL.
`test-default-golden.R` compares the live computation against it and a positive
control shows the comparator bites. `tools/golden_dump.R` regenerates only by
explicit, reviewed invocation.

Cross-revision evidence: this golden file is byte-identical to the one generated in
the released-core revision (`pr1/native-core`). The draft lane landed on top of it and
`goldenDifferences=0` in this revision's acceptance run is what proves the lane is
strictly additive over the default path - the same argument the Java library made with
a golden generated from its pre-registry commit, made here with a golden generated from
the pre-lane commit.

Honest limitation, stated rather than papered over: the Java library's golden was
generated from its pre-refactor commit (237da6c), proving that its registry
refactor changed nothing. This package had **no prior implementation** - `main`
was an empty stub - so the golden cannot prove equivalence to a past version; it
anchors the accepted-at-v0.6.0 behaviour so that later changes (draft lane, links,
refactors) must pass through it unchanged, and it makes the *next* refactor
provably additive.

## The rule V7 draft lane is separate, labelled, and never acceptance

`bh_draft_vectors()` runs the **66 FHT development vectors** published by
FHT-Specification (vendored at the pinned suite commit, re-digested before use)
through the native reader with the lane open. A pass is draft evidence against
pinned unreleased bytes, not support for FHT; the label says so; the shared
ledger's numbers do not include them; CI runs them in a separate, labelled job
whose receipt pins contract commit `226f923c...`, SHA-256 `59ad9641...`, suite
commit `156bda63...`. The advisory `draft-pin-freshness` job compares the pins
with the owning repositories' live default branches and reports drift without
gating released acceptance.

`bh_draft_fhgm_vectors()` runs the **31 FHGM development vectors** published by
FHGM-Specification, in its own labelled CI job, and never into the 291. That
suite records four independent layers per vector (`base`, `checksum`, `gff3`,
`model`), so the run reports them separately: base and checksum are compared on
all 31, the model layer only on the 7 whose rule labels are inside what this
package evaluates (K1 transport, K2 the pinned record contract). The other 24
turn on K3-K6 or B1 and are `not-run` with the rule named - never passed on the
strength of the schema layer. FHGM is not a header type: its records ride inside
an FHGFF3 header under `x-fhgm-models` and carry no `schema` field, so the lane
selects only the contract applied to the records. The receipt pins contract
commit and SHA-256 (`ac3d37b3...` / `bf1553ca...`), the suite commit
(`ac3d37b3...`) and its manifest digest (`31f14f02...`), and the workflow
asserts the counts as fixed strings, so a model layer that silently shrank or
started over-claiming fails the job.

## Controls that must go red

The draft runs are only evidence if they can fail. Three standing controls live
in `test-fhgm-lane.R`, each asserting its own mutation landed before drawing a
conclusion from it:

1. **One byte inside checksum coverage.** A valid vector is copied to a scratch
   tree, one feature-line byte changes (`ID=toy-a` to `ID=toy-A`), and the test
   asserts the bytes differ, then that the labelled run reports 31 vectors with
   exactly **1 failure** - base still `accept`, checksum `stale`.
2. **A zeroed recorded pin.** `draft_fhgm_vectors$manifest_sha256` is replaced
   with zeros in the provenance cache; the run **aborts** (`bh_conformance`
   error) and writes no receipt, rather than reporting not-run or pass.
3. **A neutered model checker.** `bh_validate_fhgm()` is bound to a stub that
   reports every record valid. The test first shows the stub live on a fixture
   the real code rejects, then requires the 4 comparable expected-rejection
   vectors to become failures reading `model pass vs expected reject`, with base
   and checksum still agreeing. If the stub were not on the called path, this
   control would be vacuous, so that check is asserted rather than assumed.

The same refusal is tested for the locators of all three suites
(`test-conformance.R`, `test-fhgm-lane.R`): a named directory without a
`manifest.json` is an error, never a fallback.

A fourth control is not in this package's source at all: it is the shape of a record.
`.bh_record_json()` hands the validator the JSON of what the YAML parse produced, and R's
`yaml` flattens a one-item sequence to an atomic vector, so `"deposit":["doi:..."]` would
arrive as a scalar and be rejected as a type error. The lane repairs the shape from the
file's own text (`.bh_fhgm_flow_scalar_keys()`), and two tests hold it honest: the suite's
`s6k` fixture must validate with its array intact, and the same bytes with the two brackets
deleted (2 bytes fewer, asserted on the file) must still be rejected. Coercing from the
contract instead would accept a genuinely scalar `deposit`, which is the dangerous direction.

## Receipts

CI asserts *receipts*, not greens: `tools/acceptance_native.R`,
`tools/acceptance_draft.R` and `tools/acceptance_fhgm.R` write key=value property
files (paths from `BH_ACCEPTANCE_RECEIPT`, `BH_GOLDEN_RECEIPT`,
`BH_DRAFT_RECEIPT`, `BH_FHGM_RECEIPT`) whose literal
lines the workflow compares with fixed strings (counted the same way Java's
`build.yml` does). `tools/run_tests.R` fails the build on any testthat failure,
**any skip**, or a test count below the current floor. A quiet skip is a red CI.

## Primary job purity

The primary acceptance job installs **no Python and no foreign toolkit**: R, the
CRAN dependencies declared in DESCRIPTION, this repository, and the vendored
suite bytes. The differential against CPython `hashlib` (recorded in
docs/DIGEST.md and docs/STATUS.md) ran once, outside acceptance; a labelled,
non-gating supplemental job reproduces it if desired.
