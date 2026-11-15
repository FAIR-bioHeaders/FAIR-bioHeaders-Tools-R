# STATUS — measured state of the R library

Date: **2026-11-14**, with the 2026-11-15 sections below added for #10 and #12. Everything in
the table was measured on the commit this document accompanied, on macOS 14 arm64 with
R 4.6.1, `jsonvalidate` 1.5.0 (V8 8.2.1), `digest` 0.6.39, `yaml` 2.3.12,
`jsonlite` 2.0.0, `roxygen2` 8.1.0, `testthat` 3.3.2. CI re-measures the same spine on
ubuntu-latest and macos-latest.

## 2026-11-15 — six duplicate top-level definitions removed, and a guard added (#12)

Measured in a fresh clone of `main` at `4611c2c`, on macOS 27.2.1 arm64, R 4.6.1.

**The state before the change.** `R/` holds 150 top-level assignments, 128 of them function
definitions, under 144 distinct names; **six names are defined twice**. #12's table gives five
names and 126 definitions; the sixth found here is `%||%`, defined at `R/framing.R:34` and
`R/internals.R:12`. The five names #12 lists reproduce in the same files; their line numbers in
`R/conditions.R` are 9 higher than the issue recorded because #11 inserted a comment block in that
file (verified: `git diff 9827944f..4611c2c -- R/conditions.R` touches only roxygen and comment
lines, no code).

| name | copy 1 | copy 2 | comparison of the two definitions |
| --- | --- | --- | --- |
| `bh_abort` | `R/conditions.R:29` | `R/internals.R:42` | raw source bytes identical |
| `bh_warn` | `R/conditions.R:40` | `R/internals.R:55` | **differs semantically** (`63e96156c4d83e9f` vs `43727c8387068674`) |
| `.bh_capture` | `R/conditions.R:55` | `R/internals.R:73` | differs by one line, no behaviour change (see below) |
| `.bh_read_all` | `R/conditions.R:76` | `R/internals.R:18` | raw source bytes identical |
| `.bh_c` | `R/framing.R:81` | `R/internals.R:14` | raw source bytes identical |
| `%||%` | `R/framing.R:34` | `R/internals.R:12` | raw source bytes identical |

Four pairs are byte-identical as written. Hashes are SHA-256(16) of the definition after
`deparse()` canonicalisation, used to compare the two that differ, so indentation and line wrapping
can neither fake a difference nor hide one.

`.bh_capture` is the case worth recording precisely, because a raw text difference here is not a
behaviour difference: after canonicalisation the two bodies differ by exactly one line — the
`R/conditions.R` copy pre-declares `val <- NULL` immediately before assigning `val` again — and both
copies, called the way the package calls them (expression passed lazily), return `identical()`
results on all four traced inputs: no condition, two `bh_warn` calls, one `bh_abort`, and a warning
followed by an error. The live binding agrees with both. #12 records this so the duplicate audit is
not read as "two behaviourally different captures".

**Which copy ran, established by execution.** The package was built and installed from the
tarball and each name was read out of the loaded namespace with `getFromNamespace()`. For all six
names the installed binding equals the `R/internals.R` copy; the `R/conditions.R` copies of
`bh_warn` and `.bh_capture` are the only two whose canonical text differs from the live binding,
which is the direct evidence that they were unreachable. `R/internals.R`'s `bh_abort` uses the same
`paste(c(message, ...), collapse = "")` fallback as its `bh_warn`, so the retained module is the
internally consistent one, as #12 predicted. A two-file control package (`R/conditions.R` and
`R/internals.R` defining `dupe()` differently) was installed the same way and its namespace returns
`"from-internals.R"` — the shadowing rule is measured, not argued.

Behavioural discriminator for `bh_warn`, with `sprintf()` failing (`bh_warn("draft", "%s %d", "a")`):
the live binding reports `’%s %da’` (the `paste()` fallback), the deleted `R/conditions.R` copy would
have reported `’%s %d’`. Neither is exported (`NAMESPACE` lists neither), and both call sites —
`R/fhgm.R:152`, `R/read.R:99` — pass `bh_warn("draft", "%s", w)`, where `sprintf()` succeeds, so no
reachable path exercised the divergence before or after this change.

**What was done.** The six dead copies were deleted; `R/internals.R` is now the sole owner of all
six helpers. Nothing else in `R/` changed. `R/conditions.R` keeps the `conditions` topic and now
records the deleted `bh_warn` fallback as an open question rather than silently discarding it: if
the maintainers want the format-string-only handler, it is a one-line change in `R/internals.R`
plus a test with mismatched directives, and no test of either handler exists today.

**Evidence that nothing moved.** `tools/check_duplicate_defs.R` is new; `R/` goes from 150
top-level assignments / 144 distinct names to 144 / 144. A canonical dump of every object in the
loaded namespace (154 objects, 32 exports, functions printed via `deparse()`, native symbols by
name only) is byte-identical before and after — SHA-256
`302b870c81978963564ce66d1fe75e3d3c15e5ce80fe655fa1834e398a5f5379` for both, `cmp` clean. On top of
that: `tests=770 failed=0 errors=0 skipped=0` (unchanged, and no test calls `bh_abort()`/`bh_warn()`
directly); ledger `291 / 228 pass / 0 fail / 63 declared not-run`; golden `goldenDifferences=0` with
`tests/testthat/reference/default-behavior-v0.6.0.json` still SHA-256
`055da14f6dcbdb8ae9e5fc3880fb5bb56d510defb2e12639bde056edc820a525`; FHT draft lane 66/66; FHGM draft
lane 31 evaluated / 7 model-compared / 24 not-run; `docs/CAPABILITY-MATRIX.md` byte-identical after
`tools/render_capability_matrix.R` (`1b4b0bbd4fddd9ea029e2b3975ad9fabb2ade66a5663d1c696c4d652d53b71a9`).
Every receipt file is byte-identical between the two runs (`cmp`). `R CMD check --as-cran
--no-manual` reports `Status: 1 NOTE` with exit 0 both before and after — the same unavoidable
"New submission" NOTE — and the two logs are identical apart from paths and timings (`diff` after
stripping those: empty). No `man/` file changed: no roxygen block was removed, and the
`read.Rd`/`yaml-shape.Rd` trailing-blank-line artifact that `roxygen2::roxygenise()` produces on
this tree appears identically on pristine `main`, so it was reverted again under the same rule as
above.

**The guard, and why it is not a status check.** `R CMD check` cannot catch this: on the two-file
control package it exits 0 and the word "duplicate" appears nowhere in its log, and on `main` at
`4611c2c` it exits 0 while reporting `Status: 1 NOTE` (#11 measured the same with
`Status: 1 WARNING, 1 NOTE`). So `tools/check_duplicate_defs.R` is its own static analysis — it
parses `R/*.R`, takes every top-level name assignment (`<-`, `<<-`, `->`, `->>`, `=`, and `assign()`
with a literal name), and exits 1 on any name bound twice, identical bodies included, exiting 2 when
it cannot see `R/` at all so that an unreadable tree is never a pass. It runs as a failing step in
both workflows (`build.yml`, `native-acceptance.yaml`). Red/green was demonstrated four ways: on the
real pre-fix tree (6 violations), on the fixed tree (green), after re-appending the identical
`.bh_c` to `R/framing.R`, and after re-appending the divergent `bh_warn` copy to `R/conditions.R`
(reported as `copies DIFFER`), plus a same-file duplicate and a directory with no `R/`. Each
mutation was proven non-vacuous with `cmp` against the pre-mutation file, and each revert was
verified byte-identical. Separately, the `R CMD check` steps now keep their log and fail on any
`WARNING` line, which is the detection #12 asked about: it is wired, not just recommended. NOTEs are
printed and not gated, because the "New submission" NOTE and the macOS pandoc NOTE are unavoidable
and would make the leg permanently red.

**A defect in the guard itself, caught by testing its own untested branch.** The first version
parsed `Collate:` looking for double-quoted file names. DESCRIPTION fields quote with single
quotes, so a package that declared `Collate:` fell through to alphabetical order while the
violation line still asserted a load order — with `Collate: 'zzz.R' 'aaa.R'` it named `zzz.R:1` as
live where the installed namespace binds `aaa.R`'s (`a(3)` returns `3`). Both quote forms now
parse, continuation lines included, files the field omits are placed first as `R CMD INSTALL`
does, and a `Collate:` field that yields no names stops the run with exit 2 instead of guessing:
the order is what the message claims, so it is not a thing to fall back on. The operator list also
read `->=` where `->>` was meant; R normalizes right-assignment before the script sees it
(`parse(text = "(f) ->> a")` gives `<<-(a, f)`), so nothing was missed on the forms this package
uses, and `->`, `->>`, `assign()` and non-function duplicates are each now tested to exit 1.

**CI on this branch.** `build` and `Native acceptance` are green at `6bff0b5` (runs 43751103290,
43751103350) and at `601eba6` (43751582981, 43751582983). The guard step runs on all three `Native
acceptance` legs — including `oldrel-3` on **R 4.3.3**, job 132926503619 — and every leg then prints
`R CMD check: no WARNING in check.log (exit status 0)`; the `build` legs print the same for
`build-check.log`. At `2ca8f76` one duplicate was put back deliberately, its bytes proven (`R/framing.R`
sha256 `79c44686f516…` → `2046b18a58b8…`, `cmp` reporting `EOF`), and **both workflows fail**
(43751638775, 43751638779) with `Assert no name is defined twice in R/` as the only failed step in
each job — the `build` jobs also fail `Upload native reports`, because the job aborted before the
receipts it uploads were ever written. The `oldrel-3` leg fails the same way (job 132926683363), so
the gate is proven on R 4.3.3 as well as on 4.6. `6ef9ea3` reverts the probe and both workflows are
green again (43751655760, 43751655787). The `oldrel-3` attribution uses the REST per-job logs
endpoint (`actions/jobs/{id}/logs`), because `Native acceptance` has two jobs named
`R CMD check (ubuntu-latest)` and the name-keyed `gh run view --log --job=` route returns
byte-identical logs for both — the trap #11 recorded.

*Supersedes* the "**Found while doing this, deliberately not changed**" paragraph in the #10 section
below, which recorded these duplicates as left in place on purpose. That was the right call for a
documentation-only PR; #12 is the code change it deferred, so that paragraph is kept as the record of
what #10 measured and should not be read as the current state.

## Baseline comparison, honestly framed

The stub package on `main` before this work reported `Status: OK / 39 checks /
0 notes` **because it was empty**: no compiled code, no exports beyond a
placeholder, no tests. Those 39 checks are not a quality bar; the numbers below
are the first real ones for this repository.

| measure | stub (main, `4b975bd`) | v0.6.0 core + lane (main, `8957f4f`) | this work (FHGM model lane) |
| --- | --- | --- | --- |
| `R CMD check --as-cran --no-manual` | 39 checks, 0 notes, Status OK | recorded by that revision as "66 checks, 0 errors, 0 warnings, 1 NOTE"; **not reproducible in this session** — the same commit `8957f4f`, checked here with the toolchain above, reports 1 WARNING and 1 NOTE | **0 errors, 1 WARNING, 1 NOTE** (66 check lines, 53 `checking` steps; `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 770 ]` inside the check). The NOTE is the unavoidable "New submission"; the WARNING is `Rd files with duplicated alias 'bh_abort'` (`man/conditions.Rd` and `man/internals.Rd`), present at `8957f4f` as well, so nothing here introduces it. Removing the duplicate roxygen block is a separate cleanup. The CI legs report the same pair (`build (ubuntu-latest)`: 1 WARNING, 1 NOTE); the macOS leg adds one NOTE, "Files 'README.md' or 'NEWS.md' cannot be checked without 'pandoc' being installed", which is a runner toolchain artifact of that workflow (it installs no pandoc) and not a package finding. |
| testthat assertions | 0 | **561, 0 failed, 0 errors, 0 skipped** (re-measured locally at `8957f4f`) | **770, 0 failed, 0 errors, 0 skipped** |
| shared v0.6.0 vectors | not run | **291 accounted: 228 pass natively, 63 not-run with reasons, 0 fail** | unchanged: the receipt is byte-identical to the one produced at `8957f4f` |
| default-behavior golden | none | `goldenDifferences=0` | `goldenDifferences=0`; the golden file is still SHA-256 `055da14f6dcbdb8ae9e5fc3880fb5bb56d510defb2e12639bde056edc820a525` |
| FHT development suite (draft lane only) | not run | **66/66 pass** against pinned bytes, in the separate labelled job | unchanged, same job |
| FHGM development suite (draft lane only) | not run | not run (the checker was not on `main`; see below) | **31 evaluated: base 31/31, checksum 31/31; model layer compared on the 7 K1/K2 vectors, all agreeing; 24 `not-run` naming K3-K6/B1** |
| compiled digest self-test | none | runs at every package load; refuses to load on any mismatch | unchanged |

## 2026-11-15 — the `R CMD check --as-cran` WARNING is gone (#10)

Re-measured on this commit, macOS arm64, R 4.6.1, `roxygen2` 8.1.0:

| measure | before (`9827944`) | after (this commit) |
| --- | --- | --- |
| `R CMD check --as-cran --no-manual` | `Status: 1 WARNING, 1 NOTE`, from `checking Rd metadata ... WARNING` / `Rd files with duplicated alias 'bh_abort': 'conditions.Rd' 'internals.Rd'` | `Status: 1 NOTE`, from `checking Rd metadata ... OK` |
| `checking` steps | 53 | 53 |
| testthat inside the check | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 770 ]` | `[ FAIL 0 \| WARN 0 \| SKIP 0 \| PASS 770 ]` |

The one remaining NOTE is the same unavoidable "New submission" under `checking CRAN
incoming feasibility`. The two `00check.log` files differ in exactly three places — the
`Rd metadata` block, the test timings, and the `Status:` line — verified with `diff` after
writing each log to its own file and stripping only the log-directory and timestamp lines.

**Why CI stayed green with a WARNING on `main`.** `.github/workflows/build.yml` does use
`--as-cran`: its `R CMD check (the spine)` step is
`R CMD check --as-cran --no-manual FAIRbioHeadersTools_*.tar.gz`.
`.github/workflows/native-acceptance.yaml` runs the check with `--no-manual` and *without*
`--as-cran`. Neither step can fail on a warning: `tools:::.check_packages()` in R 4.6.1
calls `do_exit(1L)` only when `Log$errors > 0L`, and the run on the unmodified tree exited
0 while reporting `Status: 1 WARNING, 1 NOTE`. So no flag suppressed the warning — the
spine job has been printing it — the step is just not wired to fail on one. Turning a
WARNING red is a CI change and belongs with #4, so it is not done here.

**The same two workflows, read out of CI's own logs, `main` vs this branch.** Each row is
the `checking Rd metadata` line and the `Status:` line of one job, taken from that job's own
log (`actions/jobs/{id}/logs`; note that `gh run view --log --job=` keys on the job *name*,
and `Native acceptance` has two jobs called `R CMD check (ubuntu-latest)` whose logs came
back byte-identical under that route — `cmp` proved it, so the per-job endpoint is what the
figures below come from).

| leg | flag | R | `main` at `9827944` | this branch at `e858b31` |
| --- | --- | --- | --- | --- |
| `build.yml` / `build (ubuntu-latest)` | `--as-cran` | 4.6.2 | WARNING, `Status: 1 WARNING, 1 NOTE` | OK, `Status: 1 NOTE` |
| `build.yml` / `build (macos-latest)` | `--as-cran` | 4.6.2 | WARNING, `Status: 1 WARNING, 2 NOTEs` | OK, `Status: 2 NOTEs` |
| `native-acceptance.yaml` / ubuntu release | no `--as-cran` | 4.6.2 | WARNING, `Status: 1 WARNING` | OK, `Status: OK` |
| `native-acceptance.yaml` / macOS | no `--as-cran` | 4.6.2 | WARNING, `Status: 1 WARNING` | OK, `Status: OK` |
| `native-acceptance.yaml` / ubuntu oldrel-3 | no `--as-cran` | **4.3.3** | WARNING, `Status: 1 WARNING` | OK, `Status: OK` |

Both runs on this branch are green end to end: `build` run 43728815985 (8 jobs, all
`success`, including the ledger and golden literal assertions) and `Native acceptance` run
43728815989 (3 jobs, all `success`).

Two corrections come out of this. The NOTE count on every leg is unchanged before and after
(the macOS legs carry the documented pandoc NOTE, the `--as-cran` ubuntu leg carries
"New submission", the legs without `--as-cran` carry neither), and **#10's assumption that
`--as-cran` is what surfaces the WARNING is wrong**: `Rd metadata` printed it on all five
legs above, including the three that never pass `--as-cran`, on R 4.6.2 and R 4.3.3 alike.
The WARNING was always printed, everywhere, and acted on nowhere.

**Which module owns the documented topic.** `R/internals.R` now documents
`bh_abort()`/`bh_warn()` alone (#10's option 1). `R/conditions.R` keeps the `conditions`
topic — the classed error/warning surface — and points at the helpers with `@seealso`; its
duplicate roxygen block is a plain comment. Reasons, in the order that decided it: the copy
that actually runs is `R/internals.R`'s, because there is no `Collate:` field, so
`R/conditions.R` is collated first and `R/internals.R` overwrites the shared bindings
(confirmed by installing this tree and reading `bh_warn`'s body out of the namespace: it
carries the `paste(c(message, ...), collapse = "")` handler from `R/internals.R`, not the
`error = function(e) message` one from `R/conditions.R`); and `man/internals.Rd` documents
the pair together with `@keywords internal`, while `man/conditions.Rd` documented
`bh_abort()` only and never `bh_warn()`. #10's option 2 rests on callers meeting the helper
through conditions; what a caller meets is the condition classes, which is what the
`conditions` page describes, and that page stays where it was.

**Found while doing this, deliberately not changed.** `bh_abort()`, `bh_warn()`,
`.bh_read_all()` and `.bh_capture()` are each *defined* twice on `main`, once per module.
`bh_abort()` and `.bh_read_all()` are byte-identical between the two files (verified with
`cmp`); `bh_warn()` differs in its `sprintf()`-failure fallback. Only the `R/internals.R`
copies are reachable. Removing the shadowed copies is a code change, and no test calls
`bh_abort()` directly or exercises either fallback — its documented behaviour is covered
only indirectly, by the `expect_error(..., class = "bh_*")` assertions in
`test-conformance.R`, `test-draft-lane.R`, `test-engine-pin.R` and `test-fhgm-lane.R` — so
it is left for its own decision. `R/conditions.R` now says this above the copies.

**Unmoved, re-measured on this commit:** ledger `vectorsTotal=291 vectorsRun=228
vectorsPassed=228 vectorsFailed=0 vectorsNotRun=63`; golden `goldenDifferences=0`, with
`tests/testthat/reference/default-behavior-v0.6.0.json` still SHA-256
`055da14f6dcbdb8ae9e5fc3880fb5bb56d510defb2e12639bde056edc820a525`; `tests=770`,
`skipped=0` from `tools/run_tests.R` against the CI floor of 700; FHT draft receipt 66/66
and FHGM draft receipt 31 evaluated / 7 model-compared / 24 not-run, both against their
pinned bytes and digests; `docs/CAPABILITY-MATRIX.md` byte-identical after re-running
`tools/render_capability_matrix.R` (46 cells).

**How `man/` was regenerated, and one thing reverted.** `Rscript -e
'roxygen2::roxygenise()'` (roxygen2 8.1.0, `Roxygen: list(markdown = TRUE)`), not a hand
edit. That run also appended a trailing blank line to `man/read.Rd` and
`man/yaml-shape.Rd`, which is unrelated to #10 and was reverted rather than committed: no
committed `man/*.Rd` ends with two LF bytes (checked across all 44), so this is an artifact
of re-running roxygen here, not a content difference. Every other `man/` file regenerates
byte-identical, so `man/conditions.Rd` is the only documentation page this change alters.

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

**A defect the deliberate-failure probe caught.** With the not-run policy temporarily
removed, `s6k-derived-record-fixture` disagreed with its published expectation in the other
direction: this package's K2 layer *rejected* a record the suite records as `pass`. The cause
is not the contract and not the fixture. R's `yaml` returns an atomic vector for a
one-item sequence, so the fixture's `"deposit":["doi:10.22002/e86gh-a7p16"]` reaches
`.bh_record_json()` as a scalar, and the pinned record contract - which declares
`publication.deposit` an array - rejects it. The released header path already repairs that
shape from the text (`R/yaml-shape.R`), but its scanner is line-oriented and cannot see
inside a flow value; that was harmless while every array-typed property in the released
contracts was a top-level key (measured over `fhr-2.1`, `fhp-1.2`, `fhgff3-1.2`: still true).
The FHGM record contract is the first in the family with an array nested inside an object
(`publication.deposit`, `methods.limitations`), so the lane needed its own text-derived scan
(`.bh_fhgm_flow_scalar_keys()`, `R/fhgm.R`). Nothing is coerced from the contract: a key is
re-wrapped only because this file's bytes wrote brackets around it, and the standing test
asserts both halves - the fixture's array survives, and the same bytes with the brackets
removed are still rejected (2 bytes fewer, proven on the file). The repair lives in the draft
lane only; the released path and the golden do not move.

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
